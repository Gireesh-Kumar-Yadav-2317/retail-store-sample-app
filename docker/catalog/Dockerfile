
# --------------------------------------------------
# Catalog Service - Production Multi-Stage Dockerfile
# --------------------------------------------------

# Stage 1: Build
FROM golang:1.26 AS builder

WORKDIR /build

ENV GOPROXY=https://proxy.golang.org,direct

COPY src/catalog/go.mod src/catalog/go.sum ./

RUN go mod download

COPY src/catalog/ .

RUN CGO_ENABLED=0 \
    GOOS=linux \
    go build \
    -trimpath \
    -ldflags="-s -w" \
    -o /build/main .

# Stage 2: Runtime
FROM public.ecr.aws/amazonlinux/amazonlinux:2023 AS runtime

LABEL org.opencontainers.image.title="Retail Store Catalog Service"
LABEL org.opencontainers.image.description="Retail Store Catalog Service"

RUN dnf --releasever=latest upgrade -y \
    && dnf --setopt=install_weak_deps=False install -y shadow-utils \
    && dnf clean all \
    && rm -rf /var/cache/dnf \
    && useradd --system \
       --uid 10001 \
       --create-home \
       --shell /sbin/nologin \
       appuser

WORKDIR /app

COPY --from=builder --chown=10001:10001 \
    /build/main \
    /app/main

ENV GIN_MODE=release

EXPOSE 8080

USER 10001:10001

ENTRYPOINT ["/app/main"]
