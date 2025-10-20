#!/bin/bash
# ═══════════════════════════════════════════════════
# OneStack - SSL Setup Task (Complete Fixed Version)
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
    print_info "SSL functions library is required"
    print_info "Expected: $SCRIPT_DIR/lib/06-ssl.sh"
    exit 1
fi

# ═══════════════════════════════════════════════════
# Check Prerequisites
# ═══════════════════════════════════════════════════

check_prerequisites() {
    local missing=0
    
    # Check yq
    if ! command -v yq &> /dev/null; then
        print_warning "yq not installed"
        read -p "Install yq now? (Y/n): " install
        
        if [ "$install" != "n" ]; then
            print_step "Installing yq..."
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
    
    # Check certbot
    if ! command -v certbot &> /dev/null; then
        print_info "certbot will be installed during SSL setup"
    fi
    
    return 0
}

# ═══════════════════════════════════════════════════
# Read Configuration
# ═══════════════════════════════════════════════════

read_config() {
    local config_file=$1
    
    print_step "Reading configuration..."
    
    # Try yq first
    local domain=$(yq eval '.domain.primary' "$config_file" 2>/dev/null)
    local email=$(yq eval '.domain.ssl_email' "$config_file" 2>/dev/null)
    local mode=$(yq eval '.domain.ssl_mode' "$config_file" 2>/dev/null)
    
    # Fallback to grep if yq failed
    if [ -z "$domain" ] || [ "$domain" = "null" ]; then
        print_warning "yq failed, using grep fallback..."
        
        domain=$(grep "^\s*primary:" "$config_file" | sed 's/.*primary:\s*//' | tr -d '"' | tr -d "'" | head -1)
        email=$(grep "^\s*ssl_email:" "$config_file" | sed 's/.*ssl_email:\s*//' | tr -d '"' | tr -d "'" | head -1)
        mode=$(grep "^\s*ssl_mode:" "$config_file" | sed 's/.*ssl_mode:\s*//' | tr -d '"' | tr -d "'" | tr -d '#' | awk '{print $1}' | head -1)
    fi
    
    # Return values via echo
    echo "$domain|$email|$mode"
}

# ═══════════════════════════════════════════════════
# Main SSL Setup
# ═══════════════════════════════════════════════════

main() {
    print_header "SSL Certificate Setup"
    
    # Check prerequisites
    if ! check_prerequisites; then
        print_error "Prerequisites not met"
        print_info "yq is required for SSL setup"
        exit 1
    fi
    
    # Find config file
    print_step "Looking for config.yml..."
    
    local CONFIG_FILE=""
    local search_paths=(
        "$SCRIPT_DIR/config.yml"
        "/root/onestack/config.yml"
        "/opt/onestack/config.yml"
    )
    
    for path in "${search_paths[@]}"; do
        if [ -f "$path" ]; then
            CONFIG_FILE="$path"
            print_success "Found: $CONFIG_FILE"
            break
        fi
    done
    
    if [ -z "$CONFIG_FILE" ]; then
        print_error "Config file not found"
        echo ""
        print_info "Searched locations:"
        for path in "${search_paths[@]}"; do
            echo "  • $path"
        done
        echo ""
        print_info "Create config.yml from template:"
        echo "  cp config.domain.example.yml config.yml"
        exit 1
    fi
    
    # Read configuration
    local config_values=$(read_config "$CONFIG_FILE")
    local DOMAIN=$(echo "$config_values" | cut -d'|' -f1)
    local SSL_EMAIL=$(echo "$config_values" | cut -d'|' -f2)
    local SSL_MODE=$(echo "$config_values" | cut -d'|' -f3)
    
    # Validate domain
    if [ -z "$DOMAIN" ] || [ "$DOMAIN" = "null" ]; then
        print_error "Domain not configured in config.yml"
        echo ""
        print_info "Edit: $CONFIG_FILE"
        print_info "Set domain.primary to your domain"
        exit 1
    fi
    
    # Validate email
    if [ -z "$SSL_EMAIL" ] || [ "$SSL_EMAIL" = "null" ]; then
        print_error "SSL email not configured in config.yml"
        echo ""
        print_info "Edit: $CONFIG_FILE"
        print_info "Set domain.ssl_email to your email"
        exit 1
    fi
    
    # Default mode
    if [ -z "$SSL_MODE" ] || [ "$SSL_MODE" = "null" ]; then
        SSL_MODE="staging"
        print_warning "SSL mode not specified, using: staging"
    fi
    
    # Show configuration
    echo ""
    print_info "Configuration:"
    echo "  Domain:      $DOMAIN"
    echo "  Email:       $SSL_EMAIL"
    echo "  Mode:        $SSL_MODE"
    echo ""
    
    # Check if already has SSL
    if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
        print_warning "SSL certificate already exists for $DOMAIN"
        
        # Show expiry
        if command -v openssl &> /dev/null; then
            local expiry=$(openssl x509 -in "/etc/letsencrypt/live/$DOMAIN/cert.pem" -noout -enddate 2>/dev/null | cut -d= -f2)
            if [ -n "$expiry" ]; then
                print_info "Expires: $expiry"
            fi
        fi
        
        echo ""
        read -p "Recreate certificate? (y/N): " recreate
        
        if [ "$recreate" != "y" ]; then
            print_info "Setup cancelled"
            exit 0
        fi
    fi
    
    # DNS Check
    print_step "Checking DNS configuration..."
    
    # Get DNS IP - use temp file to avoid subshell issues
    dig +short "$DOMAIN" > /tmp/onestack_dns_check 2>&1
    local DNS_IP=$(grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' /tmp/onestack_dns_check | head -1)
    rm -f /tmp/onestack_dns_check
    
    # Debug output
    if [ -z "$DNS_IP" ]; then
        print_warning "dig command output:"
        dig +short "$DOMAIN" 2>&1 | head -5
        echo ""
    fi
    
    # Get Server IP - force IPv4
    local SERVER_IP=$(curl -4 -s --max-time 5 ifconfig.me 2>/dev/null)
    
    # Fallback for Server IP
    if [ -z "$SERVER_IP" ] || [[ "$SERVER_IP" == *":"* ]]; then
        SERVER_IP=$(curl -4 -s --max-time 5 icanhazip.com 2>/dev/null)
    fi
    
    if [ -z "$SERVER_IP" ] || [[ "$SERVER_IP" == *":"* ]]; then
        SERVER_IP=$(curl -4 -s --max-time 5 api.ipify.org 2>/dev/null)
    fi
    
    # Display results
    echo "  Domain:    $DOMAIN"
    echo "  DNS IP:    ${DNS_IP:-(not resolved)}"
    echo "  Server IP: $SERVER_IP"
    echo ""
    
    # Validation
    if [ -z "$DNS_IP" ]; then
        print_error "Could not resolve domain via dig"
        echo ""
        print_info "Manual test:"
        echo "  Run: dig +short $DOMAIN"
        echo ""
        print_info "If manual test works but script doesn't,"
        print_info "you can continue anyway - Let's Encrypt uses its own DNS resolver"
        echo ""
        read -p "Continue anyway? (y/N): " force
        [ "$force" != "y" ] && exit 1
        
    elif [ -z "$SERVER_IP" ]; then
        print_warning "Could not determine server IP"
        echo ""
        read -p "Continue anyway? (y/N): " force
        [ "$force" != "y" ] && exit 1
        
    elif [ "$DNS_IP" != "$SERVER_IP" ]; then
        print_warning "DNS mismatch detected"
        echo "  DNS points to: $DNS_IP"
        echo "  Server IP is:  $SERVER_IP"
        echo ""
        print_info "This may be due to:"
        echo "  • DNS propagation in progress"
        echo "  • Wrong A record value"
        echo "  • Using proxy/CDN (e.g., Cloudflare)"
        echo ""
        read -p "Continue anyway? (y/N): " force
        [ "$force" != "y" ] && exit 1
        
    else
        print_success "DNS correctly configured! ✅"
    fi
    
    # Mode confirmation
    if [ "$SSL_MODE" = "production" ]; then
        echo ""
        print_warning "═══════════════════════════════════════════════════════"
        print_warning "  PRODUCTION MODE"
        print_warning "═══════════════════════════════════════════════════════"
        print_warning "This will request REAL SSL certificates from Let's Encrypt"
        print_warning ""
        print_warning "Rate Limits:"
        print_warning "  • 5 certificates per week per domain"
        print_warning "  • 50 certificates per week per account"
        print_warning ""
        print_warning "If you're testing, use staging mode instead!"
        print_warning "  (Change ssl_mode: staging in config.yml)"
        print_warning "═══════════════════════════════════════════════════════"
        echo ""
        read -p "Continue with PRODUCTION mode? (yes/no): " confirm
        
        if [ "$confirm" != "yes" ]; then
            print_info "Setup cancelled"
            print_info "To use staging mode, edit config.yml:"
            print_info "  ssl_mode: staging"
            exit 0
        fi
    else
        print_info "Using STAGING mode (test certificates)"
        print_warning "Browsers will not trust these certificates"
        echo ""
        read -p "Continue? (Y/n): " confirm
        [ "$confirm" = "n" ] && exit 0
    fi
    
    # Pre-flight checks
    print_step "Running pre-flight checks..."
    
    # Check port 80
    if ! nc -z localhost 80 2>/dev/null; then
        print_error "Port 80 is not accessible"
        print_info "Make sure Nginx is running:"
        print_info "  docker compose -f /opt/onestack/docker-compose.yml ps nginx"
        exit 1
    fi
    
    # Check webroot
    if [ ! -d "/opt/onestack/frontends/main" ]; then
        print_error "Webroot not found: /opt/onestack/frontends/main"
        print_info "Create the directory:"
        print_info "  mkdir -p /opt/onestack/frontends/main"
        exit 1
    fi
    
    print_success "Pre-flight checks passed"
    
    # Final confirmation
    echo ""
    read -p "Start SSL setup now? (Y/n): " start
    [ "$start" = "n" ] && exit 0
    
    # Run setup
    echo ""
    setup_ssl "$CONFIG_FILE"
    
    if [ $? -eq 0 ]; then
        echo ""
        print_success "═══════════════════════════════════════════════════════"
        print_success "  SSL Setup Complete!"
        print_success "═══════════════════════════════════════════════════════"
        echo ""
        print_info "Your site is now accessible via HTTPS:"
        echo ""
        echo "  ✅ https://$DOMAIN"
        echo "  ✅ https://www.$DOMAIN"
        echo "  ✅ https://storage.$DOMAIN"
        echo "  ✅ https://s3.$DOMAIN"
        echo "  ✅ https://api.$DOMAIN"
        echo "  ✅ https://monitor.$DOMAIN"
        echo "  ✅ https://prometheus.$DOMAIN"
        echo "  ✅ https://db.$DOMAIN"
        echo ""
        print_info "Auto-renewal is configured (runs twice daily)"
        echo ""
        
        if [ "$SSL_MODE" = "production" ]; then
            print_info "Test your SSL grade:"
            echo "  https://www.ssllabs.com/ssltest/analyze.html?d=$DOMAIN"
        else
            print_warning "STAGING MODE - Certificates are not trusted by browsers"
            print_info "To get real certificates:"
            echo "  1. Edit config.yml → ssl_mode: production"
            echo "  2. Run SSL setup again"
        fi
        
        echo ""
        
        # Update Parse Server URL
        if grep -q "http://api.$DOMAIN" /opt/onestack/.env 2>/dev/null; then
            print_step "Updating Parse Server public URL..."
            sed -i "s|http://api.$DOMAIN|https://api.$DOMAIN|g" /opt/onestack/.env
            
            if docker compose -f /opt/onestack/docker-compose.yml restart parse-server 2>/dev/null; then
                print_success "Parse Server updated"
            fi
        fi
        
        print_success "Setup complete!"
    else
        echo ""
        print_error "SSL setup failed"
        print_info "Check the errors above and try again"
        echo ""
        print_info "Common issues:"
        echo "  • DNS not configured correctly"
        echo "  • Port 80 blocked by firewall"
        echo "  • Nginx not running"
        echo "  • Rate limit exceeded (use staging mode)"
        exit 1
    fi
}

# Run
check_root
main
```

---

## 🎯 **คำตอบ: เพิ่ม n8n.sixamdev.com ยังไง?**

---

## 📝 **วิธีเพิ่ม Subdomain ใหม่ (n8n):**

### **Step 1: DNS (ไม่ต้องทำ - มี wildcard แล้ว)**
```
✅ DNS: ไม่ต้องเพิ่ม!
   CNAME * → sixamdev.com (มีอยู่แล้ว)
   
   n8n.sixamdev.com จะชี้มา server อัตโนมัติ!