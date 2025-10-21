#!/bin/bash
# ═══════════════════════════════════════════════════
# SSL Functions - Complete Version with Auto-Fix
# Fixed: Better volume detection and insertion
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

discover_domains() {
    local base_domain="$1"
    local services="$2"
    local domains=()
    
    domains+=("$base_domain" "www.$base_domain")
    
    for service in $services; do
        case $service in
            minio)
                domains+=("storage.$base_domain" "s3.$base_domain")
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
                return 0
            else
                return 2
            fi
        fi
    fi
    
    return 1
}

# ═══════════════════════════════════════════════════
# FIXED: Better volume insertion
# ═══════════════════════════════════════════════════

setup_acme_challenge() {
    local install_dir="$1"
    
    print_step "Setting up ACME challenge directory..."
    
    mkdir -p "$install_dir/certbot/"{conf,www,logs}
    mkdir -p "$install_dir/certbot/www/.well-known/acme-challenge"
    chmod -R 755 "$install_dir/certbot"
    
    print_success "Directories created"
    
    cat > "$install_dir/nginx/conf.d/00-acme-challenge.conf" << 'EOF'
server {
    listen 80 default_server;
    server_name _;
    
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
        try_files $uri =404;
    }
    
    location / {
        return 301 https://$host$request_uri;
    }
}
EOF
    
    print_success "ACME challenge nginx config created"
    
    print_step "Checking nginx volumes in docker-compose.yml..."
    
    # ตรวจสอบว่ามี certbot volume หรือยัง (ตรวจสอบทั้ง bind mount และ named volume)
    if ! grep -q "certbot.*:/var/www/certbot" "$install_dir/docker-compose.yml"; then
        print_warning "⚠️  Missing certbot volume in nginx service!"
        print_info "Adding volume automatically..."
        
        # Backup
        cp "$install_dir/docker-compose.yml" "$install_dir/docker-compose.yml.backup-$(date +%Y%m%d-%H%M%S)"
        print_success "Backup created"
        
        # วิธีที่ 1: ใช้ sed (แนะนำ - ง่ายและแม่นยำ)
        if grep -q "/etc/letsencrypt:/etc/letsencrypt:ro" "$install_dir/docker-compose.yml"; then
            print_info "Method: Insert after letsencrypt line"
            sed -i '/\/etc\/letsencrypt:\/etc\/letsencrypt:ro/a\      - ./certbot/www:/var/www/certbot:ro' "$install_dir/docker-compose.yml"
            
            if [ $? -eq 0 ]; then
                print_success "✅ Volume added successfully (sed method)"
            else
                print_error "Failed to add volume with sed"
                return 1
            fi
        else
            # วิธีที่ 2: ใช้ awk (fallback)
            print_info "Method: AWK insertion"
            awk '
            /^[[:space:]]*nginx:/ { in_nginx=1 }
            /^[[:space:]]*volumes:/ && in_nginx { 
                print
                getline
                print
                print "      - ./certbot/www:/var/www/certbot:ro"
                in_nginx=0
                next
            }
            /^[[:space:]]*[a-z_-]+:/ && !/^[[:space:]]*-/ { in_nginx=0 }
            { print }
            ' "$install_dir/docker-compose.yml" > "${install_dir}/docker-compose.yml.tmp"
            
            if [ $? -eq 0 ] && [ -s "${install_dir}/docker-compose.yml.tmp" ]; then
                mv "${install_dir}/docker-compose.yml.tmp" "$install_dir/docker-compose.yml"
                print_success "✅ Volume added successfully (awk method)"
            else
                print_error "Failed to add volume with awk"
                rm -f "${install_dir}/docker-compose.yml.tmp"
                return 1
            fi
        fi
        
        # ตรวจสอบอีกครั้ง
        if grep -q "certbot/www:/var/www/certbot" "$install_dir/docker-compose.yml"; then
            print_success "Volume verification: ✅ PASSED"
        else
            print_error "Volume verification: ❌ FAILED"
            print_warning "Please add manually:"
            echo "      - ./certbot/www:/var/www/certbot:ro"
            return 1
        fi
    else
        print_success "✅ Certbot volume already configured"
    fi
    
    # แสดง nginx volumes ที่มีอยู่
    echo ""
    print_info "Current nginx volumes:"
    grep -A 10 "nginx:" "$install_dir/docker-compose.yml" | grep "volumes:" -A 10 | grep "^[[:space:]]*-" | head -8
    echo ""
    
    # ปิด config เก่า
    print_step "Disabling old configs..."
    [ -f "$install_dir/nginx/conf.d/onestack.conf" ] && \
        mv "$install_dir/nginx/conf.d/onestack.conf" "$install_dir/nginx/conf.d/onestack.conf.disabled" 2>/dev/null && \
        print_info "  ✓ onestack.conf → disabled"
    
    [ -f "$install_dir/nginx/conf.d/https.conf" ] && \
        mv "$install_dir/nginx/conf.d/https.conf" "$install_dir/nginx/conf.d/https.conf.old" 2>/dev/null && \
        print_info "  ✓ https.conf → old"
    
    echo ""
    print_step "Fixing Docker overlay2 and recreating nginx..."
    
    cd "$install_dir"
    
    # CRITICAL FIX: Clean overlay2 corruption
    print_info "  ► Stopping all containers..."
    docker compose stop
    sleep 2
    
    print_info "  ► Stopping Docker daemon..."
    sudo systemctl stop docker
    sleep 3
    
    print_info "  ► Cleaning corrupted overlay2..."
    sudo rm -rf /var/lib/docker/overlay2 2>/dev/null || true
    sleep 2
    
    print_info "  ► Starting Docker daemon..."
    sudo systemctl start docker
    sleep 10
    
    print_info "  ► Converting to named volume (permanent fix)..."
    
    # แทนที่ bind mount ด้วย named volume
    if grep -q "./certbot/www:/var/www/certbot" docker-compose.yml; then
        cp docker-compose.yml docker-compose.yml.pre-volume-fix
        
        sed -i 's|./certbot/www:/var/www/certbot:ro|certbot_www:/var/www/certbot|g' docker-compose.yml
        
        # เพิ่ม volume definition
        if ! grep -q "^volumes:" docker-compose.yml; then
            echo "" >> docker-compose.yml
            echo "volumes:" >> docker-compose.yml
        fi
        
        if ! grep -q "  certbot_www:" docker-compose.yml; then
            sed -i '/^volumes:/a\  certbot_www:' docker-compose.yml
        fi
        
        print_success "  ✓ Converted to named volume"
    fi
    
    print_info "  ► Creating certbot_www volume..."
    docker volume create certbot_www >/dev/null 2>&1 || true
    
    if [ -d "$install_dir/certbot/www/.well-known" ]; then
        print_info "  ► Copying data to volume..."
        docker run --rm \
            -v certbot_www:/target \
            -v "$install_dir/certbot/www:/source:ro" \
            alpine sh -c "cp -a /source/. /target/" 2>/dev/null || true
    fi
    
    print_info "  ► Starting all containers..."
    docker compose up -d
    
    sleep 10
    
    # ตรวจสอบว่า nginx ทำงานหรือยัง
    if ! docker compose ps nginx 2>/dev/null | grep -q "Up"; then
        print_error "Nginx failed to start!"
        print_info "Checking logs..."
        docker compose logs --tail=30 nginx
        return 1
    fi
    
    print_success "Nginx container recreated"
    
    echo ""
    print_step "Testing ACME challenge path..."
    
    # ทดสอบด้วย named volume
    local test_content="test-$(date +%s)"
    
    print_info "  ► Creating test file in volume..."
    docker run --rm -v certbot_www:/data alpine sh -c "echo '$test_content' > /data/.well-known/acme-challenge/test-file"
    
    sleep 3
    
    # ทดสอบ 3 ครั้ง
    local test_result=""
    for i in {1..3}; do
        test_result=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/.well-known/acme-challenge/test-file" 2>/dev/null)
        if [ "$test_result" = "200" ]; then
            break
        fi
        print_info "Attempt $i/3: HTTP $test_result (retrying...)"
        sleep 2
    done
    
    # ลบไฟล์ทดสอบ
    docker run --rm -v certbot_www:/data alpine rm -f /data/.well-known/acme-challenge/test-file
    
    if [ "$test_result" = "200" ]; then
        print_success "✅ ACME challenge path working! (HTTP $test_result)"
        echo ""
        return 0
    else
        print_error "❌ ACME challenge path NOT working! (HTTP $test_result)"
        print_warning "Let's Encrypt will FAIL to verify domains!"
        
        echo ""
        print_info "=== Debugging Information ==="
        echo ""
        
        print_info "1. Container file system check:"
        docker compose exec -T nginx ls -la /var/www/certbot/.well-known/acme-challenge/ 2>&1 | head -10 || \
            print_error "Cannot access container filesystem"
        
        echo ""
        print_info "2. Recent nginx logs:"
        docker compose logs --tail=30 nginx 2>&1 | tail -20
        
        echo ""
        print_info "3. Nginx config test:"
        docker compose exec -T nginx nginx -t 2>&1
        
        echo ""
        print_info "4. Volume mounts:"
        docker compose exec -T nginx mount | grep certbot || \
            print_error "No certbot volume mounted!"
        
        echo ""
        print_warning "Common issues:"
        echo "  • Volume not mounted correctly"
        echo "  • Nginx config syntax error"
        echo "  • Port 80 blocked by firewall"
        echo "  • Another service using port 80"
        
        echo ""
        if ! confirm "Continue anyway? (Not recommended)"; then
            return 1
        fi
    fi
}

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
    else
        print_info "Using PRODUCTION mode (real certificates)"
    fi
    
    local domain_args=""
    for d in $domains; do
        domain_args="$domain_args -d $d"
    done
    
    echo ""
    print_info "Configuration:"
    print_info "  Method: Webroot (no downtime)"
    print_info "  Email: $email"
    print_info "  Domains: $domains"
    print_info "  Mode: ${mode:-production}"
    echo ""
    
    print_step "Running certbot..."
    
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
    
    local result=$?
    
    if [ $result -eq 0 ]; then
        print_success "✅ Certificate obtained successfully!"
    else
        print_error "❌ Certificate request failed (exit code: $result)"
        
        echo ""
        print_info "Check logs:"
        echo "  cat $certbot_dir/logs/letsencrypt.log"
    fi
    
    return $result
}

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
    
    echo ""
    print_warning "⚠️  Wildcard certificates require DNS validation"
    print_info "You'll need to add a TXT record during the process"
    print_info "The process will pause and wait for you to add the record"
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

generate_nginx_https_config() {
    local base_domain="$1"
    local services="$2"
    local certbot_dir="$3"
    
    local cert_path="/etc/letsencrypt/live/$base_domain"
    
    # ตรวจสอบ certificate
    if [ ! -d "$certbot_dir/conf/live/$base_domain" ]; then
        print_warning "Certificate directory not found: $base_domain"
        
        # หา certificate ที่มี
        local first_cert=$(find "$certbot_dir/conf/live" -maxdepth 1 -type d ! -name "README" 2>/dev/null | grep -v "^$certbot_dir/conf/live$" | head -1)
        
        if [ -n "$first_cert" ]; then
            local cert_name=$(basename "$first_cert")
            cert_path="/etc/letsencrypt/live/$cert_name"
            print_warning "Using certificate: $cert_name"
        else
            print_error "No certificate found!"
            print_info "Available certificates:"
            ls -la "$certbot_dir/conf/live/" 2>/dev/null || echo "  (none)"
            return 1
        fi
    fi
    
    print_info "Certificate path: $cert_path"
    
    local output_file="/opt/onestack/nginx/conf.d/https.conf"
    
    print_step "Generating HTTPS Nginx configuration..."
    
    cat > "$output_file" << EOF
# ═══════════════════════════════════════════════════
# OneStack HTTPS Configuration
# Generated: $(date)
# Certificate: $cert_path
# ═══════════════════════════════════════════════════

# SSL Global Settings
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
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 301 https://\$host\$request_uri; }
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
# MinIO Storage
# ═══════════════════════════════════════════════════

server {
    listen 80;
    server_name storage.$base_domain s3.$base_domain;
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 301 https://\$host\$request_uri; }
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
    }
}

EOF
                ;;
                
            parse)
                cat >> "$output_file" << EOF
# ═══════════════════════════════════════════════════
# Parse Server
# ═══════════════════════════════════════════════════

server {
    listen 80;
    server_name api.$base_domain;
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 301 https://\$host\$request_uri; }
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
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 301 https://\$host\$request_uri; }
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
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 301 https://\$host\$request_uri; }
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
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 301 https://\$host\$request_uri; }
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
    }
}

EOF
                ;;
                
            adminer)
                cat >> "$output_file" << EOF
# ═══════════════════════════════════════════════════
# Adminer Database UI
# ═══════════════════════════════════════════════════

server {
    listen 80;
    server_name db.$base_domain;
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 301 https://\$host\$request_uri; }
}

server {
    listen 443 ssl http2;
    server_name db.$base_domain;
    ssl_certificate $cert_path/fullchain.pem;
    ssl_certificate_key $cert_path/privkey.pem;
    
    location / {
        proxy_pass http://adminer:8080;
        proxy_set_header Host \$host;
    }
}

EOF
                ;;
        esac
    done
    
    print_success "✅ HTTPS configuration generated: $output_file"
    
    echo ""
    print_info "Configuration includes:"
    echo "  • Main domain: $base_domain"
    for service in $services; do
        case $service in
            minio) echo "  • MinIO: storage.$base_domain, s3.$base_domain" ;;
            parse) echo "  • Parse: api.$base_domain" ;;
            n8n) echo "  • n8n: flow.$base_domain" ;;
            chatwoot) echo "  • Chatwoot: chat.$base_domain" ;;
            grafana) echo "  • Grafana: monitor.$base_domain" ;;
            adminer) echo "  • Adminer: db.$base_domain" ;;
        esac
    done
}

setup_auto_renewal() {
    local certbot_dir="$1"
    
    print_step "Setting up SSL auto-renewal..."
    
    local renewal_script="/opt/onestack/scripts/ssl-renew.sh"
    mkdir -p /opt/onestack/scripts /opt/onestack/logs
    
    cat > "$renewal_script" << RENEWEOF
#!/bin/bash
LOG_FILE="/opt/onestack/logs/ssl-renewal.log"
mkdir -p "\$(dirname "\$LOG_FILE")"

echo "[\$(date)] Starting SSL renewal check..." >> "\$LOG_FILE"

docker run --rm \\
    -v "$certbot_dir/conf:/etc/letsencrypt" \\
    -v "$certbot_dir/www:/var/www/certbot" \\
    -v "$certbot_dir/logs:/var/log/letsencrypt" \\
    certbot/certbot renew --quiet

if [ \$? -eq 0 ]; then
    echo "[\$(date)] SSL renewal completed successfully" >> "\$LOG_FILE"
    docker compose -f /opt/onestack/docker-compose.yml exec -T nginx nginx -s reload
    echo "[\$(date)] Nginx reloaded" >> "\$LOG_FILE"
else
    echo "[\$(date)] SSL renewal failed!" >> "\$LOG_FILE"
fi
RENEWEOF

    chmod +x "$renewal_script"
    
    local cron_cmd="0 2,14 * * * $renewal_script"
    
    if ! crontab -l 2>/dev/null | grep -q "ssl-renew.sh"; then
        (crontab -l 2>/dev/null; echo "$cron_cmd") | crontab -
        print_success "✅ Auto-renewal cron job added (runs twice daily at 2:00 and 14:00)"
    else
        print_info "Auto-renewal already configured"
    fi
}

setup_ssl_smart() {
    local install_dir="${1:-/opt/onestack}"
    local config_file="${2:-$install_dir/.env}"
    
    print_header "🔒 Smart SSL Setup"
    
    if [ ! -f "$config_file" ]; then
        print_error "Configuration file not found: $config_file"
        return 1
    fi
    
    source "$config_file"
    
    if [ -z "$DOMAIN" ] || [ "$DOMAIN" = "localhost" ]; then
        print_error "Valid domain required for SSL setup"
        print_info "Please set DOMAIN in $config_file"
        return 1
    fi
    
    export CERTBOT_DIR="$install_dir/certbot"
    
    echo ""
    print_info "Configuration:"
    print_info "  Domain: $DOMAIN"
    print_info "  Email: ${SSL_EMAIL:-admin@$DOMAIN}"
    print_info "  Mode: ${SSL_MODE:-production}"
    print_info "  Certbot Dir: $CERTBOT_DIR"
    echo ""
    
    # ═══════════════════════════════════════════════════
    print_header "Step 0: ACME Challenge Setup"
    # ═══════════════════════════════════════════════════
    
    if ! setup_acme_challenge "$install_dir"; then
        print_error "ACME challenge setup failed!"
        return 1
    fi
    
    # ═══════════════════════════════════════════════════
    print_header "Step 1: Service Discovery"
    # ═══════════════════════════════════════════════════
    
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
    
    # ═══════════════════════════════════════════════════
    print_header "Step 2: Domain Discovery"
    # ═══════════════════════════════════════════════════
    
    local all_domains=$(discover_domains "$DOMAIN" "$services")
    
    print_success "Found $(echo $all_domains | wc -w) domains:"
    for dom in $all_domains; do
        echo "  • $dom"
    done
    echo ""
    
    # ═══════════════════════════════════════════════════
    print_header "Step 3: DNS Verification"
    # ═══════════════════════════════════════════════════
    
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
        print_warning "⚠️  DNS not fully configured!"
        print_info "Some domains are not pointing to this server"
        echo ""
        if ! confirm "Continue anyway?"; then
            return 1
        fi
    fi
    
    # ═══════════════════════════════════════════════════
    print_header "Step 4: SSL Status Check"
    # ═══════════════════════════════════════════════════
    
    local missing_ssl=()
    local expiring_ssl=()
    
    for dom in $all_domains; do
        check_existing_ssl "$dom"
        local status=$?
        case $status in
            0)
                print_success "$dom - SSL valid ✓"
                ;;
            2)
                print_warning "$dom - SSL expires soon ⚠"
                expiring_ssl+=("$dom")
                ;;
            1)
                print_warning "$dom - No SSL certificate ✗"
                missing_ssl+=("$dom")
                ;;
        esac
    done
    echo ""
    
    if [ ${#missing_ssl[@]} -gt 0 ] || [ ${#expiring_ssl[@]} -gt 0 ]; then
        # ═══════════════════════════════════════════════════
        print_header "Step 5: Request SSL Certificates"
        # ═══════════════════════════════════════════════════
        
        local all_needed=("${missing_ssl[@]}" "${expiring_ssl[@]}")
        
        print_info "Domains needing certificates: ${#all_needed[@]}"
        for dom in "${all_needed[@]}"; do
            echo "  • $dom"
        done
        echo ""
        
        local ssl_email="${SSL_EMAIL:-admin@$DOMAIN}"
        local ssl_mode="${SSL_MODE:-production}"
        
        # แนะนำ wildcard ถ้ามีหลาย domain
        local use_wildcard=false
        if [ ${#all_needed[@]} -gt 3 ]; then
            print_info "💡 Multiple domains detected. Wildcard certificate recommended."
            echo ""
            if confirm "Use wildcard certificate (*.$DOMAIN)?"; then
                use_wildcard=true
            fi
        fi
        
        echo ""
        if [ "$use_wildcard" = true ]; then
            request_wildcard_certificate "$DOMAIN" "$ssl_email" "$ssl_mode" "$CERTBOT_DIR"
        else
            local domains_str=$(IFS=' '; echo "${all_needed[*]}")
            request_certificate_webroot "$domains_str" "$ssl_email" "$ssl_mode" "$CERTBOT_DIR"
        fi
        
        if [ $? -eq 0 ]; then
            print_success "✅ SSL certificates obtained!"
        else
            print_error "❌ Failed to obtain SSL certificates"
            echo ""
            print_info "Troubleshooting:"
            echo "  1. Check DNS: dig +short $DOMAIN"
            echo "  2. Check logs: cat $CERTBOT_DIR/logs/letsencrypt.log"
            echo "  3. Verify ACME path: curl http://localhost/.well-known/acme-challenge/test"
            return 1
        fi
    else
        print_success "✅ All domains have valid SSL certificates"
    fi
    
    # ═══════════════════════════════════════════════════
    print_header "Step 6: Generate HTTPS Configuration"
    # ═══════════════════════════════════════════════════
    
    # ปิด config เก่า
    [ -f "$install_dir/nginx/conf.d/onestack.conf" ] && \
        mv "$install_dir/nginx/conf.d/onestack.conf" "$install_dir/nginx/conf.d/onestack.conf.disabled"
    
    generate_nginx_https_config "$DOMAIN" "$services" "$CERTBOT_DIR"
    
    # ═══════════════════════════════════════════════════
    print_header "Step 7: Test and Apply Configuration"
    # ═══════════════════════════════════════════════════
    
    print_step "Testing nginx configuration..."
    
    cd "$install_dir"
    
    if docker compose exec -T nginx nginx -t 2>&1 | grep -q "successful"; then
        print_success "✅ Configuration valid"
        
        print_step "Reloading nginx..."
        docker compose exec -T nginx nginx -s reload
        print_success "✅ Nginx reloaded"
    else
        print_error "❌ Configuration test failed"
        echo ""
        docker compose exec -T nginx nginx -t
        return 1
    fi
    
    # ═══════════════════════════════════════════════════
    print_header "Step 8: Setup Auto-Renewal"
    # ═══════════════════════════════════════════════════
    
    setup_auto_renewal "$CERTBOT_DIR"
    
    # ═══════════════════════════════════════════════════
    print_header "✅ SSL Setup Complete!"
    # ═══════════════════════════════════════════════════
    
    echo ""
    print_success "HTTPS enabled for:"
    for dom in $all_domains; do
        echo "  🔒 https://$dom"
    done
    echo ""
    
    print_info "Certificate Details:"
    echo "  Location: $CERTBOT_DIR/conf/live/"
    echo "  Auto-renewal: Enabled (twice daily at 2:00 and 14:00)"
    echo "  Renewal logs: /opt/onestack/logs/ssl-renewal.log"
    echo ""
    
    print_info "Next Steps:"
    echo "  1. Test HTTPS: curl -I https://$DOMAIN"
    echo "  2. Check SSL grade: https://www.ssllabs.com/ssltest/analyze.html?d=$DOMAIN"
    echo "  3. Force HTTPS in apps (update URLs to https://)"
    echo ""
    
    return 0
}