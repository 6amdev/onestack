#!/bin/bash
# ═══════════════════════════════════════════════════
# OneStack Manager
# Manage your OneStack installation
# ═══════════════════════════════════════════════════

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/onestack"

# โหลด utilities
if [ -f "$SCRIPT_DIR/lib/01-utils.sh" ]; then
    source "$SCRIPT_DIR/lib/01-utils.sh"
elif [ -f "$SCRIPT_DIR/lib/utils.sh" ]; then
    source "$SCRIPT_DIR/lib/utils.sh"
else
    echo "Error: utils.sh not found"
    exit 1
fi

# โหลด SSL functions
if [ -f "$SCRIPT_DIR/lib/06-ssl.sh" ]; then
    source "$SCRIPT_DIR/lib/06-ssl.sh"
fi

# ═══════════════════════════════════════════════════
# Check Installation
# ═══════════════════════════════════════════════════

check_installation() {
    if [ ! -d "$INSTALL_DIR" ]; then
        print_error "OneStack not installed"
        print_info "Please run: sudo bash install.sh"
        exit 1
    fi
    
    if [ ! -f "$INSTALL_DIR/docker-compose.yml" ]; then
        print_error "docker-compose.yml not found"
        exit 1
    fi
}

# ═══════════════════════════════════════════════════
# Show Status
# ═══════════════════════════════════════════════════

show_status() {
    clear
    print_header "OneStack Status"
    
    cd "$INSTALL_DIR"
    
    # โหลด config
    if [ -f ".env" ]; then
        source .env
        echo ""
        print_info "Domain: ${DOMAIN:-Not configured}"
        print_info "Install Directory: $INSTALL_DIR"
        echo ""
    fi
    
    # แสดง services
    print_step "Running Services:"
    echo ""
    docker compose ps --format "table {{.Service}}\t{{.Status}}\t{{.Ports}}"
    echo ""
    
    # แสดง SSL status
    if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
        print_success "SSL: Enabled"
        
        # ตรวจสอบวันหมดอายุ
        if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
            local expiry=$(openssl x509 -in "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" -noout -enddate 2>/dev/null | cut -d= -f2)
            local expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null)
            local now_epoch=$(date +%s)
            local days_left=$(( ($expiry_epoch - $now_epoch) / 86400 ))
            
            print_info "SSL expires in: $days_left days"
        fi
    else
        print_warning "SSL: Not configured"
    fi
    
    echo ""
    print_info "Press any key to return to menu..."
    read -n 1 -s
}

# ═══════════════════════════════════════════════════
# Setup SSL
# ═══════════════════════════════════════════════════

setup_ssl_menu() {
    clear
    print_header "SSL Certificate Setup"
    
    cd "$INSTALL_DIR"
    
    # โหลด domain
    if [ -f ".env" ]; then
        source .env
    fi
    
    if [ -z "$DOMAIN" ] || [ "$DOMAIN" = "localhost" ]; then
        print_error "Domain not configured"
        echo ""
        print_info "Please set DOMAIN in $INSTALL_DIR/.env"
        echo ""
        print_info "Example:"
        echo "  DOMAIN=example.com"
        echo "  SSL_EMAIL=admin@example.com"
        echo "  SSL_MODE=production"
        echo ""
        read -p "Press Enter to return to menu..."
        return
    fi
    
    echo ""
    print_info "Current Configuration:"
    echo "  Domain: $DOMAIN"
    echo "  Email: ${SSL_EMAIL:-admin@$DOMAIN}"
    echo "  Mode: ${SSL_MODE:-production}"
    echo ""
    
    # ตรวจสอบ SSL status
    if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
        print_warning "SSL certificates already exist"
        echo ""
        echo "Options:"
        echo "  1) Renew certificates"
        echo "  2) Re-scan services and update"
        echo "  3) Return to menu"
        echo ""
        read -p "Choose option [1-3]: " ssl_option
        
        case $ssl_option in
            1)
                print_step "Renewing certificates..."
                certbot renew --force-renewal
                docker compose exec -T nginx nginx -s reload
                print_success "Certificates renewed!"
                ;;
            2)
                setup_ssl_smart "$INSTALL_DIR" "$INSTALL_DIR/.env"
                ;;
            *)
                return
                ;;
        esac
    else
        # ติดตั้งใหม่
        echo ""
        print_info "This will:"
        echo "  1. Scan all installed services"
        echo "  2. Discover all domains/subdomains"
        echo "  3. Request SSL certificates"
        echo "  4. Configure HTTPS for all services"
        echo "  5. Setup auto-renewal"
        echo ""
        
        if confirm "Start SSL setup?"; then
            setup_ssl_smart "$INSTALL_DIR" "$INSTALL_DIR/.env"
        fi
    fi
    
    echo ""
    read -p "Press Enter to return to menu..."
}

# ═══════════════════════════════════════════════════
# Add Redirect Domain
# ═══════════════════════════════════════════════════

add_redirect_domain_menu() {
    clear
    print_header "Add Redirect Domain"
    
    echo "This will redirect another domain to your main domain."
    echo "All requests to the new domain will be forwarded to your OneStack domain."
    echo ""
    
    cd "$INSTALL_DIR"
    
    # โหลด domain
    if [ -f ".env" ]; then
        source .env
    fi
    
    if [ -z "$DOMAIN" ] || [ "$DOMAIN" = "localhost" ]; then
        print_error "Main domain not configured"
        echo ""
        read -p "Press Enter to return to menu..."
        return
    fi
    
    print_info "Main Domain: $DOMAIN"
    echo ""
    
    read -p "Enter domain to redirect (e.g., 6amdev.com): " REDIRECT_DOMAIN
    
    if [ -z "$REDIRECT_DOMAIN" ]; then
        print_error "Domain cannot be empty"
        echo ""
        read -p "Press Enter to return to menu..."
        return
    fi
    
    # Clean domain
    REDIRECT_DOMAIN=$(echo "$REDIRECT_DOMAIN" | sed 's|https\?://||' | sed 's|/.*||')
    
    echo ""
    print_info "Redirect: $REDIRECT_DOMAIN → $DOMAIN"
    echo ""
    
    if ! confirm "Continue?"; then
        return
    fi
    
    # เรียกใช้ add-redirect-domain script
    if [ -f "$SCRIPT_DIR/tasks/add-redirect-domain.sh" ]; then
        bash "$SCRIPT_DIR/tasks/add-redirect-domain.sh" "$REDIRECT_DOMAIN"
    elif [ -f "$INSTALL_DIR/tasks/add-redirect-domain.sh" ]; then
        bash "$INSTALL_DIR/tasks/add-redirect-domain.sh" "$REDIRECT_DOMAIN"
    elif [ -f "$SCRIPT_DIR/add-redirect-domain.sh" ]; then
        bash "$SCRIPT_DIR/add-redirect-domain.sh" "$REDIRECT_DOMAIN"
    elif [ -f "/usr/local/bin/add-redirect-domain.sh" ]; then
        bash /usr/local/bin/add-redirect-domain.sh "$REDIRECT_DOMAIN"
    else
        print_error "add-redirect-domain.sh not found"
        print_info "Please ensure the script is in:"
        echo "  - $SCRIPT_DIR/tasks/add-redirect-domain.sh"
        echo "  - $INSTALL_DIR/tasks/add-redirect-domain.sh"
        echo "  - $SCRIPT_DIR/add-redirect-domain.sh"
        echo "  - /usr/local/bin/add-redirect-domain.sh"
    fi
    
    echo ""
    read -p "Press Enter to return to menu..."
}

# ═══════════════════════════════════════════════════
# Add Service
# ═══════════════════════════════════════════════════

add_service_menu() {
    clear
    print_header "Add Service"
    
    echo "Available Services:"
    echo ""
    echo "  1) n8n (Workflow Automation)"
    echo "  2) Chatwoot (Customer Support)"
    echo "  3) Parse Server (Backend-as-a-Service)"
    echo "  4) Monitoring (Grafana + Prometheus)"
    echo "  5) Adminer (Database UI)"
    echo "  6) Return to menu"
    echo ""
    read -p "Choose service to add [1-6]: " service_choice
    
    case $service_choice in
        1)
            print_info "Adding n8n..."
            # TODO: เพิ่ม logic การติดตั้ง n8n
            print_warning "Not implemented yet"
            ;;
        2)
            print_info "Adding Chatwoot..."
            # TODO: เพิ่ม logic การติดตั้ง Chatwoot
            print_warning "Not implemented yet"
            ;;
        *)
            print_info "Invalid choice"
            ;;
    esac
    
    echo ""
    read -p "Press Enter to return to menu..."
}

# ═══════════════════════════════════════════════════
# Service Control
# ═══════════════════════════════════════════════════

service_control_menu() {
    clear
    print_header "Service Control"
    
    cd "$INSTALL_DIR"
    
    echo "Actions:"
    echo ""
    echo "  1) Start all services"
    echo "  2) Stop all services"
    echo "  3) Restart all services"
    echo "  4) View logs"
    echo "  5) Return to menu"
    echo ""
    read -p "Choose action [1-5]: " action_choice
    
    case $action_choice in
        1)
            print_step "Starting all services..."
            docker compose up -d
            print_success "Services started"
            ;;
        2)
            print_step "Stopping all services..."
            docker compose down
            print_success "Services stopped"
            ;;
        3)
            print_step "Restarting all services..."
            docker compose restart
            print_success "Services restarted"
            ;;
        4)
            echo ""
            echo "Which service logs?"
            docker compose ps --services
            echo ""
            read -p "Service name (or 'all'): " service_name
            
            if [ "$service_name" = "all" ]; then
                docker compose logs -f --tail=50
            else
                docker compose logs -f --tail=50 "$service_name"
            fi
            ;;
        5)
            return
            ;;
    esac
    
    echo ""
    read -p "Press Enter to return to menu..."
}

# ═══════════════════════════════════════════════════
# Backup System
# ═══════════════════════════════════════════════════

backup_menu() {
    clear
    print_header "Backup System"
    
    echo "Backup Options:"
    echo ""
    echo "  1) Create full backup"
    echo "  2) Create database backup only"
    echo "  3) List backups"
    echo "  4) Restore from backup"
    echo "  5) Return to menu"
    echo ""
    read -p "Choose option [1-5]: " backup_choice
    
    case $backup_choice in
        1)
            print_step "Creating full backup..."
            # TODO: เพิ่ม backup logic
            print_warning "Not implemented yet"
            ;;
        *)
            print_info "Invalid choice"
            ;;
    esac
    
    echo ""
    read -p "Press Enter to return to menu..."
}

# ═══════════════════════════════════════════════════
# System Info
# ═══════════════════════════════════════════════════

show_system_info() {
    clear
    print_header "System Information"
    
    echo ""
    print_step "Server Info"
    echo "  OS: $(lsb_release -d | cut -f2)"
    echo "  Kernel: $(uname -r)"
    echo "  Uptime: $(uptime -p)"
    echo ""
    
    print_step "Resources"
    echo "  CPU: $(nproc) cores"
    echo "  RAM: $(free -h | awk '/^Mem:/ {print $2}') total, $(free -h | awk '/^Mem:/ {print $3}') used"
    echo "  Disk: $(df -h /opt/onestack 2>/dev/null | tail -1 | awk '{print $2}') total, $(df -h /opt/onestack 2>/dev/null | tail -1 | awk '{print $3}') used ($(df -h /opt/onestack 2>/dev/null | tail -1 | awk '{print $5}'))"
    echo ""
    
    print_step "Docker Info"
    echo "  Version: $(docker --version | cut -d' ' -f3 | tr -d ',')"
    echo "  Compose: $(docker compose version --short 2>/dev/null || echo 'N/A')"
    echo "  Containers: $(docker ps -q | wc -l) running, $(docker ps -aq | wc -l) total"
    echo "  Images: $(docker images -q | wc -l)"
    echo ""
    
    cd "$INSTALL_DIR" 2>/dev/null
    if [ -f ".env" ]; then
        source .env
        print_step "OneStack Info"
        echo "  Domain: ${DOMAIN:-Not set}"
        echo "  Install Directory: $INSTALL_DIR"
        echo "  Version: $(grep "^VERSION=" .env 2>/dev/null | cut -d= -f2 || echo 'Unknown')"
        echo ""
    fi
    
    read -p "Press Enter to return to menu..."
}

# ═══════════════════════════════════════════════════
# Main Menu
# ═══════════════════════════════════════════════════

show_menu() {
    clear
    echo ""
    echo "╔════════════════════════════════════════════════╗"
    echo "║                                                ║"
    echo "║           OneStack Manager v1.0                ║"
    echo "║                                                ║"
    echo "╚════════════════════════════════════════════════╝"
    echo ""
    echo "  1) Show Status"
    echo "  2) Setup/Manage SSL Certificates"
    echo "  3) Add Redirect Domain"
    echo "  4) Add Service"
    echo "  5) Service Control"
    echo "  6) Backup System"
    echo "  7) System Information"
    echo "  8) Exit"
    echo ""
    read -p "Choose option [1-8]: " choice
    
    case $choice in
        1) show_status ;;
        2) setup_ssl_menu ;;
        3) add_redirect_domain_menu ;;
        4) add_service_menu ;;
        5) service_control_menu ;;
        6) backup_menu ;;
        7) show_system_info ;;
        8) 
            clear
            print_success "Goodbye!"
            exit 0
            ;;
        *)
            print_error "Invalid option"
            sleep 1
            ;;
    esac
}

# ═══════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════

main() {
    # ตรวจสอบ root
    if [ "$EUID" -ne 0 ]; then
        print_error "Please run as root (use sudo)"
        exit 1
    fi
    
    # ตรวจสอบ installation
    check_installation
    
    # แสดง menu loop
    while true; do
        show_menu
    done
}

# รัน
main