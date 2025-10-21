#!/bin/bash
# ═══════════════════════════════════════════════════
# OneStack - Smart SSL Manager
# Automatically discovers services and manages SSL
# ═══════════════════════════════════════════════════

# ═══════════════════════════════════════════════════
# Discover Installed Services
# ═══════════════════════════════════════════════════

discover_services() {
    local compose_file="$1"
    local services=()
    
    print_step "Discovering installed services..."
    
    # อ่าน services จาก docker-compose.yml
    if [ -f "$compose_file" ]; then
        # ใช้ grep หา service names
        while IFS= read -r line; do
            if [[ $line =~ ^[[:space:]]*([a-z0-9_-]+):[[:space:]]*$ ]]; then
                service="${BASH_REMATCH[1]}"
                # กรองเฉพาะ services ที่เราสนใจ
                case $service in
                    nginx|postgres|mongodb|redis|minio|parse|n8n|chatwoot|grafana|prometheus|adminer)
                        services+=("$service")
                        ;;
                esac
            fi
        done < "$compose_file"
    fi
    
    echo "${services[@]}"
}

# ═══════════════════════════════════════════════════
# Discover All Domains & Subdomains
# ═══════════════════════════════════════════════════

discover_domains() {
    local base_domain="$1"
    local services="$2"
    local domains=()
    
    print_step "Discovering domains and subdomains..."
    
    # เพิ่ม primary domain และ www
    domains+=("$base_domain")
    domains+=("www.$base_domain")
    
    # แปลง services เป็น subdomains
    for service in $services; do
        case $service in
            minio)
                domains+=("storage.$base_domain")
                domains+=("s3.$base_domain")
                ;;
            parse)
                domains+=("api.$base_domain")
                ;;
            n8n)
                domains+=("flow.$base_domain")
                ;;
            chatwoot)
                domains+=("chat.$base_domain")
                ;;
            grafana)
                domains+=("monitor.$base_domain")
                ;;
            prometheus)
                domains+=("prometheus.$base_domain")
                ;;
            adminer)
                domains+=("db.$base_domain")
                ;;
        esac
    done
    
    # ลบ duplicates และ sort
    domains=($(printf "%s\n" "${domains[@]}" | sort -u))
    
    echo "${domains[@]}"
}

# ═══════════════════════════════════════════════════
# Check Existing SSL Certificates
# ═══════════════════════════════════════════════════

check_existing_ssl() {
    local domain="$1"
    local cert_dir="/etc/letsencrypt/live"
    
    if [ -d "$cert_dir/$domain" ] && [ -f "$cert_dir/$domain/fullchain.pem" ]; then
        # ตรวจสอบวันหมดอายุ
        local expiry=$(openssl x509 -in "$cert_dir/$domain/fullchain.pem" -noout -enddate 2>/dev/null | cut -d= -f2)
        
        if [ -n "$expiry" ]; then
            local expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null)
            local now_epoch=$(date +%s)
            local days_left=$(( ($expiry_epoch - $now_epoch) / 86400 ))
            
            if [ $days_left -gt 30 ]; then
                return 0  # มี cert และยังไม่หมดอายุ
            else
                return 2  # มี cert แต่ใกล้หมดอายุ
            fi
        fi
    fi
    
    return 1  # ไม่มี cert
}

# ═══════════════════════════════════════════════════
# Request SSL Certificate (Wildcard)
# ═══════════════════════════════════════════════════

request_wildcard_certificate() {
    local domain="$1"
    local email="$2"
    local mode="$3"  # production or staging
    
    print_step "Requesting wildcard certificate for *.$domain"
    
    # ตรวจสอบ mode
    local staging_flag=""
    if [ "$mode" = "staging" ]; then
        staging_flag="--staging"
        print_warning "Using STAGING mode (test certificates)"
    fi
    
    # ต้องใช้ DNS validation สำหรับ wildcard
    print_info "Wildcard certificates require DNS validation"
    print_info "You'll need to add a TXT record to your DNS"
    echo ""
    
    certbot certonly \
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
# Request SSL Certificate (HTTP-01)
# ═══════════════════════════════════════════════════

request_certificate_http() {
    local domains="$1"  # รับหลาย domains
    local email="$2"
    local mode="$3"
    local webroot="$4"
    
    print_step "Requesting SSL certificate..."
    
    local staging_flag=""
    if [ "$mode" = "staging" ]; then
        staging_flag="--staging"
        print_warning "Using STAGING mode"
    fi
    
    # สร้าง domain arguments
    local domain_args=""
    for d in $domains; do
        domain_args="$domain_args -d $d"
    done
    
    print_info "Domains: $domains"
    echo ""
    
    # Stop nginx ถ้าใช้ standalone
    if [ -z "$webroot" ]; then
        print_step "Stopping Nginx temporarily..."
        docker compose -f /opt/onestack/docker-compose.yml stop nginx 2>/dev/null
        
        certbot certonly \
            --standalone \
            $staging_flag \
            --email "$email" \
            --agree-tos \
            --no-eff-email \
            $domain_args
        
        local result=$?
        
        print_step "Starting Nginx..."
        docker compose -f /opt/onestack/docker-compose.yml start nginx
        
        return $result
    else
        # ใช้ webroot
        certbot certonly \
            --webroot \
            -w "$webroot" \
            $staging_flag \
            --email "$email" \
            --agree-tos \
            --no-eff-email \
            $domain_args
        
        return $?
    fi
}

# ═══════════════════════════════════════════════════
# Generate HTTPS Nginx Config
# ═══════════════════════════════════════════════════

generate_nginx_https_config() {
    local base_domain="$1"
    local services="$2"
    local cert_path="/etc/letsencrypt/live/$base_domain"
    local output_file="/opt/onestack/nginx/conf.d/https.conf"
    
    print_step "Generating HTTPS Nginx configuration..."
    
    # สร้าง config file
    cat > "$output_file" << NGINXEOF
# ═══════════════════════════════════════════════════
# OneStack HTTPS Configuration
# Auto-generated by SSL Manager
# Generated: $(date)
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
# Main Domain - Redirect HTTP to HTTPS
# ═══════════════════════════════════════════════════

server {
    listen 80;
    server_name $base_domain www.$base_domain;
    return 301 https://\$host\$request_uri;
}

# ═══════════════════════════════════════════════════
# Main Domain - HTTPS
# ═══════════════════════════════════════════════════

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

NGINXEOF

    # เพิ่ม config สำหรับแต่ละ service
    for service in $services; do
        case $service in
            minio)
                cat >> "$output_file" << 'MINIOEOF'

# ═══════════════════════════════════════════════════
# MinIO Object Storage
# ═══════════════════════════════════════════════════

server {
    listen 80;
    server_name storage.$base_domain s3.$base_domain;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name storage.$base_domain;
    
    ssl_certificate $cert_path/fullchain.pem;
    ssl_certificate_key $cert_path/privkey.pem;
    
    client_max_body_size 100M;
    
    location / {
        proxy_pass http://minio:9001;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
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
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
MINIOEOF
                ;;
                
            parse)
                cat >> "$output_file" << 'PARSEEOF'

# ═══════════════════════════════════════════════════
# Parse Server API
# ═══════════════════════════════════════════════════

server {
    listen 80;
    server_name api.$base_domain;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name api.$base_domain;
    
    ssl_certificate $cert_path/fullchain.pem;
    ssl_certificate_key $cert_path/privkey.pem;
    
    location / {
        proxy_pass http://parse:1337;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
PARSEEOF
                ;;
                
            n8n)
                cat >> "$output_file" << 'N8NEOF'

# ═══════════════════════════════════════════════════
# n8n Workflow Automation
# ═══════════════════════════════════════════════════

server {
    listen 80;
    server_name flow.$base_domain;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name flow.$base_domain;
    
    ssl_certificate $cert_path/fullchain.pem;
    ssl_certificate_key $cert_path/privkey.pem;
    
    location / {
        proxy_pass http://n8n:5678;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
N8NEOF
                ;;
                
            chatwoot)
                cat >> "$output_file" << 'CHATWOOTEOF'

# ═══════════════════════════════════════════════════
# Chatwoot Customer Support
# ═══════════════════════════════════════════════════

server {
    listen 80;
    server_name chat.$base_domain;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name chat.$base_domain;
    
    ssl_certificate $cert_path/fullchain.pem;
    ssl_certificate_key $cert_path/privkey.pem;
    
    location / {
        proxy_pass http://chatwoot:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
CHATWOOTEOF
                ;;
                
            grafana)
                cat >> "$output_file" << 'GRAFANAEOF'

# ═══════════════════════════════════════════════════
# Grafana Monitoring
# ═══════════════════════════════════════════════════

server {
    listen 80;
    server_name monitor.$base_domain;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name monitor.$base_domain;
    
    ssl_certificate $cert_path/fullchain.pem;
    ssl_certificate_key $cert_path/privkey.pem;
    
    location / {
        proxy_pass http://grafana:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
GRAFANAEOF
                ;;
                
            adminer)
                cat >> "$output_file" << 'ADMINEREOF'

# ═══════════════════════════════════════════════════
# Adminer Database Management
# ═══════════════════════════════════════════════════

server {
    listen 80;
    server_name db.$base_domain;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name db.$base_domain;
    
    ssl_certificate $cert_path/fullchain.pem;
    ssl_certificate_key $cert_path/privkey.pem;
    
    location / {
        proxy_pass http://adminer:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
ADMINEREOF
                ;;
        esac
    done
    
    print_success "HTTPS configuration generated: $output_file"
}

# ═══════════════════════════════════════════════════
# Setup Auto-Renewal
# ═══════════════════════════════════════════════════

setup_auto_renewal() {
    print_step "Setting up SSL auto-renewal..."
    
    # สร้าง renewal script
    local renewal_script="/opt/onestack/scripts/ssl-renew.sh"
    
    mkdir -p /opt/onestack/scripts
    
    cat > "$renewal_script" << 'RENEWEOF'
#!/bin/bash
# Auto-renewal script for SSL certificates

LOG_FILE="/opt/onestack/logs/ssl-renewal.log"
mkdir -p "$(dirname "$LOG_FILE")"

echo "[$(date)] Starting SSL renewal check..." >> "$LOG_FILE"

# Renew certificates
certbot renew --quiet --deploy-hook "docker compose -f /opt/onestack/docker-compose.yml exec -T nginx nginx -s reload" >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    echo "[$(date)] SSL renewal completed successfully" >> "$LOG_FILE"
else
    echo "[$(date)] SSL renewal failed!" >> "$LOG_FILE"
fi
RENEWEOF

    chmod +x "$renewal_script"
    
    # เพิ่มใน crontab (ทุกวันเวลา 2:00 และ 14:00)
    local cron_cmd="0 2,14 * * * $renewal_script"
    
    # ตรวจสอบว่ามีอยู่แล้วหรือไม่
    if ! crontab -l 2>/dev/null | grep -q "ssl-renew.sh"; then
        (crontab -l 2>/dev/null; echo "$cron_cmd") | crontab -
        print_success "Auto-renewal cron job added (runs twice daily)"
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
    
    # โหลด config
    if [ ! -f "$config_file" ]; then
        print_error "Configuration file not found: $config_file"
        return 1
    fi
    
    source "$config_file"
    
    # ตรวจสอบ domain
    if [ -z "$DOMAIN" ] || [ "$DOMAIN" = "localhost" ]; then
        print_error "Valid domain required for SSL setup"
        print_info "Domain in .env: ${DOMAIN:-not set}"
        return 1
    fi
    
    print_info "Base Domain: $DOMAIN"
    print_info "SSL Email: ${SSL_EMAIL:-admin@$DOMAIN}"
    echo ""
    
    # 1. Discover services
    print_header "Step 1: Service Discovery"
    local services=$(discover_services "$install_dir/docker-compose.yml")
    
    if [ -z "$services" ]; then
        print_warning "No services discovered"
        return 1
    fi
    
    print_success "Discovered services:"
    for svc in $services; do
        echo "  ✓ $svc"
    done
    echo ""
    
    # 2. Discover domains
    print_header "Step 2: Domain Discovery"
    local all_domains=$(discover_domains "$DOMAIN" "$services")
    
    print_success "Discovered domains:"
    for dom in $all_domains; do
        echo "  • $dom"
    done
    echo ""
    
    # 3. Check existing SSL
    print_header "Step 3: SSL Status Check"
    local missing_ssl=()
    local expiring_ssl=()
    
    for dom in $all_domains; do
        check_existing_ssl "$dom"
        case $? in
            0)
                print_success "$dom - SSL valid"
                ;;
            1)
                print_warning "$dom - No SSL certificate"
                missing_ssl+=("$dom")
                ;;
            2)
                print_warning "$dom - SSL expires soon"
                expiring_ssl+=("$dom")
                ;;
        esac
    done
    echo ""
    
    # 4. Request missing certificates
    if [ ${#missing_ssl[@]} -gt 0 ]; then
        print_header "Step 4: Request SSL Certificates"
        
        print_info "Missing SSL for:"
        for dom in "${missing_ssl[@]}"; do
            echo "  • $dom"
        done
        echo ""
        
        print_warning "DNS Check Required!"
        echo ""
        echo "Make sure these DNS records point to this server:"
        local server_ip=$(curl -s ifconfig.me 2>/dev/null)
        echo "  Server IP: $server_ip"
        echo ""
        for dom in "${missing_ssl[@]}"; do
            echo "  A    $dom  →  $server_ip"
        done
        echo ""
        
        if ! confirm "DNS configured correctly?"; then
            print_info "Please configure DNS first"
            return 1
        fi
        
        # ติดตั้ง certbot ถ้ายังไม่มี
        if ! command -v certbot &> /dev/null; then
            print_step "Installing certbot..."
            apt-get update -qq
            apt-get install -y certbot
        fi
        
        # ขอ certificate
        local ssl_mode="${SSL_MODE:-production}"
        local ssl_email="${SSL_EMAIL:-admin@$DOMAIN}"
        
        # แปลง array เป็น string
        local domains_str=$(IFS=' '; echo "${missing_ssl[*]}")
        
        request_certificate_http "$domains_str" "$ssl_email" "$ssl_mode" ""
        
        if [ $? -eq 0 ]; then
            print_success "SSL certificates obtained!"
        else
            print_error "Failed to obtain SSL certificates"
            return 1
        fi
    else
        print_success "All domains have valid SSL certificates"
    fi
    
    # 5. Generate HTTPS config
    print_header "Step 5: Update Nginx Configuration"
    generate_nginx_https_config "$DOMAIN" "$services"
    
    # Test และ reload nginx
    print_step "Testing Nginx configuration..."
    if docker compose -f "$install_dir/docker-compose.yml" exec -T nginx nginx -t 2>&1 | grep -q "successful"; then
        print_success "Nginx configuration valid"
        
        print_step "Reloading Nginx..."
        docker compose -f "$install_dir/docker-compose.yml" exec -T nginx nginx -s reload
        print_success "Nginx reloaded"
    else
        print_error "Nginx configuration test failed"
        return 1
    fi
    
    # 6. Setup auto-renewal
    print_header "Step 6: Setup Auto-Renewal"
    setup_auto_renewal
    
    # Summary
    echo ""
    print_header "✅ SSL Setup Complete!"
    echo ""
    print_success "HTTPS enabled for:"
    for dom in $all_domains; do
        echo "  🔒 https://$dom"
    done
    echo ""
    print_info "Auto-renewal: Enabled (checks twice daily)"
    print_info "Next renewal: $(certbot renew --dry-run 2>&1 | grep "renewal" | head -1 || echo 'Run: certbot renew --dry-run')"
    echo ""
    
    return 0
}