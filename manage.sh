#!/bin/bash
# ═══════════════════════════════════════════════════
# OneStack Management Console
# ═══════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

# ═══════════════════════════════════════════════════
# Check if OneStack is installed
# ═══════════════════════════════════════════════════

check_installation() {
    if [ ! -d "/opt/onestack" ]; then
        print_error "OneStack is not installed"
        print_info "Please run install.sh first"
        exit 1
    fi
    
    if [ ! -f "/opt/onestack/docker-compose.yml" ]; then
        print_error "OneStack docker-compose.yml not found"
        exit 1
    fi
}

# ═══════════════════════════════════════════════════
# Show Service Status
# ═══════════════════════════════════════════════════

show_service_status() {
    cd /opt/onestack
    
    echo ""
    print_info "Service Status:"
    docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | head -12
    echo ""
}

# ═══════════════════════════════════════════════════
# Main Menu
# ═══════════════════════════════════════════════════

show_main_menu() {
    clear
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║              OneStack Management Console v1.0                 ║
╠═══════════════════════════════════════════════════════════════╣
EOF
    
    show_service_status
    
    cat << 'EOF'
Management Tasks:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🔐 SSL Management:
  1) Setup SSL (first time)
  2) Renew SSL certificates
  3) Check SSL status

🔧 Service Management:
  4) Restart service
  5) View service logs
  6) Check service health

💾 System Maintenance:
  7) Create backup
  8) System health check
  9) View system status

🛠️ Troubleshooting:
  10) Fix Parse Dashboard
  11) Reset service
  12) Clean up resources

📚 Information:
  13) Show credentials
  14) Show URLs
  15) Check for updates

🚪 Other:
  16) Restart all services
  17) Stop all services
  18) Exit

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
    
    read -p "Enter choice [1-18]: " choice
    handle_menu_choice "$choice"
}

# ═══════════════════════════════════════════════════
# Menu Handler
# ═══════════════════════════════════════════════════

handle_menu_choice() {
    case $1 in
        1)  bash "$SCRIPT_DIR/tasks/ssl-setup.sh" ;;
        2)  bash "$SCRIPT_DIR/tasks/ssl-renew.sh" ;;
        3)  bash "$SCRIPT_DIR/tasks/ssl-status.sh" ;;
        4)  bash "$SCRIPT_DIR/tasks/service-restart.sh" ;;
        5)  bash "$SCRIPT_DIR/tasks/service-logs.sh" ;;
        6)  bash "$SCRIPT_DIR/tasks/health-check.sh" ;;
        7)  bash "$SCRIPT_DIR/tasks/backup-create.sh" ;;
        8)  bash "$SCRIPT_DIR/tasks/health-check.sh" ;;
        9)  bash "$SCRIPT_DIR/tasks/system-status.sh" ;;
        10) bash "$SCRIPT_DIR/tasks/fix-parse-dashboard.sh" ;;
        11) bash "$SCRIPT_DIR/tasks/service-reset.sh" ;;
        12) bash "$SCRIPT_DIR/tasks/cleanup.sh" ;;
        13) show_credentials ;;
        14) show_urls ;;
        15) check_updates ;;
        16) restart_all_services ;;
        17) stop_all_services ;;
        18) exit 0 ;;
        *)  print_error "Invalid choice" && sleep 2 ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
    show_main_menu
}

# ═══════════════════════════════════════════════════
# Quick Actions
# ═══════════════════════════════════════════════════

show_credentials() {
    clear
    print_header "OneStack Credentials"
    
    if [ -f "/opt/onestack/.credentials" ]; then
        cat /opt/onestack/.credentials
    else
        print_error "Credentials file not found"
    fi
    
    echo ""
    print_info "Environment variables: /opt/onestack/.env"
}

show_urls() {
    clear
    print_header "OneStack Service URLs"
    
    local DOMAIN=$(grep "^DOMAIN=" /opt/onestack/.env 2>/dev/null | cut -d= -f2)
    
    if [ -z "$DOMAIN" ]; then
        DOMAIN="sixamdev.com"
    fi
    
    # Check if SSL is configured
    if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
        local PROTOCOL="https"
        print_success "SSL is configured ✅"
    else
        local PROTOCOL="http"
        print_warning "SSL not configured (HTTP only)"
    fi
    
    echo ""
    echo "Service URLs:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Main Site:       $PROTOCOL://$DOMAIN"
    echo "  MinIO Console:   $PROTOCOL://storage.$DOMAIN"
    echo "  MinIO S3 API:    $PROTOCOL://s3.$DOMAIN"
    echo "  Parse Server:    $PROTOCOL://api.$DOMAIN/parse"
    echo "  Parse Dashboard: $PROTOCOL://api.$DOMAIN"
    echo "  Grafana:         $PROTOCOL://monitor.$DOMAIN"
    echo "  Prometheus:      $PROTOCOL://prometheus.$DOMAIN"
    echo "  Adminer:         $PROTOCOL://db.$DOMAIN"
}

check_updates() {
    clear
    print_header "Check for Updates"
    
    print_info "Current OneStack version: 1.0.0"
    print_info "Checking for updates..."
    
    # This would check GitHub releases or similar
    print_warning "Update check not implemented yet"
    print_info "Check manually: https://github.com/yourusername/onestack"
}

restart_all_services() {
    print_header "Restart All Services"
    
    read -p "This will restart all OneStack services. Continue? (y/N): " confirm
    
    if [ "$confirm" = "y" ]; then
        print_step "Restarting all services..."
        cd /opt/onestack
        docker compose restart
        
        print_success "All services restarted"
        sleep 3
    fi
}

stop_all_services() {
    print_header "Stop All Services"
    
    print_warning "This will stop all OneStack services"
    read -p "Are you sure? (y/N): " confirm
    
    if [ "$confirm" = "y" ]; then
        print_step "Stopping all services..."
        cd /opt/onestack
        docker compose down
        
        print_success "All services stopped"
        print_info "To start again: cd /opt/onestack && docker compose up -d"
        
        read -p "Press Enter to exit..."
        exit 0
    fi
}

# ═══════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════

check_root
check_installation

show_main_menu