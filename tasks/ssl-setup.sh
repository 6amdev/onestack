#!/bin/bash
# ═══════════════════════════════════════════════════
# OneStack - SSL Setup Task (Main Domain Only)
# ═══════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Source utilities
if [ -f "$SCRIPT_DIR/lib/utils.sh" ]; then
    source "$SCRIPT_DIR/lib/utils.sh"
else
    echo "ERROR: utils.sh not found"
    exit 1
fi

# Source SSL functions
if [ -f "$SCRIPT_DIR/lib/06-ssl.sh" ]; then
    source "$SCRIPT_DIR/lib/06-ssl.sh"
else
    print_error "lib/06-ssl.sh not found"
    exit 1
fi

# ═══════════════════════════════════════════════════
# Check Prerequisites
# ═══════════════════════════════════════════════════

check_prerequisites() {
    if ! command -v yq &> /dev/null; then
        print_warning "yq not installed"
        read -p "Install yq now? (Y/n): " install
        
        if [ "$install" != "n" ]; then
            wget -q https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq
            chmod +x /usr/bin/yq
            
            if command -v yq &> /dev/null; then
                print_success "yq installed"
            else
                print_error "Failed to install yq"
                return 1
            fi
        else
            return 1
        fi
    fi
    
    return 0
}

# ═══════════════════════════════════════════════════
# Read Configuration
# ═══════════════════════════════════════════════════

read_config() {
    local config_file=$1
    
    local domain=$(yq eval '.domain.primary' "$config_file" 2>/dev/null)
    local email=$(yq eval '.domain.ssl_email' "$config_file" 2>/dev/null)
    local mode=$(yq eval '.domain.ssl_mode' "$config_file" 2>/dev/null)
    
    if [ -z "$domain" ] || [ "$domain" = "null" ]; then
        domain=$(grep "^\s*primary:" "$config_file" | sed 's/.*primary:\s*//' | tr -d '"' | tr -d "'" | head -1)
        email=$(grep "^\s*ssl_email:" "$config_file" | sed 's/.*ssl_email:\s*//' | tr -d '"' | tr -d "'" | head -1)
        mode=$(grep "^\s*ssl_mode:" "$config_file" | sed 's/.*ssl_mode:\s*//' | tr -d '"' | tr -d "'" | awk '{print $1}' | head -1)
    fi
    
    echo "$domain|$email|$mode"
}

# ═══════════════════════════════════════════════════
# Main SSL Setup
# ═══════════════════════════════════════════════════

main() {
    print_header "SSL Certificate Setup"
    
    if ! check_prerequisites; then
        print_error "Prerequisites not met"
        exit 1
    fi
    
    print_step "Looking for config.yml..."
    
    local CONFIG_FILE=""
    for path in "$SCRIPT_DIR/config.yml" "/root/onestack/config.yml" "/opt/onestack/config.yml"; do
        if [ -f "$path" ]; then
            CONFIG_FILE="$path"
            print_success "Found: $CONFIG_FILE"
            break
        fi
    done
    
    if [ -z "$CONFIG_FILE" ]; then
        print_error "Config file not found"
        exit 1
    fi
    
    local config_values=$(read_config "$CONFIG_FILE")
    local DOMAIN=$(echo "$config_values" | cut -d'|' -f1)
    local SSL_EMAIL=$(echo "$config_values" | cut -d'|' -f2)
    local SSL_MODE=$(echo "$config_values" | cut -d'|' -f3)
    
    if [ -z "$DOMAIN" ] || [ "$DOMAIN" = "null" ]; then
        print_error "Domain not configured"
        exit 1
    fi
    
    if [ -z "$SSL_EMAIL" ] || [ "$SSL_EMAIL" = "null" ]; then
        print_error "Email not configured"
        exit 1
    fi
    
    [ -z "$SSL_MODE" ] && SSL_MODE="staging"
    
    echo ""
    print_info "Configuration:"
    echo "  Domain: $DOMAIN"
    echo "  Email:  $SSL_EMAIL"
    echo "  Mode:   $SSL_MODE"
    echo ""
    
    if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
        print_warning "SSL certificate already exists"
        read -p "Recreate? (y/N): " recreate
        [ "$recreate" != "y" ] && exit 0
    fi
    
    print_step "Checking configuration..."
    
    local SERVER_IP=$(curl -4 -s --max-time 5 ifconfig.me 2>/dev/null)
    [ -z "$SERVER_IP" ] && SERVER_IP=$(curl -4 -s --max-time 5 icanhazip.com 2>/dev/null)
    
    echo "  Domain:    $DOMAIN"
    echo "  Server IP: $SERVER_IP"
    echo ""
    
    if [ -z "$SERVER_IP" ]; then
        print_error "Could not determine server IP"
        exit 1
    fi
    
    print_info "DNS Requirements:"
    echo "  A    @    $SERVER_IP"
    echo "  A    *    $SERVER_IP"
    echo ""
    
    read -p "DNS configured? Continue? (Y/n): " cont
    [ "$cont" = "n" ] && exit 0
    
    if [ "$SSL_MODE" = "production" ]; then
        echo ""
        print_warning "═════════════════════════════════"
        print_warning "  PRODUCTION MODE"
        print_warning "═════════════════════════════════"
        print_warning "Real certificates (5/week limit)"
        echo ""
        read -p "Continue? (yes/no): " confirm
        [ "$confirm" != "yes" ] && exit 0
    else
        print_info "STAGING mode (test certificates)"
        echo ""
    fi
    
    print_step "Pre-flight checks..."
    
    if ! nc -z localhost 80 2>/dev/null; then
        print_error "Port 80 not accessible"
        exit 1
    fi
    
    if [ ! -d "/opt/onestack/frontends/main" ]; then
        print_error "Webroot not found"
        exit 1
    fi
    
    print_success "Checks passed"
    
    echo ""
    print_info "Starting SSL setup..."
    sleep 2
    
    # Run setup (calls setup_ssl from lib/06-ssl.sh)
    setup_ssl "$CONFIG_FILE"
    
    if [ $? -eq 0 ]; then
        echo ""
        print_success "═════════════════════════════════"
        print_success "  SSL Setup Complete!"
        print_success "═════════════════════════════════"
        echo ""
        print_info "HTTPS enabled for:"
        echo "  ✅ https://$DOMAIN"
        echo "  ✅ https://www.$DOMAIN"
        echo ""
        
        if [ "$SSL_MODE" = "staging" ]; then
            print_warning "STAGING - not trusted by browsers"
            print_info "For real certificates:"
            echo "  1. Edit config.yml → ssl_mode: production"
            echo "  2. Run SSL setup again"
        else
            print_info "Test SSL:"
            echo "  https://www.ssllabs.com/ssltest/analyze.html?d=$DOMAIN"
        fi
        
        echo ""
        print_success "Done!"
    else
        echo ""
        print_error "SSL setup failed"
        exit 1
    fi
}

check_root
main