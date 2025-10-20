#!/bin/bash
# ═══════════════════════════════════════════════════
# Enable HTTPS - Complete Fix
# Fix Parse Dashboard + Enable HTTPS
# ═══════════════════════════════════════════════════

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_info() { echo -e "${YELLOW}ℹ${NC} $1"; }
print_step() { echo -e "${BLUE}▶${NC} $1"; }
print_header() {
    echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
}

if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root"
    exit 1
fi

cd /opt/onestack

# Get domain
DOMAIN=$(grep "^DOMAIN=" .env 2>/dev/null | cut -d= -f2)

if [ -z "$DOMAIN" ]; then
    print_error "Domain not found in .env"
    exit 1
fi

print_header "Enable HTTPS for $DOMAIN"
echo ""

# ═══════════════════════════════════════════════════
# Step 1: Fix Parse Dashboard
# ═══════════════════════════════════════════════════

print_step "Step 1: Fixing Parse Dashboard..."
echo ""

print_info "Stopping Parse Dashboard..."
docker compose stop parse-dashboard

print_info "Removing Parse Dashboard container..."
docker compose rm -f parse-dashboard

print_info "Starting Parse Dashboard..."
docker compose up -d parse-dashboard

print_info "Waiting 15 seconds for Parse Dashboard to start..."
sleep 15

# Check status
STATUS=$(docker compose ps parse-dashboard --format '{{.Status}}' 2>/dev/null)

if [[ "$STATUS" == *"Up"* ]]; then
    print_success "Parse Dashboard is running"
else
    print_error "Parse Dashboard failed to start"
    print_info "Status: $STATUS"
    print_info "Continuing without Parse Dashboard..."
    SKIP_DASHBOARD=true
fi

echo ""

# ═══════════════════════════════════════════════════
# Step 2: Check SSL Certificates
# ═══════════════════════════════════════════════════

print_step "Step 2: Checking SSL certificates..."
echo ""

if [ ! -d "/etc/letsencrypt/live/$DOMAIN" ]; then
    print_error "SSL certificates not found"
    print_info "Run: ./manage.sh → 1) Setup SSL"
    exit 1
fi

print_success "SSL certificates found"
echo ""

# ═══════════════════════════════════════════════════
# Step 3: Backup Current Config
# ═══════════════════════════════════════════════════

print_step "Step 3: Backing up current config..."
echo ""

cp nginx/conf.d/onestack.conf nginx/conf.d/onestack.conf.backup-$(date +%Y%m%d_%H%M%S)
print_success "Config backed up"
echo ""

# ═══════════════════════════════════════════════════
# Step 4: Create HTTPS Config
# ═══════════════════════════════════════════════════

print_step "Step 4: Creating HTTPS configuration..."
echo ""

if [ "$SKIP_DASHBOARD" = "true" ]; then
    print_info "Creating config without Parse Dashboard..."
    
cat > nginx/conf.d/onestack.conf << EOF
# ═══════════════════════════════════════════════════
# OneStack - HTTPS Configuration
# Domain: $DOMAIN (Parse Dashboard disabled)
# ═══════════════════════════════════════════════════

# HTTP to HTTPS Redirect
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN storage.$DOMAIN s3.$DOMAIN api.$DOMAIN monitor.$DOMAIN prometheus.$DOMAIN db.$DOMAIN;
    
    location /.well-known/acme-challenge/ {
        root /var/www/main;
        allow all;
    }
    
    location / {
        return 301 https://\$host\$request_uri;
    }
}

# Main Site (HTTPS)
server {
    listen 443 ssl;
    http2 on;
    server_name $DOMAIN www.$DOMAIN;
    
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
    ssl_session_cache shared:SSL:10m;
    
    add_header Strict-Transport-Security "max-age=63072000" always;
    
    root /var/www/main;
    index index.html;
    
    location / {
        try_files \$uri \$uri/ /index.html;
    }
}

# MinIO Console (HTTPS)
server {
    listen 443 ssl;
    http2 on;
    server_name storage.$DOMAIN;
    
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
    client_max_body_size 100M;
    
    location / {
        proxy_pass http://minio:9001;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

# MinIO S3 API (HTTPS)
server {
    listen 443 ssl;
    http2 on;
    server_name s3.$DOMAIN;
    
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
    client_max_body_size 100M;
    
    location / {
        proxy_pass http://minio:9000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}

# Parse Server API (HTTPS) - Dashboard disabled
server {
    listen 443 ssl;
    http2 on;
    server_name api.$DOMAIN;
    
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
    location /parse {
        proxy_pass http://parse-server:1337/parse;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    location / {
        return 200 'Parse Server API: /parse\n';
        add_header Content-Type text/plain;
    }
}

# Grafana (HTTPS)
server {
    listen 443 ssl;
    http2 on;
    server_name monitor.$DOMAIN;
    
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
    location / {
        proxy_pass http://grafana:3000;
        proxy_set_header Host \$host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

# Prometheus (HTTPS)
server {
    listen 443 ssl;
    http2 on;
    server_name prometheus.$DOMAIN;
    
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
    location / {
        proxy_pass http://prometheus:9090;
        proxy_set_header Host \$host;
    }
}

# Adminer (HTTPS)
server {
    listen 443 ssl;
    http2 on;
    server_name db.$DOMAIN;
    
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
    location / {
        proxy_pass http://adminer:8080;
        proxy_set_header Host \$host;
    }
}
EOF

else
    print_info "Creating config with Parse Dashboard..."
    
cat > nginx/conf.d/onestack.conf << EOF
# ═══════════════════════════════════════════════════
# OneStack - HTTPS Configuration
# Domain: $DOMAIN
# ═══════════════════════════════════════════════════

# HTTP to HTTPS Redirect
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN storage.$DOMAIN s3.$DOMAIN api.$DOMAIN monitor.$DOMAIN prometheus.$DOMAIN db.$DOMAIN;
    
    location /.well-known/acme-challenge/ {
        root /var/www/main;
        allow all;
    }
    
    location / {
        return 301 https://\$host\$request_uri;
    }
}

# Main Site (HTTPS)
server {
    listen 443 ssl;
    http2 on;
    server_name $DOMAIN www.$DOMAIN;
    
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
    ssl_session_cache shared:SSL:10m;
    
    add_header Strict-Transport-Security "max-age=63072000" always;
    
    root /var/www/main;
    index index.html;
    
    location / {
        try_files \$uri \$uri/ /index.html;
    }
}

# MinIO Console (HTTPS)
server {
    listen 443 ssl;
    http2 on;
    server_name storage.$DOMAIN;
    
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
    client_max_body_size 100M;
    
    location / {
        proxy_pass http://minio:9001;
        proxy_set_header Host \$host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

# MinIO S3 API (HTTPS)
server {
    listen 443 ssl;
    http2 on;
    server_name s3.$DOMAIN;
    
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
    client_max_body_size 100M;
    
    location / {
        proxy_pass http://minio:9000;
        proxy_set_header Host \$host;
    }
}

# Parse Server + Dashboard (HTTPS)
server {
    listen 443 ssl;
    http2 on;
    server_name api.$DOMAIN;
    
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
    # Parse Server API
    location /parse {
        proxy_pass http://parse-server:1337/parse;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    # Parse Dashboard
    location / {
        proxy_pass http://parse-dashboard:4040;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

# Grafana (HTTPS)
server {
    listen 443 ssl;
    http2 on;
    server_name monitor.$DOMAIN;
    
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
    location / {
        proxy_pass http://grafana:3000;
        proxy_set_header Host \$host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

# Prometheus (HTTPS)
server {
    listen 443 ssl;
    http2 on;
    server_name prometheus.$DOMAIN;
    
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
    location / {
        proxy_pass http://prometheus:9090;
        proxy_set_header Host \$host;
    }
}

# Adminer (HTTPS)
server {
    listen 443 ssl;
    http2 on;
    server_name db.$DOMAIN;
    
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
    location / {
        proxy_pass http://adminer:8080;
        proxy_set_header Host \$host;
    }
}
EOF

fi

print_success "HTTPS configuration created"
echo ""

# ═══════════════════════════════════════════════════
# Step 5: Test & Reload Nginx
# ═══════════════════════════════════════════════════

print_step "Step 5: Testing Nginx configuration..."
echo ""

docker compose exec nginx nginx -t

if [ $? -eq 0 ]; then
    print_success "Nginx configuration is valid"
    
    echo ""
    print_step "Reloading Nginx..."
    docker compose exec nginx nginx -s reloa