#!/bin/bash
# fix-ssl-and-parse.sh - แก้ปัญหา SSL และ Parse Dashboard

DOMAIN="sixamdev.com"
EMAIL="your-email@example.com"  # เปลี่ยนเป็น email ของคุณ

echo "═══════════════════════════════════════════════════"
echo "  Fix SSL Certificate & Parse Dashboard"
echo "═══════════════════════════════════════════════════"
echo ""

# ═══════════════════════════════════════════════════
# Step 1: Switch back to HTTP first
# ═══════════════════════════════════════════════════
echo "▶ Step 1: Switching to HTTP configuration..."

cd /opt/onestack

cat > nginx/conf.d/onestack.conf << 'EOF'
# ═══════════════════════════════════════════════════
# OneStack - HTTP Configuration (for SSL setup)
# ═══════════════════════════════════════════════════

# Main Site
server {
    listen 80;
    server_name sixamdev.com www.sixamdev.com;
    
    root /var/www/main;
    index index.html;
    
    # For Let's Encrypt
    location /.well-known/acme-challenge/ {
        root /var/www/main;
        allow all;
    }
    
    location / {
        try_files $uri $uri/ /index.html;
    }
}

# MinIO Console
server {
    listen 80;
    server_name storage.sixamdev.com;
    
    client_max_body_size 100M;
    
    location / {
        proxy_pass http://minio:9001;
        proxy_set_header Host $host;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

# MinIO S3 API
server {
    listen 80;
    server_name s3.sixamdev.com;
    
    client_max_body_size 100M;
    
    location / {
        proxy_pass http://minio:9000;
        proxy_set_header Host $host;
    }
}

# Parse Server + Dashboard
server {
    listen 80;
    server_name api.sixamdev.com;
    
    # Parse Server API
    location /parse {
        proxy_pass http://parse-server:1337/parse;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    # Parse Dashboard
    location / {
        proxy_pass http://parse-dashboard:4040;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# Grafana
server {
    listen 80;
    server_name monitor.sixamdev.com;
    
    location / {
        proxy_pass http://grafana:3000;
        proxy_set_header Host $host;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

# Prometheus
server {
    listen 80;
    server_name prometheus.sixamdev.com;
    
    location / {
        proxy_pass http://prometheus:9090;
        proxy_set_header Host $host;
    }
}

# Adminer
server {
    listen 80;
    server_name db.sixamdev.com;
    
    location / {
        proxy_pass http://adminer:8080;
        proxy_set_header Host $host;
    }
}
EOF

echo "✓ HTTP config created"

# ═══════════════════════════════════════════════════
# Step 2: Fix Parse Dashboard environment
# ═══════════════════════════════════════════════════
echo ""
echo "▶ Step 2: Fixing Parse Dashboard configuration..."

# Update .env file
cat >> .env << 'EOF'

# Parse Dashboard Configuration
PARSE_DASHBOARD_SERVER_URL=http://parse-server:1337/parse
PARSE_DASHBOARD_APP_ID=onestack_app_id
PARSE_DASHBOARD_MASTER_KEY=onestack_master_key_12345
PARSE_DASHBOARD_APP_NAME=OneStack
PARSE_DASHBOARD_USER=admin
PARSE_DASHBOARD_PASS=onestack123
EOF

echo "✓ Environment variables updated"

# ═══════════════════════════════════════════════════
# Step 3: Restart services
# ═══════════════════════════════════════════════════
echo ""
echo "▶ Step 3: Restarting services..."

docker compose down
docker compose up -d

echo "⏳ Waiting 20 seconds for services to start..."
sleep 20

# ═══════════════════════════════════════════════════
# Step 4: Check service status
# ═══════════════════════════════════════════════════
echo ""
echo "▶ Step 4: Checking service status..."
echo ""

docker compose ps

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Parse Dashboard Status:"
docker compose logs --tail=20 parse-dashboard
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ═══════════════════════════════════════════════════
# Step 5: Request SSL Certificate
# ═══════════════════════════════════════════════════
echo ""
echo "▶ Step 5: Requesting SSL Certificate..."
echo ""

read -p "Enter your email for Let's Encrypt: " EMAIL

# Install certbot if not exists
if ! command -v certbot &> /dev/null; then
    echo "Installing Certbot..."
    apt-get update
    apt-get install -y certbot python3-certbot-nginx
fi

# Create webroot directory
mkdir -p /opt/onestack/frontends/main/.well-known/acme-challenge

# Request certificate
certbot certonly --webroot \
    -w /opt/onestack/frontends/main \
    -d ${DOMAIN} \
    -d www.${DOMAIN} \
    -d storage.${DOMAIN} \
    -d s3.${DOMAIN} \
    -d api.${DOMAIN} \
    -d monitor.${DOMAIN} \
    -d prometheus.${DOMAIN} \
    -d db.${DOMAIN} \
    --email ${EMAIL} \
    --agree-tos \
    --non-interactive

if [ $? -eq 0 ]; then
    echo "✓ SSL Certificate obtained successfully!"
    
    # ═══════════════════════════════════════════════════
    # Step 6: Enable HTTPS
    # ═══════════════════════════════════════════════════
    echo ""
    echo "▶ Step 6: Enabling HTTPS..."
    
    ./enable-https-complete.sh
    
else
    echo "✗ Failed to obtain SSL certificate"
    echo ""
    echo "Please check:"
    echo "  1. Domain DNS is pointing to this server"
    echo "  2. Port 80 is accessible from internet"
    echo "  3. No firewall blocking port 80"
    echo ""
    echo "You can test manually with:"
    echo "  curl -I http://${DOMAIN}"
fi