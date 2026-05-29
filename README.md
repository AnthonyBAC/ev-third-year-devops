# Backend — EV. Devops

Microservicios backend de la solución: dos APIs REST en **Spring Boot** (Ventas y
Despachos), contenerizadas con Docker y desplegadas de forma automatizada a una
instancia **EC2 privada** mediante GitHub Actions. La base de datos **MySQL 8**
corre en su **propia EC2** (tier de datos), siguiendo una arquitectura **3-tier**.

## Repositorios del proyecto (3-tier)

- **Frontend:** https://github.com/AnthonyBAC/ev-third-year-devops-frontend
- **Backend:** https://github.com/AnthonyBAC/ev-third-year-devops-backend
- **Datos (DB):** https://github.com/AnthonyBAC/ev-third-year-devops-db

---

## Arquitectura (3-tier)

```
   EC2 Frontend (pública/bastion)   EC2 Backend (privada)        EC2 DB (privada)
   ┌──────────────┐                 ┌──────────────────┐         ┌──────────────┐
   │  nginx :80   │  /api/v1/* ───► │  back-ventas :8080│  3306   │  MySQL       │
   │  (bastion)   │                 │  back-despachos   │ ──────► │  + volumen   │
   └──────────────┘                 │       :8081       │         │  mysql-data  │
        ▲ único público             └──────────────────┘         └──────────────┘
                                      ▲ deploy entra por el bastion (SSH proxy)
```

- **back-ventas**: API REST de ventas, puerto `8080`, base `db_ventas`.
- **back-despachos**: API REST de despachos, puerto `8081`, base `db_despachos`.
- **MySQL**: en su EC2 dedicada (privada); el backend la consume por `${DB_HOST}:3306`.
- El backend está en **subred privada** (sin IP pública); el deploy entra vía SSH
  usando el frontend como **bastion**, y el backend sale a internet por un **NAT Gateway**.
- Solo el frontend es accesible desde Internet. El acceso a `8080/8081` (backend) y
  `3306` (db) está restringido por Security Groups a la IP de quien corresponde.

---

## Estructura del repositorio

```
.
├── back-Ventas_SpringBoot/Springboot-API-REST/          # codigo + Dockerfile API Ventas
├── back-Despachos_SpringBoot/Springboot-API-REST-DESPACHO/  # codigo + Dockerfile API Despachos
├── docker-compose.yml      # levanta las 2 APIs (apuntan a la EC2 db por ${DB_HOST})
├── .env.example            # plantilla de variables para correr en local
└── .github/workflows/deploy.yml   # pipeline CI/CD
```

---

## Dockerfiles (multi-stage + usuario no root)

Cada API usa un **build multi-stage**:

1. **Etapa builder**: `maven:3.9-eclipse-temurin-17-alpine` compila y empaqueta el `.jar`.
   Se copia primero el `pom.xml` y se hace `mvn dependency:go-offline` para cachear
   dependencias y acelerar builds posteriores.
2. **Etapa runtime**: `eclipse-temurin:17-jre-alpine` (solo JRE, imagen liviana).
   Se crea un usuario **no root** (`appuser`) y se ejecuta el `.jar` con él, aplicando
   el principio de **mínimo privilegio**.

Flags de JVM pensadas para contenedor: `-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0`.
En el deploy se acotan además con `JAVA_TOOL_OPTIONS=-Xmx256m -Xms128m -XX:+UseSerialGC`
para caber en la t3.micro.

---

## Persistencia de datos

La persistencia vive en la **EC2 del tier de datos** (no en este backend). MySQL usa un
**named volume** (`mysql-data`) montado en `/var/lib/mysql`, definido en el
`docker-compose.yml` de la carpeta `db-tier`.

| Aspecto | Decisión |
|---|---|
| Tipo de volumen | **Named volume** (`mysql-data`) |
| ¿Por qué named y no bind mount? | Lo administra Docker, es portable, no depende de rutas del host y sobrevive a `docker compose down` / recreación del contenedor. Un bind mount ataría los datos a una ruta específica del EC2 y complica permisos. |

Gracias al named volume, **los datos de MySQL no se pierden** al reiniciar o recrear
el contenedor. El script `init-db.sql` (en la EC2 db) solo corre cuando el volumen está
vacío, creando `db_ventas` / `db_despachos` y otorgando permisos a `appuser`.

---

## Correr en local

```bash
cp .env.example .env      # completa DOCKER_USERNAME y las claves MySQL
docker compose up -d --build
docker compose ps
```

- API Ventas: http://localhost:8080
- API Despachos: http://localhost:8081

Para levantar un servicio individual: `docker compose up -d mysql back-ventas`.

---

## Pipeline CI/CD (GitHub Actions)

Archivo: `.github/workflows/deploy.yml`. Se dispara con **push a la rama `deploy`**.

```
push a deploy
   │
   ├─ build-and-push  (matriz: back-ventas + back-despachos)
   │     1. checkout
   │     2. login en Docker Hub
   │     3. build + push de cada imagen  (tags :latest y :<sha>)
   │
   └─ deploy-backend  (needs: build-and-push)
         1. checkout
         2. scp de docker-compose.yml + init-db.sql al EC2
         3. ssh: docker compose pull + docker compose up -d
```

El deploy en EC2 **levanta el stack con `docker compose`**, usando las imágenes ya
publicadas en Docker Hub (no compila en la instancia).

### Secrets requeridos (Settings → Secrets and variables → Actions)

| Secret | Descripción |
|---|---|
| `DOCKER_USERNAME` | Usuario de Docker Hub |
| `DOCKER_TOKEN` | Token de acceso de Docker Hub |
| `EC2_USER` | `ubuntu` |
| `EC2_SSH_PRIVATE_KEY` | Clave privada SSH (`nuevo-front-backend.pem`) |
| `EC2_HOST_BACKEND` | IP **privada** del EC2 backend (se llega por el bastion) |
| `BASTION_HOST` | IP pública del frontend, usado como bastion para el salto SSH |
| `DB_HOST` | IP privada de la EC2 de datos (MySQL) |
| `EC2_USER` | `ubuntu` |
| `EC2_SSH_PRIVATE_KEY` | Clave privada SSH (`nuevo-front-backend.pem`) |
| `EC2_HOST_BACKEND` | IP pública del EC2 backend |
| `MYSQL_ROOT_PASSWORD` | Password root de MySQL |
| `MYSQL_USER` | Usuario de aplicación (`appuser`) |
| `MYSQL_PASSWORD` | Password del usuario de aplicación |

Los secrets se inyectan al shell remoto vía el parámetro `envs` de la action, y
`docker compose` los sustituye en las variables `${...}` del `docker-compose.yml`.
Nunca se escriben en el repositorio.

---

## Requisitos en la instancia EC2

- Docker con el **plugin Compose v2** (`docker compose version`).
  Si falta: `sudo apt-get install -y docker-compose-plugin`.
- ~2 GB de swap (la t3.micro tiene 1 GB de RAM) y un disco EBS de al menos 20 GB.
- Security Group que permita 8080/8081 **solo** desde el SG del frontend, y 22 para el deploy.
