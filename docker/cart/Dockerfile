# --------------------------------------------------
# Cart Service - Production Multi-Stage Dockerfile
# --------------------------------------------------

# Stage 1: Build
FROM amazoncorretto:21 AS builder

WORKDIR /build

# Install Maven Wrapper dependencies
RUN dnf install -y tar gzip \
    && dnf clean all

# Copy Maven project files
COPY src/cart/.mvn/ .mvn/
COPY src/cart/mvnw .
COPY src/cart/pom.xml .

# Download dependencies
RUN chmod +x mvnw \
    && ./mvnw --batch-mode --no-transfer-progress \
       dependency:go-offline

# Copy application source
COPY src/cart/src/ src/

# Package application
RUN ./mvnw --batch-mode --no-transfer-progress \
    clean package -DskipTests


# Stage 2: Runtime
FROM amazoncorretto:21 AS runtime

LABEL org.opencontainers.image.title="Retail Store Cart Service"
LABEL org.opencontainers.image.description="Retail Store Cart Service"

# Create non-root application user
RUN dnf install -y shadow-utils \
    && dnf clean all \
    && useradd --system \
       --uid 10001 \
       --create-home \
       --shell /sbin/nologin \
       appuser

WORKDIR /app

# Copy application artifact
COPY --from=builder --chown=10001:10001 \
    /build/target/carts-0.0.1-SNAPSHOT.jar \
    /app/app.jar

ENV SPRING_PROFILES_ACTIVE=prod
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75.0 -XX:+ExitOnOutOfMemoryError"

EXPOSE 8080

USER 10001:10001

ENTRYPOINT ["java", "-jar", "/app/app.jar"]