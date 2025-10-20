#!/bin/bash
# ═══════════════════════════════════════════════════
# OneStack - Fix Parse Dashboard Task
# ═══════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

# ═══════════════════════════════════════════════════
# Main Fix
# ═══════════════════════════════════════════════════

main() {
    print_header "Fix Parse Dashboard"
    
    print_info "This will attempt to fix the Parse Dashboard 502 error"
    print_info "Known issue: Config file mount problem"
    echo ""
    
    read -p "Continue? (Y/n): " confirm
    [ "$confirm" = "n" ] && exit 0
    
    echo ""
    
    # Check current status
    print_step "Checking current status..."
    
    cd /opt/onestack
    docker compose ps parse-dashboard
    
    echo ""
    
    # Check config file
    print_step "Checking config file..."
    
    if [ -f "/opt/onestack/parse-dashboard/config.json" ]; then
        print_success "Config file exists"
        echo ""
        cat /opt/onestack/parse-dashboard/config.json
    else
        print_warning "Config file not found, will create..."
        
        mkdir -p /opt/onestack/parse-dashboard
        
        # Get credentials from .env
        local APP_ID=$(grep "^PARSE_APP_ID=" /opt/onestack/.env | cut -d= -f2)
        local MASTER_KEY=$(grep "^PARSE_MASTER_KEY=" /opt/onestack/.env | cut -d= -f2)
        local DOMAIN=$(grep "^DOMAIN=" /opt/onestack/.env | cut -d= -f2)
        
        # Determine protocol
        if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
            local PROTOCOL="https"
        else
            local PROTOCOL="http"
        fi
        
        # Create config
        cat > /opt/onestack/parse-dashboard/config.json << EOF
{
  "apps": [
    {
      "serverURL": "$PROTOCOL://api.$DOMAIN/parse",
      "appId": "$APP_ID",
      "masterKey": "$MASTER_KEY",
      "appName": "OneStack"
    }
  ],
  "users": [
    {
      "user": "admin",
      "pass": "$MASTER_KEY"
    }
  ],
  "iconsFolder": "icons"
}
EOF
        
        print_success "Config file created"
    fi
    
    echo ""
    
    # Fix docker-compose volume mount
    print_step "Checking docker-compose.yml..."
    
    if grep -q "parse-dashboard/config.json" /opt/onestack/docker-compose.yml; then
        print_success "Volume mount is configured"
    else
        print_warning "Volume mount not found in docker-compose.yml"
        print_info "Please ensure parse-dashboard service has:"
        print_info "  volumes:"
        print_info "    - ./parse-dashboard/config.json:/src/Parse-Dashboard/parse-dashboard-config.json"
        echo ""
        read -p "Would you like to edit docker-compose.yml now? (y/N): " edit
        
        if [ "$edit" = "y" ]; then
            nano /opt/onestack/docker-compose.yml
        fi
    fi
    
    echo ""
    
    # Restart Parse Dashboard
    print_step "Restarting Parse Dashboard..."
    
    docker compose stop parse-dashboard
    docker compose rm -f parse-dashboard
    docker compose up -d parse-dashboard
    
    # Wait and check
    print_info "Waiting for service to start..."
    sleep 5
    
    echo ""
    docker compose ps parse-dashboard
    
    echo ""
    
    # Test access
    print_step "Testing access..."
    
    local DOMAIN=$(grep "^DOMAIN=" /opt/onestack/.env | cut -d= -f2)
    
    if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
        local URL="https://api.$DOMAIN"
    else
        local URL="http://api.$DOMAIN"
    fi
    
    echo ""
    print_info "Testing: $URL"
    
    local STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$URL" 2>&1)
    
    if [[ "$STATUS" =~ ^[23] ]]; then
        echo ""
        print_success "Parse Dashboard is now accessible!"
        print_info "URL: $URL"
        print_info "Username: admin"
        print_info "Password: (check .credentials file)"
    else
        echo ""
        print_error "Still getting $STATUS error"
        print_info "Check logs:"
        print_info "  docker compose logs parse-dashboard"
    fi
}

# Run
check_root
main