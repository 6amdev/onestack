#!/bin/bash
# ═══════════════════════════════════════════════════
# OneStack - Complete Nginx + SSL Fix
# แก้ปัญหา: upstream, SSL paths, resolver, error handling
# ═══════════════════════════════════════════════════

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}\n"
}

print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_info() { echo -e "${CYAN}ℹ${NC} $1"; }
print_step() { echo -e "${CYAN}▶${NC} $1"; }

# ═══════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════

INSTALL_DIR="/opt/onestack"
CONFIG_FILE="$INSTALL_DIR/.env"

# Load config
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    DOMAIN="${DOMAIN:-sixamdev.com}"
else
    print_error "Config file not found: $CONFIG_FILE"
    DOMAIN="sixamdev.com"
    print_warning "Using default domain: $DOMAIN"
fi

print_header "OneStack Nginx + SSL Fix"
echo "Domain: $DOMAIN"
echo "Install Directory: $INSTALL_DIR"
echo ""

# ═══════════════════════════════════════════════════
# Check Root
# ═══════════════════════════════════════════════════

if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root (use sudo)"
    exit 1
fi

# ═══════════════════════════════════════════════════
# Backup
# ═══════════════════════════════════════════════════

print_step "Creating backup..."
BACKUP_DIR="$INSTALL_DIR/backups/nginx_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

if [ -d "$INSTALL_DIR/nginx" ]; then
    cp -r "$INSTALL_DIR/nginx" "$BACKUP_DIR/"
    print_success "Nginx config backed up to: $BACKUP_DIR"
fi

if [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
    cp "$INSTALL_DIR/docker-compose.yml" "$BACKUP_DIR/"
    print_success "docker-compose.yml backed up"
fi

# ═══════════════════════════════════════════════════
# Part 1: Upstream Configuration
# ═══════════════════════════════════════════════════

print_header "Part 1: Upstream Configuration"

print_step "Creating upstream configuration..."
cat > "$INSTALL_DIR/nginx/conf.d/00-upstream.conf" <<'EOF'
# ═══════════════════════════════════════════════════
# Upstream Backend Configuration
# Prevents Nginx from failing when backends are not ready
# ═══════════════════════════════════════════════════

upstream parse_backend {
    server parse-server:1337 max_fails=3 fail_timeout=30s;
    keepalive 32;
}

upstream grafana_backend {
    server grafana:3000 max_fails=3 fail_timeout=30s;
    keepalive 32;
}

upstream prometheus_backend {
    server prometheus:9090 max_fails=3 fail_timeout=30s;
    keepalive 32;
}

upstream adminer_backend {
    server adminer:8080 max_fails=3 fail_timeout=30s;
    keepalive 32;
}

upstream minio_api {
    server minio:9000 max_fails=3 fail_timeout=30s;
    keepalive 32;
}

upstream minio_console {
    server minio:9001 max_fails=3 fail_timeout=30s;
    keepalive 32;
}

# Add more upstreams as needed
# upstream n8n_backend {
#     server n8n:5678 max_fails=3 fail_timeout=30s;
#     keepalive 32;
# }

# upstream chatwoot_backend {
#     server chatwoot:3000 max_fails=3 fail_timeout=30s;
#     keepalive 32;
# }
EOF

print_success "Upstream configuration created"

# ═══════════════════════════════════════════════════
# Part 2: DNS Resolver
# ═══════════════════════════════════════════════════

print_header "Part 2: DNS Resolver"

print_step "Creating resolver configuration..."
cat > "$INSTALL_DIR/nginx/conf.d/01-resolver.conf" <<'EOF'
# ═══════════════════════════════════════════════════
# DNS Resolver Configuration
# Fixes "no resolver defined" error
# ═══════════════════════════════════════════════════

# Use Docker's internal DNS (works inside containers)
resolver 127.0.0.11 valid=30s ipv6=off;
resolver_timeout 5s;

# Alternative: Use public DNS (if above doesn't work)
# resolver 8.8.8.8 8.8.4.4 valid=300s;
# resolver 1.1.1.1 1.0.0.1 valid=300s;
EOF

print_success "Resolver configuration created"

# ═══════════════════════════════════════════════════
# Part 3: SSL Directory Structure
# ═══════════════════════════════════════════════════

print_header "Part 3: SSL Directory Structure"

print_step "Creating SSL directories..."
mkdir -p "$INSTALL_DIR/nginx/ssl/live/$DOMAIN"
mkdir -p "$INSTALL_DIR/nginx/ssl/certbot/conf"
mkdir -p "$INSTALL_DIR/nginx/ssl/certbot/www"
print_success "SSL directories created"

# Symlink certificates if they exist
print_step "Checking for existing SSL certificates..."
if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
    print_info "Found certificates in /etc/letsencrypt"
    
    # Remove old symlinks if exist
    rm -f "$INSTALL_DIR/nginx/ssl/live/$DOMAIN/fullchain.pem" 2>/dev/null || true
    rm -f "$INSTALL_DIR/nginx/ssl/live/$DOMAIN/privkey.pem" 2>/dev/null || true
    
    # Create new symlinks
    ln -sf "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" \
           "$INSTALL_DIR/nginx/ssl/live/$DOMAIN/fullchain.pem"
    ln -sf "/etc/letsencrypt/live/$DOMAIN/privkey.pem" \
           "$INSTALL_DIR/nginx/ssl/live/$DOMAIN/privkey.pem"
    
    print_success "SSL certificates linked"
    
    # Verify
    if [ -f "$INSTALL_DIR/nginx/ssl/live/$DOMAIN/fullchain.pem" ]; then
        print_success "Certificate verification: OK"
    else
        print_warning "Certificate symlink may not work (check permissions)"
    fi
else
    print_warning "No SSL certificates found in /etc/letsencrypt/live/$DOMAIN"
    print_info "You'll need to request certificates later (use manage.sh)"
fi

# ═══════════════════════════════════════════════════
# Part 4: Update Virtual Host Configurations
# ═══════════════════════════════════════════════════

print_header "Part 4: Update Virtual Host Configurations"

print_step "Updating SSL certificate paths in all configs..."

# Update all .conf files in conf.d
for conf_file in "$INSTALL_DIR/nginx/conf.d"/*.conf; do
    if [ -f "$conf_file" ]; then
        filename=$(basename "$conf_file")
        
        # Skip our new config files
        if [[ "$filename" == "00-upstream.conf" || "$filename" == "01-resolver.conf" ]]; then
            continue
        fi
        
        print_info "Processing: $filename"
        
        # Update SSL certificate paths
        if grep -q "ssl_certificate" "$conf_file"; then
            # Backup
            cp "$conf_file" "$conf_file.bak"
            
            # Replace paths (handle various formats)
            sed -i "s|ssl_certificate /etc/letsencrypt/live/|ssl_certificate /etc/nginx/ssl/live/|g" "$conf_file"
            sed -i "s|ssl_certificate_key /etc/letsencrypt/live/|ssl_certificate_key /etc/nginx/ssl/live/|g" "$conf_file"
            
            print_success "  ✓ Updated SSL paths"
        fi
        
        # Add error handling comment (manual step needed)
        if ! grep -q "proxy_next_upstream" "$conf_file"; then
            print_warning "  ⚠  Consider adding proxy_next_upstream (see documentation)"
        fi
    fi
done

print_success "All virtual host configs updated"

# ═══════════════════════════════════════════════════
# Part 5: Create/Update Main Nginx Config
# ═══════════════════════════════════════════════════

print_header "Part 5: Main Nginx Configuration"

print_step "Checking nginx.conf..."

if [ ! -f "$INSTALL_DIR/nginx/nginx.conf" ]; then
    print_warning "nginx.conf not found, creating basic config..."
    cat > "$INSTALL_DIR/nginx/nginx.conf" <<'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
    use epoll;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 100M;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript 
               application/json application/javascript application/xml+rss 
               application/rss+xml font/truetype font/opentype 
               application/vnd.ms-fontobject image/svg+xml;

    # Include config files
    include /etc/nginx/conf.d/*.conf;
}
EOF
    print_success "Basic nginx.conf created"
else
    print_success "nginx.conf already exists"
fi

# ═══════════════════════════════════════════════════
# Part 6: Update Docker Compose (if exists)
# ═══════════════════════════════════════════════════

print_header "Part 6: Docker Compose Configuration"

COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"

if [ -f "$COMPOSE_FILE" ]; then
    print_step "Checking docker-compose.yml..."
    
    # Check if nginx service exists and has health check
    if grep -q "nginx:" "$COMPOSE_FILE"; then
        if ! grep -A 20 "nginx:" "$COMPOSE_FILE" | grep -q "healthcheck:"; then
            print_warning "Nginx service missing health check"
            print_info "Consider adding health check manually:"
            echo ""
            echo "  healthcheck:"
            echo "    test: [\"CMD\", \"nginx\", \"-t\"]"
            echo "    interval: 30s"
            echo "    timeout: 10s"
            echo "    retries: 3"
            echo "    start_period: 40s"
            echo ""
        else
            print_success "Nginx health check already configured"
        fi
        
        # Check volume mounts
        if ! grep -A 10 "nginx:" "$COMPOSE_FILE" | grep -q "/etc/nginx/ssl"; then
            print_warning "Nginx missing SSL volume mount"
            print_info "Ensure these volumes are mounted:"
            echo "  - ./nginx/ssl:/etc/nginx/ssl:ro"
            echo "  - /etc/letsencrypt:/etc/letsencrypt:ro"
            echo ""
        else
            print_success "Nginx volume mounts look good"
        fi
    fi
else
    print_warning "docker-compose.yml not found"
fi

# ═══════════════════════════════════════════════════
# Part 7: Create Helper Scripts
# ═══════════════════════════════════════════════════

print_header "Part 7: Helper Scripts"

# 7.1 Create start script with proper order
print_step "Creating startup script..."
cat > "$INSTALL_DIR/start-services.sh" <<'STARTSCRIPT'
#!/bin/bash
# Start OneStack services in proper order

set -e

echo "🚀 Starting OneStack services..."

cd /opt/onestack

# 1. Start databases
echo "1/4 Starting databases..."
docker compose up -d postgres mongodb redis
sleep 10

# 2. Start storage and backends
echo "2/4 Starting backends..."
docker compose up -d minio parse-server
sleep 10

# 3. Start monitoring
echo "3/4 Starting monitoring..."
docker compose up -d grafana prometheus adminer
sleep 5

# 4. Start Nginx
echo "4/4 Starting Nginx..."
docker compose up -d nginx

echo ""
echo "✓ All services started!"
echo ""
echo "Check status: docker compose ps"
echo "View logs: docker compose logs -f"
STARTSCRIPT

chmod +x "$INSTALL_DIR/start-services.sh"
print_success "Created start-services.sh"

# 7.2 Create test script
print_step "Creating test script..."
cat > "$INSTALL_DIR/test-nginx.sh" <<TESTSCRIPT
#!/bin/bash
# Test Nginx configuration and connectivity

set -e

DOMAIN="${DOMAIN}"

echo "🔍 Testing Nginx configuration..."
echo ""

# Test 1: Nginx config syntax
echo "1. Testing Nginx config syntax..."
docker compose exec nginx nginx -t
echo ""

# Test 2: Check if Nginx is running
echo "2. Checking Nginx status..."
docker compose ps nginx
echo ""

# Test 3: Test backend connectivity (from inside nginx container)
echo "3. Testing backend connectivity..."
echo "   Parse Server:"
docker compose exec nginx wget -q -O- http://parse-server:1337/parse/health 2>&1 | head -n 1 || echo "   ✗ Not reachable"
echo "   Grafana:"
docker compose exec nginx wget -q -O- http://grafana:3000/api/health 2>&1 | head -n 1 || echo "   ✗ Not reachable"
echo "   MinIO:"
docker compose exec nginx wget -q -O- http://minio:9000/minio/health/live 2>&1 | head -n 1 || echo "   ✗ Not reachable"
echo ""

# Test 4: Check SSL certificates
echo "4. Checking SSL certificates..."
if [ -f "/etc/letsencrypt/live/\${DOMAIN}/fullchain.pem" ]; then
    echo "   Certificate found:"
    openssl x509 -in /etc/letsencrypt/live/\${DOMAIN}/fullchain.pem -noout -subject -dates
else
    echo "   ✗ No SSL certificate found"
fi
echo ""

# Test 5: Test HTTP endpoints (external)
echo "5. Testing HTTP endpoints..."
echo "   Main site:"
curl -sI http://\${DOMAIN} | head -n 1 || echo "   ✗ Failed"
echo "   API:"
curl -sI http://api.\${DOMAIN}/parse/health | head -n 1 || echo "   ✗ Failed"
echo ""

echo "✓ Test complete!"
TESTSCRIPT

chmod +x "$INSTALL_DIR/test-nginx.sh"
print_success "Created test-nginx.sh"

# 7.3 Create troubleshoot script
print_step "Creating troubleshoot script..."
cat > "$INSTALL_DIR/troubleshoot-nginx.sh" <<'TROUBLESCRIPT'
#!/bin/bash
# Troubleshoot Nginx issues

echo "🔍 OneStack Nginx Troubleshooting"
echo "================================"
echo ""

cd /opt/onestack

# 1. Service status
echo "1. Service Status:"
docker compose ps
echo ""

# 2. Nginx logs (last 20 lines)
echo "2. Recent Nginx Logs:"
docker compose logs nginx --tail=20
echo ""

# 3. Nginx config test
echo "3. Nginx Configuration Test:"
docker compose exec nginx nginx -t 2>&1
echo ""

# 4. SSL certificates
echo "4. SSL Certificates:"
if [ -d "/etc/letsencrypt/live" ]; then
    ls -la /etc/letsencrypt/live/
else
    echo "   ✗ No certificates found"
fi
echo ""

# 5. Network connectivity
echo "5. Network Connectivity (from Nginx container):"
echo "   DNS Resolution:"
docker compose exec nginx nslookup parse-server 2>&1 | grep -A 2 "Name:" || echo "   ✗ Cannot resolve"
echo ""

# 6. Port check
echo "6. Port Status:"
netstat -tulpn | grep -E ':(80|443)' || echo "   ✗ Ports not listening"
echo ""

echo "================================"
echo "For more details:"
echo "  - View full logs: docker compose logs nginx"
echo "  - Check specific service: docker compose logs [service-name]"
echo "  - Enter nginx container: docker compose exec nginx sh"
TROUBLESCRIPT

chmod +x "$INSTALL_DIR/troubleshoot-nginx.sh"
print_success "Created troubleshoot-nginx.sh"

# ═══════════════════════════════════════════════════
# Summary & Next Steps
# ═══════════════════════════════════════════════════

print_header "Fix Complete!"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
print_success "All fixes applied successfully!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "📋 What was fixed:"
echo "   ✓ Upstream backend configuration (graceful failures)"
echo "   ✓ DNS resolver configuration (no more errors)"
echo "   ✓ SSL directory structure (proper paths)"
echo "   ✓ Certificate symlinks (if certificates exist)"
echo "   ✓ Virtual host configs (updated SSL paths)"
echo "   ✓ Helper scripts (start, test, troubleshoot)"
echo ""

echo "📁 Backup location:"
echo "   $BACKUP_DIR"
echo ""

echo "🚀 Next steps:"
echo ""
echo "1. Restart services (recommended order):"
echo "   cd $INSTALL_DIR"
echo "   ./start-services.sh"
echo ""
echo "2. Test configuration:"
echo "   ./test-nginx.sh"
echo ""
echo "3. If you need SSL certificates:"
echo "   sudo bash manage.sh"
echo "   → Choose option 2 (SSL Setup)"
echo ""
echo "4. Check status:"
echo "   docker compose ps"
echo "   docker compose logs -f nginx"
echo ""
echo "5. If issues persist:"
echo "   ./troubleshoot-nginx.sh"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
print_info "Files created/modified:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  • nginx/conf.d/00-upstream.conf (NEW)"
echo "  • nginx/conf.d/01-resolver.conf (NEW)"
echo "  • nginx/conf.d/*.conf (UPDATED - SSL paths)"
echo "  • nginx/ssl/ (NEW - directories & symlinks)"
echo "  • start-services.sh (NEW)"
echo "  • test-nginx.sh (NEW)"
echo "  • troubleshoot-nginx.sh (NEW)"
echo ""

print_success "Ready to restart services!"
