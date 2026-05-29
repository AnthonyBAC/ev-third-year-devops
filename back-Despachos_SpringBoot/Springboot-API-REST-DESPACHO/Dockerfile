# ─────────────────────────────────────────────
# ETAPA 1: BUILD
# Usamos Maven + Java 17 para compilar el proyecto y generar el .jar
# ─────────────────────────────────────────────
FROM maven:3.9-eclipse-temurin-17-alpine AS builder

WORKDIR /app

# Copiamos primero solo el pom.xml para aprovechar el cache de Docker:
# si las dependencias no cambiaron, Maven no las vuelve a descargar
COPY pom.xml .
RUN mvn dependency:go-offline -B

# Ahora copiamos el código fuente
COPY src ./src

# Compilamos y empaquetamos, saltando los tests
# (los tests se corren en el pipeline CI/CD, no en el build de imagen)
RUN mvn package -DskipTests -B

# ─────────────────────────────────────────────
# ETAPA 2: RUNTIME
# Solo copiamos el .jar generado, sin Maven ni código fuente
# Usamos JRE (solo ejecución) en vez de JDK (desarrollo) → imagen más liviana
# ─────────────────────────────────────────────
FROM eclipse-temurin:17-jre-alpine AS runtime

WORKDIR /app

# Creamos usuario no root
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Copiamos el .jar desde la etapa de build
# El * en el nombre cubre cualquier versión del artifact
COPY --from=builder /app/target/*.jar app.jar

# Le damos propiedad del jar al usuario no root
RUN chown appuser:appgroup app.jar

# Cambiamos al usuario no root
USER appuser

# Puerto que expone este backend (definido en application.properties)
EXPOSE 8081

# Opciones de JVM recomendadas para contenedores:
# -XX:+UseContainerSupport → detecta los límites de CPU/RAM del contenedor
# -XX:MaxRAMPercentage=75  → usa máximo el 75% de la RAM disponible
ENTRYPOINT ["java", "-XX:+UseContainerSupport", "-XX:MaxRAMPercentage=75.0", "-jar", "app.jar"]
