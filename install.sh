#!/bin/bash
# OneStack v2 - Complete Installer
# Phase 1: System Setup + Phase 2: Service Deployment

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load utilities
source "$SCRIPT_DIR/lib/utils.sh"

# ════════════════════════════════════════════════
# BANNER
# ════════════════════════════════════════════════

clear
cat << 'BANNER'
╔═══════════════════════════════════════════════╗
║                                               ║
║           🚀 OneStack v2 Installer            ║
║                                               ║
║     Complete Self-Hosted SME Platform         ║
║                                               ║
╚═══════════════════════════════════════════════╝
BANNER

echo ""
print_info "Complete Installation System"
echo ""
print_info "This will install:"
echo "  Phase 1: System preparation, users, Docker, security"
echo "  Phase 2: OneStack services deployment"
echo ""

# ════════════════════════════════════════════════
# ROOT CHECK
# ════════════════════════════════════════════════

check_root

# ════════════════════════════════════════════════
# LOAD CONFIGURATION
# ════════════════════════════════════════════════

print_header "Loading Configuration"

CONFIG_FILE="$SCRIPT_DIR/config.yml"

if [ ! -f "$CONFIG_FILE" ]; then
    print_error "Configuration file not found: $CONFIG_FILE"
    echo ""
    print_info "Please create config.yml first:"
    echo ""
    
    # แสดงตัวเลือก
    if [ -f "$SCRIPT_DIR/config.example.yml" ]; then
        echo "  Option 1: Copy from example"
        echo "    cp config.example.yml config.yml"
        echo "    nano config.yml"
        echo ""
    fi
    
    if [ -f "$SCRIPT_DIR/config.domain.example.yml" ]; then
        echo "  Option 2: Use domain template"
        echo "    cp config.domain.example.yml config.yml"
        echo "    nano config.yml  # Edit your domain"
        echo ""
    fi
    
    if [ -f "$SCRIPT_DIR/config.ip.example.yml" ]; then
        echo "  Option 3: Use IP template"
        echo "    cp config.ip.example.yml config.yml"
        echo "    nano config.yml  # Edit your IP"
        echo ""
    fi
    
    echo "  Then run installer again:"
    echo "    sudo bash install.sh"
    echo ""
    
    exit 1
fi

load_config "$CONFIG_FILE"
print_success "Configuration loaded"
echo ""

# ════════════════════════════════════════════════
# SHOW INSTALLATION PLAN
# ════════════════════════════════════════════════

print_header "Installation Plan"

echo "System Configuration:"
echo "  • Admin User: $ADMIN_USER (with sudo)"
echo "  • Service User: $ONESTACK_USER (no sudo)"
echo "  • Install Directory: $INSTALL_DIR"
echo "  • Timezone: ${CONFIG_system_timezone:-UTC}"
echo ""

echo "Domain Configuration:"
echo "  • Primary Domain: $PRIMARY_DOMAIN"
echo "  • SSL Email: $SSL_EMAIL"
echo "  • SSL Mode: $SSL_MODE"
echo ""

echo "Core Services (Always Installed):"
echo "  ✓ Nginx Reverse Proxy"
echo "  ✓ PostgreSQL Database (with pgvector)"
echo "  ✓ MongoDB Database"
echo "  ✓ Redis Cache"
echo "  ✓ MinIO Object Storage"
echo ""

echo "Optional Components:"
if [ "$INSTALL_PARSE" = "true" ]; then
    echo "  ✓ Parse Server (Backend-as-a-Service)"
else
    echo "  ✗ Parse Server (disabled)"
fi

if [ "$INSTALL_MONITORING" = "true" ]; then
    echo "  ✓ Monitoring Stack (Grafana + Prometheus)"
else
    echo "  ✗ Monitoring Stack (disabled)"
fi

if [ "$INSTALL_ADMINER" = "true" ]; then
    echo "  ✓ Adminer (Database UI)"
else
    echo "  ✗ Adminer (disabled)"
fi

echo ""

echo "Security Features:"
if [ "${CONFIG_security_fail2ban_enabled:-true}" = "true" ]; then
    echo "  ✓ Fail2Ban (intrusion prevention)"
else
    echo "  ✗ Fail2Ban (disabled)"
fi

if [ "${CONFIG_security_ssh_disable_root_login:-true}" = "true" ]; then
    echo "  ✓ SSH: Root login will be disabled"
else
    echo "  ⚠ SSH: Root login will remain enabled"
fi

echo ""

# Estimated time
print_info "Estimated installation time: 15-25 minutes"
echo ""

if ! confirm "Start installation with this configuration?"; then
    print_info "Installation cancelled"
    echo ""
    print_info "To change settings:"
    echo "  1. Edit: nano config.yml"
    echo "  2. Run again: sudo bash install.sh"
    exit 0
fi

# Create log file
export LOG_FILE="/var/log/onestack-install.log"
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

log_message "INFO" "OneStack installation started"
log_message "INFO" "Configuration loaded from: $CONFIG_FILE"

# ════════════════════════════════════════════════
# PHASE 1: SYSTEM PREPARATION
# ════════════════════════════════════════════════

print_header "PHASE 1: System Preparation"
echo ""
log_message "INFO" "Starting Phase 1: System Preparation"

# Step 1: System Check & Update
print_info "[1/4] System Preparation..."
source "$SCRIPT_DIR/lib/01-system.sh"
run_system_preparation
log_message "INFO" "System preparation completed"

# Step 2: User Management
print_info "[2/4] User Management..."
source "$SCRIPT_DIR/lib/02-users.sh"
run_user_management
log_message "INFO" "User management completed"

# Step 3: Docker Installation
print_info "[3/4] Docker Installation..."
source "$SCRIPT_DIR/lib/03-docker.sh"
run_docker_installation
log_message "INFO" "Docker installation completed"

# Step 4: Security Setup
print_info "[4/4] Security Configuration..."
source "$SCRIPT_DIR/lib/04-security.sh"
run_security_setup
log_message "INFO" "Security setup completed"

# ════════════════════════════════════════════════
# PHASE 1 COMPLETE
# ════════════════════════════════════════════════

print_header "Phase 1 Complete! ✓"
echo ""

print_success "✓ System Preparation"
print_success "✓ User Management"
print_success "✓ Docker Installation"
print_success "✓ Security Setup"
echo ""

# Save Phase 1 state
cat > /root/.onestack_install_state << EOF
PHASE_1_COMPLETE=true
PHASE_1_DATE="$(date +"%Y-%m-%d_%H-%M-%S")"
ADMIN_USER=$ADMIN_USER
ONESTACK_USER=$ONESTACK_USER
INSTALL_DIR=$INSTALL_DIR
PRIMARY_DOMAIN=$PRIMARY_DOMAIN
SSL_EMAIL=$SSL_EMAIL
SSL_MODE=$SSL_MODE
INSTALL_PARSE=$INSTALL_PARSE
INSTALL_MONITORING=$INSTALL_MONITORING
INSTALL_ADMINER=$INSTALL_ADMINER
EOF

log_message "INFO" "Phase 1 state saved"

# ════════════════════════════════════════════════
# SECURITY CHECKPOINT
# ════════════════════════════════════════════════

if [ "${CONFIG_security_ssh_disable_root_login:-true}" = "true" ]; then
    echo ""
    print_warning "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_warning "SECURITY CHECKPOINT"
    print_warning "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    if grep -q "^PermitRootLogin no" /etc/ssh/sshd_config 2>/dev/null; then
        print_warning "Root SSH login has been disabled for security"
        echo ""
        echo "Before continuing to Phase 2:"
        echo "  1. Keep this terminal open"
        echo "  2. Open a NEW terminal"
        echo "  3. Test admin login:"
        echo ""
        print_info "     ssh $ADMIN_USER@$(get_server_ip)"
        echo ""
        echo "  4. Test sudo access:"
        echo ""
        print_info "     sudo whoami"
        echo ""
        echo "  5. If successful, return here to continue"
        echo ""
        
        if ! confirm "Have you tested and confirmed admin login works?"; then
            print_warning "Installation paused for safety"
            echo ""
            print_info "When ready, run Phase 2 manually:"
            print_info "  sudo bash -c 'source lib/utils.sh && source lib/05-onestack.sh && run_onestack_setup'"
            echo ""
            exit 0
        fi
    fi
fi

# ════════════════════════════════════════════════
# PHASE 2: SERVICE DEPLOYMENT
# ════════════════════════════════════════════════

echo ""
print_header "PHASE 2: Service Deployment"
echo ""
log_message "INFO" "Starting Phase 2: Service Deployment"

print_info "This will:"
echo "  • Create directory structure"
echo "  • Generate secure passwords"
echo "  • Create Docker Compose configuration"
echo "  • Deploy all selected services"
echo "  • Setup Nginx reverse proxy"
echo "  • Create welcome page"
echo ""

if ! confirm "Continue with Phase 2 (Service Deployment)?"; then
    print_info "Phase 2 postponed"
    echo ""
    print_info "To continue later, run:"
    print_info "  sudo bash -c 'source lib/utils.sh && source lib/05-onestack.sh && run_onestack_setup'"
    echo ""
    exit 0
fi

# Load Phase 2
source "$SCRIPT_DIR/lib/05-onestack.sh"
run_onestack_setup

log_message "INFO" "Phase 2 completed"

# ════════════════════════════════════════════════
# INSTALLATION COMPLETE
# ════════════════════════════════════════════════

print_header "🎉 Installation Complete!"

log_message "INFO" "OneStack installation completed successfully"

# Update state
cat >> /root/.onestack_install_state << EOF
PHASE_2_COMPLETE=true
PHASE_2_DATE=$(date +"%Y-%m-%d %H:%M:%S")
INSTALLATION_COMPLETE=true
EOF

echo ""
print_success "Both phases completed successfully!"
echo ""
print_info "Installation log saved to: $LOG_FILE"
echo ""

# ════════════════════════════════════════════════
# NEXT STEPS
# ════════════════════════════════════════════════

print_header "Next Steps"
echo ""

if [ "$PRIMARY_DOMAIN" != "localhost" ]; then
    print_warning "DNS Configuration Required:"
    echo ""
    echo "Add these DNS records for your domain:"
    echo ""
    echo "  Type    Name                Value"
    echo "  ────────────────────────────────────────────────"
    echo "  A       @                   $(get_server_ip)"
    echo "  A       *                   $(get_server_ip)"
    echo "  CNAME   www                 @"
    echo ""
    print_info "Or add to /etc/hosts on your computer:"
    echo "  $(get_server_ip)  $PRIMARY_DOMAIN"
    echo "  $(get_server_ip)  www.$PRIMARY_DOMAIN"
    echo "  $(get_server_ip)  api.$PRIMARY_DOMAIN"
    echo "  $(get_server_ip)  monitor.$PRIMARY_DOMAIN"
    echo "  $(get_server_ip)  storage.$PRIMARY_DOMAIN"
    echo ""
fi

echo "Recommended next steps:"
echo ""
echo "  1. View credentials:"
echo "     cat $INSTALL_DIR/.credentials"
echo ""
echo "  2. Visit welcome page:"
if [ "$PRIMARY_DOMAIN" = "localhost" ]; then
    echo "     http://localhost"
else
    echo "     http://$PRIMARY_DOMAIN"
fi
echo ""
echo "  3. Check service status:"
echo "     cd $INSTALL_DIR && docker compose ps"
echo ""
echo "  4. View logs:"
echo "     cd $INSTALL_DIR && docker compose logs -f"
echo ""
echo "  5. Setup SSL (if using real domain):"
echo "     Coming soon: sudo bash setup-ssl.sh"
echo ""

print_info "For help and documentation:"
echo "  • Installation log: $LOG_FILE"
echo "  • Credentials: $INSTALL_DIR/.credentials"
echo "  • Architecture: ARCHITECTURE.md"
echo ""

echo "To uninstall:"
echo "  sudo bash uninstall.sh"
echo ""

print_success "Thank you for using OneStack! 🚀"
echo ""

log_message "INFO" "Installation process finished"