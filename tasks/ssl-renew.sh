#!/bin/bash
# ═══════════════════════════════════════════════════
# OneStack - SSL Certificate Renewal Task
# ═══════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/06-ssl.sh"

# ═══════════════════════════════════════════════════
# Main Renewal
# ═══════════════════════════════════════════════════

main() {
    print_header "SSL Certificate Renewal"
    
    # Check if SSL is configured
    if ! command -v certbot &> /dev/null; then
        print_error "Certbot is not installed"
        print_info "Run ssl-setup.sh first"
        exit 1
    fi
    
    # Check existing certificates
    print_step "Checking current certificates..."
    echo ""
    
    certbot certificates
    
    echo ""
    
    # Check if renewal is needed
    print_step "Checking if renewal is needed..."
    
    local RENEWAL_OUTPUT=$(certbot renew --dry-run 2>&1)
    
    if echo "$RENEWAL_OUTPUT" | grep -q "No renewals were attempted"; then
        print_success "All certificates are up to date!"
        
        # Show expiry dates
        echo ""
        print_info "Certificate expiry dates:"
        certbot certificates 2>/dev/null | grep "Expiry Date" || true
        
        echo ""
        print_info "Certificates are automatically renewed 30 days before expiry"
        print_info "Auto-renewal runs twice daily (2 AM and 2 PM)"
        
        exit 0
    fi
    
    # Renewal is needed or possible
    echo ""
    print_warning "Some certificates can be renewed"
    echo ""
    read -p "Renew certificates now? (Y/n): " confirm
    
    [ "$confirm" = "n" ] && exit 0
    
    # Perform renewal
    print_step "Renewing certificates..."
    echo ""
    
    certbot renew
    
    if [ $? -eq 0 ]; then
        print_success "Certificates renewed successfully"
        
        # Reload Nginx
        print_step "Reloading Nginx..."
        docker compose -f /opt/onestack/docker-compose.yml exec nginx nginx -s reload
        
        if [ $? -eq 0 ]; then
            print_success "Nginx reloaded successfully"
        else
            print_warning "Failed to reload Nginx"
            print_info "You may need to restart manually:"
            print_info "  docker compose -f /opt/onestack/docker-compose.yml restart nginx"
        fi
        
        echo ""
        print_success "Renewal complete!"
        
        # Show new expiry
        echo ""
        print_info "New expiry dates:"
        certbot certificates 2>/dev/null | grep "Expiry Date" || true
        
    else
        print_error "Certificate renewal failed"
        echo ""
        print_info "Common issues:"
        print_info "  • Domain DNS changed"
        print_info "  • Port 80 not accessible"
        print_info "  • Rate limit exceeded"
        echo ""
        print_info "Check logs: /var/log/letsencrypt/letsencrypt.log"
        exit 1
    fi
}

# Run
check_root
main