#!/bin/bash
# ═══════════════════════════════════════════════════
# Task: SSL Setup
# Description: Setup SSL certificates with Let's Encrypt
# ═══════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

# Source SSL functions
if [ -f "$SCRIPT_DIR/lib/06-ssl.sh" ]; then
    source "$SCRIPT_DIR/lib/06-ssl.sh"
else
    print_error "SSL library not found: $SCRIPT_DIR/lib/06-ssl.sh"
    exit 1
fi

# ═══════════════════════════════════════════════════
# Main SSL Setup
# ═══════════════════════════════════════════════════

main() {
    clear
    print_header "SSL Certificate Setup"
    
    # Check if OneStack is installed
    if [ ! -d "/opt/onestack" ]; then
        print_error "OneStack not installed"
        exit 1
    fi
    
    # Get domain from .env
    cd /opt/onestack
    local DOMAIN=$(grep "^DOMAIN=" .env 2>/dev/null | cut -d= -f2)
    
    if [ -z "$DOMAIN" ]; then
        echo ""
        print_warning "Domain not configured in .env"
        echo ""
        read -p "Enter your domain name (e.g., example.com): " DOMAIN
        
        if [ -z "$DOMAIN" ]; then
            print_error "Domain is required"
            exit 1
        fi
        
        # Add to .env
        echo "" >> .env
        echo "# Domain Configuration" >> .env
        echo "DOMAIN=$DOMAIN" >> .env
        print_success "Added DOMAIN to .env"
    fi
    
    echo ""
    print_info "Domain: $DOMAIN"
    
    # Get email for Let's Encrypt
    local EMAIL=$(grep "^SSL_EMAIL=" .env 2>/dev/null | cut -d= -f2)
    
    if [ -z "$EMAIL" ]; then
        echo ""
        read -p "Enter email for SSL notifications: " EMAIL
        
        if [ -z "$EMAIL" ]; then
            print_error "Email is required for Let's Encrypt"
            exit 1
        fi
        
        # Add to .env
        echo "SSL_EMAIL=$EMAIL" >> .env
        print_success "Added SSL_EMAIL to .env"
    fi
    
    echo ""
    print_info "Email: $EMAIL"
    
    # Check DNS
    echo ""
    print_header "DNS Verification"
    
    print_step "Checking DNS records for $DOMAIN..."
    
    local SERVER_IP=$(curl -s ifconfig.me)
    local DOMAIN_IP=$(dig +short "$DOMAIN" | tail -n1)
    
    echo "  Server IP: $SERVER_IP"
    echo "  Domain IP: $DOMAIN_IP"
    
    if [ "$SERVER_IP" != "$DOMAIN_IP" ]; then
        echo ""
        print_warning "DNS mismatch detected!"
        echo ""
        echo "Required DNS Records:"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  Type    Host    Value"
        echo "  A       @       $SERVER_IP"
        echo "  A       *       $SERVER_IP"
        echo "  CNAME   www     @"
        echo ""
        
        if ! confirm "Continue with SSL setup anyway?"; then
            print_info "SSL setup cancelled"
            exit 0
        fi
    else
        print_success "DNS is correctly configured"
    fi
    
    # SSL setup mode
    echo ""
    print_header "SSL Setup Mode"
    echo ""
    echo "Choose SSL setup mode:"
    echo "  1) Wildcard certificate (*.domain.com) - Recommended"
    echo "  2) Individual certificates per subdomain"
    echo "  0) Cancel"
    echo ""
    
    read -p "Select mode [1-2]: " mode
    
    case $mode in
        1)
            SSL_MODE="wildcard"
            print_info "Using wildcard mode"
            ;;
        2)
            SSL_MODE="individual"
            print_info "Using individual mode"
            ;;
        0)
            print_info "Cancelled"
            exit 0
            ;;
        *)
            print_error "Invalid choice"
            exit 1
            ;;
    esac
    
    # Confirm
    echo ""
    print_warning "This will:"
    echo "  1. Install Certbot"
    echo "  2. Request SSL certificates from Let's Encrypt"
    echo "  3. Configure Nginx for HTTPS"
    echo "  4. Setup auto-renewal"
    echo ""
    
    if ! confirm "Continue with SSL setup?"; then
        print_info "SSL setup cancelled"
        exit 0
    fi
    
    # Run setup if function exists
    if type setup_ssl &>/dev/null; then
        echo ""
        setup_ssl "$DOMAIN" "$EMAIL" "$SSL_MODE"
        
        if [ $? -eq 0 ]; then
            echo ""
            print_success "SSL setup completed successfully!"
            echo ""
            print_info "Your sites are now accessible via HTTPS:"
            echo "  ✅ https://$DOMAIN"
            echo "  ✅ https://storage.$DOMAIN"
            echo "  ✅ https://api.$DOMAIN"
            echo "  ✅ https://monitor.$DOMAIN"
            echo ""
            print_info "Test your SSL: https://www.ssllabs.com/ssltest/analyze.html?d=$DOMAIN"
        else
            echo ""
            print_error "SSL setup failed"
            exit 1
        fi
    else
        # Fallback if setup_ssl doesn't exist
        print_warning "setup_ssl function not found, using fallback method"
        echo ""
        
        # Simple SSL setup
        print_step "Installing Certbot..."
        if ! command -v certbot &> /dev/null; then
            apt-get update -qq
            apt-get install -y certbot python3-certbot-nginx -qq
            print_success "Certbot installed"
        else
            print_success "Certbot already installed"
        fi
        
        echo ""
        print_step "Requesting SSL certificate..."
        
        if [ "$SSL_MODE" = "wildcard" ]; then
            print_info "Wildcard certificates require DNS validation"
            print_info "Manual setup required. Please run:"
            echo ""
            echo "  certbot certonly --manual --preferred-challenges dns \\"
            echo "    -d $DOMAIN -d *.$DOMAIN \\"
            echo "    --email $EMAIL --agree-tos"
        else
            certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" \
                -d "storage.$DOMAIN" -d "s3.$DOMAIN" \
                -d "api.$DOMAIN" -d "monitor.$DOMAIN" \
                -d "prometheus.$DOMAIN" -d "db.$DOMAIN" \
                --email "$EMAIL" --agree-tos --non-interactive
            
            if [ $? -eq 0 ]; then
                print_success "SSL certificates obtained"
                
                # Setup auto-renewal
                (crontab -l 2>/dev/null | grep -v "certbot renew"; echo "0 2,14 * * * certbot renew --quiet") | crontab -
                print_success "Auto-renewal configured"
            else
                print_error "Failed to obtain SSL certificates"
                exit 1
            fi
        fi
    fi
}

main "$@"