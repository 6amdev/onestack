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
    
    cd /opt/onestack
    
    # Get domain from .env
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
    
    local SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || echo "unknown")
    local DOMAIN_IP=$(dig +short "$DOMAIN" 2>/dev/null | tail -n1)
    
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
    echo "  1) Individual certificates per subdomain (Recommended)"
    echo "  2) Wildcard certificate (*.domain.com) - Requires DNS validation"
    echo "  0) Cancel"
    echo ""
    
    read -p "Select mode [0-2]: " mode
    
    local SSL_MODE
    case $mode in
        1)
            SSL_MODE="individual"
            print_info "Using individual certificates mode"
            ;;
        2)
            SSL_MODE="wildcard"
            print_info "Using wildcard mode"
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
    echo "  1. Install Certbot (if not installed)"
    echo "  2. Request SSL certificates from Let's Encrypt"
    echo "  3. Setup auto-renewal (twice daily)"
    echo ""
    
    if ! confirm "Continue with SSL setup?"; then
        print_info "SSL setup cancelled"
        exit 0
    fi
    
    # Run setup
    echo ""
    print_header "Installing SSL Certificates"
    echo ""
    
    # Call the setup_ssl function with correct parameters
    setup_ssl "$DOMAIN" "$EMAIL" "$SSL_MODE"
    
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        echo ""
        print_success "SSL setup completed successfully!"
        echo ""
        print_info "Your sites are now accessible via HTTPS:"
        echo "  ✅ https://$DOMAIN"
        echo "  ✅ https://www.$DOMAIN"
        echo "  ✅ https://storage.$DOMAIN"
        echo "  ✅ https://api.$DOMAIN"
        echo "  ✅ https://monitor.$DOMAIN"
        echo ""
        print_info "Test your SSL grade:"
        print_info "  https://www.ssllabs.com/ssltest/analyze.html?d=$DOMAIN"
        echo ""
        print_info "Auto-renewal is configured to run twice daily"
    else
        echo ""
        print_error "SSL setup failed"
        echo ""
        print_info "Common issues:"
        echo "  1. DNS not pointing to this server"
        echo "  2. Ports 80/443 not accessible"
        echo "  3. Domain validation failed"
        echo ""
        print_info "For manual setup, run:"
        echo "  certbot certonly --nginx -d $DOMAIN -d www.$DOMAIN --email $EMAIL"
        exit 1
    fi
}

main "$@"