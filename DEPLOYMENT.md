# ORISO-Redis Deployment Guide

This guide provides detailed instructions for deploying Redis with Redis Commander GUI and monitoring for the ORISO platform.

## 📋 Prerequisites

- Kubernetes cluster (k3s)
- kubectl configured
- Persistent storage (optional, for data persistence)

## 🚀 Deployment Options

### Option 1: Deploy to Kubernetes (Recommended - Current Setup)

#### Step 1: Apply Kubernetes Configurations

```bash
# Navigate to ORISO-Redis directory
cd /home/caritas/Desktop/online-beratung/caritas-workspace/ORISO-Redis

# Apply services first
kubectl apply -f redis-services.yaml

# Apply deployments
kubectl apply -f redis-deployments.yaml
```

#### Step 2: Verify Deployment

```bash
# Check all Redis components
kubectl get all -n caritas | grep redis

# Expected output:
# - redis pod: Running
# - redis-commander pod: Running
# - redis-exporter pod: Running
# - Services for each component

# Check logs
kubectl logs -n caritas deployment/redis
kubectl logs -n caritas deployment/redis-commander
kubectl logs -n caritas deployment/redis-exporter
```

#### Step 3: Test Access

```bash
# Test Redis CLI
kubectl exec -it -n caritas deployment/redis -- redis-cli ping
# Expected: PONG

# Test Redis Commander (open in browser)
# http://91.99.219.182:9021

# Test Redis Exporter metrics
curl http://91.99.219.182:9020/metrics | head -20
```

### Option 2: Deploy with Docker Compose

```yaml
version: '3.8'

services:
  redis:
    image: redis:latest
    container_name: redis
    ports:
      - "6379:6379"
    volumes:
      - redis-data:/data
    command: redis-server --appendonly yes
    networks:
      - oriso-network

  redis-commander:
    image: rediscommander/redis-commander:latest
    container_name: redis-commander
    ports:
      - "9021:8081"
    environment:
      - REDIS_HOSTS=local:redis:6379
    depends_on:
      - redis
    networks:
      - oriso-network

  redis-exporter:
    image: oliver006/redis_exporter:latest
    container_name: redis-exporter
    ports:
      - "9020:9121"
    environment:
      - REDIS_ADDR=redis:6379
    depends_on:
      - redis
    networks:
      - oriso-network

volumes:
  redis-data:

networks:
  oriso-network:
    driver: bridge
```

```bash
# Save as docker-compose.yml and run
docker-compose up -d

# Verify
docker-compose ps
```

### Option 3: Deploy Standalone Redis

```bash
# Basic Redis deployment
kubectl create deployment redis --image=redis:latest -n caritas

# Expose as service
kubectl expose deployment redis --port=6379 --type=ClusterIP -n caritas

# Add Redis Commander
kubectl create deployment redis-commander \
  --image=rediscommander/redis-commander:latest -n caritas

kubectl expose deployment redis-commander \
  --port=8081 --type=LoadBalancer --name=redis-commander -n caritas

# Set Redis connection for Commander
kubectl set env deployment/redis-commander \
  REDIS_HOSTS=redis:redis.caritas.svc.cluster.local:6379 -n caritas
```

## 🔧 Configuration

### Redis Configuration

Create a ConfigMap for custom redis.conf:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: redis-config
  namespace: caritas
data:
  redis.conf: |
    # Network
    bind 0.0.0.0
    protected-mode no
    port 6379
    
    # Memory
    maxmemory 2gb
    maxmemory-policy allkeys-lru
    
    # Persistence
    save 900 1
    save 300 10
    save 60 10000
    appendonly yes
    appendfsync everysec
    
    # Performance
    timeout 300
    tcp-keepalive 60
    
    # Limits
    maxclients 10000
```

```bash
# Apply config
kubectl apply -f redis-config.yaml

# Update deployment to use config
kubectl set volume deployment/redis \
  --add --name=redis-config \
  --type=configmap \
  --configmap-name=redis-config \
  --mount-path=/usr/local/etc/redis/redis.conf \
  --sub-path=redis.conf -n caritas
```

### Redis Commander Configuration

Environment variables for Redis Commander:

```yaml
env:
- name: REDIS_HOSTS
  value: "oriso:redis.caritas.svc.cluster.local:6379"
- name: HTTP_USER
  value: "admin"  # Optional: Basic auth username
- name: HTTP_PASSWORD
  value: "password"  # Optional: Basic auth password
- name: PORT
  value: "8081"
```

### Redis Exporter Configuration

Environment variables for Redis Exporter:

```yaml
env:
- name: REDIS_ADDR
  value: "redis.caritas.svc.cluster.local:6379"
- name: REDIS_PASSWORD
  value: ""  # If Redis has password
- name: REDIS_EXPORTER_LOG_FORMAT
  value: "json"
```

## 💾 Persistent Storage

### Using Persistent Volume Claim (PVC)

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: redis-pvc
  namespace: caritas
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: local-path
---
# Update deployment to use PVC
spec:
  template:
    spec:
      containers:
      - name: redis
        volumeMounts:
        - name: redis-storage
          mountPath: /data
      volumes:
      - name: redis-storage
        persistentVolumeClaim:
          claimName: redis-pvc
```

```bash
# Apply PVC
kubectl apply -f redis-pvc.yaml

# Verify
kubectl get pvc -n caritas | grep redis
```

## 📊 Monitoring Setup

### Integrate with Prometheus

```yaml
apiVersion: v1
kind: Service
metadata:
  name: redis-exporter-metrics
  namespace: caritas
  labels:
    app: redis-exporter
spec:
  type: LoadBalancer
  selector:
    app: redis-exporter
  ports:
  - port: 9121
    targetPort: 9121
    protocol: TCP
    name: metrics
```

### Prometheus Scrape Configuration

```yaml
scrape_configs:
  - job_name: 'redis'
    static_configs:
      - targets: ['redis-exporter.caritas.svc.cluster.local:9121']
        labels:
          service: 'redis'
          environment: 'production'
```

### SignOZ Integration

Redis metrics are automatically discovered by SignOZ OTEL collector when running in the same namespace.

## 🔐 Security Configuration

### Enable Redis Authentication

```yaml
# Create secret for Redis password
apiVersion: v1
kind: Secret
metadata:
  name: redis-password
  namespace: caritas
type: Opaque
stringData:
  password: "your-secure-password"
```

```bash
# Apply secret
kubectl apply -f redis-password-secret.yaml

# Update Redis deployment
kubectl set env deployment/redis \
  --from=secret/redis-password \
  --keys=password -n caritas

# Update Redis Commander
kubectl set env deployment/redis-commander \
  REDIS_HOSTS="oriso:redis.caritas.svc.cluster.local:6379:0:your-secure-password" \
  -n caritas

# Update Redis Exporter
kubectl set env deployment/redis-exporter \
  REDIS_PASSWORD="your-secure-password" -n caritas
```

### Enable TLS/SSL

```yaml
# Create TLS secret
kubectl create secret tls redis-tls \
  --cert=path/to/cert.pem \
  --key=path/to/key.pem \
  -n caritas

# Update Redis deployment
spec:
  template:
    spec:
      containers:
      - name: redis
        command:
          - redis-server
          - --tls-port
          - "6380"
          - --port
          - "0"
          - --tls-cert-file
          - /tls/tls.crt
          - --tls-key-file
          - /tls/tls.key
        volumeMounts:
        - name: tls
          mountPath: /tls
      volumes:
      - name: tls
        secret:
          secretName: redis-tls
```

## 📈 Scaling

### Vertical Scaling (More Resources)

```yaml
# Update deployment with resource limits
spec:
  template:
    spec:
      containers:
      - name: redis
        resources:
          requests:
            memory: "1Gi"
            cpu: "500m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
```

```bash
kubectl apply -f redis-deployment.yaml
```

### Horizontal Scaling (Redis Cluster)

For production environments with high availability:

```bash
# Deploy Redis Sentinel or Redis Cluster
# See Redis documentation for cluster setup:
# https://redis.io/topics/cluster-tutorial
```

## ✅ Post-Deployment Verification

### 1. Health Checks

```bash
# Redis health
kubectl exec -it -n caritas deployment/redis -- redis-cli ping

# Redis Commander health
curl -I http://91.99.219.182:9021

# Redis Exporter health
curl http://91.99.219.182:9020/metrics | grep redis_up
```

### 2. Performance Test

```bash
# Benchmark Redis
kubectl exec -it -n caritas deployment/redis -- \
  redis-benchmark -q -n 100000
```

### 3. Data Persistence Test

```bash
# Write test data
kubectl exec -it -n caritas deployment/redis -- \
  redis-cli SET test-key "test-value"

# Restart Redis
kubectl rollout restart deployment/redis -n caritas

# Verify data persisted
kubectl exec -it -n caritas deployment/redis -- \
  redis-cli GET test-key
# Expected: "test-value"
```

## 🔄 Updates and Maintenance

### Update Redis Version

```bash
# Update image in deployment
kubectl set image deployment/redis \
  redis=redis:7.2 -n caritas

# Monitor rollout
kubectl rollout status deployment/redis -n caritas

# Verify new version
kubectl exec -it -n caritas deployment/redis -- redis-cli INFO server | grep redis_version
```

### Backup and Restore

```bash
# Create backup
kubectl exec -it -n caritas deployment/redis -- redis-cli BGSAVE

# Copy RDB file
kubectl cp caritas/<redis-pod>:/data/dump.rdb ./dump.rdb

# Restore (copy RDB to new instance)
kubectl cp ./dump.rdb caritas/<new-redis-pod>:/data/dump.rdb

# Restart Redis
kubectl rollout restart deployment/redis -n caritas
```

## 🐛 Troubleshooting

### Redis Not Starting

```bash
# Check pod events
kubectl describe pod -n caritas <redis-pod>

# Check logs
kubectl logs -n caritas <redis-pod>

# Common issues:
# - Permission issues with /data directory
# - Invalid redis.conf configuration
# - Port already in use
```

### Redis Commander Can't Connect

```bash
# Check Redis Commander logs
kubectl logs -n caritas deployment/redis-commander

# Verify Redis connection
kubectl exec -it -n caritas deployment/redis-commander -- \
  env | grep REDIS_HOSTS

# Test Redis connectivity from Commander pod
kubectl exec -it -n caritas deployment/redis-commander -- \
  nc -zv redis 6379
```

### High Memory Usage

```bash
# Check memory usage
kubectl exec -it -n caritas deployment/redis -- \
  redis-cli INFO memory

# Find large keys
kubectl exec -it -n caritas deployment/redis -- \
  redis-cli --bigkeys

# Clear specific keys
kubectl exec -it -n caritas deployment/redis -- \
  redis-cli DEL large-key-name
```

## 📝 Checklist

### Pre-Deployment
- [ ] Kubernetes cluster is ready
- [ ] kubectl is configured
- [ ] Namespace `caritas` exists
- [ ] Storage class is available (for persistence)

### Deployment
- [ ] Redis deployed and running
- [ ] Redis Commander deployed and accessible
- [ ] Redis Exporter deployed and exporting metrics
- [ ] Services exposed correctly
- [ ] Persistent storage configured (if needed)

### Post-Deployment
- [ ] Health checks pass
- [ ] Redis Commander accessible
- [ ] Metrics visible in monitoring system
- [ ] Data persistence verified
- [ ] Backup strategy in place
- [ ] Documentation updated

### Security (Production)
- [ ] Redis password configured
- [ ] TLS/SSL enabled
- [ ] Network policies applied
- [ ] Access controls configured
- [ ] Monitoring and alerts set up

---

**Last Updated**: 2025-10-31  
**Part of the ORISO Platform**

