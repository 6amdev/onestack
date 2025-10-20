#!/bin/bash
# ═══════════════════════════════════════════════════
# OneStack - System Status Task
# ═══════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

# ═══════════════════════════════════════════════════
# Main Status Display
# ═══════════════════════════════════════════════════

main() {
    clear
    print_header "OneStack System Status"
    
    # System Info
    echo ""
    print_info "System Information:"
    echo "  OS:          $(lsb_release -d | cut -f2)"
    echo "  Kernel:      $(uname -r)"
    echo "  Uptime:      $(uptime -p)"
    echo "  Date:        $(date)"
    
    # Server Info
    echo ""
    print_info "Server Details:"
    echo "  Hostname:    $(hostname)"
    echo "  IP Address:  $(curl -s ifconfig.me)"
    echo "  CPUs:        $(nproc)"
    echo "  Memory:      $(free -h | awk 'NR==2{print $2}')"
    echo "  Disk:        $(df -h / | awk 'NR==2{print $2}')"
    
    # OneStack Info
    echo ""
    print_info "OneStack Configuration:"
    
    if [ -f "/opt/onestack/.env" ]; then
        local DOMAIN=$(grep "^DOMAIN=" /opt/onestack/.env | cut -d= -f2)
        local TIMEZONE=$(grep "^TIMEZONE=" /opt/onestack/.env | cut -d= -f2)
        
        echo "  Domain:      $DOMAIN"
        echo "  Timezone:    $TIMEZONE"
        echo "  Install Dir: /opt/onestack"
    fi
    
    # Docker Info
    echo ""
    print_info "Docker Status:"
    echo "  Version:     $(docker --version | awk '{print $3}' | sed 's/,//')"
    echo "  Compose:     $(docker compose version --short)"
    
    # Services
    echo ""
    print_info "Service Status:"
    echo ""
    
    cd /opt/onestack
    docker compose ps --format "  {{.Name}}: {{.Status}}"
    
    # Resource Usage
    echo ""
    print_info "Resource Usage:"
    echo ""
    
    # CPU
    local LOAD=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    echo "  CPU Load:    $LOAD"
    
    # Memory
    free -h | awk 'NR==2{print "  Memory:      "$3" / "$2" ("int($3/$2*100)"%)"}'
    
    # Disk
    df -h / | awk 'NR==2{print "  Disk:        "$3" / "$2" ("$5" used)"}'
    
    # SSL Status
    echo ""
    print_info "SSL Status:"
    
    local DOMAIN=$(grep "^DOMAIN=" /opt/onestack/.env 2>/dev/null | cut -d= -f2)
    
    if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
        echo "  ✅ SSL Configured"
        
        local EXPIRY_DATE=$(openssl x509 -in "/etc/letsencrypt/live/$DOMAIN/cert.pem" -noout -enddate 2>/dev/null | cut -d= -f2)
        
        if [ -n "$EXPIRY_DATE" ]; then
            local EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s 2>/dev/null)
            local NOW_EPOCH=$(date +%s)
            local DAYS_LEFT=$(( ($EXPIRY_EPOCH - $NOW_EPOCH) / 86400 ))
            
            echo "  Expires in:  $DAYS_LEFT days"
        fi
    else
        echo "  ⏸️  SSL Not Configured"
    fi
    
    # Access URLs
    echo ""
    print_info "Access URLs:"
    
    if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
        echo "  https://$DOMAIN"
    else
        echo "  http://$DOMAIN"
    fi
    
    echo ""
}

# Run
main