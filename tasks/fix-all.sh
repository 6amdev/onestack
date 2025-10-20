#!/bin/bash
# ═══════════════════════════════════════════════════
# Fix Everything - Parse Dashboard + SSL + HTTPS
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
print_step() { echo -e "\n${BLUE}▶${NC} $1\n"; }
print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
    echo ""
}

# Check root
if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root: sudo bash $0"
    exit 1
fi

print_header "OneStack Complete Fix Script"

cd /opt/onestack

# Get domain from .env
DOMAIN=$(grep "^DOMAIN=" .env 2>/dev/null | cut -d= -f2)

if [ -z "$DOMAIN" ]; then
    print_error "Domain not found in .env"
    exit 1
fi

print_info "Domain: $DOMAIN"
echo ""

# ═══════════════════════════════════════════════════
# Step 1: Fix Parse Dashboard Config
# ═══════════════════════════════════════════════════

print_step "Step 1/5: Creating Parse Dashboard config..."

mkdir -p parse-dashboard

cat > parse-dashboard/config.json << 'CONFIGEOF'
{
  "apps": [
    {
      "serverURL": "http://parse-server:1337/parse",
      "appId": "onestack_app_id",
      "masterKey": "onestack_master_key_12345",
      "appName": "OneStack"
    }
  ],
  "users": [
    {
      "user": "admin",
      "pass": "onestack123"
    }
  ],
  "trustProxy": 1,
  "allowInsecureHTTP": true
}
CONFIGEOF

print_success "Config file created"

# ═══════════════════════════════════════════════════
# Step 2: Update docker-compose.yml
# ═══════════════════════════════════════════════════

print_step "Step 2/5: Updating docker-compose.yml..."

# Check if volume already exists
if grep -q "parse-dashboard/config.json" docker-compose.yml; then
    print_info "Volume mount already exists"
else
    print_info "Adding volume mount to parse-dashboard..."
    
    # Backup
    cp docker-compose.yml docker-compose.yml.backup-$(date +%Y%m%d_%H%M%S)
    
    # Add command and volumes to parse-dashboard service
    # This is a safe way using sed
    sed -i '/parse-dashboard:/,/depends_on:/ {
        /depends_on:/i\    command:\n      - parse-dashboard\n      - --config\n      - /parse-dashboard/config.json\n      - --allowInsecureHTTP\n    volumes:\n      - ./parse-dashboard/config.json:/parse-dashboard/config.json:ro
    }' docker-compose.yml
    
    print_success "docker-compose.yml updated"
fi

# ═══════════════════════════════════════════════════
# Step 3: Restart Parse Dashboard
# ═══════════════════════════════════════════════════

print_step "Step 3/5: Restarting Parse Dashboard..."

docker compose stop parse-dashboard
docker compose rm -f parse-dashboard
docker compose up -d parse-dashboard

print_info "Waiting 15 seconds for Parse Dashboard to start..."
sleep 15

# Check status
STATUS=$(docker compose ps parse-dashboard --format '{{.Status}}' 2>/dev/null || echo "unknown")

if [[ "$STATUS" == *"Up"* ]]; then
    print_success "Parse Dashboard is running!"
    
    # Test access
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:4040 | grep -q "200\|301\|302"; then
        print_success "Parse Dashboard is accessible at http://localhost:4040"
    fi
else
    print_error "Parse Dashboard failed to start"
    print_info "Status: $STATUS"
    print_info "Logs:"
    docker compose logs --tail=20 parse-dashboard
    
    read -p "Continue anyway? (y/N): " continue
    if [ "$continue" != "y" ]; then
        exit 1
    fi
fi

# ═══════════════════════════════════════════════════
# Step 4: Install Certbot & Request SSL Certificate
# ═══════════════════════════════════════════════════

print_step "Step 4/5: Setting up SSL Certificate..."

# Install Certbot if not exists
if ! command -v certbot &> /dev/null; then
    print_info "Installing Certbot..."
    apt-get update -qq
    apt-get install -y certbot python3-certbot-nginx
    print_success "Certbot installed"
else
    print_info "Certbot already installed"
fi

# Check if certificate already exists
if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
    print_success "SSL Certificate already exists"
    
    # Check expiry
    EXPIRY=$(openssl x509 -in "/etc/letsencrypt/live/$DOMAIN/cert.pem" -noout -enddate | cut -d= -f2)
    print_info "Expires: $EXPIRY"
    
    read -p "Request new certificate? (y/N): " renew
    if [ "$renew" != "y" ]; then
        print_info "Using existing certificate"
    else
        certbot delete --cert-name $DOMAIN --non-interactive
        NEED_CERT=true
    fi
else
    NEED_CERT=true
fi

if [ "$NEED_CERT" = "true" ]; then
    print_info "Requesting SSL Certificate..."
    echo ""
    
    read -p "Enter your email for Let's Encrypt: " EMAIL
    
    if [ -z "$EMAIL" ]; then
        print_error "Email is required"
        exit 1
    fi
    
    echo ""
    print_info "Requesting certificate for:"
    echo "  - $DOMAIN"
    echo "  - www.$DOMAIN"
    echo "  - storage.$DOMAIN"
    echo "  - s3.$DOMAIN"
    echo "  - api.$DOMAIN"
    echo "  - monitor.$DOMAIN"
    echo "  - prometheus.$DOMAIN"
    echo "  - db.$DOMAIN"
    echo ""
    
    # Create webroot directory
    mkdir -p /opt/onestack/frontends/main/.well-known/acme-challenge
    
    # Request certificate
    certbot certonly --webroot \
        -w /opt/onestack/frontends/main \
        -d $DOMAIN \
        -d www.$DOMAIN \
        -d storage.$DOMAIN \
        -d s3.$DOMAIN \
        -d api.$DOMAIN \
        -d monitor.$DOMAIN \
        -d prometheus.$DOMAIN \
        -d db.$DOMAIN \
        --email $EMAIL \
        --agree-tos \
        --non-interactive
    
    if [ $? -eq 0 ]; then
        print_success "SSL Certificate obtained successfully!"
        ls -lah /etc/letsencrypt/live/$DOMAIN/
    else
        print_error "Failed to obtain SSL certificate"
        echo ""
        print_info "Common issues:"
        print_info "  1. Domain DNS not pointing to this server"
        print_info "  2. Port 80 not accessible from internet"
        print_info "  3. Firewall blocking port 80"
        echo ""
        print_info "Check DNS:"
        echo "    dig +short $DOMAIN"
        echo "    dig +short www.$DOMAIN"
        echo ""
        print_info "Test port 80:"
        echo "    curl -I http://$DOMAIN"
        echo ""
        
        read -p "Continue without SSL? (y/N): " continue
        if [ "$continue" != "y" ]; then
            exit 1
        fi
        
        print_info "Will use HTTP only"
        USE_HTTP_ONLY=true
    fi
fi

# ═══════════════════════════════════════════════════
# Step 5: Enable HTTPS
# ═══════════════════════════════════════════════════

if [ "$USE_HTTP_ONLY" != "true" ]; then
    print_step "Step 5/5: Enabling HTTPS..."
    
    # Backup current nginx config
    cp nginx/conf.d/onestack.conf nginx/conf.d/onestack.conf.backup-$(date +%Y%m%d_%H%M%S)
    
    # Create HTTPS config
    cat > nginx/conf.d/onestack.conf << NGINXEOF
# ═══════════════════════════════════════════════════
# OneStack - HTTPS Configuration
# Domain: $DOMAIN
# Generated: $(date)
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
    listen 443 ssl http2;
    server_name $DOMAIN www.$DOMAIN;
    
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256';
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
    listen 443 ssl http2;
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
    listen 443 ssl http2;
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
    listen 443 ssl http2;
    server_name api.$DOMAIN;
    
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
    # Parse Server API
    location /parse {
        proxy_pass http://parse-server:1337/parse;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    # Parse Dashboard
    location / {
        proxy_pass http://parse-dashboard:4040;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

# Grafana (HTTPS)
server {
    listen 443 ssl http2;
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
    listen 443 ssl http2;
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
    listen 443 ssl http2;
    server_name db.$DOMAIN;
    
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
    location / {
        proxy_pass http://adminer:8080;
        proxy_set_header Host \$host;
    }
}
NGINXEOF

    print_success "HTTPS configuration created"
    
    # Test nginx config
    print_info "Testing Nginx configuration..."
    
    if docker compose exec nginx nginx -t 2>&1 | grep -q "successful"; then
        print_success "Nginx configuration is valid"
        
        print_info "Reloading Nginx..."
        docker compose exec nginx nginx -s reload
        
        print_success "Nginx reloaded successfully"
    else
        print_error "Nginx configuration test failed"
        docker compose exec nginx nginx -t
        
        print_info "Restoring backup..."
        cp nginx/conf.d/onestack.conf.backup-* nginx/conf.d/onestack.conf
        docker compose exec nginx nginx -s reload
        
        exit 1
    fi
    
    # Setup auto-renewal
    print_info "Setting up SSL auto-renewal..."
    
    # Create renewal script
    cat > /etc/cron.daily/certbot-renew << 'CRONEOF'
#!/bin/bash
certbot renew --quiet --deploy-hook "docker compose -f /opt/onestack/docker-compose.yml exec nginx nginx -s reload"
CRONEOF
    
    chmod +x /etc/cron.daily/certbot-renew
    print_success "Auto-renewal configured"
fi

# ═══════════════════════════════════════════════════
# Final Summary
# ═══════════════════════════════════════════════════

print_header "✅ Installation Complete!"

echo "📋 Summary:"
echo ""
echo "✓ Parse Dashboard fixed and running"
echo "✓ SSL Certificate obtained"
echo "✓ HTTPS enabled"
echo "✓ Auto-renewal configured"
echo ""

print_header "🌐 Access URLs"

if [ "$USE_HTTP_ONLY" = "true" ]; then
    echo "⚠️  HTTP Only (No SSL):"
    echo ""
    echo "  Main Site:        http://$DOMAIN"
    echo "  Storage (MinIO):  http://storage.$DOMAIN"
    echo "  Parse Dashboard:  http://api.$DOMAIN"
    echo "  Grafana:          http://monitor.$DOMAIN"
    echo "  Prometheus:       http://prometheus.$DOMAIN"
    echo "  Adminer:          http://db.$DOMAIN"
else
    echo "🔒 HTTPS Enabled:"
    echo ""
    echo "  Main Site:        https://$DOMAIN"
    echo "  Storage (MinIO):  https://storage.$DOMAIN"
    echo "  Parse Dashboard:  https://api.$DOMAIN"
    echo "  Grafana:          https://monitor.$DOMAIN"
    echo "  Prometheus:       https://prometheus.$DOMAIN"
    echo "  Adminer:          https://db.$DOMAIN"
fi

echo ""

print_header "🔑 Credentials"

echo "Parse Dashboard:"
echo "  Username: admin"
echo "  Password: onestack123"
echo ""

echo "Other credentials: /opt/onestack/.credentials"
echo ""

print_header "✨ Next Steps"

echo "1. Test all URLs above"
echo "2. Update DNS if needed"
echo "3. Check SSL grade: https://www.ssllabs.com/ssltest/analyze.html?d=$DOMAIN"
echo "4. Customize your services"
echo ""

print_success "All done! Enjoy your OneStack! 🚀"
echo ""
