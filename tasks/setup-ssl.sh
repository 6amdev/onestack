#!/bin/bash
# Setup SSL/HTTPS with Let's Encrypt

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh" 2>/dev/null || {
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    BLUE='\033[0;34m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
    print_header() { echo -e "\n${BLUE}=== $1 ===${NC}\n"; }
    print_step() { echo -e "${BLUE}▶${NC} $1"; }
    print_success() { echo -e "${GREEN}✓${NC} $1"; }
    print_error() { echo -e "${RED}✗${NC} $1"; exit 1; }
    print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
    print_info() { echo -e "${YELLOW}ℹ${NC} $1"; }
}

check_root

print_header "SSL/HTTPS Setup with Let's Encrypt"

INSTALL_DIR="/opt/onestack"

# Load domain from .env
if [ -f "$INSTALL_DIR/.env" ]; then
    source "$INSTALL_DIR/.env"
else
    print_error ".env file not found. Please run installation first."
fi

# Check if localhost
if [ "$DOMAIN" = "localhost" ]; then
    print_error "Cannot setup SSL for localhost. Please configure a real domain first."
fi

echo ""
print_info "Domain: $DOMAIN"
print_info "Email: ${SSL_EMAIL:-admin@$DOMAIN}"
echo ""

# Get all subdomains from nginx config
SUBDOMAINS="www storage s3"

# Check if services are installed
[ -f "$INSTALL_DIR/nginx/conf.d/onestack.conf" ] && {
    grep -q "api\.$DOMAIN" "$INSTALL_DIR/nginx/conf.d/onestack.conf" && SUBDOMAINS="$SUBDOMAINS api"
    grep -q "monitor\.$DOMAIN" "$INSTALL_DIR/nginx/conf.d/onestack.conf" && SUBDOMAINS="$SUBDOMAINS monitor"
    grep -q "db\.$DOMAIN" "$INSTALL_DIR/nginx/conf.d/onestack.conf" && SUBDOMAINS="$SUBDOMAINS db"
    grep -q "chat\.$DOMAIN" "$INSTALL_DIR/nginx/conf.d/onestack.conf" && SUBDOMAINS="$SUBDOMAINS chat"
    grep -q "flow\.$DOMAIN" "$INSTALL_DIR/nginx/conf.d/onestack.conf" && SUBDOMAINS="$SUBDOMAINS flow"
    grep -q "ai\.$DOMAIN" "$INSTALL_DIR/nginx/conf.d/onestack.conf" && SUBDOMAINS="$SUBDOMAINS ai"
}

print_info "Subdomains detected: $SUBDOMAINS"
echo ""

# Build domain list for certbot
DOMAIN_ARGS="-d $DOMAIN"
for sub in $SUBDOMAINS; do
    DOMAIN_ARGS="$DOMAIN_ARGS -d $sub.$DOMAIN"
done

print_warning "DNS Check Required!"
echo ""
echo "Before continuing, make sure these DNS records point to this server:"
echo ""
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
echo "  A    $DOMAIN                → $SERVER_IP"
for sub in $SUBDOMAINS; do
    echo "  A    $sub.$DOMAIN         → $SERVER_IP"
done
echo ""
read -p "Have you configured DNS records? (y/N): " dns_ready

if [ "$dns_ready" != "y" ]; then
    print_info "Please configure DNS first, then run this script again."
    exit 0
fi

# Install certbot
print_step "Installing certbot..."
apt-get update -qq
apt-get install -y certbot

# Test webroot access
print_step "Testing webroot access..."
WEBROOT="$INSTALL_DIR/frontends/main"

if [ ! -d "$WEBROOT" ]; then
    print_error "Webroot not found: $WEBROOT"
fi

# Create test file
echo "test" > "$WEBROOT/test.txt"

# Test HTTP access
TEST_URL="http://$DOMAIN/test.txt"
print_step "Testing: $TEST_URL"

if curl -sf "$TEST_URL" > /dev/null; then
    print_success "Webroot accessible"
    rm -f "$WEBROOT/test.txt"
else
    print_warning "Cannot access $TEST_URL"
    print_info "Make sure:"
    echo "  1. DNS is propagated"
    echo "  2. Nginx is running"
    echo "  3. Port 80 is open"
    echo ""
    read -p "Continue anyway? (y/N): " force
    [ "$force" != "y" ] && exit 0
fi

# Choose mode
echo ""
print_info "SSL Mode:"
echo "  1) Staging (testing, fake certificates)"
echo "  2) Production (real certificates)"
echo ""
read -p "Choose mode [1/2]: " ssl_mode

case $ssl_mode in
    1)
        MODE_ARG="--staging"
        print_info "Using STAGING mode (test certificates)"
        ;;
    2)
        MODE_ARG=""
        print_warning "Using PRODUCTION mode (real certificates)"
        ;;
    *)
        print_error "Invalid choice"
        ;;
esac

# Request certificate
print_step "Requesting SSL certificate..."
echo ""

certbot certonly \
    --webroot \
    -w "$WEBROOT" \
    $DOMAIN_ARGS \
    --email "${SSL_EMAIL:-admin@$DOMAIN}" \
    --agree-tos \
    --no-eff-email \
    $MODE_ARG \
    --non-interactive

if [ $? -ne 0 ]; then
    print_error "Failed to obtain SSL certificate"
fi

print_success "SSL certificate obtained!"

# Backup nginx config
print_step "Backing up nginx config..."
cp "$INSTALL_DIR/nginx/conf.d/onestack.conf" "$INSTALL_DIR/nginx/conf.d/onestack.conf.backup"

# Create HTTPS config
print_step "Creating HTTPS configuration..."

cat > "$INSTALL_DIR/nginx/conf.d/https.conf" << HTTPSCONF
# Force HTTPS redirect
server {
    listen 80;
    server_name $DOMAIN $( echo "$SUBDOMAINS" | sed "s/ / $DOMAIN /g; s/^/$DOMAIN /; s/\$/$DOMAIN/" | sed "s/ \+/.$DOMAIN /g" );
    
    location /.well-known/acme-challenge/ {
        root $WEBROOT;
        allow all;
    }
    
    location / {
        return 301 https://\$host\$request_uri;
    }
}

# Main domain HTTPS
server {
    listen 443 ssl http2;
    server_name $DOMAIN www.$DOMAIN;
    
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/$DOMAIN/chain.pem;
    
    # SSL settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256';
    ssl_prefer_server_ciphers off;
    
    # HSTS
    add_header Strict-Transport-Security "max-age=63072000" always;
    
    # OCSP Stapling
    ssl_stapling on;
    ssl_stapling_verify on;
    
    # Session
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;
    
    root $WEBROOT;
    index index.html;
    
    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
HTTPSCONF

# Add HTTPS for subdomains if they exist
for sub in $SUBDOMAINS; do
    # Skip www as it's already in main config
    [ "$sub" = "www" ] && continue
    
    # Determine backend
    case $sub in
        storage)
            BACKEND="minio:9001"
            ;;
        s3)
            BACKEND="minio:9000"
            ;;
        api)
            BACKEND="nodejs-api-v1:4000"
            ;;
        monitor)
            BACKEND="grafana:3000"
            ;;
        db)
            BACKEND="adminer:8080"
            ;;
        chat)
            BACKEND="chatwoot:3000"
            ;;
        flow)
            BACKEND="n8n:5678"
            ;;
        ai)
            BACKEND="python-rag:8000"
            ;;
        *)
            continue
            ;;
    esac
    
    cat >> "$INSTALL_DIR/nginx/conf.d/https.conf" << SUBHTTPS

# $sub.$DOMAIN HTTPS
server {
    listen 443 ssl http2;
    server_name $sub.$DOMAIN;
    
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/$DOMAIN/chain.pem;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    
    location / {
        proxy_pass http://$BACKEND;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
SUBHTTPS

done

# Disable old HTTP-only config
mv "$INSTALL_DIR/nginx/conf.d/onestack.conf" "$INSTALL_DIR/nginx/conf.d/onestack.conf.disabled" 2>/dev/null || true

# Test nginx config
print_step "Testing nginx configuration..."
docker compose -f "$INSTALL_DIR/docker-compose.yml" exec nginx nginx -t

if [ $? -ne 0 ]; then
    print_error "Nginx configuration test failed"
    # Restore backup
    mv "$INSTALL_DIR/nginx/conf.d/onestack.conf.disabled" "$INSTALL_DIR/nginx/conf.d/onestack.conf"
    rm -f "$INSTALL_DIR/nginx/conf.d/https.conf"
    exit 1
fi

# Reload nginx
print_step "Reloading nginx..."
docker compose -f "$INSTALL_DIR/docker-compose.yml" exec nginx nginx -s reload

# Setup auto-renewal
print_step "Setting up auto-renewal..."

RENEWAL_SCRIPT="$INSTALL_DIR/scripts/renew-ssl.sh"
cat > "$RENEWAL_SCRIPT" << 'RENEWSCRIPT'
#!/bin/bash
certbot renew --quiet --webroot -w /opt/onestack/frontends/main
docker compose -f /opt/onestack/docker-compose.yml exec nginx nginx -s reload
RENEWSCRIPT

chmod +x "$RENEWAL_SCRIPT"

# Add to crontab
CRON_CMD="0 0 * * * $RENEWAL_SCRIPT >> $INSTALL_DIR/logs/ssl-renewal.log 2>&1"
(crontab -l 2>/dev/null | grep -v "renew-ssl"; echo "$CRON_CMD") | crontab -

print_success "SSL/HTTPS Setup Complete!"
echo ""
print_header "✅ Your site is now secured with HTTPS!"
echo ""
echo "Access URLs (HTTPS):"
echo "  https://$DOMAIN"
for sub in $SUBDOMAINS; do
    [ "$sub" != "www" ] && echo "  https://$sub.$DOMAIN"
done
echo ""
print_info "Certificate will auto-renew daily"
print_info "Manual renewal: certbot renew"
echo ""

if [ "$ssl_mode" = "1" ]; then
    print_warning "STAGING MODE: These are TEST certificates"
    echo ""
    echo "To get real certificates, run:"
    echo "  sudo bash $0"
    echo "  (and choose Production mode)"
fi
