
# --------------------------------------------------
# Retail Store UI - Production Multi-Stage Dockerfile
# --------------------------------------------------

# ==================================================
# Stage 1: Build
# ==================================================
FROM amazoncorretto:21 AS builder

WORKDIR /build

# Install tools required by Maven Wrapper
RUN dnf install -y tar gzip \
    && dnf clean all

# Copy Maven configuration and project descriptor first
COPY src/ui/.mvn/ .mvn/
COPY src/ui/mvnw src/ui/pom.xml ./

# Make Maven Wrapper executable
RUN chmod +x mvnw

# Download and cache Maven dependencies
RUN --mount=type=cache,target=/root/.m2 \
    ./mvnw --batch-mode --no-transfer-progress \
    dependency:go-offline

# Copy application source code
COPY src/ui/src/ src/

# Build application
RUN --mount=type=cache,target=/root/.m2 \
    ./mvnw --batch-mode --no-transfer-progress \
    clean package -DskipTests


# ==================================================
# Stage 2: Runtime
# ==================================================
FROM amazoncorretto:21 AS runtime

LABEL org.opencontainers.image.title="Retail Store UI"
LABEL org.opencontainers.image.description="Retail Store UI service"

# Create non-root application user
RUN dnf install -y shadow-utils \
    && dnf clean all \
    && useradd --system \
       --uid 10001 \
       --create-home \
       --shell /sbin/nologin \
       appuser

WORKDIR /app

# Copy only the executable JAR
COPY --from=builder --chown=10001:10001 \
    /build/target/ui-0.0.1-SNAPSHOT.jar \
    /app/app.jar

# JVM container configuration
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75.0 -XX:+ExitOnOutOfMemoryError"

EXPOSE 8080

# Run application as non-root
USER 10001:10001

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
