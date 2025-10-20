#!/bin/bash
# ═══════════════════════════════════════════════════
# OneStack SSL Management Library
# ═══════════════════════════════════════════════════

# Get library directory
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LIB_DIR/utils.sh"

# ═══════════════════════════════════════════════════
# SSL Certificate Management Functions
# ═══════════════════════════════════════════════════

install_certbot() {
    print_step "Installing Certbot..."
    
    if command -v certbot &> /dev/null; then
        print_success "Certbot already installed"
        certbot --version
        return 0
    fi
    
    # Install Certbot
    apt-get update -qq
    apt-get install -y certbot python3-certbot-nginx -qq
    
    if command -v certbot &> /dev/null; then
        print_success "Certbot installed successfully"
        certbot --version
        return 0
    else
        print_error "Failed to install Certbot"
        return 1
    fi
}

request_ssl_certificate() {
    local domain=$1
    local email=$2
    local subdomains=$3
    
    print_step "Requesting SSL certificate for $domain..."
    
    # Build domain list
    local domain_args="-d $domain -d www.$domain"
    
    if [ -n "$subdomains" ]; then
        for sub in $subdomains; do
            domain_args="$domain_args -d ${sub}.${domain}"
        done
    fi
    
    # Request certificate
    certbot certonly --nginx \
        $domain_args \
        --email "$email" \
        --agree-tos \
        --non-interactive \
        --redirect
    
    if [ $? -eq 0 ]; then
        print_success "SSL certificate obtained"
        return 0
    else
        print_error "Failed to obtain SSL certificate"
        return 1
    fi
}

setup_ssl_auto_renewal() {
    print_step "Setting up SSL auto-renewal..."
    
    # Create renewal script
    local renewal_script="/opt/onestack/scripts/ssl-renew.sh"
    mkdir -p /opt/onestack/scripts
    
    cat > "$renewal_script" << 'RENEWAL_SCRIPT'
#!/bin/bash
# SSL Certificate Auto-Renewal

LOG_FILE="/opt/onestack/logs/ssl-renewal.log"
mkdir -p "$(dirname "$LOG_FILE")"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting SSL renewal..." >> "$LOG_FILE"

certbot renew --quiet --deploy-hook "docker exec onestack-nginx nginx -s reload" >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Renewal completed successfully" >> "$LOG_FILE"
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Renewal failed" >> "$LOG_FILE"
fi
RENEWAL_SCRIPT

    chmod +x "$renewal_script"
    
    # Add to crontab
    (crontab -l 2>/dev/null | grep -v "ssl-renew.sh"; echo "0 2,14 * * * $renewal_script") | crontab -
    
    print_success "Auto-renewal configured"
    print_info "Renewal check: Twice daily at 2 AM and 2 PM"
}

setup_ssl() {
    local domain=$1
    local email=$2
    local mode=${3:-"individual"}
    
    print_header "SSL Certificate Setup"
    
    # Validate inputs
    if [ -z "$domain" ] || [ -z "$email" ]; then
        print_error "Domain and email are required"
        return 1
    fi
    
    print_info "Domain: $domain"
    print_info "Email: $email"
    print_info "Mode: $mode"
    echo ""
    
    # Step 1: Install Certbot
    install_certbot || return 1
    
    echo ""
    
    # Step 2: Request certificates
    if [ "$mode" = "wildcard" ]; then
        print_warning "Wildcard certificates require DNS validation"
        print_info "Run manually: certbot certonly --manual --preferred-challenges dns -d $domain -d *.$domain"
        return 1
    else
        # Individual certificates for each subdomain
        local subdomains="storage s3 api monitor prometheus db"
        request_ssl_certificate "$domain" "$email" "$subdomains" || return 1
    fi
    
    echo ""
    
    # Step 3: Setup auto-renewal
    setup_ssl_auto_renewal || return 1
    
    echo ""
    
    # Step 4: Update Nginx (if function exists)
    if type update_nginx_ssl_config &>/dev/null; then
        update_nginx_ssl_config "$domain" || return 1
    else
        print_warning "Nginx SSL config update skipped"
        print_info "Reload Nginx manually: docker compose exec nginx nginx -s reload"
    fi
    
    print_success "SSL setup completed!"
    return 0
}

renew_ssl_certificates() {
    print_header "Renewing SSL Certificates"
    
    print_step "Running Certbot renewal..."
    certbot renew
    
    if [ $? -eq 0 ]; then
        print_success "Certificate renewal completed"
        
        # Reload Nginx
        print_step "Reloading Nginx..."
        if docker compose -f /opt/onestack/docker-compose.yml exec nginx nginx -s reload 2>/dev/null; then
            print_success "Nginx reloaded"
        fi
        
        return 0
    else
        print_error "Certificate renewal failed"
        return 1
    fi
}

check_ssl_status() {
    print_header "SSL Certificate Status"
    
    local domain=$1
    
    if [ -z "$domain" ]; then
        # Try to get from .env
        if [ -f "/opt/onestack/.env" ]; then
            domain=$(grep "^DOMAIN=" /opt/onestack/.env | cut -d= -f2)
        fi
    fi
    
    if [ -z "$domain" ]; then
        print_error "Domain not specified"
        return 1
    fi
    
    print_info "Checking SSL for: $domain"
    echo ""
    
    # Check if certificate exists
    if [ -d "/etc/letsencrypt/live/$domain" ]; then
        print_success "Certificate found"
        
        # Show certificate info
        local cert_file="/etc/letsencrypt/live/$domain/cert.pem"
        
        if [ -f "$cert_file" ]; then
            echo ""
            print_info "Certificate Details:"
            openssl x509 -in "$cert_file" -noout -text | grep -E "Subject:|Issuer:|Not Before:|Not After:" | sed 's/^/  /'
            
            # Check expiry
            local expiry=$(openssl x509 -in "$cert_file" -noout -enddate | cut -d= -f2)
            local expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null)
            local now_epoch=$(date +%s)
            local days_left=$(( ($expiry_epoch - $now_epoch) / 86400 ))
            
            echo ""
            if [ $days_left -gt 30 ]; then
                print_success "Certificate valid for $days_left days"
            elif [ $days_left -gt 7 ]; then
                print_warning "Certificate expires in $days_left days"
            else
                print_error "Certificate expires in $days_left days - RENEWAL REQUIRED!"
            fi
        fi
    else
        print_warning "No certificate found for $domain"
    fi
    
    echo ""
    
    # List all certificates
    print_info "All installed certificates:"
    certbot certificates 2>/dev/null || echo "  (none)"
}

# Export functions
export -f install_certbot
export -f request_ssl_certificate
export -f setup_ssl_auto_renewal
export -f setup_ssl
export -f renew_ssl_certificates
export -f check_ssl_status