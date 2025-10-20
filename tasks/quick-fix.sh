#!/bin/bash
# ═══════════════════════════════════════════════════
# Task: Quick Fix Common Issues
# Description: Auto-fix issues found in service tests
# ═══════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ═══════════════════════════════════════════════════
# Diagnostic Functions
# ═══════════════════════════════════════════════════

check_nginx_config() {
    print_step "Diagnosing Nginx configuration..."
    
    cd /opt/onestack
    
    # Test config
    local test_output=$(docker compose exec -T nginx nginx -t 2>&1)
    
    if echo "$test_output" | grep -q "successful"; then
        print_success "Nginx configuration is valid"
        return 0
    else
        print_error "Nginx configuration has errors"
        echo ""
        echo "Error details:"
        echo "$test_output" | grep -i "error\|fail" | sed 's/^/  /'
        echo ""
        return 1
    fi
}

check_ssl_certificates() {
    print_step "Checking SSL certificates..."
    
    local DOMAIN=$(grep "^DOMAIN=" /opt/onestack/.env 2>/dev/null | cut -d= -f2)
    
    if [ -z "$DOMAIN" ]; then
        print_warning "No domain configured in .env"
        return 1
    fi
    
    if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
        print_success "SSL certificates found for: $DOMAIN"
        
        # Check if certificate files exist
        local missing_files=""
        for file in cert.pem chain.pem fullchain.pem privkey.pem; do
            if [ ! -f "/etc/letsencrypt/live/$DOMAIN/$file" ]; then
                missing_files="$missing_files $file"
            fi
        done
        
        if [ -n "$missing_files" ]; then
            print_error "Missing certificate files:$missing_files"
            return 1
        fi
        
        return 0
    else
        print_warning "SSL certificates not found for: $DOMAIN"
        return 1
    fi
}

# ═══════════════════════════════════════════════════
# Fix Functions
# ═══════════════════════════════════════════════════

fix_nginx() {
    print_header "Fixing Nginx"
    
    cd /opt/onestack
    
    # Check if SSL certificates exist
    check_ssl_certificates
    local ssl_status=$?
    
    if [ $ssl_status -ne 0 ]; then
        print_warning "SSL not configured, switching to HTTP-only config"
        
        # Backup current config
        local NGINX_CONF="nginx/conf.d/onestack.conf"
        if [ -f "$NGINX_CONF" ]; then
            cp "$NGINX_CONF" "${NGINX_CONF}.backup-$(date +%Y%m%d_%H%M%S)"
            print_info "Backed up current config"
        fi
        
        # Get domain
        local DOMAIN=$(grep "^DOMAIN=" .env 2>/dev/null | cut -d= -f2)
        if [ -z "$DOMAIN" ]; then
            DOMAIN="localhost"
        fi
        
        # Create HTTP-only config (no SSL references)
        print_step "Creating HTTP-only configuration..."
        
        cat > "$NGINX_CONF" << EOF
# OneStack - Nginx HTTP Configuration (No SSL)

# Main Site
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;
    
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

# MinIO Console
server {
    listen 80;
    server_name storage.$DOMAIN;
    
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

# MinIO S3 API
server {
    listen 80;
    server_name s3.$DOMAIN;
    
    client_max_body_size 100M;
    
    location / {
        proxy_pass http://minio:9000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

# Parse Server & Dashboard
server {
    listen 80;
    server_name api.$DOMAIN;
    
    # Parse Server
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

# Grafana
server {
    listen 80;
    server_name monitor.$DOMAIN;
    
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

# Prometheus
server {
    listen 80;
    server_name prometheus.$DOMAIN;
    
    location / {
        proxy_pass http://prometheus:9090;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

# Adminer
server {
    listen 80;
    server_name db.$DOMAIN;
    
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
        
        print_success "HTTP-only configuration created"
    fi
    
    # Test configuration
    check_nginx_config
    
    if [ $? -eq 0 ]; then
        print_step "Reloading Nginx..."
        docker compose restart nginx
        sleep 3
        print_success "Nginx fixed and reloaded"
        return 0
    else
        print_error "Configuration still invalid. Manual intervention required."
        return 1
    fi
}

fix_parse_server() {
    print_header "Fixing Parse Server"
    
    cd /opt/onestack
    
    print_step "Checking Parse Server logs..."
    local logs=$(docker compose logs parse-server --tail 20 2>&1)
    
    # Common issues
    if echo "$logs" | grep -qi "database"; then
        print_warning "Database connection issue detected"
        print_info "Checking database..."
        
        # Test PostgreSQL connection
        if docker compose exec -T postgres pg_isready -U postgres &> /dev/null; then
            print_success "PostgreSQL is ready"
        else
            print_error "PostgreSQL not ready"
            print_step "Restarting PostgreSQL..."
            docker compose restart postgres
            sleep 5
        fi
    fi
    
    print_step "Restarting Parse Server..."
    docker compose restart parse-server
    
    sleep 5
    
    # Wait for health check
    print_step "Waiting for Parse Server to be healthy..."
    local max_wait=30
    local waited=0
    
    while [ $waited -lt $max_wait ]; do
        local health=$(curl -sf http://localhost:1337/parse/health 2>/dev/null)
        if [ $? -eq 0 ]; then
            print_success "Parse Server is healthy"
            echo "$health" | jq . 2>/dev/null || echo "$health"
            return 0
        fi
        
        sleep 2
        ((waited+=2))
        echo -n "."
    done
    
    echo ""
    print_warning "Parse Server may need more time to start"
    return 1
}

fix_parse_dashboard() {
    print_header "Fixing Parse Dashboard"
    
    cd /opt/onestack
    
    print_step "Checking Parse Dashboard logs..."
    local logs=$(docker compose logs parse-dashboard --tail 30 2>&1)
    
    echo "Recent logs:"
    echo "$logs" | tail -10 | sed 's/^/  /'
    echo ""
    
    # Common issues
    if echo "$logs" | grep -qi "ECONNREFUSED\|connection refused"; then
        print_warning "Connection refused - Parse Server may not be ready"
        print_info "Ensuring Parse Server is running..."
        docker compose restart parse-server
        sleep 5
    fi
    
    if echo "$logs" | grep -qi "PARSE_DASHBOARD_APP_NAME"; then
        print_warning "Configuration issue detected"
    fi
    
    print_step "Stopping Parse Dashboard..."
    docker compose stop parse-dashboard
    sleep 2
    
    print_step "Starting Parse Dashboard..."
    docker compose start parse-dashboard
    
    sleep 5
    
    # Check if running
    local status=$(docker compose ps parse-dashboard --format '{{.Status}}' 2>/dev/null)
    
    if [[ "$status" == *"Up"* ]]; then
        print_success "Parse Dashboard is running"
        
        # Test HTTP accessibility
        local http_code=$(curl -sf -o /dev/null -w "%{http_code}" http://localhost:4040 2>/dev/null)
        if [ "$http_code" = "200" ] || [ "$http_code" = "302" ]; then
            print_success "Parse Dashboard is accessible (HTTP $http_code)"
            return 0
        else
            print_warning "Parse Dashboard running but not accessible (HTTP $http_code)"
            return 1
        fi
    else
        print_error "Parse Dashboard failed to start"
        print_info "Status: $status"
        return 1
    fi
}

# ═══════════════════════════════════════════════════
# Main Menu
# ═══════════════════════════════════════════════════

show_menu() {
    clear
    print_header "Quick Fix - Auto Repair Common Issues"
    
    echo ""
    echo "Detected Issues (from test results):"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  ❌ Nginx: Configuration invalid"
    echo "  ❌ Parse Server: Unhealthy"
    echo "  ❌ Parse Dashboard: Not running"
    echo ""
    echo "Fix Options:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  1) Fix Nginx configuration"
    echo "  2) Fix Parse Server"
    echo "  3) Fix Parse Dashboard"
    echo "  4) Fix all issues (recommended) 🔧"
    echo "  5) View detailed logs"
    echo "  0) Cancel"
    echo ""
    
    read -p "Select option [0-5]: " choice
    
    case $choice in
        1)
            echo ""
            fix_nginx
            ;;
            
        2)
            echo ""
            fix_parse_server
            ;;
            
        3)
            echo ""
            fix_parse_dashboard
            ;;
            
        4)
            echo ""
            print_header "Fixing All Issues"
            
            local fixed=0
            local failed=0
            
            # Fix in order of dependency
            echo ""
            if fix_nginx; then
                ((fixed++))
            else
                ((failed++))
            fi
            
            echo ""
            if fix_parse_server; then
                ((fixed++))
            else
                ((failed++))
            fi
            
            echo ""
            if fix_parse_dashboard; then
                ((fixed++))
            else
                ((failed++))
            fi
            
            echo ""
            print_header "Fix Summary"
            echo ""
            echo "  Fixed: $fixed"
            echo "  Failed: $failed"
            echo ""
            
            if [ $failed -eq 0 ]; then
                print_success "All issues fixed! ✅"
            else
                print_warning "Some issues remain. Check logs for details."
            fi
            ;;
            
        5)
            echo ""
            print_header "Service Logs"
            
            echo ""
            echo "Nginx logs:"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            docker compose logs nginx --tail 20 | sed 's/^/  /'
            
            echo ""
            echo "Parse Server logs:"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            docker compose logs parse-server --tail 20 | sed 's/^/  /'
            
            echo ""
            echo "Parse Dashboard logs:"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            docker compose logs parse-dashboard --tail 20 | sed 's/^/  /'
            
            echo ""
            read -p "Press Enter to continue..."
            show_menu
            ;;
            
        0)
            print_info "Cancelled"
            exit 0
            ;;
            
        *)
            print_error "Invalid choice"
            sleep 2
            show_menu
            ;;
    esac
}

# ═══════════════════════════════════════════════════
# Post-Fix Verification
# ═══════════════════════════════════════════════════

verify_fixes() {
    print_header "Verifying Fixes"
    
    cd /opt/onestack
    
    echo ""
    print_step "Waiting for services to stabilize..."
    sleep 10
    
    echo ""
    print_info "Service Status:"
    docker compose ps --format "  {{.Name}}: {{.Status}}" | grep -E "(nginx|parse-server|parse-dashboard)"
    
    echo ""
    print_info "Quick Health Checks:"
    
    # Nginx
    if docker compose exec -T nginx nginx -t &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} Nginx configuration valid"
    else
        echo -e "  ${RED}✗${NC} Nginx configuration still invalid"
    fi
    
    # Parse Server
    if curl -sf http://localhost:1337/parse/health &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} Parse Server healthy"
    else
        echo -e "  ${YELLOW}⚠${NC} Parse Server not responding"
    fi
    
    # Parse Dashboard
    local pd_status=$(docker compose ps parse-dashboard --format '{{.Status}}' 2>/dev/null)
    if [[ "$pd_status" == *"Up"* ]]; then
        echo -e "  ${GREEN}✓${NC} Parse Dashboard running"
    else
        echo -e "  ${RED}✗${NC} Parse Dashboard not running"
    fi
    
    echo ""
}

# ═══════════════════════════════════════════════════
# Main Entry Point
# ═══════════════════════════════════════════════════

main() {
    # Check if OneStack is installed
    if [ ! -d "/opt/onestack" ]; then
        print_error "OneStack not installed"
        exit 1
    fi
    
    # Show menu
    show_menu
    
    # Verify fixes after actions
    echo ""
    if confirm "Verify fixes now?"; then
        verify_fixes
    fi
    
    echo ""
    print_info "Next steps:"
    echo "  1. Run full test: ./manage.sh → 10) Test all services"
    echo "  2. View logs: ./manage.sh → 5) View service logs"
    echo "  3. If SSL needed: ./manage.sh → 1) Setup SSL"
    echo ""
}

main "$@"