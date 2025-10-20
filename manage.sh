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

# ═══════════════════════════════════════════════════
# Task Runner Helper
# ═══════════════════════════════════════════════════

run_task() {
    local task_name=$1
    local task_file="$SCRIPT_DIR/tasks/${task_name}.sh"
    
    if [ -f "$task_file" ]; then
        bash "$task_file"
    else
        print_error "Task not available: ${task_name}"
        print_info "File not found: $task_file"
        echo ""
        print_warning "This feature requires task scripts to be installed"
        print_info "Please upload task scripts to: $SCRIPT_DIR/tasks/"
        
        # Show what's available
        if [ -d "$SCRIPT_DIR/tasks" ]; then
            local available=$(ls -1 "$SCRIPT_DIR/tasks/"*.sh 2>/dev/null | wc -l)
            if [ "$available" -gt 0 ]; then
                echo ""
                print_info "Available tasks:"
                ls -1 "$SCRIPT_DIR/tasks/"*.sh 2>/dev/null | xargs -n1 basename
            fi
        fi
    fi
}

# ═══════════════════════════════════════════════════
# Menu Handler
# ═══════════════════════════════════════════════════

handle_menu_choice() {
    case $1 in
        # SSL Management
        1)  run_task "ssl-setup" ;;
        2)  run_task "ssl-renew" ;;
        3)  run_task "ssl-status" ;;
        
        # Service Management
        4)  run_task "service-restart" ;;
        5)  run_task "service-logs" ;;
        6)  run_task "health-check" ;;
        
        # System Maintenance
        7)  run_task "backup-create" ;;
        8)  run_task "health-check" ;;
        9)  run_task "system-status" ;;
        
        # Troubleshooting
        10) run_task "fix-parse-dashboard" ;;
        11) run_task "service-reset" ;;
        12) run_task "cleanup" ;;
        
        # Information (these work without task files)
        13) show_credentials ;;
        14) show_urls ;;
        15) check_updates ;;
        
        # Other (these work without task files)
        16) restart_all_services ;;
        17) stop_all_services ;;
        18) exit 0 ;;
        
        *)  
            print_error "Invalid choice"
            sleep 2
            ;;
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