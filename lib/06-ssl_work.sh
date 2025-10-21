#!/bin/bash
# ═══════════════════════════════════════════════════
# OneStack - Smart SSL Manager (Complete Version)
# Automatically discovers services and manages SSL
# ═══════════════════════════════════════════════════

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() { echo -e "\n${BLUE}═══════════════════════════════════════════════════${NC}\n${BLUE}$1${NC}\n${BLUE}═══════════════════════════════════════════════════${NC}\n"; }
print_step() { echo -e "${YELLOW}▶${NC} $1"; }
print_success() { echo -e "${GREEN}✔${NC} $1"; }
print_error() { echo -e "${RED}✖${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_info() { echo -e "${BLUE}ℹ${NC} $1"; }
confirm() { read -p "$1 [y/N]: " -n 1 -r; echo; [[ $REPLY =~ ^[Yy]$ ]]; }

# ═══════════════════════════════════════════════════
# Discover Installed Services
# ═══════════════════════════════════════════════════

discover_services() {
    local compose_file="$1"
    local services=()
    
    if [ -f "$compose_file" ]; then
        while IFS= read -r line; do
            if [[ $line =~ ^[[:space:]]*([a-z0-9_-]+):[[:space:]]*$ ]]; then
                service="${BASH_REMATCH[1]}"
                case $service in
                    nginx|postgres|mongodb|redis|minio|parse|n8n|chatwoot|grafana|prometheus|adminer)
                        services+=("$service")
                        ;;
                esac
            fi
        done < "$compose_file"
    fi
    
    services=($(printf "%s\n" "${services[@]}" | sort -u))
    echo "${services[@]}"
}

# ═══════════════════════════════════════════════════
# Discover All Domains & Subdomains
# ═══════════════════════════════════════════════════

discover_domains() {
    local base_domain="$1"
    local services="$2"
    local domains=()
    
    domains+=("$base_domain")
    domains+=("www.$base_domain")
    
    for service in $services; do
        case $service in
            minio)
                domains+=("storage.$base_domain")
                domains+=("s3.$base_domain")
                ;;
            parse) domains+=("api.$base_domain") ;;
            n8n) domains+=("flow.$base_domain") ;;
            chatwoot) domains+=("chat.$base_domain") ;;
            grafana) domains+=("monitor.$base_domain") ;;
            prometheus) domains+=("prometheus.$base_domain") ;;
            adminer) domains+=("db.$base_domain") ;;
        esac
    done
    
    domains=($(printf "%s\n" "${domains[@]}" | sort -u))
    echo "${domains[@]}"
}

# ═══════════════════════════════════════════════════
# Check Existing SSL Certificates
# ═══════════════════════════════════════════════════

check_existing_ssl() {
    local domain="$1"
    local cert_dir="${CERTBOT_DIR:-/opt/onestack/certbot/conf}/live"
    
    if [ -d "$cert_dir/$domain" ] && [ -f "$cert_dir/$domain/fullchain.pem" ]; then
        local expiry=$(openssl x509 -in "$cert_dir/$domain/fullchain.pem" -noout -enddate 2>/dev/null | cut -d= -f2)
        
        if [ -n "$expiry" ]; then
            local expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null || echo "0")
            local now_epoch=$(date +%s)
            
            if [ "$expiry_epoch" = "0" ]; then
                return 0
            fi
            
            local days_left=$(( ($expiry_epoch - $now_epoch) / 86400 ))
            
            if [ $days_left -gt 30 ]; then
                return 0  # Valid
            else
                return 2  # Expiring soon
            fi
        fi
    fi
    
    return 1  # Missing
}

# ═══════════════════════════════════════════════════
# Setup ACME Challenge Directory (CRITICAL!)
# ═══════════════════════════════════════════════════

setup_acme_challenge() {
    local install_dir="$1"
    
    print_step "Setting up ACME challenge directory..."
    
    # สร้างโฟลเดอร์
    mkdir -p "$install_dir/certbot/"{conf,www,logs}
    mkdir -p "$install_dir/certbot/www/.well-known/acme-challenge"
    chmod -R 755 "$install_dir/certbot"
    
    print_success "Directories created"
    
    # สร้าง nginx config สำหรับ ACME challenge
    cat > "$install_dir/nginx/conf.d/00-acme-challenge.conf" << 'EOF'
# ACME Challenge Configuration
# This MUST be loaded BEFORE other server blocks

server {
    listen 80 default_server;
    server_name _;
    
    # ACME challenge location (highest priority)
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
        try_files $uri =404;
    }
    
    # All other traffic redirects to HTTPS
    location / {
        return 301 https://$host$request_uri;
    }
}
EOF
    
    print_success "ACME challenge nginx config created"
    
    # ตรวจสอบ docker-compose.yml volume
    print_step "Checking nginx volumes in docker-compose.yml..."
    
    if ! grep -q "/var/www/certbot" "$install_dir/docker-compose.yml"; then
        print_warning "⚠️  Missing certbot volume in nginx service!"
        print_info ""
        print_info "You need to add this line to nginx volumes:"
        echo "      - ./certbot/www:/var/www/certbot:ro"
        print_info ""
        
        if confirm "Add volume automatically?"; then
            # Backup
            cp "$install_dir/docker-compose.yml" "$install_dir/docker-compose.yml.backup-$(date +%Y%m%d-%H%M%S)"
            
            # แทรก volume (หา nginx: section แล้วหา volumes: แล้วเพิ่ม)
            # ใช้วิธีที่ปลอดภัย: แสดงคำสั่งให้ user ทำเอง
            print_warning "Please add manually for safety:"
            echo ""
            echo "nano $install_dir/docker-compose.yml"
            echo ""
            echo "Find 'nginx:' section, add under 'volumes:':"
            echo "      - ./certbot/www:/var/www/certbot:ro"
            echo ""
            
            if ! confirm "Added and saved?"; then
                print_error "Volume not added. Cannot proceed."
                return 1
            fi
        else
            print_error "Volume is required for SSL setup!"
            return 1
        fi
    else
        print_success "Certbot volume found in nginx config"
    fi
    
    # Reload nginx
    print_step "Reloading nginx to apply ACME config..."
    docker compose -f "$install_dir/docker-compose.yml" restart nginx
    
    sleep 3
    
    # ทดสอบ ACME path
    print_step "Testing ACME challenge path..."
    echo "test-$(date +%s)" > "$install_dir/certbot/www/.well-known/acme-challenge/test-file"
    
    sleep 2
    
    # ทดสอบจาก localhost
    local test_result=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/.well-known/acme-challenge/test-file")
    
    if [ "$test_result" = "200" ]; then
        print_success "✅ ACME challenge path working!"
        rm -f "$install_dir/certbot/www/.well-known/acme-challenge/test-file"
        return 0
    else
        print_error "❌ ACME challenge path NOT working! (HTTP $test_result)"
        print_warning "Let's Encrypt will FAIL to verify domains!"
        
        # Debug
        print_info "Debugging..."
        echo ""
        echo "1. Check if file exists in container:"
        docker compose -f "$install_dir/docker-compose.yml" exec -T nginx ls -la /var/www/certbot/.well-known/acme-challenge/ || true
        echo ""
        echo "2. Check nginx error log:"
        docker compose -f "$install_dir/docker-compose.yml" logs --tail=20 nginx
        echo ""
        
        rm -f "$install_dir/certbot/www/.well-known/acme-challenge/test-file"
        
        if ! confirm "Continue anyway? (Not recommended)"; then
            return 1
        fi
    fi
}

# ═══════════════════════════════════════════════════
# Request SSL Certificate (Webroot - NO DOWNTIME)
# ═══════════════════════════════════════════════════

request_certificate_webroot() {
    local domains="$1"
    local email="$2"
    local mode="$3"
    local certbot_dir="$4"
    
    print_step "Requesting SSL certificate (webroot method)..."
    
    local staging_flag=""
    if [ "$mode" = "staging" ]; then
        staging_flag="--staging"
        print_warning "Using STAGING mode (test certificates)"
    fi
    
    # สร้าง domain arguments
    local domain_args=""
    for d in $domains; do
        domain_args="$domain_args -d $d"
    done
    
    print_info "Method: Webroot (no downtime required)"
    print_info "Domains: $domains"
    echo ""
    
    # ใช้ docker run
    docker run --rm \
        -v "$certbot_dir/conf:/etc/letsencrypt" \
        -v "$certbot_dir/www:/var/www/certbot" \
        -v "$certbot_dir/logs:/var/log/letsencrypt" \
        certbot/certbot certonly \
        --webroot \
        --webroot-path=/var/www/certbot \
        $staging_flag \
        --email "$email" \
        --agree-tos \
        --no-eff-email \
        --non-interactive \
        $domain_args
    
    return $?
}

# ═══════════════════════════════════════════════════
# Request Wildcard Certificate (DNS validation)
# ═══════════════════════════════════════════════════

request_wildcard_certificate() {
    local domain="$1"
    local email="$2"
    local mode="$3"
    local certbot_dir="$4"
    
    print_step "Requesting wildcard certificate for *.$domain"
    
    local staging_flag=""
    if [ "$mode" = "staging" ]; then
        staging_flag="--staging"
        print_warning "Using STAGING mode"
    fi
    
    print_warning "Wildcard certificates require DNS validation"
    print_info "You'll need to add a TXT record during the process"
    echo ""
    
    docker run --rm -it \
        -v "$certbot_dir/conf:/etc/letsencrypt" \
        -v "$certbot_dir/logs:/var/log/letsencrypt" \
        certbot/certbot certonly \
        --manual \
        --preferred-challenges dns \
        $staging_flag \
        --email "$email" \
        --agree-tos \
        --no-eff-email \
        -d "$domain" \
        -d "*.$domain"
    
    return $?
}

# ═══════════════════════════════════════════════════
# Generate HTTPS Nginx Config
# ═══════════════════════════════════════════════════

generate_nginx_https_config() {
    local base_domain="$1"
    local services="$2"
    local certbot_dir="$3"
    
    # หา certificate path
    local cert_path="/etc/letsencrypt/live/$base_domain"
    
    if [ ! -d "$certbot_dir/conf/live/$base_domain" ]; then
        local first_cert=$(find "$certbot_dir/conf/live" -maxdepth 1 -type d ! -name "README" | grep -v "^$certbot_dir/conf/live$" | head -1)
        if [ -n "$first_cert" ]; then
            local cert_name=$(basename "$first_cert")
            cert_path="/etc/letsencrypt/live/$cert_name"
            print_warning "Using certificate: $cert_name"
        else
            print_error "No certificate found!"
            return 1
        fi
    fi
    
    print_info "Certificate path: $cert_path"
    
    local output_file="/opt/onestack/nginx/conf.d/https.conf"
    
    print_step "Generating HTTPS Nginx configuration..."
    
    cat > "$output_file" << EOF
# ═══════════════════════════════════════════════════
# OneStack HTTPS Configuration
# Auto-generated by SSL Manager
# Generated: $(date)
# Certificate: $cert_path
# ═══════════════════════════════════════════════════

# SSL Parameters
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
ssl_prefer_server_ciphers off;
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 10m;

# Security Headers
add_header Strict-Transport-Security "max-age=63072000" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;

# ═══════════════════════════════════════════════════
# Main Domain
# ═══════════════════════════════════════════════════

server {
    listen 80;
    server_name $base_domain www.$base_domain;
    
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name $base_domain www.$base_domain;
    
    ssl_certificate $cert_path/fullchain.pem;
    ssl_certificate_key $cert_path/privkey.pem;
    
    root /var/www/main;
    index index.html;
    
    location / {
        try_files \$uri \$uri/ /index.html;
    }
}

EOF

    # เพิ่ม config สำหรับแต่ละ service
    for service in $services; do
        case $service in
            minio)
                cat >> "$output_file" << EOF

# ═══════════════════════════════════════════════════
# MinIO Object Storage
# ═══════════════════════════════════════════════════

server {
    listen 80;
    server_name storage.$base_domain s3.$base_domain;
    
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name storage.$base_domain;
    
    ssl_certificate $cert_path/fullchain.pem;
    ssl_certificate_key $cert_path/privkey.pem;
    
    client_max_body_size 100M;
    
    location / {
        proxy_pass http://minio:9001;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

server {
    listen 443 ssl http2;
    server_name s3.$base_domain;
    
    ssl_certificate $cert_path/fullchain.pem;
    ssl_certificate_key $cert_path/privkey.pem;
    
    client_max_body_size 100M;
    
    location / {
        proxy_pass http://minio:9000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
                ;;
                
            parse)
                cat >> "$output_file" << EOF

# ═══════════════════════════════════════════════════
# Parse Server API
# ═══════════════════════════════════════════════════

server {
    listen 80;
    server_name api.$base_domain;
    
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name api.$base_domain;
    
    ssl_certificate $cert_path/fullchain.pem;
    ssl_certificate_key $cert_path/privkey.pem;
    
    location / {
        proxy_pass http://parse:1337;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
                ;;
                
            n8n)
                cat >> "$output_file" << EOF

# ═══════════════════════════════════════════════════
# n8n Workflow Automation
# ═══════════════════════════════════════════════════

server {
    listen 80;
    server_name flow.$base_domain;
    
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name flow.$base_domain;
    
    ssl_certificate $cert_path/fullchain.pem;
    ssl_certificate_key $cert_path/privkey.pem;
    
    location / {
        proxy_pass http://n8n:5678;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF
                ;;
                
            chatwoot)
                cat >> "$output_file" << EOF

# ═══════════════════════════════════════════════════
# Chatwoot Customer Support
# ═══════════════════════════════════════════════════

server {
    listen 80;
    server_name chat.$base_domain;
    
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name chat.$base_domain;
    
    ssl_certificate $cert_path/fullchain.pem;
    ssl_certificate_key $cert_path/privkey.pem;
    
    location / {
        proxy_pass http://chatwoot-rails:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF
                ;;
                
            grafana)
                cat >> "$output_file" << EOF

# ═══════════════════════════════════════════════════
# Grafana Monitoring
# ═══════════════════════════════════════════════════

server {
    listen 80;
    server_name monitor.$base_domain;
    
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name monitor.$base_domain;
    
    ssl_certificate $cert_path/fullchain.pem;
    ssl_certificate_key $cert_path/privkey.pem;
    
    location / {
        proxy_pass http://grafana:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
                ;;
                
            adminer)
                cat >> "$output_file" << EOF

# ═══════════════════════════════════════════════════
# Adminer Database Management
# ═══════════════════════════════════════════════════

server {
    listen 80;
    server_name db.$base_domain;
    
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name db.$base_domain;
    
    ssl_certificate $cert_path/fullchain.pem;
    ssl_certificate_key $cert_path/privkey.pem;
    
    location / {
        proxy_pass http://adminer:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
                ;;
        esac
    done
    
    print_success "HTTPS configuration generated: $output_file"
}

# ═══════════════════════════════════════════════════
# Setup Auto-Renewal
# ═══════════════════════════════════════════════════

setup_auto_renewal() {
    local certbot_dir="$1"
    
    print_step "Setting up SSL auto-renewal..."
    
    local renewal_script="/opt/onestack/scripts/ssl-renew.sh"
    mkdir -p /opt/onestack/scripts
    
    cat > "$renewal_script" << RENEWEOF
#!/bin/bash
# Auto-renewal script for SSL certificates

LOG_FILE="/opt/onestack/logs/ssl-renewal.log"
mkdir -p "\$(dirname "\$LOG_FILE")"

echo "[\$(date)] Starting SSL renewal check..." >> "\$LOG_FILE"

# Renew certificates using docker
docker run --rm \\
    -v "$certbot_dir/conf:/etc/letsencrypt" \\
    -v "$certbot_dir/www:/var/www/certbot" \\
    -v "$certbot_dir/logs:/var/log/letsencrypt" \\
    certbot/certbot renew --quiet

if [ \$? -eq 0 ]; then
    echo "[\$(date)] SSL renewal completed successfully" >> "\$LOG_FILE"
    
    # Reload nginx
    docker compose -f /opt/onestack/docker-compose.yml exec -T nginx nginx -s reload
    echo "[\$(date)] Nginx reloaded" >> "\$LOG_FILE"
else
    echo "[\$(date)] SSL renewal failed!" >> "\$LOG_FILE"
fi
RENEWEOF

    chmod +x "$renewal_script"
    
    # เพิ่มใน crontab
    local cron_cmd="0 2,14 * * * $renewal_script"
    
    if ! crontab -l 2>/dev/null | grep -q "ssl-renew.sh"; then
        (crontab -l 2>/dev/null; echo "$cron_cmd") | crontab -
        print_success "Auto-renewal cron job added (runs twice daily at 2:00 and 14:00)"
    else
        print_info "Auto-renewal already configured"
    fi
}

# ═══════════════════════════════════════════════════
# Main SSL Setup Function
# ═══════════════════════════════════════════════════

setup_ssl_smart() {
    local install_dir="${1:-/opt/onestack}"
    local config_file="${2:-$install_dir/.env}"
    
    print_header "Smart SSL Setup"
    
    # Load config
    if [ ! -f "$config_file" ]; then
        print_error "Configuration file not found: $config_file"
        return 1
    fi
    
    source "$config_file"
    
    # Check domain
    if [ -z "$DOMAIN" ] || [ "$DOMAIN" = "localhost" ]; then
        print_error "Valid domain required for SSL setup"
        return 1
    fi
    
    export CERTBOT_DIR="$install_dir/certbot"
    
    print_info "Base Domain: $DOMAIN"
    print_info "Certbot Dir: $CERTBOT_DIR"
    echo ""
    
    # Step 0: ACME Challenge Setup (CRITICAL!)
    print_header "Step 0: ACME Challenge Setup ⚠️  CRITICAL"
    if ! setup_acme_challenge "$install_dir"; then
        print_error "ACME challenge setup failed!"
        print_error "Cannot proceed with SSL certificates"
        return 1
    fi
    
    # Step 1: Service Discovery
    print_header "Step 1: Service Discovery"
    local services=$(discover_services "$install_dir/docker-compose.yml")
    
    if [ -z "$services" ]; then
        print_warning "No services discovered"
        return 1
    fi
    
    print_success "Found $(echo $services | wc -w) services:"
    for svc in $services; do
        echo "  • $svc"
    done
    echo ""
    
    # Step 2: Domain Discovery
    print_header "Step 2: Domain Discovery"
    local all_domains=$(discover_domains "$DOMAIN" "$services")
    
    print_success "Found $(echo $all_domains | wc -w) domains:"
    for dom in $all_domains; do
        echo "  • $dom"
    done
    echo ""
    
    # Step 3: DNS Verification
    print_header "Step 3: DNS Verification"
    
    local server_ip=$(curl -4 -s ifconfig.me 2>/dev/null || curl -s api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')
    print_info "Server IP: $server_ip"
    echo ""
    
    print_step "Checking DNS records..."
    local dns_ok=true
    
    for dom in $all_domains; do
        local dns_ip=$(dig +short "$dom" @8.8.8.8 | tail -1)
        if [ "$dns_ip" = "$server_ip" ]; then
            print_success "$dom → $dns_ip ✓"
        else
            print_warning "$dom → ${dns_ip:-NOT FOUND} (expected: $server_ip)"
            dns_ok=false
        fi
    done
    echo ""
    
    if [ "$dns_ok" = false ]; then
        print_warning "DNS not fully configured!"
        if ! confirm "Continue anyway?"; then
            return 1
        fi
    fi
    
    # Step 4: SSL Status Check
    print_header "Step 4: SSL Status Check"
    local missing_ssl=()
    local expiring_ssl=()
    
    for dom in $all_domains; do
        check_existing_ssl "$dom"
        local status=$?
        case $status in
            0)
                print_success "$dom - SSL valid"
                ;;
            2)
                print_warning "$dom - SSL expires soon"
                expiring_ssl+=("$dom")
                ;;
            1)
                print_warning "$dom - No SSL certificate"
                missing_ssl+=("$dom")
                ;;
        esac
    done
    echo ""
    
    # Step 5: Request SSL Certificates
    if [ ${#missing_ssl[@]} -gt 0 ] || [ ${#expiring_ssl[@]} -gt 0 ]; then
        print_header "Step 5: Request SSL Certificates"
        
        local all_needed=("${missing_ssl[@]}" "${expiring_ssl[@]}")
        
        print_info "Domains needing certificates:"
        for dom in "${all_needed[@]}"; do
            echo "  • $dom"
        done
        echo ""
        
        local ssl_email="${SSL_EMAIL:-admin@$DOMAIN}"
        local ssl_mode="${SSL_MODE:-production}"
        
        # ถามว่าจะใช้ wildcard หรือไม่
        local use_wildcard=false
        if [ ${#all_needed[@]} -gt 3 ]; then
            print_info "Multiple domains detected. Wildcard certificate recommended."
            if confirm "Use wildcard certificate (*.$DOMAIN)?"; then
                use_wildcard=true
            fi
        fi
        
        if [ "$use_wildcard" = true ]; then
            request_wildcard_certificate "$DOMAIN" "$ssl_email" "$ssl_mode" "$CERTBOT_DIR"
        else
            local domains_str=$(IFS=' '; echo "${all_needed[*]}")
            request_certificate_webroot "$domains_str" "$ssl_email" "$ssl_mode" "$CERTBOT_DIR"
        fi
        
        if [ $? -eq 0 ]; then
            print_success "SSL certificates obtained!"
        else
            print_error "Failed to obtain SSL certificates"
            return 1
        fi
    else
        print_success "All domains have valid SSL certificates"
    fi
    
    # Step 6: Generate HTTPS Config
    print_header "Step 6: Generate HTTPS Configuration"
    
    # Disable HTTP-only config
    if [ -f "$install_dir/nginx/conf.d/onestack.conf" ]; then
        print_step "Disabling HTTP-only config..."
        mv "$install_dir/nginx/conf.d/onestack.conf" "$install_dir/nginx/conf.d/onestack.conf.disabled"
    fi
    
    generate_nginx_https_config "$DOMAIN" "$services" "$CERTBOT_DIR"
    
    # Step 7: Test and Apply
    print_header "Step 7: Test and Apply Configuration"
    
    print_step "Testing nginx configuration..."
    if docker compose -f "$install_dir/docker-compose.yml" exec -T nginx nginx -t 2>&1 | grep -q "successful"; then
        print_success "Configuration valid"
        
        print_step "Reloading nginx..."
        docker compose -f "$install_dir/docker-compose.yml" exec -T nginx nginx -s reload
        print_success "Nginx reloaded"
    else
        print_error "Configuration test failed"
        docker compose -f "$install_dir/docker-compose.yml" exec -T nginx nginx -t
        return 1
    fi
    
    # Step 8: Setup Auto-Renewal
    print_header "Step 8: Setup Auto-Renewal"
    setup_auto_renewal "$CERTBOT_DIR"
    
    # Summary
    print_header "✅ SSL Setup Complete!"
    echo ""
    print_success "HTTPS enabled for:"
    for dom in $all_domains; do
        echo "  🔒 https://$dom"
    done
    echo ""
    print_info "Certificate location: $CERTBOT_DIR/conf/live/"
    print_info "Auto-renewal: Enabled (twice daily)"
    print_info "Renewal logs: /opt/onestack/logs/ssl-renewal.log"
    echo ""
    
    return 0
}

# Run if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    setup_ssl_smart "$@"
fi