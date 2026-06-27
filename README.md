# Backend — EV. Devops

Microservicios backend de la solución: dos APIs REST en **Spring Boot** (Ventas y
Despachos), contenerizadas con Docker y desplegadas mediante GitHub Actions.
Las imágenes se publican en **Amazon ECR** y los servicios corren como
**tasks de ECS Fargate** en una subred privada. La base de datos **MySQL 8**
corre en su propia EC2 (tier de datos), siguiendo una arquitectura **3-tier**.

## Repositorios del proyecto (3-tier)

- **Frontend:** https://github.com/AnthonyBAC/ev-third-year-devops-frontend
- **Backend:** https://github.com/AnthonyBAC/ev-third-year-devops-backend
- **Datos (DB):** https://github.com/AnthonyBAC/ev-third-year-devops-db

---

## Arquitectura (3-tier)

![Diagrama de arquitectura](docs/arquitectura.png)

```
ECS Fargate Frontend (pública)   ECS Fargate Backend (privada)   EC2 DB (privada)
┌──────────────┐                 ┌──────────────────┐            ┌──────────────┐
│  nginx :8080 │  /api/v1/* ───► │  back-ventas:8080│   3306     │  MySQL       │
│  (bastion)   │                 │  back-despachos  │ ─────────► │  + volumen   │
└──────────────┘                 │      :8081       │            │  mysql-data  │
     ▲ único público             └──────────────────┘            └──────────────┘
                                   ▲ deploy vía SSH proxy (bastion)
```

- **back-ventas**: API REST de ventas, puerto `8080`, base `db_ventas`.
- **back-despachos**: API REST de despachos, puerto `8081`, base `db_despachos`.
- **MySQL**: en EC2 dedicada (privada); consumida por `${DB_HOST}:3306`.
- El backend corre en **subred privada** (sin IP pública); el deploy entra vía SSH
usando el frontend como **bastion**, y el backend sale a internet por un **NAT Gateway**.
- Solo el frontend es accesible desde Internet. El acceso a `8080/8081` (backend)
está restringido por Security Groups.

---

## Estructura del repositorio

```
.
├── back-Ventas_SpringBoot/Springboot-API-REST/               # código + Dockerfile API Ventas
├── back-Despachos_SpringBoot/Springboot-API-REST-DESPACHO/   # código + Dockerfile API Despachos
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
2. **Etapa runtime**: `eclipse-temurin:17-jre-alpine` (solo JRE, imagen ~180MB vs ~600MB con JDK).
Se crea un usuario **no root** (`appuser`) y se ejecuta el `.jar` con él, aplicando
el principio de **mínimo privilegio**.

Flags de JVM para contenedor: `-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0`.
En el deploy se acotan con `JAVA_TOOL_OPTIONS=-Xmx256m -Xms128m -XX:+UseSerialGC`.

---

## Persistencia de datos

La persistencia vive en la **EC2 del tier de datos**. MySQL usa un **named volume**
(`mysql-data`) montado en `/var/lib/mysql`.

| Aspecto            | Decisión                                                            |
| ------------------ | ------------------------------------------------------------------- |
| Tipo de volumen    | **Named volume** (`mysql-data`)                                     |
| Ventaja            | Sobrevive a `docker compose down`, portable, no depende de rutas del host |

El script `init-db.sql` solo corre cuando el volumen está vacío, creando
`db_ventas` / `db_despachos` y otorgando permisos a `appuser`.

---

## Correr en local

```bash
cp .env.example .env      # completa las claves MySQL y DB_HOST
docker compose up -d --build
docker compose ps
```

- API Ventas: http://localhost:8080
- API Despachos: http://localhost:8081

---

## Pipeline CI/CD (GitHub Actions)

Archivo: `.github/workflows/deploy.yml`. Se dispara con **push a la rama `deploy`**.

```
push a deploy
   │
   ├─ build-and-push  (matriz: back-ventas + back-despachos en paralelo)
   │     1. checkout
   │     2. Configurar credenciales AWS
   │     3. Login en Amazon ECR
   │     4. build + push de cada imagen (tags :latest y :<sha>)
   │
   └─ deploy-backend  (needs: build-and-push)
         1. checkout
         2. scp de docker-compose.yml al EC2 backend (vía bastion frontend)
         3. ssh: login ECR + docker compose pull + docker compose up -d
```

### Secrets requeridos (Settings → Secrets and variables → Actions)

| Secret                  | Descripción                                              |
| ----------------------- | -------------------------------------------------------- |
| `AWS_ACCESS_KEY_ID`     | Access Key del Learner Lab (actualizar cada sesión)      |
| `AWS_SECRET_ACCESS_KEY` | Secret Key del Learner Lab (actualizar cada sesión)      |
| `AWS_SESSION_TOKEN`     | Session Token del Learner Lab (actualizar cada sesión)   |
| `EC2_USER`              | `ubuntu`                                                 |
| `EC2_SSH_PRIVATE_KEY`   | Clave privada SSH                                        |
| `BASTION_HOST`          | IP pública del frontend (bastion para el salto SSH)      |
| `EC2_HOST_BACKEND`      | IP privada del EC2 backend                               |
| `DB_HOST`               | IP privada de la EC2 de datos (MySQL)                    |
| `MYSQL_USER`            | Usuario de aplicación (`appuser`)                        |
| `MYSQL_PASSWORD`        | Password del usuario de aplicación                       |

> **Nota:** Las credenciales AWS del Learner Lab expiran cada ~4 horas.
> En producción se usaría un IAM Role asignado directamente a las EC2.

---

## Registro de imágenes — Amazon ECR

Las imágenes se publican en:
```
211125593312.dkr.ecr.us-east-1.amazonaws.com/back-ventas:latest
211125593312.dkr.ecr.us-east-1.amazonaws.com/back-ventas:<sha>
211125593312.dkr.ecr.us-east-1.amazonaws.com/back-despachos:latest
211125593312.dkr.ecr.us-east-1.amazonaws.com/back-despachos:<sha>
```

---

## Orquestación — ECS Fargate

Los backends corren como **ECS Services** en el cluster `devops-ecs`:

| Parámetro       | back-ventas          | back-despachos       |
| --------------- | -------------------- | -------------------- |
| Service         | `svc-back-ventas`    | `svc-back-despachos` |
| Launch type     | Fargate              | Fargate              |
| CPU / Memory    | 0.5 vCPU / 1 GB      | 0.5 vCPU / 1 GB      |
| Subred          | back-subnet (privada)| back-subnet (privada)|
| Security Group  | backend              | backend              |
| Desired tasks   | 1                    | 1                    |

ECS reinicia los tasks automáticamente si fallan, sin intervención manual.

---

## Requisitos en la instancia EC2 backend

- Docker con el **plugin Compose v2** (`docker compose version`).
- AWS CLI instalado (`aws --version`) para login a ECR.
- Security Group que permita 8080/8081 **solo** desde el SG del frontend,
y 22 para el deploy vía bastion.
