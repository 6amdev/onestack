#!/bin/bash
# ═══════════════════════════════════════════════════
# OneStack - SSL Status Check Task
# ═══════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

# ═══════════════════════════════════════════════════
# Main Status Check
# ═══════════════════════════════════════════════════

main() {
    print_header "SSL Certificate Status"
    
    # Check if certbot is installed
    if ! command -v certbot &> /dev/null; then
        print_error "Certbot is not installed"
        print_info "SSL has not been configured yet"
        print_info "Run: ./manage.sh → SSL Setup"
        exit 1
    fi
    
    # Show all certificates
    print_step "Installed Certificates:"
    echo ""
    
    certbot certificates
    
    echo ""
    
    # Get domain from config
    local CONFIG_FILE="$SCRIPT_DIR/config.yml"
    if [ ! -f "$CONFIG_FILE" ]; then
        CONFIG_FILE="/root/onestack/config.yml"
    fi
    
    if [ -f "$CONFIG_FILE" ]; then
        local DOMAIN=$(yq eval '.domain.primary' "$CONFIG_FILE" 2>/dev/null)
        
        if [ -n "$DOMAIN" ] && [ "$DOMAIN" != "null" ]; then
            # Check certificate details
            if [ -f "/etc/letsencrypt/live/$DOMAIN/cert.pem" ]; then
                print_step "Certificate Details for: $DOMAIN"
                echo ""
                
                # Get certificate info
                openssl x509 -in "/etc/letsencrypt/live/$DOMAIN/cert.pem" -noout -text | grep -A 2 "Subject:"
                echo ""
                openssl x509 -in "/etc/letsencrypt/live/$DOMAIN/cert.pem" -noout -dates
                
                # Calculate days until expiry
                local EXPIRY_DATE=$(openssl x509 -in "/etc/letsencrypt/live/$DOMAIN/cert.pem" -noout -enddate | cut -d= -f2)
                local EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s 2>/dev/null)
                local NOW_EPOCH=$(date +%s)
                
                if [ -n "$EXPIRY_EPOCH" ]; then
                    local DAYS_LEFT=$(( ($EXPIRY_EPOCH - $NOW_EPOCH) / 86400 ))
                    
                    echo ""
                    echo "Days until expiry: $DAYS_LEFT"
                    
                    if [ $DAYS_LEFT -lt 30 ]; then
                        print_warning "Certificate expires in less than 30 days!"
                        print_info "Renewal is recommended"
                        print_info "Run: ./manage.sh → Renew SSL"
                    elif [ $DAYS_LEFT -lt 60 ]; then
                        print_warning "Certificate will be renewed automatically soon"
                    else
                        print_success "Certificate is valid and up to date"
                    fi
                fi
                
                # Test HTTPS access
                echo ""
                print_step "Testing HTTPS Access:"
                echo ""
                
                local URLS=(
                    "https://$DOMAIN"
                    "https://api.$DOMAIN/parse/health"
                    "https://storage.$DOMAIN"
                )
                
                for url in "${URLS[@]}"; do
                    echo -n "  Testing: $url ... "
                    
                    local STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>&1)
                    
                    if [[ "$STATUS" =~ ^[23] ]]; then
                        echo "✅ $STATUS"
                    else
                        echo "❌ $STATUS"
                    fi
                done
                
                # SSL Labs test link
                echo ""
                print_info "Run full SSL test:"
                echo "  https://www.ssllabs.com/ssltest/analyze.html?d=$DOMAIN"
                
            else
                print_warning "Certificate file not found for $DOMAIN"
            fi
        fi
    fi
    
    # Check auto-renewal cron
    echo ""
    print_step "Auto-Renewal Configuration:"
    echo ""
    
    if crontab -l 2>/dev/null | grep -q "ssl-renew"; then
        print_success "Auto-renewal cron job is configured"
        echo ""
        echo "Cron schedule:"
        crontab -l 2>/dev/null | grep "ssl-renew"
    else
        print_warning "Auto-renewal cron job not found"
        print_info "Certificates will need to be renewed manually"
    fi
    
    # Check renewal log
    if [ -f "/opt/onestack/logs/ssl-renewal.log" ]; then
        echo ""
        print_step "Recent Renewal Attempts:"
        echo ""
        tail -20 /opt/onestack/logs/ssl-renewal.log
    fi
}

# Run
main