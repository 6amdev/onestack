#!/bin/bash
# Setup Automated Backup System

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh" 2>/dev/null || {
    BLUE='\033[0;34m'; GREEN='\033[0;32m'; NC='\033[0m'
    print_header() { echo -e "\n${BLUE}=== $1 ===${NC}\n"; }
    print_step() { echo -e "${BLUE}▶${NC} $1"; }
    print_success() { echo -e "${GREEN}✓${NC} $1"; }
}

check_root

print_header "Automated Backup System Setup"

INSTALL_DIR="/opt/onestack"
BACKUP_DIR="$INSTALL_DIR/backups"

mkdir -p "$BACKUP_DIR"

# Create backup script
cat > "$INSTALL_DIR/scripts/backup.sh" << 'BACKUPSCRIPT'
#!/bin/bash
# OneStack Automated Backup

set -e

INSTALL_DIR="/opt/onestack"
BACKUP_DIR="$INSTALL_DIR/backups"
DATE=$(date +%Y%m%d_%H%M%S)

echo "Starting backup: $DATE"

cd "$INSTALL_DIR"

# Backup PostgreSQL
echo "Backing up PostgreSQL..."
docker compose exec -T postgres pg_dumpall -U postgres | gzip > "$BACKUP_DIR/postgres_$DATE.sql.gz"

# Backup MongoDB
echo "Backing up MongoDB..."
docker compose exec -T mongodb mongodump --archive --gzip > "$BACKUP_DIR/mongodb_$DATE.gz"

# Backup Redis
echo "Backing up Redis..."
docker compose exec -T redis redis-cli --rdb /data/dump.rdb SAVE
docker cp onestack-redis:/data/dump.rdb "$BACKUP_DIR/redis_$DATE.rdb"

# Backup configs
echo "Backing up configs..."
tar czf "$BACKUP_DIR/configs_$DATE.tar.gz" \
    "$INSTALL_DIR/.env" \
    "$INSTALL_DIR/docker-compose.yml" \
    "$INSTALL_DIR/nginx/" \
    2>/dev/null || true

# Cleanup old backups (keep last 7 days)
find "$BACKUP_DIR" -name "*.gz" -mtime +7 -delete
find "$BACKUP_DIR" -name "*.rdb" -mtime +7 -delete

echo "✓ Backup completed: $BACKUP_DIR"
ls -lh "$BACKUP_DIR" | tail -10
BACKUPSCRIPT

chmod +x "$INSTALL_DIR/scripts/backup.sh"

# Create restore script
cat > "$INSTALL_DIR/scripts/restore.sh" << 'RESTORESCRIPT'
#!/bin/bash
# OneStack Restore from Backup

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <backup_date>"
    echo "Example: $0 20250122_140000"
    exit 1
fi

DATE=$1
INSTALL_DIR="/opt/onestack"
BACKUP_DIR="$INSTALL_DIR/backups"

cd "$INSTALL_DIR"

# Restore PostgreSQL
if [ -f "$BACKUP_DIR/postgres_$DATE.sql.gz" ]; then
    echo "Restoring PostgreSQL..."
    gunzip < "$BACKUP_DIR/postgres_$DATE.sql.gz" | docker compose exec -T postgres psql -U postgres
fi

# Restore MongoDB
if [ -f "$BACKUP_DIR/mongodb_$DATE.gz" ]; then
    echo "Restoring MongoDB..."
    docker compose exec -T mongodb mongorestore --archive --gzip < "$BACKUP_DIR/mongodb_$DATE.gz"
fi

# Restore Redis
if [ -f "$BACKUP_DIR/redis_$DATE.rdb" ]; then
    echo "Restoring Redis..."
    docker compose stop redis
    docker cp "$BACKUP_DIR/redis_$DATE.rdb" onestack-redis:/data/dump.rdb
    docker compose start redis
fi

echo "✓ Restore completed"
RESTORESCRIPT

chmod +x "$INSTALL_DIR/scripts/restore.sh"

# Setup cron job
print_step "Setting up daily backup cron job..."

CRON_CMD="0 2 * * * $INSTALL_DIR/scripts/backup.sh >> $INSTALL_DIR/logs/backup.log 2>&1"

(crontab -l 2>/dev/null | grep -v "backup.sh"; echo "$CRON_CMD") | crontab -

print_success "Backup system installed!"
echo ""
echo "Manual backup:"
echo "  $INSTALL_DIR/scripts/backup.sh"
echo ""
echo "Restore:"
echo "  $INSTALL_DIR/scripts/restore.sh 20250122_140000"
echo ""
echo "Automated: Daily at 2:00 AM"
echo "Location: $BACKUP_DIR"