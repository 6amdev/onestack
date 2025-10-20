#!/bin/bash
# ═══════════════════════════════════════════════════
# OneStack Management Console v2.2
# ═══════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

# ═══════════════════════════════════════════════════
# Prerequisites Check
# ═══════════════════════════════════════════════════

check_prerequisites() {
    local missing=0
    
    # Check yq
    if ! command -v yq &> /dev/null; then
        print_warning "yq not installed (needed for SSL setup)"
        read -p "Install yq now? (Y/n): " install_yq
        
        if [ "$install_yq" != "n" ]; then
            print_step "Installing yq..."
            wget -q https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq
            chmod +x /usr/bin/yq
            
            if command -v yq &> /dev/null; then
                print_success "yq installed successfully"
            else
                print_error "Failed to install yq"
                missing=1
            fi
        else
            print_warning "Some features may not work without yq"
            missing=1
        fi
    fi
    
    # Check tasks directory
    if [ ! -d "$SCRIPT_DIR/tasks" ]; then
        print_warning "Tasks directory not found"
        mkdir -p "$SCRIPT_DIR/tasks"
        print_info "Created: $SCRIPT_DIR/tasks"
        print_warning "Please upload task scripts"
        missing=1
    else
        local task_count=$(find "$SCRIPT_DIR/tasks" -name "*.sh" -type f 2>/dev/null | wc -l)
        if [ "$task_count" -eq 0 ]; then
            print_warning "No task scripts found (0 tasks)"
            print_info "Some menu options will not work"
            missing=1
        fi
    fi
    
    # Check lib/06-ssl.sh
    if [ ! -f "$SCRIPT_DIR/lib/06-ssl.sh" ]; then
        print_warning "lib/06-ssl.sh not found (SSL features unavailable)"
        missing=1
    fi
    
    if [ "$missing" -eq 1 ]; then
        echo ""
        read -p "Continue anyway? (Y/n): " cont
        [ "$cont" = "n" ] && exit 0
    fi
}

# ═══════════════════════════════════════════════════
# Check Installation
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
# Task Runner
# ═══════════════════════════════════════════════════

run_task() {
    local task_name=$1
    local task_file="$SCRIPT_DIR/tasks/${task_name}.sh"
    
    clear
    
    if [ -f "$task_file" ]; then
        if [ ! -x "$task_file" ]; then
            chmod +x "$task_file"
        fi
        
        bash "$task_file"
        local exit_code=$?
        
        if [ $exit_code -ne 0 ]; then
            echo ""
            print_error "Task exited with error code: $exit_code"
        fi
        
        return $exit_code
    else
        print_error "Task not available: ${task_name}"
        echo ""
        print_info "File not found: $task_file"
        echo ""
        print_warning "This feature requires task scripts"
        echo ""
        print_info "Available tasks:"
        
        if [ -d "$SCRIPT_DIR/tasks" ]; then
            local available=$(find "$SCRIPT_DIR/tasks" -name "*.sh" -type f 2>/dev/null)
            if [ -n "$available" ]; then
                echo "$available" | while read file; do
                    echo "  ✓ $(basename "$file" .sh)"
                done
            else
                echo "  (none - please upload task scripts)"
            fi
        else
            echo "  (tasks directory not found)"
        fi
        
        echo ""
        print_info "Upload location: $SCRIPT_DIR/tasks/"
        return 1
    fi
}

# ═══════════════════════════════════════════════════
# Service Status
# ═══════════════════════════════════════════════════

show_service_status() {
    if [ -d "/opt/onestack" ] && [ -f "/opt/onestack/docker-compose.yml" ]; then
        cd /opt/onestack
        
        echo ""
        print_info "Service Status:"
        docker compose ps --format "table {{.Name}}\t{{.Status}}" 2>/dev/null | head -12 || \
            echo "  (Unable to get service status)"
        echo ""
    fi
}

# ═══════════════════════════════════════════════════
# Main Menu
# ═══════════════════════════════════════════════════

show_main_menu() {
    clear
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║           OneStack Management Console v2.2                    ║
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
  10) 🧪 Test all services (comprehensive)
  11) ✅ Validate installation

🛠️ Troubleshooting:
  12) Fix Parse Dashboard
  13) Reset service
  14) Clean up resources
  15) 🔧 Quick Fix (auto-repair issues)
  16) 📝 Fix .env configuration

📚 Information:
  17) Show credentials
  18) Show URLs
  19) Check for updates

🚪 Other:
  20) Restart all services
  21) Stop all services
  22) Exit

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
    
    read -p "Enter choice [1-22]: " choice
    handle_menu_choice "$choice"
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
        10) run_task "test-services" ;;
        11) run_task "validate-install" ;;
        
        # Troubleshooting
        12) run_task "fix-parse-dashboard" ;;
        13) run_task "service-reset" ;;
        14) run_task "cleanup" ;;
        15) run_task "quick-fix" ;;
        16) run_task "fix-env" ;;
        
        # Information
        17) show_credentials ;;
        18) show_urls ;;
        19) check_updates ;;
        
        # Other
        20) restart_all_services ;;
        21) stop_all_services ;;
        22) exit 0 ;;
        
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
# Built-in Functions
# ═══════════════════════════════════════════════════

show_credentials() {
    clear
    print_header "OneStack Credentials"
    
    if [ -f "/opt/onestack/.credentials" ]; then
        cat /opt/onestack/.credentials
    else
        print_error "Credentials file not found"
        print_info "Expected: /opt/onestack/.credentials"
    fi
    
    echo ""
    print_info "Environment variables: /opt/onestack/.env"
}

show_urls() {
    clear
    print_header "OneStack Service URLs"
    
    local DOMAIN=$(grep "^DOMAIN=" /opt/onestack/.env 2>/dev/null | cut -d= -f2)
    
    if [ -z "$DOMAIN" ]; then
        DOMAIN="localhost"
        print_warning "Domain not found in .env, using default"
    fi
    
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
    echo ""
    
    print_info "Testing accessibility..."
    for url in "$PROTOCOL://$DOMAIN" "$PROTOCOL://api.$DOMAIN/parse/health"; do
        local status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>&1)
        if [[ "$status" =~ ^[23] ]]; then
            echo "  ✅ $url"
        else
            echo "  ❌ $url (HTTP $status)"
        fi
    done
}

check_updates() {
    clear
    print_header "Check for Updates"
    
    print_info "Current OneStack version: 1.0.0"
    print_info "Checking for updates..."
    
    print_warning "Update check not implemented yet"
    print_info "Check manually: https://github.com/yourusername/onestack"
}

restart_all_services() {
    clear
    print_header "Restart All Services"
    
    read -p "This will restart all OneStack services. Continue? (y/N): " confirm
    
    if [ "$confirm" = "y" ]; then
        print_step "Restarting all services..."
        cd /opt/onestack
        
        if docker compose restart 2>/dev/null; then
            print_success "All services restarted"
            sleep 3
        else
            print_error "Failed to restart services"
            sleep 3
        fi
    fi
}

stop_all_services() {
    clear
    print_header "Stop All Services"
    
    print_warning "This will stop all OneStack services"
    read -p "Are you sure? (y/N): " confirm
    
    if [ "$confirm" = "y" ]; then
        print_step "Stopping all services..."
        cd /opt/onestack
        
        if docker compose down 2>/dev/null; then
            print_success "All services stopped"
            print_info "To start again: cd /opt/onestack && docker compose up -d"
            
            read -p "Press Enter to exit..."
            exit 0
        else
            print_error "Failed to stop services"
            sleep 3
        fi
    fi
}

# ═══════════════════════════════════════════════════
# Main Entry Point
# ═══════════════════════════════════════════════════

main() {
    check_root
    check_installation
    check_prerequisites
    
    show_main_menu
}

# Run
main