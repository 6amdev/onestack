#!/bin/bash
# ═══════════════════════════════════════════════════
# OneStack - SSL Setup Task
# ═══════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/06-ssl.sh"

# ═══════════════════════════════════════════════════
# Main SSL Setup
# ═══════════════════════════════════════════════════

main() {
    print_header "SSL Certificate Setup"
    
    # Check if already configured
    local CONFIG_FILE="$SCRIPT_DIR/config.yml"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        # Try alternate location
        CONFIG_FILE="/root/onestack/config.yml"
    fi
    
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Config file not found: config.yml"
        print_info "Expected location: $SCRIPT_DIR/config.yml"
        exit 1
    fi
    
    # Read configuration
    local DOMAIN=$(yq eval '.domain.primary' "$CONFIG_FILE" 2>/dev/null)
    local SSL_EMAIL=$(yq eval '.domain.ssl_email' "$CONFIG_FILE" 2>/dev/null)
    local SSL_MODE=$(yq eval '.domain.ssl_mode' "$CONFIG_FILE" 2>/dev/null)
    
    # Validate
    if [ -z "$DOMAIN" ] || [ "$DOMAIN" = "null" ]; then
        print_error "Domain not configured in config.yml"
        exit 1
    fi
    
    if [ -z "$SSL_EMAIL" ] || [ "$SSL_EMAIL" = "null" ]; then
        print_error "SSL email not configured in config.yml"
        exit 1
    fi
    
    if [ -z "$SSL_MODE" ] || [ "$SSL_MODE" = "null" ]; then
        SSL_MODE="production"
        print_warning "SSL mode not specified, using: production"
    fi
    
    # Show configuration
    echo ""
    print_info "Configuration:"
    echo "  Domain:      $DOMAIN"
    echo "  Email:       $SSL_EMAIL"
    echo "  Mode:        $SSL_MODE"
    echo ""
    
    # Check if already has SSL
    if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
        print_warning "SSL certificate already exists for $DOMAIN"
        
        # Show expiry
        check_ssl_expiry "$DOMAIN"
        
        echo ""
        read -p "Recreate certificate? (y/N): " recreate
        
        if [ "$recreate" != "y" ]; then
            print_info "Setup cancelled"
            exit 0
        fi
    fi
    
    # DNS Check
    print_step "Checking DNS configuration..."
    
    local DNS_IP=$(dig +short "$DOMAIN" | tail -1)
    local SERVER_IP=$(curl -s ifconfig.me)
    
    echo "  Domain:    $DOMAIN"
    echo "  DNS IP:    $DNS_IP"
    echo "  Server IP: $SERVER_IP"
    echo ""
    
    if [ "$DNS_IP" != "$SERVER_IP" ]; then
        print_error "DNS is not pointing to this server!"
        print_info "Please configure DNS first:"
        print_info "  A    @    $SERVER_IP"
        print_info "  A    *    $SERVER_IP"
        echo ""
        read -p "Continue anyway? (y/N): " force
        [ "$force" != "y" ] && exit 1
    else
        print_success "DNS is correctly configured"
    fi
    
    # Mode confirmation
    if [ "$SSL_MODE" = "production" ]; then
        echo ""
        print_warning "═══════════════════════════════════════════════════════"
        print_warning "  PRODUCTION MODE"
        print_warning "═══════════════════════════════════════════════════════"
        print_warning "This will request REAL SSL certificates from Let's Encrypt"
        print_warning ""
        print_warning "Rate Limits:"
        print_warning "  • 5 certificates per week per domain"
        print_warning "  • 50 certificates per week per account"
        print_warning ""
        print_warning "If you're testing, use staging mode instead!"
        print_warning "  (Change ssl_mode: staging in config.yml)"
        print_warning "═══════════════════════════════════════════════════════"
        echo ""
        read -p "Continue with PRODUCTION mode? (yes/no): " confirm
        
        if [ "$confirm" != "yes" ]; then
            print_info "Setup cancelled"
            print_info "To use staging mode, edit config.yml:"
            print_info "  ssl_mode: staging"
            exit 0
        fi
    else
        print_info "Using STAGING mode (test certificates)"
    fi
    
    # Pre-flight checks
    print_step "Running pre-flight checks..."
    
    # Check port 80
    if ! nc -z localhost 80 2>/dev/null; then
        print_error "Port 80 is not accessible"
        print_info "Make sure Nginx is running"
        exit 1
    fi
    
    # Check webroot
    if [ ! -d "/opt/onestack/frontends/main" ]; then
        print_error "Webroot not found: /opt/onestack/frontends/main"
        exit 1
    fi
    
    print_success "Pre-flight checks passed"
    
    # Final confirmation
    echo ""
    read -p "Start SSL setup now? (Y/n): " start
    [ "$start" = "n" ] && exit 0
    
    # Run setup
    echo ""
    setup_ssl "$CONFIG_FILE"
    
    if [ $? -eq 0 ]; then
        echo ""
        print_success "═══════════════════════════════════════════════════════"
        print_success "  SSL Setup Complete!"
        print_success "═══════════════════════════════════════════════════════"
        echo ""
        print_info "Your site is now accessible via HTTPS:"
        echo ""
        echo "  ✅ https://$DOMAIN"
        echo "  ✅ https://www.$DOMAIN"
        echo "  ✅ https://storage.$DOMAIN"
        echo "  ✅ https://s3.$DOMAIN"
        echo "  ✅ https://api.$DOMAIN"
        echo "  ✅ https://monitor.$DOMAIN"
        echo "  ✅ https://prometheus.$DOMAIN"
        echo "  ✅ https://db.$DOMAIN"
        echo ""
        print_info "Auto-renewal is configured (runs twice daily)"
        echo ""
        print_info "Test your SSL grade:"
        echo "  https://www.ssllabs.com/ssltest/analyze.html?d=$DOMAIN"
        echo ""
        
        # Update Parse Server URL
        print_step "Updating Parse Server public URL..."
        sed -i "s|http://api.$DOMAIN|https://api.$DOMAIN|g" /opt/onestack/.env
        docker compose -f /opt/onestack/docker-compose.yml restart parse-server
        
        print_success "Setup complete!"
    else
        echo ""
        print_error "SSL setup failed"
        print_info "Check the errors above and try again"
        exit 1
    fi
}

# Run
check_root
main