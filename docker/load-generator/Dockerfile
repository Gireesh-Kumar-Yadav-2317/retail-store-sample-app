# --------------------------------------------------
# Load Generator - Production Dockerfile
# --------------------------------------------------

FROM public.ecr.aws/amazonlinux/amazonlinux:2023-minimal AS runtime

LABEL org.opencontainers.image.title="Retail Store Load Generator"
LABEL org.opencontainers.image.description="Artillery-based load testing service"

# Apply security updates
RUN microdnf --releasever=latest upgrade -y \
    && microdnf clean all

WORKDIR /artillery

# Copy load testing configuration
COPY --chown=10001:10001 src/load-generator/helpers.js ./helpers.js
COPY --chown=10001:10001 src/load-generator/scenario.yml ./scenario.yml

# Run as non-root
USER 10001:10001