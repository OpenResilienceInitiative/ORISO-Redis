FROM redis:7-alpine

# Note: In Kubernetes, redis.conf is provided via ConfigMap
# This Dockerfile builds the base image without baked-in configs

# Expose Redis port
EXPOSE 6379

# Health check
HEALTHCHECK --interval=10s --timeout=3s --start-period=30s --retries=3 \
  CMD redis-cli --no-auth-warning -a ${REDIS_PASSWORD:-} ping || exit 1

# Use the default entrypoint from base image
# The redis.conf will be mounted via ConfigMap in Kubernetes
# Command: redis-server /etc/redis/redis.conf


