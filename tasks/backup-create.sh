#!/bin/bash
# ═══════════════════════════════════════════════════
# OneStack - Create Backup Task
# ═══════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

# ═══════════════════════════════════════════════════
# Backup Functions
# ═══════════════════════════════════════════════════

backup_databases() {
    local BACKUP_DIR=$1
    
    print_step "Backing up databases..."
    
    cd /opt/onestack
    
    # PostgreSQL
    print_info "  → PostgreSQL..."
    docker compose exec -T postgres pg_dumpall -U postgres | gzip > "$BACKUP_DIR/postgres.sql.gz"
    
    # MongoDB
    print_info "  → MongoDB..."
    docker compose exec -T mongodb mongodump --archive | gzip > "$BACKUP_DIR/mongodb.archive.gz"
    
    # Redis
    print_info "  → Redis..."
    docker compose exec -T redis redis-cli --rdb - > "$BACKUP_DIR/redis.rdb"
    
    print_success "Databases backed up"
}

backup_configs() {
    local BACKUP_DIR=$1
    
    print_step "Backing up configurations..."
    
    # OneStack configs
    tar czf "$BACKUP_DIR/configs.tar.gz" \
        /opt/onestack/.env \
        /opt/onestack/.credentials \
        /opt/onestack/docker-compose.yml \
        /opt/onestack/nginx/ \
        2>/dev/null
    
    print_success "Configurations backed up"
}

backup_ssl() {
    local BACKUP_DIR=$1
    
    if [ -d "/etc/letsencrypt" ]; then
        print_step "Backing up SSL certificates..."
        
        sudo tar czf "$BACKUP_DIR/ssl.tar.gz" /etc/letsencrypt/ 2>/dev/null
        
        print_success "SSL certificates backed up"
    fi
}

# ═══════════════════════════════════════════════════
# Main Backup
# ═══════════════════════════════════════════════════

main() {
    print_header "Create OneStack Backup"
    
    # Create backup directory
    local TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    local BACKUP_NAME="onestack-backup-$TIMESTAMP"
    local BACKUP_DIR="/opt/onestack/backups/$BACKUP_NAME"
    
    mkdir -p "$BACKUP_DIR"
    
    echo ""
    print_info "Backup location: $BACKUP_DIR"
    echo ""
    
    # Confirm
    read -p "Start backup now? (Y/n): " confirm
    [ "$confirm" = "n" ] && exit 0
    
    echo ""
    
    # Perform backup
    backup_databases "$BACKUP_DIR"
    echo ""
    
    backup_configs "$BACKUP_DIR"
    echo ""
    
    backup_ssl "$BACKUP_DIR"
    echo ""
    
    # Create archive
    print_step "Creating backup archive..."
    
    cd /opt/onestack/backups
    tar czf "$BACKUP_NAME.tar.gz" "$BACKUP_NAME/"
    
    # Cleanup temp dir
    rm -rf "$BACKUP_NAME/"
    
    # Show result
    echo ""
    print_success "Backup complete!"
    echo ""
    
    local BACKUP_SIZE=$(du -h "$BACKUP_NAME.tar.gz" | cut -f1)
    
    print_info "Backup file: $BACKUP_NAME.tar.gz"
    print_info "Size:        $BACKUP_SIZE"
    print_info "Location:    /opt/onestack/backups/"
    
    echo ""
    print_info "To restore this backup:"
    print_info "  ./tasks/backup-restore.sh $BACKUP_NAME.tar.gz"
}

# Run
check_root
main