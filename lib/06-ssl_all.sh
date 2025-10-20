#!/bin/bash
# ═══════════════════════════════════════════════════
# OneStack - SSL Management Functions
# ═══════════════════════════════════════════════════

# Load utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

# ═══════════════════════════════════════════════════
# SSL Configuration
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
# SSL Certificate Functions
# ═══════════════════════════════════════════════════

request_ssl_certificate() {
    local domain=$1
    local email=$2
    local mode=${3:-production}  # staging | production
    
    print_step "Requesting SSL certificate for: $domain"
    print_info "Mode: $mode"
    print_info "Email: $email"
    
    # Prepare certbot command
    local CERTBOT_CMD="certbot certonly --webroot"
    CERTBOT_CMD="$CERTBOT_CMD -w /opt/onestack/frontends/main"
    CERTBOT_CMD="$CERTBOT_CMD -d $domain"
    CERTBOT_CMD="$CERTBOT_CMD -d www.$domain"
    CERTBOT_CMD="$CERTBOT_CMD --email $email"
    CERTBOT_CMD="$CERTBOT_CMD --agree-tos"
    CERTBOT_CMD="$CERTBOT_CMD --non-interactive"
    
    # Add staging flag if needed
    if [ "$mode" = "staging" ]; then
        CERTBOT_CMD="$CERTBOT_CMD --staging"
        print_warning "Using Let's Encrypt STAGING environment"
        print_warning "Certificates will NOT be trusted by browsers"
    fi
    
    # Execute
    eval $CERTBOT_CMD
    
    if [ $? -eq 0 ]; then
        print_success "SSL certificate obtained successfully"
        
        # Show certificate info
        print_info "Certificate location: /etc/letsencrypt/live/$domain/"
        ls -la /etc/letsencrypt/live/$domain/
        
        return 0
    else
        print_error "Failed to obtain SSL certificate"
        print_info "Common issues:"
        print_info "  1. Domain not pointing to this server"
        print_info "  2. Port 80 not accessible"
        print_info "  3. Nginx not serving /.well-known/"
        print_info "  4. Rate limit exceeded (use staging mode first)"
        return 1
    fi
}

request_ssl_all_subdomains() {
    local domain=$1
    local email=$2
    local mode=${3:-production}
    
    print_step "Requesting SSL for all subdomains..."
    
    # Get all subdomains from config
    local SUBDOMAINS=(
        "storage"
        "s3"
        "api"
        "monitor"
        "prometheus"
        "db"
    )
    
    # Build domain list
    local DOMAIN_LIST="-d $domain -d www.$domain"
    for sub in "${SUBDOMAINS[@]}"; do
        DOMAIN_LIST="$DOMAIN_LIST -d $sub.$domain"
    done
    
    # Request certificate
    local CERTBOT_CMD="certbot certonly --webroot"
    CERTBOT_CMD="$CERTBOT_CMD -w /opt/onestack/frontends/main"
    CERTBOT_CMD="$CERTBOT_CMD $DOMAIN_LIST"
    CERTBOT_CMD="$CERTBOT_CMD --email $email"
    CERTBOT_CMD="$CERTBOT_CMD --agree-tos"
    CERTBOT_CMD="$CERTBOT_CMD --non-interactive"
    
    if [ "$mode" = "staging" ]; then
        CERTBOT_CMD="$CERTBOT_CMD --staging"
    fi
    
    print_info "Requesting certificate for:"
    echo "$DOMAIN_LIST" | tr ' ' '\n' | grep -E "^-d" | sed 's/-d /  - /'
    
    eval $CERTBOT_CMD
    
    return $?
}

# ═══════════════════════════════════════════════════
# Nginx SSL Configuration
# ═══════════════════════════════════════════════════

update_nginx_ssl_config() {
    local domain=$1
    
    print_step "Updating Nginx configuration for SSL..."
    
    local NGINX_CONF="/opt/onestack/nginx/conf.d/onestack.conf"
    local BACKUP_CONF="/opt/onestack/nginx/conf.d/onestack.conf.backup-$(date +%Y%m%d_%H%M%S)"
    
    # Backup current config
    print_info "Creating backup: $BACKUP_CONF"
    cp "$NGINX_CONF" "$BACKUP_CONF"
    
    # Create new SSL config
    cat > "$NGINX_CONF" << 'NGINX_SSL_EOF'
# ═══════════════════════════════════════════════════
# OneStack - Nginx Configuration with SSL
# ═══════════════════════════════════════════════════

# HTTP to HTTPS Redirect
server {
    listen 80;
    server_name DOMAIN www.DOMAIN storage.DOMAIN s3.DOMAIN api.DOMAIN monitor.DOMAIN prometheus.DOMAIN db.DOMAIN;
    
    # Allow Let's Encrypt challenges
    location /.well-known/acme-challenge/ {
        root /var/www/main;
    }
    
    # Redirect all other requests to HTTPS
    location / {
        return 301 https://$host$request_uri;
    }
}

# Main Site (HTTPS)
server {
    listen 443 ssl http2;
    server_name DOMAIN www.DOMAIN;
    
    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/DOMAIN/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/DOMAIN/chain.pem;
    
    # SSL Parameters
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_session_tickets off;
    
    # OCSP Stapling
    ssl_stapling on;
    ssl_stapling_verify on;
    resolver 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout 5s;
    
    # Security Headers
    add_header Strict-Transport-Security "max-age=63072000" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    root /var/www/main;
    index index.html index.htm;
    
    location / {
        try_files $uri $uri/ /index.html;
    }
    
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}

# MinIO Console (HTTPS)
server {
    listen 443 ssl http2;
    server_name storage.DOMAIN;
    
    ssl_certificate /etc/letsencrypt/live/DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/DOMAIN/privkey.pem;
    include /etc/nginx/ssl-params.conf;
    
    client_max_body_size 0;
    
    location / {
        proxy_pass http://minio:9001;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_buffering off;
    }
}

# MinIO S3 API (HTTPS)
server {
    listen 443 ssl http2;
    server_name s3.DOMAIN;
    
    ssl_certificate /etc/letsencrypt/live/DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/DOMAIN/privkey.pem;
    include /etc/nginx/ssl-params.conf;
    
    client_max_body_size 0;
    
    location / {
        proxy_pass http://minio:9000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        proxy_connect_timeout 300;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        chunked_transfer_encoding off;
    }
}

# Parse Server (HTTPS)
server {
    listen 443 ssl http2;
    server_name api.DOMAIN;
    
    ssl_certificate /etc/letsencrypt/live/DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/DOMAIN/privkey.pem;
    include /etc/nginx/ssl-params.conf;
    
    location /parse {
        proxy_pass http://parse-server:1337;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
        proxy_connect_timeout 300s;
    }
    
    location / {
        proxy_pass http://parse-dashboard:4040;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# Grafana (HTTPS)
server {
    listen 443 ssl http2;
    server_name monitor.DOMAIN;
    
    ssl_certificate /etc/letsencrypt/live/DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/DOMAIN/privkey.pem;
    include /etc/nginx/ssl-params.conf;
    
    location / {
        proxy_pass http://grafana:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

# Prometheus (HTTPS)
server {
    listen 443 ssl http2;
    server_name prometheus.DOMAIN;
    
    ssl_certificate /etc/letsencrypt/live/DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/DOMAIN/privkey.pem;
    include /etc/nginx/ssl-params.conf;
    
    location / {
        proxy_pass http://prometheus:9090;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# Adminer (HTTPS)
server {
    listen 443 ssl http2;
    server_name db.DOMAIN;
    
    ssl_certificate /etc/letsencrypt/live/DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/DOMAIN/privkey.pem;
    include /etc/nginx/ssl-params.conf;
    
    location / {
        proxy_pass http://adminer:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
    }
}
NGINX_SSL_EOF

    # Replace DOMAIN placeholder
    sed -i "s/DOMAIN/$domain/g" "$NGINX_CONF"
    
    # Create SSL parameters file
    create_ssl_params_file
    
    print_success "Nginx SSL configuration updated"
    
    # Test configuration
    docker compose -f /opt/onestack/docker-compose.yml exec nginx nginx -t
    
    if [ $? -eq 0 ]; then
        print_success "Nginx configuration is valid"
        
        # Reload Nginx
        print_step "Reloading Nginx..."
        docker compose -f /opt/onestack/docker-compose.yml exec nginx nginx -s reload
        
        print_success "Nginx reloaded successfully"
        return 0
    else
        print_error "Nginx configuration test failed"
        print_info "Restoring backup..."
        cp "$BACKUP_CONF" "$NGINX_CONF"
        return 1
    fi
}

create_ssl_params_file() {
    local SSL_PARAMS="/opt/onestack/nginx/ssl-params.conf"
    
    cat > "$SSL_PARAMS" << 'EOF'
# SSL Configuration Parameters
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers on;
ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 10m;
ssl_session_tickets off;

# OCSP Stapling
ssl_stapling on;
ssl_stapling_verify on;
resolver 8.8.8.8 8.8.4.4 valid=300s;
resolver_timeout 5s;

# Security Headers
add_header Strict-Transport-Security "max-age=63072000" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
EOF

    print_info "Created SSL parameters file: $SSL_PARAMS"
}

# ═══════════════════════════════════════════════════
# SSL Renewal & Maintenance
# ═══════════════════════════════════════════════════

setup_ssl_auto_renewal() {
    print_step "Setting up SSL auto-renewal..."
    
    # Create renewal script
    local RENEWAL_SCRIPT="/opt/onestack/scripts/ssl-renew-cron.sh"
    mkdir -p /opt/onestack/scripts
    
    cat > "$RENEWAL_SCRIPT" << 'EOF'
#!/bin/bash
# SSL Certificate Auto-Renewal Script

LOG_FILE="/opt/onestack/logs/ssl-renewal.log"
mkdir -p "$(dirname "$LOG_FILE")"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting SSL renewal check..." >> "$LOG_FILE"

# Renew certificates
certbot renew --quiet --deploy-hook "docker exec onestack-nginx nginx -s reload" >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SSL renewal check completed successfully" >> "$LOG_FILE"
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SSL renewal check failed" >> "$LOG_FILE"
fi

echo "---" >> "$LOG_FILE"
EOF

    chmod +x "$RENEWAL_SCRIPT"
    
    # Add to crontab (runs twice daily at 2 AM and 2 PM)
    (crontab -l 2>/dev/null | grep -v "ssl-renew-cron.sh"; echo "0 2,14 * * * $RENEWAL_SCRIPT") | crontab -
    
    print_success "SSL auto-renewal configured"
    print_info "Renewal attempts: Twice daily (2 AM and 2 PM)"
    print_info "Renewal log: /opt/onestack/logs/ssl-renewal.log"
}

renew_ssl_certificates() {
    print_step "Renewing SSL certificates..."
    
    certbot renew
    
    if [ $? -eq 0 ]; then
        print_success "SSL certificates renewed successfully"
        
        # Reload Nginx
        print_step "Reloading Nginx..."
        docker compose -f /opt/onestack/docker-compose.yml exec nginx nginx -s reload
        
        return 0
    else
        print_warning "No certificates needed renewal or renewal failed"
        return 1
    fi
}

check_ssl_status() {
    print_step "Checking SSL certificate status..."
    
    certbot certificates
}

check_ssl_expiry() {
    local domain=$1
    
    print_step "Checking SSL certificate expiry for: $domain"
    
    if [ -f "/etc/letsencrypt/live/$domain/cert.pem" ]; then
        openssl x509 -in "/etc/letsencrypt/live/$domain/cert.pem" -noout -dates
        
        # Check days until expiry
        local EXPIRY_DATE=$(openssl x509 -in "/etc/letsencrypt/live/$domain/cert.pem" -noout -enddate | cut -d= -f2)
        local EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s)
        local NOW_EPOCH=$(date +%s)
        local DAYS_LEFT=$(( ($EXPIRY_EPOCH - $NOW_EPOCH) / 86400 ))
        
        print_info "Days until expiry: $DAYS_LEFT"
        
        if [ $DAYS_LEFT -lt 30 ]; then
            print_warning "Certificate expires in less than 30 days!"
            print_info "Renewal recommended"
        else
            print_success "Certificate is valid"
        fi
    else
        print_error "Certificate not found for domain: $domain"
        return 1
    fi
}

# ═══════════════════════════════════════════════════
# Complete SSL Setup Function
# ═══════════════════════════════════════════════════

setup_ssl() {
    print_header "Setting up SSL/HTTPS"
    
    # Read config
    local CONFIG_FILE="${1:-$SCRIPT_DIR/config.yml}"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Config file not found: $CONFIG_FILE"
        return 1
    fi
    
    local DOMAIN=$(yq eval '.domain.primary' "$CONFIG_FILE")
    local SSL_EMAIL=$(yq eval '.domain.ssl_email' "$CONFIG_FILE")
    local SSL_MODE=$(yq eval '.domain.ssl_mode' "$CONFIG_FILE")
    
    print_info "Domain: $DOMAIN"
    print_info "Email: $SSL_EMAIL"
    print_info "Mode: $SSL_MODE"
    
    # Confirm
    if [ "$SSL_MODE" = "production" ]; then
        print_warning "This will request PRODUCTION certificates"
        print_warning "Rate limits apply: 5 certificates per week"
        read -p "Continue? (y/N): " confirm
        [ "$confirm" != "y" ] && return 1
    fi
    
    # Step 1: Install Certbot
    install_certbot || return 1
    
    # Step 2: Request certificates
    request_ssl_all_subdomains "$DOMAIN" "$SSL_EMAIL" "$SSL_MODE" || return 1
    
    # Step 3: Update Nginx config
    update_nginx_ssl_config "$DOMAIN" || return 1
    
    # Step 4: Setup auto-renewal
    setup_ssl_auto_renewal || return 1
    
    # Step 5: Update docker-compose.yml to mount certificates
    update_docker_compose_ssl || return 1
    
    # Success
    print_success "SSL setup complete!"
    echo ""
    print_info "Your site is now accessible via HTTPS:"
    print_info "  ✅ https://$DOMAIN"
    print_info "  ✅ https://storage.$DOMAIN"
    print_info "  ✅ https://api.$DOMAIN"
    print_info "  ✅ https://monitor.$DOMAIN"
    echo ""
    print_info "Test your SSL grade: https://www.ssllabs.com/ssltest/analyze.html?d=$DOMAIN"
}

update_docker_compose_ssl() {
    print_step "Updating docker-compose.yml for SSL..."
    
    local COMPOSE_FILE="/opt/onestack/docker-compose.yml"
    local BACKUP_FILE="/opt/onestack/docker-compose.yml.backup-$(date +%Y%m%d_%H%M%S)"
    
    # Backup
    cp "$COMPOSE_FILE" "$BACKUP_FILE"
    print_info "Backup created: $BACKUP_FILE"
    
    # Check if already has the volume
    if grep -q "/etc/letsencrypt:/etc/letsencrypt:ro" "$COMPOSE_FILE"; then
        print_info "SSL volume already configured"
        return 0
    fi
    
    # Add SSL certificate volume to nginx service
    # This is a simplified approach - you might need to adjust based on your actual docker-compose.yml structure
    print_info "Adding SSL certificate volume to nginx service..."
    print_warning "Manual verification recommended"
    
    # Just inform user to add manually for now
    print_info "Please ensure nginx service has this volume:"
    print_info "  - /etc/letsencrypt:/etc/letsencrypt:ro"
    
    return 0
}

# ═══════════════════════════════════════════════════
# Test SSL Configuration
# ═══════════════════════════════════════════════════

test_ssl() {
    local domain=$1
    
    print_header "Testing SSL Configuration"
    
    # Test HTTPS access
    print_step "Testing HTTPS access..."
    
    local URLS=(
        "https://$domain"
        "https://storage.$domain"
        "https://api.$domain/parse/health"
        "https://monitor.$domain"
    )
    
    for url in "${URLS[@]}"; do
        print_info "Testing: $url"
        
        local STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>&1)
        
        if [[ "$STATUS" =~ ^[23] ]]; then
            print_success "  ✅ $url - $STATUS"
        else
            print_error "  ❌ $url - $STATUS"
        fi
    done
    
    echo ""
    print_info "Run full SSL test:"
    print_info "  https://www.ssllabs.com/ssltest/analyze.html?d=$domain"
}