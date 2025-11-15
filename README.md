# ORISO-Redis

This repository contains the Redis cache configuration, GUI management tools, and monitoring setup for the ORISO (Online Beratung) platform.

## 📋 Overview

**Redis** is the in-memory caching layer for the ORISO platform, providing:
- Session storage and management
- Caching for frequently accessed data
- Real-time data synchronization
- Queue management for background jobs
- Performance optimization across services

## 🚀 Current Configuration

### Access Information

#### Redis Server
- **Internal Service**: `redis.caritas.svc.cluster.local:6379`
- **ClusterIP**: `10.43.113.3:6379`
- **Namespace**: `caritas`
- **Database**: DB 0 (default)

#### Redis Commander (Web GUI)
- **URL**: `http://91.99.219.182:9021`
- **Type**: LoadBalancer
- **ClusterIP**: `10.43.155.175`
- **Port**: 9021 (NodePort: 30208)
- **Features**:
  - Browse all keys
  - View key values and TTL
  - Execute Redis commands
  - Real-time monitoring
  - Key management (add, edit, delete)

#### Redis Exporter (Metrics)
- **Metrics URL**: `http://91.99.219.182:9020/metrics`
- **Type**: LoadBalancer
- **ClusterIP**: `10.43.159.120`
- **Port**: 9020 (NodePort: 30117)
- **Prometheus Format**: Yes
- **Monitored by**: SignOZ

## 📊 Components

### 1. Redis Server
- **Image**: `redis:latest`
- **Port**: 6379
- **Persistence**: Enabled (RDB + AOF)
- **Status**: ✅ Running (9 days uptime)

### 2. Redis Commander
- **Image**: `rediscommander/redis-commander:latest`
- **Port**: 9021
- **Status**: ✅ Running
- **Purpose**: Web-based Redis management GUI

### 3. Redis Exporter
- **Image**: `oliver006/redis_exporter:latest`
- **Port**: 9121 (internal), 9020 (external)
- **Status**: ✅ Running
- **Purpose**: Prometheus metrics for Redis

### 4. RedisInsight (Optional)
- **Status**: ❌ CrashLoopBackOff (not required)
- **Note**: Redis Commander is preferred GUI

## 📁 Repository Contents

```
ORISO-Redis/
├── README.md                     # This file
├── DEPLOYMENT.md                 # Deployment guide
├── STATUS.md                     # Current status
├── redis-deployments.yaml        # Kubernetes deployments
├── redis-services.yaml           # Kubernetes services
├── monitoring/
│   ├── grafana-dashboard.json   # Grafana dashboard
│   └── alerts.yaml              # Alert rules
└── backup/
    └── redis-backup.sh          # Backup script
```

## 🎯 Quick Access

### Redis Commander GUI

1. **Open in browser**: `http://91.99.219.182:9021`
2. **Select Connection**: Should auto-connect to Redis server
3. **Features**:
   - Browse keys by pattern
   - View key details
   - Edit values
   - Set TTL
   - Execute commands in CLI

### Redis Metrics (Prometheus Format)

```bash
# View all metrics
curl http://91.99.219.182:9020/metrics

# Key metrics to watch:
# - redis_up: Redis availability (1 = up, 0 = down)
# - redis_connected_clients: Number of connected clients
# - redis_used_memory_bytes: Memory usage
# - redis_commands_processed_total: Total commands processed
# - redis_keyspace_hits_total: Cache hit rate
# - redis_keyspace_misses_total: Cache miss rate
```

### CLI Access

```bash
# Via kubectl
kubectl exec -it -n caritas deployment/redis -- redis-cli

# Test connection
kubectl exec -it -n caritas deployment/redis -- redis-cli ping
# Expected: PONG

# View info
kubectl exec -it -n caritas deployment/redis -- redis-cli INFO

# View all keys (use carefully in production!)
kubectl exec -it -n caritas deployment/redis -- redis-cli KEYS '*'
```

## 🔧 Integration with ORISO Services

### Service Configuration

Most ORISO services use Redis for caching. Example Spring Boot configuration:

```yaml
spring:
  redis:
    host: redis.caritas.svc.cluster.local
    port: 6379
    database: 0
    timeout: 2000ms
  cache:
    type: redis
    redis:
      time-to-live: 600000  # 10 minutes
```

### Session Storage

Redis is used for storing user sessions:

```yaml
spring:
  session:
    store-type: redis
    redis:
      flush-mode: on-save
      namespace: spring:session
```

## 📈 Monitoring

### SignOZ Integration

Redis metrics are automatically sent to SignOZ via Redis Exporter:
- **Service Name**: `redis`
- **Metrics Endpoint**: `http://10.43.159.120:9020/metrics`
- **Scrape Interval**: 10s
- **Visualize**: SignOZ Dashboard at `http://91.99.219.182:3001`

### Key Metrics to Monitor

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| `redis_up` | Redis availability | 0 (critical) |
| `redis_used_memory_bytes` | Memory usage | > 80% (warning) |
| `redis_connected_clients` | Active connections | > 100 (warning) |
| `redis_keyspace_hits_total` | Cache hits | Monitor ratio |
| `redis_keyspace_misses_total` | Cache misses | Monitor ratio |
| `redis_evicted_keys_total` | Evicted keys | > 0 (warning) |
| `redis_commands_duration_seconds` | Command latency | > 1s (warning) |

### Health Check

```bash
# Simple health check
curl -s http://10.43.113.3:6379 && echo "Redis is up" || echo "Redis is down"

# Detailed health check
kubectl exec -it -n caritas deployment/redis -- redis-cli --stat

# Check memory usage
kubectl exec -it -n caritas deployment/redis -- redis-cli INFO memory
```

## 🔐 Security

### Current Configuration
- **Authentication**: No password (internal cluster only)
- **Network**: ClusterIP (not exposed externally, except GUI and metrics)
- **Access Control**: Kubernetes RBAC
- **Encryption**: Not enabled (internal traffic)

### Production Recommendations
1. **Enable AUTH**: Set `requirepass` in redis.conf
2. **Rename dangerous commands**: Rename FLUSHALL, FLUSHDB, KEYS
3. **Enable TLS**: For encrypted communication
4. **Limit connections**: Set `maxclients` in redis.conf
5. **Use ACLs**: Redis 6+ ACL system

## 🛠️ Common Operations

### View Cache Hit Rate
```bash
kubectl exec -it -n caritas deployment/redis -- redis-cli INFO stats | grep keyspace
```

### Clear Specific Keys
```bash
# Clear sessions
kubectl exec -it -n caritas deployment/redis -- redis-cli KEYS "spring:session:*" | xargs redis-cli DEL

# Clear all (DANGEROUS!)
kubectl exec -it -n caritas deployment/redis -- redis-cli FLUSHALL
```

### Monitor Real-Time
```bash
# Monitor all commands
kubectl exec -it -n caritas deployment/redis -- redis-cli MONITOR

# Real-time stats
kubectl exec -it -n caritas deployment/redis -- redis-cli --stat
```

### Backup Redis Data
```bash
# Trigger RDB snapshot
kubectl exec -it -n caritas deployment/redis -- redis-cli BGSAVE

# Or use the backup script
./backup/redis-backup.sh
```

## 📊 Performance Tuning

### Memory Optimization
```conf
# redis.conf
maxmemory 2gb
maxmemory-policy allkeys-lru
```

### Persistence Configuration
```conf
# RDB (Point-in-time snapshots)
save 900 1
save 300 10
save 60 10000

# AOF (Append-only file)
appendonly yes
appendfsync everysec
```

## 🐛 Troubleshooting

### Issue: High Memory Usage
```bash
# Check memory info
kubectl exec -it -n caritas deployment/redis -- redis-cli INFO memory

# Find large keys
kubectl exec -it -n caritas deployment/redis -- redis-cli --bigkeys

# Solution: Adjust maxmemory-policy or clear old data
```

### Issue: Slow Queries
```bash
# Check slow log
kubectl exec -it -n caritas deployment/redis -- redis-cli SLOWLOG GET 10

# Solution: Optimize queries, add indexes, or increase resources
```

### Issue: Connection Refused
```bash
# Check pod status
kubectl get pods -n caritas | grep redis

# Check service
kubectl get svc -n caritas redis

# Check logs
kubectl logs -n caritas deployment/redis
```

## 📚 Resources

- **Redis Documentation**: https://redis.io/documentation
- **Redis Commander**: https://github.com/joeferner/redis-commander
- **Redis Exporter**: https://github.com/oliver006/redis_exporter
- **Best Practices**: https://redis.io/topics/admin

## 🔄 Version Information

- **Redis Version**: Latest (7.x)
- **Redis Commander**: Latest
- **Redis Exporter**: Latest
- **Last Updated**: 2025-10-31

---

**Part of the ORISO Platform**  
For more information, see the main ORISO-OVERVIEW.md

