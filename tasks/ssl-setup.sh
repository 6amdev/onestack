#!/bin/bash
# ═══════════════════════════════════════════════════
# OneStack - Quick SSL Setup
# Automatically configure SSL for all services
# ═══════════════════════════════════════════════════

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
INSTALL_DIR="/opt/onestack"

# โหลด utilities
source "$SCRIPT_DIR/lib/utils.sh" 2>/dev/null || {
    echo "Error: Cannot load utilities"
    exit 1
}

# โหลด SSL functions
source "$SCRIPT_DIR/lib/06-ssl.sh" 2>/dev/null || {
    print_error "Cannot load SSL functions"
    exit 1
}

# ═══════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════

main() {
    clear
    
    echo ""
    echo "╔════════════════════════════════════════════════╗"
    echo "║                                                ║"
    echo "║       OneStack SSL Certificate Setup           ║"
    echo "║         Smart Auto-Discovery System            ║"
    echo "║                                                ║"
    echo "╚════════════════════════════════════════════════╝"
    echo ""
    
    # ตรวจสอบ root
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root"
        echo ""
        print_info "Please run: sudo bash tasks/ssl-setup.sh"
        exit 1
    fi
    
    # ตรวจสอบว่าติดตั้ง OneStack แล้ว
    if [ ! -d "$INSTALL_DIR" ]; then
        print_error "OneStack not installed"
        echo ""
        print_info "Please install OneStack first:"
        echo "  sudo bash install.sh"
        exit 1
    fi
    
    cd "$INSTALL_DIR"
    
    # โหลด configuration
    if [ ! -f ".env" ]; then
        print_error ".env file not found"
        exit 1
    fi
    
    source .env
    
    # ตรวจสอบ domain
    if [ -z "$DOMAIN" ] || [ "$DOMAIN" = "localhost" ]; then
        print_error "Domain not configured"
        echo ""
        print_info "Please set your domain in .env file:"
        echo ""
        echo "  nano $INSTALL_DIR/.env"
        echo ""
        echo "Add these lines:"
        echo "  DOMAIN=yourdomain.com"
        echo "  SSL_EMAIL=admin@yourdomain.com"
        echo "  SSL_MODE=production"
        echo ""
        exit 1
    fi
    
    # แสดง configuration
    print_header "Current Configuration"
    echo ""
    echo "  📌 Domain: $DOMAIN"
    echo "  📧 Email: ${SSL_EMAIL:-admin@$DOMAIN}"
    echo "  🔧 Mode: ${SSL_MODE:-production}"
    echo ""
    
    # คำเตือนสำหรับ production mode
    if [ "${SSL_MODE:-production}" = "production" ]; then
        print_warning "PRODUCTION MODE"
        echo ""
        echo "  This will request REAL certificates from Let's Encrypt"
        echo ""
        echo "  Rate Limits:"
        echo "    • 5 certificates per week per domain"
        echo "    • 50 certificates per week per account"
        echo ""
        echo "  If testing, set SSL_MODE=staging in .env"
        echo ""
        
        if ! confirm "Continue with PRODUCTION mode?"; then
            print_info "Setup cancelled"
            echo ""
            print_info "To use staging mode:"
            echo "  1. Edit: nano $INSTALL_DIR/.env"
            echo "  2. Add/change: SSL_MODE=staging"
            echo "  3. Run this script again"
            exit 0
        fi
    else
        print_info "STAGING MODE - Test certificates only"
        echo ""
        print_warning "Browsers will show 'Not Secure' warning"
        echo ""
        
        if ! confirm "Continue with STAGING mode?"; then
            exit 0
        fi
    fi
    
    echo ""
    print_info "Starting Smart SSL Setup..."
    echo ""
    sleep 2
    
    # เรียกใช้ Smart SSL Manager
    setup_ssl_smart "$INSTALL_DIR" "$INSTALL_DIR/.env"
    
    local result=$?
    
    if [ $result -eq 0 ]; then
        echo ""
        echo "╔════════════════════════════════════════════════╗"
        echo "║                                                ║"
        echo "║         ✅ SSL Setup Complete!                 ║"
        echo "║                                                ║"
        echo "╚════════════════════════════════════════════════╝"
        echo ""
        
        # แสดง URLs ที่พร้อมใช้งาน
        print_success "Your secure URLs:"
        echo ""
        
        # อ่าน services จาก docker-compose
        if [ -f "docker-compose.yml" ]; then
            # Main site
            echo "  🌐 https://$DOMAIN"
            echo "  🌐 https://www.$DOMAIN"
            echo ""
            
            # Services
            if docker compose ps | grep -q "minio"; then
                echo "  💾 MinIO Console: https://storage.$DOMAIN"
                echo "  💾 S3 API: https://s3.$DOMAIN"
            fi
            
            if docker compose ps | grep -q "parse"; then
                echo "  🚀 Parse Server: https://api.$DOMAIN"
            fi
            
            if docker compose ps | grep -q "n8n"; then
                echo "  🔄 n8n: https://flow.$DOMAIN"
            fi
            
            if docker compose ps | grep -q "chatwoot"; then
                echo "  💬 Chatwoot: https://chat.$DOMAIN"
            fi
            
            if docker compose ps | grep -q "grafana"; then
                echo "  📊 Grafana: https://monitor.$DOMAIN"
            fi
            
            if docker compose ps | grep -q "adminer"; then
                echo "  🗄️ Adminer: https://db.$DOMAIN"
            fi
        fi
        
        echo ""
        print_info "SSL Management:"
        echo "  • Auto-renewal: Enabled (twice daily)"
        echo "  • Manual renewal: certbot renew"
        echo "  • Check status: certbot certificates"
        echo ""
        
        print_info "Useful Commands:"
        echo "  • View logs: tail -f /opt/onestack/logs/ssl-renewal.log"
        echo "  • Test renewal: certbot renew --dry-run"
        echo "  • Nginx reload: docker compose exec nginx nginx -s reload"
        echo ""
        
    else
        echo ""
        print_error "SSL setup failed"
        echo ""
        print_info "Common issues:"
        echo "  1. DNS not configured correctly"
        echo "     → Check: dig $DOMAIN"
        echo ""
        echo "  2. Port 80/443 not accessible"
        echo "     → Check firewall: ufw status"
        echo ""
        echo "  3. Nginx not running"
        echo "     → Check: docker compose ps nginx"
        echo ""
        print_info "For help, check:"
        echo "  • Logs: /var/log/letsencrypt/letsencrypt.log"
        echo "  • Documentation: docs/ssl-setup.md"
        echo ""
        exit 1
    fi
}

# Run
main "$@"