#!/bin/bash
# ═══════════════════════════════════════════════════
# OneStack - Add Redirect Domain
# Redirect any domain to your main domain
# ═══════════════════════════════════════════════════

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_info() { echo -e "${BLUE}ℹ${NC} $1"; }
print_step() { echo -e "${BLUE}→${NC} $1"; }
print_header() { echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n${GREEN}$1${NC}\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }

confirm() {
    local prompt="$1"
    local default="${2:-n}"
    local response
    
    if [ "$default" = "y" ]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi
    
    read -p "$prompt" response
    response=${response:-$default}
    
    [[ "$response" =~ ^[Yy]$ ]]
}

# ═══════════════════════════════════════════════════
# Main Script
# ═══════════════════════════════════════════════════

print_header "OneStack - Add Redirect Domain"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    print_error "Please run as root (use sudo)"
    exit 1
fi

# Default paths
INSTALL_DIR="/opt/onestack"
NGINX_CONF_DIR="$INSTALL_DIR/nginx/conf.d"
NGINX_SSL_DIR="$INSTALL_DIR/nginx/ssl"

# Load main domain from .env
if [ -f "$INSTALL_DIR/.env" ]; then
    source "$INSTALL_DIR/.env"
    MAIN_DOMAIN="${DOMAIN:-sixamdev.com}"
else
    print_warning ".env file not found, using default"
    MAIN_DOMAIN="sixamdev.com"
fi

print_info "Main Domain: $MAIN_DOMAIN"
echo ""

# Ask for redirect domain
read -p "Enter domain to redirect (e.g., 6amdev.com): " REDIRECT_DOMAIN

if [ -z "$REDIRECT_DOMAIN" ]; then
    print_error "Domain cannot be empty"
    exit 1
fi

# Clean domain (remove http/https)
REDIRECT_DOMAIN=$(echo "$REDIRECT_DOMAIN" | sed 's|https\?://||' | sed 's|/.*||')

print_info "Redirect Domain: $REDIRECT_DOMAIN"
print_info "Target Domain: $MAIN_DOMAIN"
echo ""

# Confirm
if ! confirm "Redirect ALL requests from $REDIRECT_DOMAIN to $MAIN_DOMAIN?" "y"; then
    print_info "Cancelled"
    exit 0
fi

# ═══════════════════════════════════════════════════
# Step 1: Check DNS
# ═══════════════════════════════════════════════════

print_header "Step 1: DNS Check"

SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || echo "unknown")
print_info "Your Server IP: $SERVER_IP"
echo ""

print_warning "Make sure you have configured DNS:"
echo "  A    $REDIRECT_DOMAIN     →  $SERVER_IP"
echo "  A    *.$REDIRECT_DOMAIN   →  $SERVER_IP"
echo ""

# Check DNS
print_step "Checking DNS for $REDIRECT_DOMAIN..."
RESOLVED_IP=$(dig +short "$REDIRECT_DOMAIN" @8.8.8.8 | head -1)

if [ -n "$RESOLVED_IP" ]; then
    if [ "$RESOLVED_IP" = "$SERVER_IP" ]; then
        print_success "DNS configured correctly: $RESOLVED_IP"
    else
        print_warning "DNS points to: $RESOLVED_IP (expected: $SERVER_IP)"
        print_info "DNS may need time to propagate (up to 48 hours)"
    fi
else
    print_warning "Cannot resolve $REDIRECT_DOMAIN"
    print_info "Make sure DNS is configured before continuing"
fi

echo ""

if ! confirm "Continue anyway?" "y"; then
    exit 0
fi

# ═══════════════════════════════════════════════════
# Step 2: SSL Certificate Options
# ═══════════════════════════════════════════════════

print_header "Step 2: SSL Certificate"

echo "Choose SSL option:"
echo "  1) Self-signed certificate (quick, browser warning)"
echo "  2) Let's Encrypt certificate (recommended, takes 1-2 min)"
echo "  3) HTTP only (no HTTPS redirect)"
echo ""

read -p "Choice [1-3]: " SSL_CHOICE

USE_SSL=true
USE_LETSENCRYPT=false

case $SSL_CHOICE in
    1)
        print_info "Using self-signed certificate"
        USE_LETSENCRYPT=false
        ;;
    2)
        print_info "Using Let's Encrypt"
        USE_LETSENCRYPT=true
        ;;
    3)
        print_info "HTTP only (no SSL)"
        USE_SSL=false
        ;;
    *)
        print_warning "Invalid choice, using self-signed"
        USE_LETSENCRYPT=false
        ;;
esac

echo ""

# ═══════════════════════════════════════════════════
# Step 3: Generate SSL Certificate
# ═══════════════════════════════════════════════════

if [ "$USE_SSL" = true ]; then
    print_header "Step 3: Generate SSL Certificate"
    
    mkdir -p "$NGINX_SSL_DIR"
    
    if [ "$USE_LETSENCRYPT" = true ]; then
        # Check certbot
        if ! command -v certbot &> /dev/null; then
            print_step "Installing certbot..."
            apt-get update -qq
            apt-get install -y certbot > /dev/null 2>&1
            print_success "Certbot installed"
        fi
        
        # Request certificate
        print_step "Requesting Let's Encrypt certificate..."
        print_warning "This will temporarily stop Nginx"
        echo ""
        
        # Stop nginx
        docker compose -f "$INSTALL_DIR/docker-compose.yml" stop nginx 2>/dev/null
        
        # Request cert
        certbot certonly \
            --standalone \
            --email "admin@$REDIRECT_DOMAIN" \
            --agree-tos \
            --no-eff-email \
            --non-interactive \
            -d "$REDIRECT_DOMAIN" \
            -d "www.$REDIRECT_DOMAIN"
        
        CERT_RESULT=$?
        
        # Start nginx
        docker compose -f "$INSTALL_DIR/docker-compose.yml" start nginx 2>/dev/null
        
        if [ $CERT_RESULT -eq 0 ]; then
            print_success "Let's Encrypt certificate obtained"
            CERT_PATH="/etc/letsencrypt/live/$REDIRECT_DOMAIN"
        else
            print_error "Failed to obtain Let's Encrypt certificate"
            print_warning "Falling back to self-signed certificate"
            USE_LETSENCRYPT=false
        fi
    fi
    
    if [ "$USE_LETSENCRYPT" = false ]; then
        # Generate self-signed
        print_step "Generating self-signed certificate..."
        
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$NGINX_SSL_DIR/$REDIRECT_DOMAIN.key" \
            -out "$NGINX_SSL_DIR/$REDIRECT_DOMAIN.crt" \
            -subj "/CN=$REDIRECT_DOMAIN" \
            > /dev/null 2>&1
        
        print_success "Self-signed certificate created"
        CERT_PATH="$NGINX_SSL_DIR"
    fi
    
    echo ""
fi

# ═══════════════════════════════════════════════════
# Step 4: Create Nginx Configuration
# ═══════════════════════════════════════════════════

print_header "Step 4: Create Nginx Configuration"

CONFIG_FILE="$NGINX_CONF_DIR/${REDIRECT_DOMAIN}-redirect.conf"

print_step "Creating configuration file..."

# Create config based on SSL choice
if [ "$USE_SSL" = false ]; then
    # HTTP only
    cat > "$CONFIG_FILE" << 'NGINXEOF'
# ═══════════════════════════════════════════════════
# REDIRECT_DOMAIN → MAIN_DOMAIN Redirect (HTTP only)
# Generated: DATE
# ═══════════════════════════════════════════════════

server {
    listen 80;
    server_name REDIRECT_DOMAIN www.REDIRECT_DOMAIN *.REDIRECT_DOMAIN;
    
    # Redirect all requests
    return 301 https://MAIN_DOMAIN$request_uri;
}
NGINXEOF

else
    # With HTTPS
    if [ "$USE_LETSENCRYPT" = true ]; then
        # Let's Encrypt
        cat > "$CONFIG_FILE" << 'NGINXEOF'
# ═══════════════════════════════════════════════════
# REDIRECT_DOMAIN → MAIN_DOMAIN Redirect
# Generated: DATE
# SSL: Let's Encrypt
# ═══════════════════════════════════════════════════

# HTTP → HTTPS
server {
    listen 80;
    server_name REDIRECT_DOMAIN www.REDIRECT_DOMAIN *.REDIRECT_DOMAIN;
    return 301 https://$host$request_uri;
}

# HTTPS → Main Domain
server {
    listen 443 ssl http2;
    server_name REDIRECT_DOMAIN www.REDIRECT_DOMAIN *.REDIRECT_DOMAIN;
    
    # Let's Encrypt SSL
    ssl_certificate /etc/letsencrypt/live/REDIRECT_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/REDIRECT_DOMAIN/privkey.pem;
    
    # SSL Settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256';
    ssl_prefer_server_ciphers off;
    
    # Redirect to main domain
    return 301 https://MAIN_DOMAIN$request_uri;
}
NGINXEOF

    else
        # Self-signed
        cat > "$CONFIG_FILE" << 'NGINXEOF'
# ═══════════════════════════════════════════════════
# REDIRECT_DOMAIN → MAIN_DOMAIN Redirect
# Generated: DATE
# SSL: Self-Signed (Browser will show warning)
# ═══════════════════════════════════════════════════

# HTTP → HTTPS
server {
    listen 80;
    server_name REDIRECT_DOMAIN www.REDIRECT_DOMAIN *.REDIRECT_DOMAIN;
    return 301 https://$host$request_uri;
}

# HTTPS → Main Domain
server {
    listen 443 ssl http2;
    server_name REDIRECT_DOMAIN www.REDIRECT_DOMAIN *.REDIRECT_DOMAIN;
    
    # Self-Signed SSL
    ssl_certificate /etc/nginx/ssl/REDIRECT_DOMAIN.crt;
    ssl_certificate_key /etc/nginx/ssl/REDIRECT_DOMAIN.key;
    
    # SSL Settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256';
    ssl_prefer_server_ciphers off;
    
    # Redirect to main domain
    return 301 https://MAIN_DOMAIN$request_uri;
}
NGINXEOF

    fi
fi

# Replace placeholders
sed -i "s|REDIRECT_DOMAIN|$REDIRECT_DOMAIN|g" "$CONFIG_FILE"
sed -i "s|MAIN_DOMAIN|$MAIN_DOMAIN|g" "$CONFIG_FILE"
sed -i "s|DATE|$(date)|g" "$CONFIG_FILE"

print_success "Configuration created: $CONFIG_FILE"
echo ""

# ═══════════════════════════════════════════════════
# Step 5: Test and Reload Nginx
# ═══════════════════════════════════════════════════

print_header "Step 5: Apply Configuration"

print_step "Testing Nginx configuration..."

if docker compose -f "$INSTALL_DIR/docker-compose.yml" exec -T nginx nginx -t 2>&1 | grep -q "successful"; then
    print_success "Configuration valid"
    
    print_step "Reloading Nginx..."
    docker compose -f "$INSTALL_DIR/docker-compose.yml" exec -T nginx nginx -s reload
    print_success "Nginx reloaded"
else
    print_error "Configuration test failed!"
    print_warning "Config file: $CONFIG_FILE"
    print_info "You can manually fix and reload with:"
    echo "  docker compose -f $INSTALL_DIR/docker-compose.yml exec nginx nginx -t"
    echo "  docker compose -f $INSTALL_DIR/docker-compose.yml exec nginx nginx -s reload"
    exit 1
fi

echo ""

# ═══════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════

print_header "✅ Setup Complete!"

print_success "Redirect configured successfully"
echo ""

print_info "Configuration:"
echo "  From: $REDIRECT_DOMAIN"
echo "  To:   $MAIN_DOMAIN"
if [ "$USE_SSL" = true ]; then
    if [ "$USE_LETSENCRYPT" = true ]; then
        echo "  SSL:  Let's Encrypt (valid)"
    else
        echo "  SSL:  Self-Signed (browser warning)"
    fi
else
    echo "  SSL:  None (HTTP only)"
fi
echo ""

print_info "Test URLs:"
echo "  http://$REDIRECT_DOMAIN"
echo "  http://www.$REDIRECT_DOMAIN"
if [ "$USE_SSL" = true ]; then
    echo "  https://$REDIRECT_DOMAIN"
    echo "  https://www.$REDIRECT_DOMAIN"
fi
echo ""

print_warning "All requests will redirect to: https://$MAIN_DOMAIN"
echo ""

# Auto-renewal reminder
if [ "$USE_LETSENCRYPT" = true ]; then
    print_info "Let's Encrypt auto-renewal:"
    echo "  Certificate will auto-renew via certbot cron job"
    echo "  Check status: certbot certificates"
    echo ""
fi

print_success "Done! Test with: curl -I http://$REDIRECT_DOMAIN"
echo ""