cat > /root/onestack/lib/06-ssl.sh << 'EOFSSL'
#!/bin/bash
# ═══════════════════════════════════════════════════
# OneStack - SSL Management Functions (Main Domain Only)
# ═══════════════════════════════════════════════════

# Load utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

# ═══════════════════════════════════════════════════
# Install Certbot
# ═══════════════════════════════════════════════════

install_certbot() {
    print_step "Installing Certbot..."
    
    apt-get update
    apt-get install -y certbot python3-certbot-nginx
    
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
# Request Certificate (Main Domain Only)
# ═══════════════════════════════════════════════════

request_ssl_certificate() {
    local domain=$1
    local email=$2
    local mode=${3:-production}
    
    print_step "Requesting SSL certificate..."
    print_info "Domain: $domain"
    print_info "Mode: $mode"
    
    local STAGING_FLAG=""
    if [ "$mode" = "staging" ]; then
        STAGING_FLAG="--staging"
        print_warning "Using STAGING mode (test certificates)"
    fi
    
    # Request cert for main domain and www only
    print_info "Requesting certificate for:"
    echo "  • $domain"
    echo "  • www.$domain"
    echo ""
    
    certbot certonly --webroot \
        -w /opt/onestack/frontends/main \
        -d "$domain" \
        -d "www.$domain" \
        --email "$email" \
        --agree-tos \
        --non-interactive \
        $STAGING_FLAG
    
    if [ $? -eq 0 ]; then
        print_success "Certificate obtained!"
        return 0
    else
        print_error "Certificate request failed"
        return 1
    fi
}

# ═══════════════════════════════════════════════════
# Update Nginx Config
# ═══════════════════════════════════════════════════

update_nginx_ssl_config() {
    local domain=$1
    
    print_step "Updating Nginx configuration..."
    
    # Backup
    local NGINX_CONF="/opt/onestack/nginx/conf.d/onestack.conf"
    local BACKUP="/opt/onestack/nginx/conf.d/onestack.conf.backup-$(date +%Y%m%d_%H%M%S)"
    
    if [ -f "$NGINX_CONF" ]; then
        cp "$NGINX_CONF" "$BACKUP"
        print_info "Backup: $BACKUP"
    fi
    
    # Create SSL config (main domain only)
    cat > "$NGINX_CONF" << NGINX_EOF
# ═══════════════════════════════════════════════════
# OneStack - Main Domain SSL Configuration
# ═══════════════════════════════════════════════════

# HTTP → HTTPS Redirect
server {
    listen 80;
    server_name $domain www.$domain;
    
    # ACME Challenge
    location /.well-known/acme-challenge/ {
        root /var/www/main;
    }
    
    # Redirect to HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}

# Main Site HTTPS
server {
    listen 443 ssl http2;
    server_name $domain www.$domain;
    
    # SSL Certificates
    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;
    
    # SSL Settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers HIGH:!aNULL:!MD5;
    
    # Security Headers
    add_header Strict-Transport-Security "max-age=31536000" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    
    # Root
    root /var/www/main;
    index index.html;
    
    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
NGINX_EOF
    
    # Test config
    docker compose -f /opt/onestack/docker-compose.yml exec nginx nginx -t
    
    if [ $? -eq 0 ]; then
        print_success "Nginx config valid"
        
        # Reload
        docker compose -f /opt/onestack/docker-compose.yml exec nginx nginx -s reload
        print_success "Nginx reloaded"
        return 0
    else
        print_error "Nginx config invalid"
        return 1
    fi
}

# ═══════════════════════════════════════════════════
# Auto-renewal Setup
# ═══════════════════════════════════════════════════

setup_ssl_auto_renewal() {
    print_step "Setting up auto-renewal..."
    
    mkdir -p /opt/onestack/scripts /opt/onestack/logs
    
    # Create renewal script
    cat > /opt/onestack/scripts/ssl-renew.sh << 'RENEWAL_EOF'
#!/bin/bash
LOG="/opt/onestack/logs/ssl-renewal.log"
echo "[$(date)] Starting renewal..." >> "$LOG"
certbot renew --quiet >> "$LOG" 2>&1
docker compose -f /opt/onestack/docker-compose.yml exec nginx nginx -s reload >> "$LOG" 2>&1
echo "[$(date)] Done" >> "$LOG"
RENEWAL_EOF
    
    chmod +x /opt/onestack/scripts/ssl-renew.sh
    
    # Add cron
    (crontab -l 2>/dev/null | grep -v ssl-renew; echo "0 2,14 * * * /opt/onestack/scripts/ssl-renew.sh") | crontab -
    
    print_success "Auto-renewal configured (2 AM and 2 PM daily)"
}

# ═══════════════════════════════════════════════════
# Main Setup Function
# ═══════════════════════════════════════════════════

setup_ssl() {
    local CONFIG_FILE="${1:-$SCRIPT_DIR/config.yml}"
    
    print_header "Setting up SSL/HTTPS"
    
    # Read config
    local DOMAIN=$(yq eval '.domain.primary' "$CONFIG_FILE" 2>/dev/null)
    local SSL_EMAIL=$(yq eval '.domain.ssl_email' "$CONFIG_FILE" 2>/dev/null)
    local SSL_MODE=$(yq eval '.domain.ssl_mode' "$CONFIG_FILE" 2>/dev/null)
    
    # Fallback
    if [ -z "$DOMAIN" ] || [ "$DOMAIN" = "null" ]; then
        DOMAIN=$(grep "primary:" "$CONFIG_FILE" | sed 's/.*primary:\s*//' | tr -d '"' | tr -d "'" | head -1)
        SSL_EMAIL=$(grep "ssl_email:" "$CONFIG_FILE" | sed 's/.*ssl_email:\s*//' | tr -d '"' | tr -d "'" | head -1)
        SSL_MODE=$(grep "ssl_mode:" "$CONFIG_FILE" | sed 's/.*ssl_mode:\s*//' | awk '{print $1}' | head -1)
    fi
    
    [ -z "$SSL_MODE" ] && SSL_MODE="staging"
    
    echo ""
    print_info "Domain: $DOMAIN"
    print_info "Email: $SSL_EMAIL"
    print_info "Mode: $SSL_MODE"
    
    # Install Certbot
    install_certbot || return 1
    
    # Request certificate (main domain only)
    request_ssl_certificate "$DOMAIN" "$SSL_EMAIL" "$SSL_MODE" || return 1
    
    # Update Nginx
    update_nginx_ssl_config "$DOMAIN" || return 1
    
    # Setup auto-renewal
    setup_ssl_auto_renewal || return 1
    
    # Success
    print_success "SSL setup complete!"
    
    return 0
}

# ═══════════════════════════════════════════════════
# Utility Functions
# ═══════════════════════════════════════════════════

check_ssl_expiry() {
    local domain=$1
    
    if [ -f "/etc/letsencrypt/live/$domain/cert.pem" ]; then
        openssl x509 -in "/etc/letsencrypt/live/$domain/cert.pem" -noout -dates
        
        local EXPIRY_DATE=$(openssl x509 -in "/etc/letsencrypt/live/$domain/cert.pem" -noout -enddate | cut -d= -f2)
        local EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s)
        local NOW_EPOCH=$(date +%s)
        local DAYS_LEFT=$(( ($EXPIRY_EPOCH - $NOW_EPOCH) / 86400 ))
        
        print_info "Days until expiry: $DAYS_LEFT"
        
        if [ $DAYS_LEFT -lt 30 ]; then
            print_warning "Certificate expires soon!"
        fi
    else
        print_error "Certificate not found"
    fi
}

renew_ssl_certificates() {
    print_step "Renewing certificates..."
    certbot renew
    docker compose -f /opt/onestack/docker-compose.yml exec nginx nginx -s reload
}

check_ssl_status() {
    certbot certificates
}
EOFSSL

chmod +x /root/onestack/lib/06-ssl.sh

echo ""
echo "✅ lib/06-ssl.sh updated (main domain only)"
echo ""
echo "Run SSL setup again:"
echo "  ./manage.sh → 1) Setup SSL"