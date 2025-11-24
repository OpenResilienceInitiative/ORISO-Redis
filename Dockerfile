FROM redis:7-alpine

# Copy custom Redis configuration if provided
# Note: In Kubernetes, this is typically provided via ConfigMap
# This Dockerfile allows for custom builds with baked-in configs if needed
COPY redis.conf /etc/redis/redis.conf 2>/dev/null || true

# Expose Redis port
EXPOSE 6379

# Health check
HEALTHCHECK --interval=10s --timeout=3s --start-period=30s --retries=3 \
  CMD redis-cli --no-auth-warning -a ${REDIS_PASSWORD:-} ping || exit 1

# Use the default entrypoint from base image
# The redis.conf will be mounted via ConfigMap in Kubernetes
# Command: redis-server /etc/redis/redis.conf

