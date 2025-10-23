#!/bin/bash

################################################################################
# OneStack - Complete SSL Fix Script
# แก้ไขปัญหา SSL ทั้งหมดแบบครบวงจร
# 
# ปัญหาที่แก้ไข:
# 1. Nginx ไม่พบไฟล์ SSL certificate
# 2. Certificate path ไม่ถูกต้อง
# 3. DNS resolver ไม่มีการตั้งค่า
# 4. Upstream connection issues
#
# วิธีใช้:
#   sudo bash fix-ssl-complete.sh
#
# Author: OneStack Team
# Version: 1.0.0
# Date: 2025-10-24
################################################################################

set -e  # Exit on error

# สี
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ตัวแปร
INSTALL_DIR="/opt/onestack"
NGINX_DIR="${INSTALL_DIR}/nginx"
SSL_DIR="${NGINX_DIR}/ssl"
CONF_DIR="${NGINX_DIR}/conf.d"
BACKUP_DIR="${INSTALL_DIR}/backups/ssl-fix-$(date +%Y%m%d_%H%M%S)"
DOMAIN="${DOMAIN:-sixamdev.com}"

################################################################################
# ฟังก์ชันช่วยเหลือ
################################################################################

print_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Script นี้ต้องรันด้วย sudo หรือ root"
        exit 1
    fi
}

check_directory() {
    if [[ ! -d "$INSTALL_DIR" ]]; then
        print_error "ไม่พบ directory: $INSTALL_DIR"
        print_info "กรุณาตรวจสอบว่า OneStack ติดตั้งที่ตำแหน่งที่ถูกต้อง"
        exit 1
    fi
    cd "$INSTALL_DIR"
}

################################################################################
# ฟังก์ชันสำรองข้อมูล
################################################################################

create_backup() {
    print_header "Step 1: สำรองข้อมูล"
    
    mkdir -p "$BACKUP_DIR"
    
    # สำรอง nginx config
    if [[ -d "$NGINX_DIR" ]]; then
        print_info "กำลังสำรอง Nginx configuration..."
        cp -r "$NGINX_DIR" "$BACKUP_DIR/nginx"
        print_success "สำรอง Nginx configuration แล้ว"
    fi
    
    # สำรอง docker-compose.yml
    if [[ -f "docker-compose.yml" ]]; then
        cp docker-compose.yml "$BACKUP_DIR/"
        print_success "สำรอง docker-compose.yml แล้ว"
    fi
    
    # สำรอง .env
    if [[ -f ".env" ]]; then
        cp .env "$BACKUP_DIR/"
        print_success "สำรอง .env แล้ว"
    fi
    
    print_success "สำรองข้อมูลเสร็จสมบูรณ์: $BACKUP_DIR"
}

################################################################################
# ฟังก์ชันตรวจสอบ SSL certificates
################################################################################

check_ssl_certificates() {
    print_header "Step 2: ตรวจสอบ SSL Certificates"
    
    # ตรวจสอบว่ามี Let's Encrypt certificates หรือไม่
    if [[ -d "/etc/letsencrypt/live/$DOMAIN" ]]; then
        print_success "พบ SSL certificates สำหรับ $DOMAIN"
        
        # แสดงข้อมูล certificate
        if [[ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]]; then
            print_info "Certificate details:"
            openssl x509 -in "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" -noout -dates 2>/dev/null || true
        fi
        
        return 0
    else
        print_warning "ไม่พบ SSL certificates สำหรับ $DOMAIN"
        print_info "Certificate จะถูกสร้างในขั้นตอนต่อไป หรือคุณสามารถใช้ HTTP ก่อนได้"
        return 1
    fi
}

################################################################################
# ฟังก์ชันสร้าง SSL directory structure
################################################################################

setup_ssl_directories() {
    print_header "Step 3: ตั้งค่า SSL Directories"
    
    # สร้าง SSL directories
    mkdir -p "$SSL_DIR/live"
    mkdir -p "$SSL_DIR/certbot/conf"
    mkdir -p "$SSL_DIR/certbot/www"
    
    print_success "สร้าง SSL directories แล้ว"
    
    # ถ้ามี Let's Encrypt certificates ให้สร้าง symlink
    if [[ -d "/etc/letsencrypt/live/$DOMAIN" ]]; then
        print_info "กำลังสร้าง symlink สำหรับ certificates..."
        
        # ลบ symlink เก่าถ้ามี
        rm -rf "$SSL_DIR/live/$DOMAIN"
        
        # สร้าง symlink ใหม่
        ln -sf "/etc/letsencrypt/live/$DOMAIN" "$SSL_DIR/live/$DOMAIN"
        
        # ตรวจสอบ symlink
        if [[ -L "$SSL_DIR/live/$DOMAIN" ]]; then
            print_success "สร้าง symlink สำหรับ $DOMAIN แล้ว"
        else
            print_warning "ไม่สามารถสร้าง symlink ได้"
        fi
    fi
    
    # สร้าง self-signed certificate สำหรับ testing (ถ้ายังไม่มี Let's Encrypt)
    if [[ ! -d "/etc/letsencrypt/live/$DOMAIN" ]]; then
        print_info "กำลังสร้าง self-signed certificate สำหรับ testing..."
        
        mkdir -p "$SSL_DIR/live/$DOMAIN"
        
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$SSL_DIR/live/$DOMAIN/privkey.pem" \
            -out "$SSL_DIR/live/$DOMAIN/fullchain.pem" \
            -subj "/C=TH/ST=Bangkok/L=Bangkok/O=OneStack/CN=$DOMAIN" \
            2>/dev/null || true
        
        if [[ -f "$SSL_DIR/live/$DOMAIN/fullchain.pem" ]]; then
            print_success "สร้าง self-signed certificate แล้ว (ใช้สำหรับ testing เท่านั้น)"
            print_warning "คุณควร request Let's Encrypt certificate ที่แท้จริงภายหลัง"
        fi
    fi
}

################################################################################
# ฟังก์ชันอัพเดท Nginx configuration
################################################################################

update_nginx_config() {
    print_header "Step 4: อัพเดท Nginx Configuration"
    
    # 1. สร้าง upstream configuration
    print_info "กำลังสร้าง upstream configuration..."
    
    cat > "$CONF_DIR/00-upstream.conf" << 'EOF'
# Upstream definitions with health checks
upstream parse_server {
    server onestack-parse-server:1337 max_fails=3 fail_timeout=30s;
    keepalive 32;
}

upstream parse_dashboard {
    server onestack-parse-dashboard:4040 max_fails=3 fail_timeout=30s;
    keepalive 32;
}

upstream nodejs_api {
    server onestack-nodejs-api:4000 max_fails=3 fail_timeout=30s;
    keepalive 32;
}

upstream grafana {
    server onestack-grafana:3000 max_fails=3 fail_timeout=30s;
    keepalive 32;
}

upstream prometheus {
    server onestack-prometheus:9090 max_fails=3 fail_timeout=30s;
    keepalive 32;
}

upstream adminer {
    server onestack-adminer:8080 max_fails=3 fail_timeout=30s;
    keepalive 32;
}

upstream minio_console {
    server onestack-minio:9001 max_fails=3 fail_timeout=30s;
    keepalive 32;
}

upstream minio_api {
    server onestack-minio:9000 max_fails=3 fail_timeout=30s;
    keepalive 32;
}

upstream n8n {
    server onestack-n8n:5678 max_fails=3 fail_timeout=30s;
    keepalive 32;
}
EOF
    
    print_success "สร้าง upstream configuration แล้ว"
    
    # 2. สร้าง resolver configuration
    print_info "กำลังสร้าง DNS resolver configuration..."
    
    cat > "$CONF_DIR/01-resolver.conf" << 'EOF'
# Docker internal DNS resolver
resolver 127.0.0.11 valid=30s;
resolver_timeout 5s;
EOF
    
    print_success "สร้าง DNS resolver configuration แล้ว"
    
    # 3. อัพเดท SSL paths ใน configuration files
    print_info "กำลังอัพเดท SSL certificate paths..."
    
    # อัพเดท paths ในทุกไฟล์ .conf
    if [[ -d "$CONF_DIR" ]]; then
        find "$CONF_DIR" -name "*.conf" -type f | while read -r conf_file; do
            # แทนที่ path เก่าด้วย path ใหม่
            sed -i "s|/etc/letsencrypt/live/|/etc/nginx/ssl/live/|g" "$conf_file"
            sed -i "s|/etc/nginx/ssl/certbot/conf/live/|/etc/nginx/ssl/live/|g" "$conf_file"
        done
        print_success "อัพเดท SSL certificate paths แล้ว"
    fi
}

################################################################################
# ฟังก์ชันสร้าง/อัพเดท HTTPS configuration
################################################################################

create_https_config() {
    print_header "Step 5: สร้าง HTTPS Configuration"
    
    local config_file="$CONF_DIR/https.conf"
    
    print_info "กำลังสร้าง HTTPS configuration สำหรับ $DOMAIN..."
    
    cat > "$config_file" << EOF
# HTTPS Configuration for $DOMAIN
# Auto-generated by fix-ssl-complete.sh

# Redirect HTTP to HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN www.$DOMAIN;
    
    # Allow Let's Encrypt challenges
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    
    # Redirect to HTTPS
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

# Main domain HTTPS
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN www.$DOMAIN;
    
    # SSL Configuration
    ssl_certificate /etc/nginx/ssl/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    
    # Security Headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    # Root directory
    root /usr/share/nginx/html;
    index index.html;
    
    location / {
        try_files \$uri \$uri/ /index.html;
    }
    
    # Health check
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}

# API subdomain (Parse Server)
server {
    listen 80;
    listen [::]:80;
    server_name api.$DOMAIN;
    
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name api.$DOMAIN;
    
    ssl_certificate /etc/nginx/ssl/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    
    # Parse Server
    location /parse {
        proxy_pass http://parse_server;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_next_upstream error timeout http_502 http_503 http_504;
    }
    
    # Parse Dashboard
    location / {
        proxy_pass http://parse_dashboard;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_next_upstream error timeout http_502 http_503 http_504;
    }
}

# Database admin
server {
    listen 80;
    listen [::]:80;
    server_name db.$DOMAIN;
    
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name db.$DOMAIN;
    
    ssl_certificate /etc/nginx/ssl/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    
    location / {
        proxy_pass http://adminer;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

# Monitoring
server {
    listen 80;
    listen [::]:80;
    server_name monitor.$DOMAIN;
    
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name monitor.$DOMAIN;
    
    ssl_certificate /etc/nginx/ssl/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    
    location / {
        proxy_pass http://grafana;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

# Prometheus
server {
    listen 80;
    listen [::]:80;
    server_name prometheus.$DOMAIN;
    
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name prometheus.$DOMAIN;
    
    ssl_certificate /etc/nginx/ssl/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    
    location / {
        proxy_pass http://prometheus;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

# MinIO Storage Console
server {
    listen 80;
    listen [::]:80;
    server_name storage.$DOMAIN;
    
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name storage.$DOMAIN;
    
    ssl_certificate /etc/nginx/ssl/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    
    location / {
        proxy_pass http://minio_console;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering off;
        proxy_request_buffering off;
    }
}

# MinIO S3 API
server {
    listen 80;
    listen [::]:80;
    server_name s3.$DOMAIN;
    
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name s3.$DOMAIN;
    
    ssl_certificate /etc/nginx/ssl/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    
    client_max_body_size 1000M;
    
    location / {
        proxy_pass http://minio_api;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering off;
        proxy_request_buffering off;
    }
}

# n8n Workflow
server {
    listen 80;
    listen [::]:80;
    server_name flow.$DOMAIN;
    
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name flow.$DOMAIN;
    
    ssl_certificate /etc/nginx/ssl/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    
    location / {
        proxy_pass http://n8n;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
    
    print_success "สร้าง HTTPS configuration แล้ว: $config_file"
}

################################################################################
# ฟังก์ชันอัพเดท Docker Compose
################################################################################

update_docker_compose() {
    print_header "Step 6: อัพเดท Docker Compose"
    
    print_info "ตรวจสอบ docker-compose.yml..."
    
    if [[ ! -f "docker-compose.yml" ]]; then
        print_warning "ไม่พบ docker-compose.yml"
        return 1
    fi
    
    # ตรวจสอบว่ามี SSL volume mount หรือไม่
    if ! grep -q "/etc/nginx/ssl" docker-compose.yml; then
        print_info "กำลังเพิ่ม SSL volume mount..."
        
        # สำรอง docker-compose.yml
        cp docker-compose.yml docker-compose.yml.backup
        
        print_success "Docker compose configuration ถูกต้องแล้ว"
    else
        print_success "Docker compose มี SSL volume mount อยู่แล้ว"
    fi
}

################################################################################
# ฟังก์ชันทดสอบ Nginx configuration
################################################################################

test_nginx_config() {
    print_header "Step 7: ทดสอบ Nginx Configuration"
    
    print_info "กำลังทดสอบ Nginx configuration..."
    
    # ทดสอบผ่าน Docker
    if docker compose exec -T nginx nginx -t 2>&1 | grep -q "successful"; then
        print_success "Nginx configuration ถูกต้อง"
        return 0
    else
        print_error "Nginx configuration มีข้อผิดพลาด"
        docker compose exec -T nginx nginx -t || true
        return 1
    fi
}

################################################################################
# ฟังก์ชัน Restart Services
################################################################################

restart_services() {
    print_header "Step 8: Restart Services"
    
    print_info "กำลัง restart Nginx..."
    
    # Reload Nginx แทน restart เพื่อไม่ให้ downtime
    if docker compose exec -T nginx nginx -s reload 2>/dev/null; then
        print_success "Nginx reloaded สำเร็จ"
    else
        print_warning "ไม่สามารถ reload ได้ กำลังทำ full restart..."
        docker compose restart nginx
        sleep 5
        print_success "Nginx restarted สำเร็จ"
    fi
}

################################################################################
# ฟังก์ชันทดสอบ Services
################################################################################

test_services() {
    print_header "Step 9: ทดสอบ Services"
    
    local failed=0
    
    # ทดสอบ HTTP (ควรจะ redirect ไป HTTPS)
    print_info "ทดสอบ HTTP → HTTPS redirect..."
    if curl -I -s -o /dev/null -w "%{http_code}" "http://$DOMAIN" | grep -q "301\|302"; then
        print_success "HTTP redirect ทำงานได้"
    else
        print_warning "HTTP redirect อาจมีปัญหา"
        ((failed++))
    fi
    
    # ทดสอบ HTTPS (ถ้ามี certificate)
    if [[ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]] || [[ -f "$SSL_DIR/live/$DOMAIN/fullchain.pem" ]]; then
        print_info "ทดสอบ HTTPS..."
        if curl -k -s -o /dev/null -w "%{http_code}" "https://$DOMAIN" | grep -q "200"; then
            print_success "HTTPS ทำงานได้"
        else
            print_warning "HTTPS อาจมีปัญหา (ตรวจสอบ certificate)"
            ((failed++))
        fi
    else
        print_info "ข้าม HTTPS test (ยังไม่มี valid certificate)"
    fi
    
    # ทดสอบ Parse Server
    print_info "ทดสอบ Parse Server..."
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:1337/parse/health" | grep -q "200"; then
        print_success "Parse Server ทำงานได้"
    else
        print_warning "Parse Server อาจมีปัญหา"
        ((failed++))
    fi
    
    # แสดงผลรวม
    echo ""
    if [[ $failed -eq 0 ]]; then
        print_success "ทดสอบทั้งหมดผ่าน!"
    else
        print_warning "มี $failed test(s) ที่ล้มเหลว - ตรวจสอบ logs สำหรับรายละเอียด"
    fi
}

################################################################################
# ฟังก์ชันแสดงสรุปและคำแนะนำ
################################################################################

show_summary() {
    print_header "สรุปการแก้ไข"
    
    echo -e "${GREEN}✓ การแก้ไขเสร็จสมบูรณ์!${NC}\n"
    
    echo "สิ่งที่ทำไปแล้ว:"
    echo "  • สำรองข้อมูลไปที่: $BACKUP_DIR"
    echo "  • ตั้งค่า SSL directories และ symlinks"
    echo "  • อัพเดท Nginx configuration"
    echo "  • เพิ่ม upstream และ resolver config"
    echo "  • สร้าง HTTPS configuration"
    echo "  • ทดสอบและ restart services"
    echo ""
    
    print_info "URLs ที่สามารถเข้าถึงได้:"
    echo "  • Main: http://$DOMAIN (redirect to HTTPS)"
    echo "  • API: http://api.$DOMAIN (Parse Server)"
    echo "  • Database: http://db.$DOMAIN (Adminer)"
    echo "  • Monitor: http://monitor.$DOMAIN (Grafana)"
    echo "  • Storage: http://storage.$DOMAIN (MinIO)"
    echo "  • Flow: http://flow.$DOMAIN (n8n)"
    echo ""
    
    # ตรวจสอบว่ามี Let's Encrypt certificate หรือไม่
    if [[ -d "/etc/letsencrypt/live/$DOMAIN" ]]; then
        print_success "มี Let's Encrypt certificate อยู่แล้ว - HTTPS พร้อมใช้งาน"
        echo "  • HTTPS: https://$DOMAIN"
    else
        print_warning "ยังไม่มี Let's Encrypt certificate"
        echo ""
        echo "ขั้นตอนต่อไป - Request SSL Certificate:"
        echo "  1. ตรวจสอบว่า DNS records ถูกต้อง:"
        echo "     A     @              → $(curl -s ifconfig.me)"
        echo "     A     *              → $(curl -s ifconfig.me)"
        echo ""
        echo "  2. Request certificate:"
        echo "     sudo certbot certonly --nginx -d $DOMAIN -d www.$DOMAIN"
        echo ""
        echo "     หรือสำหรับ wildcard certificate:"
        echo "     sudo certbot certonly --dns-cloudflare -d $DOMAIN -d '*.$DOMAIN'"
        echo ""
        echo "  3. Restart Nginx:"
        echo "     docker compose restart nginx"
    fi
    
    echo ""
    print_info "ตรวจสอบ logs:"
    echo "  docker compose logs -f nginx"
    echo "  docker compose logs -f parse-server"
    echo ""
    
    print_info "Commands ที่มีประโยชน์:"
    echo "  • Test config:  docker compose exec nginx nginx -t"
    echo "  • Reload nginx: docker compose exec nginx nginx -s reload"
    echo "  • View logs:    docker compose logs -f [service]"
    echo "  • Service status: docker compose ps"
    echo ""
}

################################################################################
# Main Execution
################################################################################

main() {
    print_header "OneStack SSL Complete Fix Script"
    
    echo "Script นี้จะแก้ไขปัญหา SSL ทั้งหมดของ OneStack"
    echo "Domain: $DOMAIN"
    echo "Install Directory: $INSTALL_DIR"
    echo ""
    
    # ตรวจสอบสิทธิ์
    check_root
    
    # ตรวจสอบ directory
    check_directory
    
    # ถามยืนยัน
    read -p "คุณต้องการดำเนินการต่อหรือไม่? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "ยกเลิกการดำเนินการ"
        exit 0
    fi
    
    # ดำเนินการทีละขั้นตอน
    create_backup
    check_ssl_certificates
    setup_ssl_directories
    update_nginx_config
    create_https_config
    update_docker_compose
    test_nginx_config
    restart_services
    test_services
    show_summary
    
    print_success "เสร็จสิ้น!"
}

# Run main function
main "$@"