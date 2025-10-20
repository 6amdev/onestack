#!/bin/bash
# ═══════════════════════════════════════════════════
# Task: Fix .env Configuration
# Description: Fix missing environment variables
# ═══════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

fix_env_file() {
    print_header "Fixing .env Configuration"
    
    local ENV_FILE="/opt/onestack/.env"
    
    if [ ! -f "$ENV_FILE" ]; then
        print_error ".env file not found"
        exit 1
    fi
    
    # Backup
    cp "$ENV_FILE" "${ENV_FILE}.backup-$(date +%Y%m%d_%H%M%S)"
    print_success "Backed up .env file"
    
    echo ""
    print_step "Checking for missing variables..."
    
    # Check DOMAIN
    if ! grep -q "^DOMAIN=" "$ENV_FILE"; then
        print_warning "DOMAIN not found"
        read -p "Enter domain name (e.g., example.com): " domain
        
        if [ -n "$domain" ]; then
            echo "" >> "$ENV_FILE"
            echo "# Domain Configuration" >> "$ENV_FILE"
            echo "DOMAIN=$domain" >> "$ENV_FILE"
            print_success "Added DOMAIN=$domain"
        fi
    else
        local domain=$(grep "^DOMAIN=" "$ENV_FILE" | cut -d= -f2)
        print_success "DOMAIN is set: $domain"
    fi
    
    # Check MONGODB_PASSWORD
    if ! grep -q "^MONGODB_PASSWORD=" "$ENV_FILE"; then
        print_warning "MONGODB_PASSWORD not found"
        
        # Generate secure password
        local mongo_pass=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
        echo "MONGODB_PASSWORD=$mongo_pass" >> "$ENV_FILE"
        print_success "Added MONGODB_PASSWORD"
    else
        print_success "MONGODB_PASSWORD is set"
    fi
    
    # Check other critical variables
    local required_vars=(
        "POSTGRES_PASSWORD"
        "REDIS_PASSWORD"
        "MINIO_ROOT_PASSWORD"
        "PARSE_APP_ID"
        "PARSE_MASTER_KEY"
    )
    
    for var in "${required_vars[@]}"; do
        if ! grep -q "^${var}=" "$ENV_FILE"; then
            print_warning "$var not found, generating..."
            local value=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
            echo "${var}=$value" >> "$ENV_FILE"
            print_success "Added $var"
        fi
    done
    
    echo ""
    print_success "All required variables configured"
    
    # Restart services if needed
    echo ""
    if confirm "Restart services to apply changes?"; then
        cd /opt/onestack
        docker compose restart
        print_success "Services restarted"
    fi
}

main() {
    clear
    fix_env_file
}

main "$@"