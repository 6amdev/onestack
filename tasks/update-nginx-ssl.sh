#!/bin/bash
# ═══════════════════════════════════════════════════
# Update Nginx Configuration for HTTPS
# ═══════════════════════════════════════════════════

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_info() { echo -e "${YELLOW}ℹ${NC} $1"; }
print_step() { echo -e "${BLUE}▶${NC} $1"; }

# Check root
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

print_info "Domain: $DOMAIN"

# Check if SSL certificates exist
if [ ! -d "/etc/letsencrypt/live/$DOMAIN" ]; then
    print_error "SSL certificates not found"
    print_info "Run: ./manage.sh → 1) Setup SSL"
    exit 1
fi

print_success "SSL certificates found"

# Backup current config
print_step "Backing up current Nginx config..."
cp nginx/conf.d/onestack.conf nginx/conf.d/onestack.conf.backup-$(date +%Y%m%d_%H%M%S)
print_success "Config backed up"

# Create new HTTPS config
print_step "Creating HTTPS configuration..."

cat > nginx/conf.d/onestack.conf << EOF
# ═══════════════════════════════════════════════════
# OneStack - Nginx Configuration with HTTPS
# Domain: $DOMAIN
# ═══════════════════════════════════════════════════

# HTTP to HTTPS Redirect
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN storage.$DOMAIN s3.$DOMAIN api.$DOMAIN monitor.$DOMAIN prometheus.$DOMAIN db.$DOMAIN;
    
    # Allow Let's Encrypt challenges
    location /.well-known/acme-challenge/ {
        root /var/www/main;
        allow all;
    }
    
    # Redirect all other requests to HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}

# ═══════════════════════════════════════════════════
# Main Site (HTTPS)
# ═══════════════════════════════════════════════════

server {
    listen 443 ssl http2;
    server_name $DOMAIN www.$DOMAIN;
    
    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/$DOMAIN/chain.pem;
    
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
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    root /var/www/main;
    index index.html index.htm;
    
    location / {
        try_files \$uri \$uri/ /index.html;
    }
    
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
}

# ═══════════════════════════════════════════════════
# MinIO Console (HTTPS)
# ═══════════════════════════════════════════════════

server {
    listen 443 ssl http2;
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
        proxy_buffering off;
    }
}

# ═══════════════════════════════════════════════════
# MinIO S3 API (HTTPS)
# ═══════════════════════════════════════════════════

server {
    listen 443 ssl http2;
    server_name s3.$DOMAIN;
    
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
    client_max_body_size 100M;
    
    location / {
        proxy_pass http://minio:9000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering off;
    }
}

# ═══════════════════════════════════════════════════
# Parse Server & Dashboard (HTTPS)
# ═══════════════════════════════════════════════════

server {
    listen 443 ssl http2;
    server_name api.$DOMAIN;
    
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
    # Parse Server
    location /parse {
        proxy_pass http://parse-server:1337/parse;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300s;
    }
    
    # Parse Dashboard
    location / {
        proxy_pass http://parse-dashboard:4040;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300s;
    }
}

# ═══════════════════════════════════════════════════
# Grafana (HTTPS)
# ═══════════════════════════════════════════════════

server {
    listen 443 ssl http2;
    server_name monitor.$DOMAIN;
    
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
    location / {
        proxy_pass http://grafana:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

# ═══════════════════════════════════════════════════
# Prometheus (HTTPS)
# ═══════════════════════════════════════════════════

server {
    listen 443 ssl http2;
    server_name prometheus.$DOMAIN;
    
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
    location / {
        proxy_pass http://prometheus:9090;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

# ═══════════════════════════════════════════════════
# Adminer (HTTPS)
# ═══════════════════════════════════════════════════

server {
    listen 443 ssl http2;
    server_name db.$DOMAIN;
    
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
    location / {
        proxy_pass http://adminer:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300s;
    }
}
EOF

print_success "HTTPS configuration created"

# Test Nginx config
print_step "Testing Nginx configuration..."
docker compose exec nginx nginx -t

if [ $? -eq 0 ]; then
    print_success "Nginx configuration is valid"
    
    # Reload Nginx
    print_step "Reloading Nginx..."
    docker compose exec nginx nginx -s reload
    
    print_success "Nginx reloaded successfully"
    
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "✅ HTTPS Enabled Successfully!"
    echo "═══════════════════════════════════════════════════"
    echo ""
    echo "Your sites are now accessible via HTTPS:"
    echo "  🔒 https://$DOMAIN"
    echo "  🔒 https://www.$DOMAIN"
    echo "  🔒 https://storage.$DOMAIN"
    echo "  🔒 https://s3.$DOMAIN"
    echo "  🔒 https://api.$DOMAIN"
    echo "  🔒 https://monitor.$DOMAIN"
    echo "  🔒 https://prometheus.$DOMAIN"
    echo "  🔒 https://db.$DOMAIN"
    echo ""
    echo "HTTP will automatically redirect to HTTPS"
    echo ""
    echo "Test your SSL grade:"
    echo "  https://www.ssllabs.com/ssltest/analyze.html?d=$DOMAIN"
    echo ""
    
else
    print_error "Nginx configuration test failed"
    print_info "Restoring backup..."
    
    # Find latest backup
    latest_backup=$(ls -t nginx/conf.d/onestack.conf.backup-* 2>/dev/null | head -1)
    if [ -n "$latest_backup" ]; then
        cp "$latest_backup" nginx/conf.d/onestack.conf
        docker compose exec nginx nginx -s reload
        print_info "Backup restored"
    fi
    
    exit 1
fi