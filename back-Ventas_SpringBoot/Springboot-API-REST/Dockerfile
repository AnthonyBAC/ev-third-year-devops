# ─────────────────────────────────────────────
# ETAPA 1: BUILD
# Maven + Java 17 para compilar y empaquetar el .jar
# ─────────────────────────────────────────────
FROM maven:3.9-eclipse-temurin-17-alpine AS builder

WORKDIR /app

# Primero solo el pom.xml → cachea las dependencias de Maven
COPY pom.xml .
RUN mvn dependency:go-offline -B

# Luego el código fuente
COPY src ./src

# Compila y empaqueta
# Los tests de este proyecto usan H2 en memoria, pero los corremos
# en el pipeline CI/CD, no aquí, para mantener el build rápido
RUN mvn package -DskipTests -B

# ─────────────────────────────────────────────
# ETAPA 2: RUNTIME
# Solo el .jar, con JRE liviano y usuario no root
# ─────────────────────────────────────────────
FROM eclipse-temurin:17-jre-alpine AS runtime

WORKDIR /app

# Usuario no root para mayor seguridad
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Copiamos solo el .jar desde la etapa builder
COPY --from=builder /app/target/*.jar app.jar

RUN chown appuser:appgroup app.jar

USER appuser

# Puerto por defecto de Spring Boot
EXPOSE 8080

# Flags de JVM optimizadas para contenedores
ENTRYPOINT ["java", "-XX:+UseContainerSupport", "-XX:MaxRAMPercentage=75.0", "-jar", "app.jar"]
