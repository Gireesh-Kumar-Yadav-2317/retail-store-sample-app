
# --------------------------------------------------
# Retail Store Checkout - Production Multi-Stage Dockerfile
# --------------------------------------------------

# ==================================================
# Stage 1: Build
# ==================================================
FROM node:20-alpine AS builder

WORKDIR /build

ENV NODE_ENV=development

# Copy dependency manifests and local Yarn configuration
COPY src/checkout/package.json \
     src/checkout/yarn.lock \
     src/checkout/.yarnrc.yml \
     ./

# Copy the repository-pinned Yarn 4.11.0 release
COPY src/checkout/.yarn/ .yarn/

# Install dependencies using the checked-in Yarn binary
RUN node .yarn/releases/yarn-4.11.0.cjs install --immutable

# Copy application source
COPY src/checkout/ .

# Build NestJS application
RUN node .yarn/releases/yarn-4.11.0.cjs build

# ==================================================
# Stage 2: Production Dependencies
# ==================================================
FROM builder AS production-dependencies

# Install only production dependencies
RUN node .yarn/releases/yarn-4.11.0.cjs workspaces focus --all --production

# ==================================================
# Stage 3: Runtime
# ==================================================
FROM public.ecr.aws/amazonlinux/amazonlinux:2023 AS runtime

LABEL org.opencontainers.image.title="Retail Store Checkout Service"
LABEL org.opencontainers.image.description="Retail Store Checkout Service"

# Apply security updates, install Node.js and create non-root user
RUN dnf --releasever=latest upgrade -y \
    && dnf --setopt=install_weak_deps=False install -y \
       nodejs20 \
       shadow-utils \
    && dnf clean all \
    && rm -rf /var/cache/dnf \
    && alternatives --install /usr/bin/node node /usr/bin/node-20 90 \
    && useradd --system \
       --uid 10001 \
       --create-home \
       --shell /sbin/nologin \
       appuser

WORKDIR /app

# Copy production dependencies only
COPY --from=production-dependencies --chown=10001:10001 \
    /build/node_modules ./node_modules

# Copy compiled application
COPY --from=builder --chown=10001:10001 \
    /build/dist ./dist

ENV NODE_ENV=production

EXPOSE 8080

USER 10001:10001

ENTRYPOINT ["node", "dist/main.js"]
