#!/bin/bash
# ═══════════════════════════════════════════════════
# OneStack - Complete Fix Script
# Fix all SSL and task files at once
# ═══════════════════════════════════════════════════

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${YELLOW}ℹ${NC} $1"
}

print_step() {
    echo -e "${BLUE}▶${NC} $1"
}

# Check root
if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root"
    exit 1
fi

# Check if OneStack installed
if [ ! -d "/root/onestack" ]; then
    print_error "OneStack not found at /root/onestack"
    exit 1
fi

cd /root/onestack

print_header "OneStack Complete Fix"
echo ""
print_info "This will fix all SSL and task files"
echo ""

# ═══════════════════════════════════════════════════
# 1. Fix lib/06-ssl.sh
# ═══════════════════════════════════════════════════

print_step "Fixing lib/06-ssl.sh..."

cat > lib/06-ssl.sh << 'EOF_SSL_LIB'
#!/bin/bash
# ═══════════════════════════════════════════════════
# OneStack SSL Management Library
# ═══════════════════════════════════════════════════

# Get library directory
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LIB_DIR/utils.sh"

# ═══════════════════════════════════════════════════
# Install Certbot
# ═══════════════════════════════════════════════════

install_certbot() {
    print_step "Installing Certbot..."
    
    if command -v certbot &> /dev/null; then
        print_success "Certbot already installed"
        certbot --version
        return 0
    fi
    
    apt-get update -qq
    apt-get install -y certbot -qq
    
    if command -v certbot &> /dev/null; then
        print_success "Certbot installed successfully"
        certbot --version
        return 0
    else
        print_error "Failed to install Certbot"
        return 1
    fi
}

# ═══════════════════════════════════════════════════
# Setup SSL (Standalone Mode)
# ═══════════════════════════════════════════════════

setup_ssl() {
    local domain=$1
    local email=$2
    local mode=${3:-"standalone"}
    
    if [ -z "$domain" ] || [ -z "$email" ]; then
        print_error "Domain and email are required"
        return 1
    fi
    
    print_header "SSL Setup - Standalone Mode"
    
    cd /opt/onestack
    
    # Stop Docker Nginx temporarily
    print_step "Stopping Docker Nginx..."
    docker compose stop nginx
    sleep 3
    print_success "Nginx stopped"
    
    # Request certificate using standalone mode
    print_step "Requesting SSL certificate..."
    certbot certonly --standalone \
        -d "$domain" \
        -d "www.$domain" \
        -d "storage.$domain" \
        -d "s3.$domain" \
        -d "api.$domain" \
        -d "monitor.$domain" \
        -d "prometheus.$domain" \
        -d "db.$domain" \
        --email "$email" \
        --agree-tos \
        --non-interactive
    
    local result=$?
    
    # Start Docker Nginx back
    print_step "Starting Docker Nginx..."
    docker compose start nginx
    sleep 3
    print_success "Nginx started"
    
    if [ $result -eq 0 ]; then
        print_success "SSL certificates obtained successfully!"
        
        # Setup auto-renewal
        print_step "Setting up auto-renewal..."
        (crontab -l 2>/dev/null | grep -v "certbot renew"; \
         echo "0 2,14 * * * certbot renew --quiet --pre-hook 'docker compose -f /opt/onestack/docker-compose.yml stop nginx' --post-hook 'docker compose -f /opt/onestack/docker-compose.yml start nginx'") | crontab -
        
        print_success "Auto-renewal configured (twice daily)"
        return 0
    else
        print_error "Failed to obtain SSL certificates"
        return 1
    fi
}

# ═══════════════════════════════════════════════════
# Renew SSL Certificates
# ═══════════════════════════════════════════════════

renew_ssl_certificates() {
    print_header "Renewing SSL Certificates"
    
    print_step "Running certificate renewal..."
    certbot renew
    
    if [ $? -eq 0 ]; then
        print_success "Certificate renewal completed"
        
        # Reload Nginx
        print_step "Reloading Nginx..."
        docker compose -f /opt/onestack/docker-compose.yml exec nginx nginx -s reload 2>/dev/null
        
        return 0
    else
        print_error "Certificate renewal failed"
        return 1
    fi
}

# ═══════════════════════════════════════════════════
# Check SSL Status
# ═══════════════════════════════════════════════════

check_ssl_status() {
    print_header "SSL Certificate Status"
    
    local domain=$1
    
    if [ -z "$domain" ]; then
        if [ -f "/opt/onestack/.env" ]; then
            domain=$(grep "^DOMAIN=" /opt/onestack/.env 2>/dev/null | cut -d= -f2)
        fi
    fi
    
    if [ -z "$domain" ]; then
        print_warning "Domain not specified"
        echo ""
    else
        print_info "Checking SSL for: $domain"
        echo ""
        
        if [ -d "/etc/letsencrypt/live/$domain" ]; then
            print_success "Certificate found for $domain"
            
            local cert_file="/etc/letsencrypt/live/$domain/cert.pem"
            if [ -f "$cert_file" ]; then
                local expiry=$(openssl x509 -in "$cert_file" -noout -enddate | cut -d= -f2)
                echo "  Expires: $expiry"
            fi
        else
            print_warning "No certificate found for $domain"
        fi
        echo ""
    fi
    
    print_info "All installed certificates:"
    certbot certificates 2>/dev/null || echo "  (none)"
}

# Export functions
export -f install_certbot
export -f setup_ssl
export -f renew_ssl_certificates
export -f check_ssl_status
EOF_SSL_LIB

print_success "lib/06-ssl.sh fixed"

# ═══════════════════════════════════════════════════
# 2. Fix tasks/ssl-setup.sh
# ═══════════════════════════════════════════════════

print_step "Fixing tasks/ssl-setup.sh..."

cat > tasks/ssl-setup.sh << 'EOF_SSL_SETUP'
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
    print_error "SSL library not found"
    exit 1
fi

# ═══════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════

main() {
    clear
    print_header "SSL Certificate Setup"
    
    if [ ! -d "/opt/onestack" ]; then
        print_error "OneStack not installed"
        exit 1
    fi
    
    cd /opt/onestack
    
    # Get domain
    local DOMAIN=$(grep "^DOMAIN=" .env 2>/dev/null | cut -d= -f2)
    
    if [ -z "$DOMAIN" ]; then
        echo ""
        print_warning "Domain not configured in .env"
        echo ""
        read -p "Enter your domain name: " DOMAIN
        
        if [ -z "$DOMAIN" ]; then
            print_error "Domain is required"
            exit 1
        fi
        
        echo "DOMAIN=$DOMAIN" >> .env
        print_success "Added DOMAIN to .env"
    fi
    
    # Get email
    local EMAIL=$(grep "^SSL_EMAIL=" .env 2>/dev/null | cut -d= -f2)
    
    if [ -z "$EMAIL" ]; then
        echo ""
        read -p "Enter email for SSL notifications: " EMAIL
        
        if [ -z "$EMAIL" ]; then
            print_error "Email is required"
            exit 1
        fi
        
        echo "SSL_EMAIL=$EMAIL" >> .env
        print_success "Added SSL_EMAIL to .env"
    fi
    
    echo ""
    print_info "Domain: $DOMAIN"
    print_info "Email: $EMAIL"
    echo ""
    
    # Confirm
    print_warning "This will:"
    echo "  1. Stop Docker Nginx temporarily"
    echo "  2. Request SSL certificates from Let's Encrypt"
    echo "  3. Start Docker Nginx"
    echo "  4. Setup auto-renewal (twice daily)"
    echo ""
    
    if ! confirm "Continue with SSL setup?"; then
        print_info "Cancelled"
        exit 0
    fi
    
    # Install Certbot
    echo ""
    install_certbot
    
    # Setup SSL
    echo ""
    setup_ssl "$DOMAIN" "$EMAIL" "standalone"
    
    if [ $? -eq 0 ]; then
        echo ""
        print_success "✅ SSL Setup Complete!"
        echo ""
        print_info "Certificates location: /etc/letsencrypt/live/$DOMAIN/"
        print_info "Auto-renewal: Twice daily (2 AM, 2 PM)"
        echo ""
        print_warning "⚠️  Next: Update Nginx config to use HTTPS"
        print_info "Run: ./manage.sh → 15) Quick Fix"
    else
        echo ""
        print_error "SSL setup failed"
        exit 1
    fi
}

main "$@"
EOF_SSL_SETUP

chmod +x tasks/ssl-setup.sh
print_success "tasks/ssl-setup.sh fixed"

# ═══════════════════════════════════════════════════
# 3. Fix tasks/ssl-renew.sh
# ═══════════════════════════════════════════════════

print_step "Fixing tasks/ssl-renew.sh..."

cat > tasks/ssl-renew.sh << 'EOF_SSL_RENEW'
#!/bin/bash
# ═══════════════════════════════════════════════════
# Task: SSL Renew
# Description: Renew SSL certificates
# ═══════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/06-ssl.sh"

main() {
    clear
    renew_ssl_certificates
    
    if [ $? -eq 0 ]; then
        print_success "✅ SSL certificates renewed successfully"
        
        print_step "Reloading Nginx..."
        docker compose -f /opt/onestack/docker-compose.yml exec nginx nginx -s reload 2>/dev/null
    else
        print_error "SSL renewal failed"
        exit 1
    fi
}

main "$@"
EOF_SSL_RENEW

chmod +x tasks/ssl-renew.sh
print_success "tasks/ssl-renew.sh fixed"

# ═══════════════════════════════════════════════════
# 4. Fix tasks/ssl-status.sh
# ═══════════════════════════════════════════════════

print_step "Fixing tasks/ssl-status.sh..."

cat > tasks/ssl-status.sh << 'EOF_SSL_STATUS'
#!/bin/bash
# ═══════════════════════════════════════════════════
# Task: SSL Status
# Description: Check SSL certificate status
# ═══════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/06-ssl.sh"

main() {
    clear
    check_ssl_status
    echo ""
}

main "$@"
EOF_SSL_STATUS

chmod +x tasks/ssl-status.sh
print_success "tasks/ssl-status.sh fixed"

# ═══════════════════════════════════════════════════
# 5. Create tasks/fix-env.sh (if not exists)
# ═══════════════════════════════════════════════════

if [ ! -f "tasks/fix-env.sh" ]; then
    print_step "Creating tasks/fix-env.sh..."
    
    cat > tasks/fix-env.sh << 'EOF_FIX_ENV'
#!/bin/bash
# ═══════════════════════════════════════════════════
# Task: Fix .env Configuration
# Description: Fix missing environment variables
# ═══════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

main() {
    clear
    print_header "Fix .env Configuration"
    
    local ENV_FILE="/opt/onestack/.env"
    
    if [ ! -f "$ENV_FILE" ]; then
        print_error ".env file not found"
        exit 1
    fi
    
    # Backup
    cp "$ENV_FILE" "${ENV_FILE}.backup-$(date +%Y%m%d_%H%M%S)"
    print_success "Backed up .env file"
    
    echo ""
    print_step "Checking for missing variables..."
    
    # Check DOMAIN
    if ! grep -q "^DOMAIN=" "$ENV_FILE"; then
        print_warning "DOMAIN not found"
        read -p "Enter domain name: " domain
        if [ -n "$domain" ]; then
            echo "" >> "$ENV_FILE"
            echo "DOMAIN=$domain" >> "$ENV_FILE"
            print_success "Added DOMAIN=$domain"
        fi
    else
        print_success "DOMAIN is set"
    fi
    
    # Check MONGODB_PASSWORD
    if ! grep -q "^MONGODB_PASSWORD=" "$ENV_FILE"; then
        print_warning "MONGODB_PASSWORD not found"
        local pass=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
        echo "MONGODB_PASSWORD=$pass" >> "$ENV_FILE"
        print_success "Added MONGODB_PASSWORD"
    else
        print_success "MONGODB_PASSWORD is set"
    fi
    
    echo ""
    print_success "✅ .env configuration fixed"
    
    echo ""
    if confirm "Restart services to apply changes?"; then
        cd /opt/onestack
        docker compose restart
        print_success "Services restarted"
    fi
}

main "$@"
EOF_FIX_ENV
    
    chmod +x tasks/fix-env.sh
    print_success "tasks/fix-env.sh created"
else
    print_info "tasks/fix-env.sh already exists (skipped)"
fi

# ═══════════════════════════════════════════════════
# Done!
# ═══════════════════════════════════════════════════

echo ""
print_header "Fix Complete"
echo ""
print_success "All files have been fixed!"
echo ""
echo "📋 Fixed files:"
echo "  ✓ lib/06-ssl.sh"
echo "  ✓ tasks/ssl-setup.sh"
echo "  ✓ tasks/ssl-renew.sh"
echo "  ✓ tasks/ssl-status.sh"
echo "  ✓ tasks/fix-env.sh"
echo ""
echo "🎯 Ready to use:"
echo "  ./manage.sh → 1) Setup SSL"
echo "  ./manage.sh → 2) Renew SSL"
echo "  ./manage.sh → 3) Check SSL status"
echo "  ./manage.sh → 16) Fix .env configuration"
echo ""
echo "✨ OneStack is ready!"
echo ""