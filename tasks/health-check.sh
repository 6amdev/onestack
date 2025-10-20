#!/bin/bash
# ═══════════════════════════════════════════════════
# OneStack - System Health Check Task
# ═══════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

# ═══════════════════════════════════════════════════
# Health Check Functions
# ═══════════════════════════════════════════════════

check_services() {
    print_step "Checking Services..."
    echo ""
    
    cd /opt/onestack
    
    local TOTAL=$(docker compose ps -q | wc -l)
    local RUNNING=$(docker compose ps --filter "status=running" -q | wc -l)
    
    echo "Services: $RUNNING/$TOTAL running"
    echo ""
    
    docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
    
    if [ $RUNNING -eq $TOTAL ]; then
        print_success "All services are running"
    else
        print_warning "Some services are not running"
    fi
}

check_disk_space() {
    print_step "Checking Disk Space..."
    echo ""
    
    df -h / | tail -1 | awk '{
        usage=$5+0
        print "  Root:        "$3" / "$2" ("$5" used)"
        if (usage >= 90) print "  ❌ WARNING: Disk usage is critical!"
        else if (usage >= 80) print "  ⚠️  WARNING: Disk usage is high"
        else print "  ✅ Disk usage is normal"
    }'
    
    echo ""
    
    if [ -d "/opt/onestack" ]; then
        local ONESTACK_SIZE=$(du -sh /opt/onestack 2>/dev/null | cut -f1)
        echo "  OneStack:    $ONESTACK_SIZE"
    fi
    
    echo ""
    
    # Check Docker disk usage
    print_info "Docker disk usage:"
    docker system df
}

check_memory() {
    print_step "Checking Memory..."
    echo ""
    
    free -h | awk 'NR==2{
        usage=$3/$2*100
        print "  Total:       "$2
        print "  Used:        "$3" ("int(usage)"%)"
        print "  Free:        "$4
        if (usage >= 90) print "  ❌ WARNING: Memory usage is critical!"
        else if (usage >= 80) print "  ⚠️  WARNING: Memory usage is high"
        else print "  ✅ Memory usage is normal"
    }'
}

check_cpu() {
    print_step "Checking CPU..."
    echo ""
    
    local LOAD=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    local CORES=$(nproc)
    
    echo "  Load average: $LOAD"
    echo "  CPU cores:    $CORES"
    
    # Calculate load per core
    local LOAD_PER_CORE=$(echo "scale=2; $LOAD / $CORES" | bc 2>/dev/null || echo "N/A")
    
    if [ "$LOAD_PER_CORE" != "N/A" ]; then
        echo "  Load/core:    $LOAD_PER_CORE"
        
        local THRESHOLD=$(echo "$LOAD_PER_CORE > 1" | bc)
        if [ "$THRESHOLD" -eq 1 ]; then
            print_warning "CPU load is high"
        else
            print_success "CPU load is normal"
        fi
    fi
}

check_urls() {
    print_step "Checking Service URLs..."
    echo ""
    
    local DOMAIN=$(grep "^DOMAIN=" /opt/onestack/.env 2>/dev/null | cut -d= -f2)
    
    if [ -z "$DOMAIN" ]; then
        print_warning "Domain not configured"
        return
    fi
    
    # Determine protocol
    if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
        local PROTOCOL="https"
    else
        local PROTOCOL="http"
    fi
    
    # Test URLs
    local URLS=(
        "$PROTOCOL://$DOMAIN"
        "$PROTOCOL://api.$DOMAIN/parse/health"
        "$PROTOCOL://storage.$DOMAIN"
        "$PROTOCOL://monitor.$DOMAIN"
    )
    
    for url in "${URLS[@]}"; do
        echo -n "  Testing: $url ... "
        
        local STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>&1)
        
        if [[ "$STATUS" =~ ^[23] ]]; then
            echo "✅ $STATUS"
        else
            echo "❌ $STATUS"
        fi
    done
}

check_databases() {
    print_step "Checking Databases..."
    echo ""
    
    cd /opt/onestack
    
    # PostgreSQL
    echo -n "  PostgreSQL: "
    if docker compose exec -T postgres pg_isready -U postgres &>/dev/null; then
        echo "✅ Ready"
    else
        echo "❌ Not ready"
    fi
    
    # MongoDB
    echo -n "  MongoDB:    "
    if docker compose exec -T mongodb mongosh --quiet --eval "db.adminCommand('ping')" &>/dev/null; then
        echo "✅ Ready"
    else
        echo "❌ Not ready"
    fi
    
    # Redis
    echo -n "  Redis:      "
    if docker compose exec -T redis redis-cli ping &>/dev/null | grep -q "PONG"; then
        echo "✅ Ready"
    else
        echo "❌ Not ready"
    fi
}

check_ssl() {
    print_step "Checking SSL Status..."
    echo ""
    
    local DOMAIN=$(grep "^DOMAIN=" /opt/onestack/.env 2>/dev/null | cut -d= -f2)
    
    if [ -z "$DOMAIN" ]; then
        echo "  ⏸️  Domain not configured"
        return
    fi
    
    if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
        echo "  ✅ SSL certificate exists"
        
        # Check expiry
        local EXPIRY_DATE=$(openssl x509 -in "/etc/letsencrypt/live/$DOMAIN/cert.pem" -noout -enddate 2>/dev/null | cut -d= -f2)
        
        if [ -n "$EXPIRY_DATE" ]; then
            local EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s 2>/dev/null)
            local NOW_EPOCH=$(date +%s)
            local DAYS_LEFT=$(( ($EXPIRY_EPOCH - $NOW_EPOCH) / 86400 ))
            
            echo "  Days until expiry: $DAYS_LEFT"
            
            if [ $DAYS_LEFT -lt 30 ]; then
                echo "  ⚠️  Renewal needed soon"
            fi
        fi
    else
        echo "  ⏸️  SSL not configured"
    fi
}

check_backups() {
    print_step "Checking Backups..."
    echo ""
    
    if [ -d "/opt/onestack/backups" ]; then
        local BACKUP_COUNT=$(find /opt/onestack/backups -type f -name "*.tar.gz" 2>/dev/null | wc -l)
        
        if [ $BACKUP_COUNT -gt 0 ]; then
            echo "  Backup files: $BACKUP_COUNT"
            echo ""
            echo "  Latest backups:"
            ls -lht /opt/onestack/backups/*.tar.gz 2>/dev/null | head -5 | awk '{print "    "$9" ("$5")"}'
        else
            echo "  ⚠️  No backup files found"
        fi
    else
        echo "  ⏸️  Backup directory not found"
    fi
}

# ═══════════════════════════════════════════════════
# Main Health Check
# ═══════════════════════════════════════════════════

main() {
    print_header "OneStack Health Check"
    echo ""
    
    check_services
    echo ""
    
    check_disk_space
    echo ""
    
    check_memory
    echo ""
    
    check_cpu
    echo ""
    
    check_databases
    echo ""
    
    check_urls
    echo ""
    
    check_ssl
    echo ""
    
    check_backups
    echo ""
    
    print_success "Health check complete!"
    
    # Summary
    echo ""
    print_info "For detailed logs, use:"
    print_info "  ./manage.sh → View service logs"
}

# Run
main