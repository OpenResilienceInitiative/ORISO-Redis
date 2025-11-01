#!/bin/bash
# Redis Backup Script for ORISO Platform

TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
BACKUP_DIR="/home/caritas/Desktop/online-beratung/caritas-workspace/ORISO-Redis/backup"
REDIS_POD=$(kubectl get pods -n caritas -l app=redis -o jsonpath='{.items[0].metadata.name}')

echo "💾 ORISO Redis Backup"
echo "=================================================="
echo "Backup started at: $(date)"
echo "Target pod: $REDIS_POD"
echo "Backup directory: $BACKUP_DIR"
echo "=================================================="

if [ -z "$REDIS_POD" ]; then
    echo "❌ Error: Redis pod not found in 'caritas' namespace."
    exit 1
fi

# Create backup subdirectory for this backup
BACKUP_SUBDIR="$BACKUP_DIR/redis-backup-$TIMESTAMP"
mkdir -p "$BACKUP_SUBDIR"

echo ""
echo "📤 Step 1: Triggering Redis BGSAVE..."

# Trigger background save
kubectl exec -n caritas "$REDIS_POD" -- redis-cli BGSAVE

if [ $? -eq 0 ]; then
    echo "✅ BGSAVE triggered successfully"
else
    echo "❌ BGSAVE failed"
    exit 1
fi

# Wait for BGSAVE to complete
echo "⏳ Waiting for BGSAVE to complete..."
sleep 5

# Check BGSAVE status
SAVE_STATUS=$(kubectl exec -n caritas "$REDIS_POD" -- redis-cli LASTSAVE)
echo "📊 Last save timestamp: $SAVE_STATUS"

echo ""
echo "📤 Step 2: Backing up RDB file..."

# Copy RDB snapshot
kubectl cp "caritas/$REDIS_POD:/data/dump.rdb" "$BACKUP_SUBDIR/dump.rdb" 2>/dev/null

if [ $? -eq 0 ] && [ -f "$BACKUP_SUBDIR/dump.rdb" ]; then
    RDB_SIZE=$(du -h "$BACKUP_SUBDIR/dump.rdb" | cut -f1)
    echo "✅ RDB file backed up successfully: dump.rdb ($RDB_SIZE)"
else
    echo "⚠️  RDB file not found or backup failed"
fi

echo ""
echo "📤 Step 3: Backing up AOF file (if exists)..."

# Copy AOF file if it exists
kubectl cp "caritas/$REDIS_POD:/data/appendonly.aof" "$BACKUP_SUBDIR/appendonly.aof" 2>/dev/null

if [ $? -eq 0 ] && [ -f "$BACKUP_SUBDIR/appendonly.aof" ]; then
    AOF_SIZE=$(du -h "$BACKUP_SUBDIR/appendonly.aof" | cut -f1)
    echo "✅ AOF file backed up successfully: appendonly.aof ($AOF_SIZE)"
else
    echo "ℹ️  AOF file not found (may not be enabled)"
fi

echo ""
echo "📤 Step 4: Exporting Redis INFO..."

# Export Redis info
kubectl exec -n caritas "$REDIS_POD" -- redis-cli INFO ALL > "$BACKUP_SUBDIR/redis-info.txt" 2>/dev/null

if [ $? -eq 0 ]; then
    echo "✅ Redis INFO exported: redis-info.txt"
else
    echo "⚠️  Redis INFO export failed"
fi

echo ""
echo "📤 Step 5: Exporting key statistics..."

# Export key count and database info
kubectl exec -n caritas "$REDIS_POD" -- redis-cli INFO keyspace > "$BACKUP_SUBDIR/keyspace.txt" 2>/dev/null
kubectl exec -n caritas "$REDIS_POD" -- redis-cli DBSIZE > "$BACKUP_SUBDIR/key-count.txt" 2>/dev/null

if [ $? -eq 0 ]; then
    KEY_COUNT=$(cat "$BACKUP_SUBDIR/key-count.txt")
    echo "✅ Key statistics exported (Total keys: $KEY_COUNT)"
else
    echo "⚠️  Key statistics export failed"
fi

echo ""
echo "📤 Step 6: Creating backup manifest..."

# Create backup manifest
cat > "$BACKUP_SUBDIR/backup-manifest.txt" <<EOF
ORISO Redis Backup Manifest
============================
Backup Date: $(date)
Timestamp: $TIMESTAMP
Pod Name: $REDIS_POD
Namespace: caritas

Files in this backup:
- dump.rdb: Redis RDB snapshot
- appendonly.aof: Redis AOF file (if enabled)
- redis-info.txt: Complete Redis INFO output
- keyspace.txt: Keyspace statistics
- key-count.txt: Total key count
- backup-manifest.txt: This file

Backup Location: $BACKUP_SUBDIR

To restore this backup:
1. Copy dump.rdb to Redis data directory
2. Restart Redis
3. Verify data with: redis-cli KEYS '*'

Total Keys: $(cat "$BACKUP_SUBDIR/key-count.txt" 2>/dev/null || echo "N/A")
Redis Version: $(kubectl exec -n caritas "$REDIS_POD" -- redis-cli INFO server | grep redis_version | cut -d: -f2 | tr -d '\r')
EOF

echo "✅ Backup manifest created"

echo ""
echo "📦 Step 7: Creating compressed archive..."

# Create tar.gz archive
cd "$BACKUP_DIR" || exit
tar -czf "redis-backup-$TIMESTAMP.tar.gz" "redis-backup-$TIMESTAMP" 2>/dev/null

if [ $? -eq 0 ]; then
    ARCHIVE_SIZE=$(du -h "redis-backup-$TIMESTAMP.tar.gz" | cut -f1)
    echo "✅ Compressed archive created: redis-backup-$TIMESTAMP.tar.gz ($ARCHIVE_SIZE)"
    
    # Remove uncompressed directory
    rm -rf "$BACKUP_SUBDIR"
    echo "✅ Cleaned up temporary files"
else
    echo "⚠️  Archive creation failed, keeping uncompressed backup"
fi

echo ""
echo "=================================================="
echo "✅ Backup completed successfully!"
echo ""
echo "📁 Backup Files:"
if [ -f "$BACKUP_DIR/redis-backup-$TIMESTAMP.tar.gz" ]; then
    ls -lh "$BACKUP_DIR/redis-backup-$TIMESTAMP.tar.gz" | awk '{print "   " $9, "(" $5 ")"}'
else
    ls -lh "$BACKUP_SUBDIR" | tail -n +2 | awk '{print "   " $9, "(" $5 ")"}'
fi
echo ""
echo "=================================================="

# Cleanup old backups (keep last 10)
echo ""
echo "🧹 Cleaning up old backups (keeping last 10)..."
cd "$BACKUP_DIR" || exit
ls -t redis-backup-*.tar.gz 2>/dev/null | tail -n +11 | xargs -r rm
ls -td redis-backup-* 2>/dev/null | tail -n +11 | xargs -r rm -rf
echo "✅ Cleanup complete"

# List all backups
echo ""
echo "📁 Available backups:"
ls -lht "$BACKUP_DIR"/redis-backup-* 2>/dev/null | head -10 | awk '{print "   " $9, "(" $5 ")"}'

echo ""
echo "Backup completed at: $(date)"
echo ""
echo "To restore this backup:"
echo "  tar -xzf redis-backup-$TIMESTAMP.tar.gz"
echo "  kubectl cp redis-backup-$TIMESTAMP/dump.rdb caritas/$REDIS_POD:/data/dump.rdb"
echo "  kubectl rollout restart deployment/redis -n caritas"

