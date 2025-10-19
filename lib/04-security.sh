#!/bin/bash
# OneStack - Security Configuration

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LIB_DIR/utils.sh"

setup_firewall() {
    print_header "Firewall Configuration (UFW)"
    
    # Check if UFW is installed
    if ! command_exists ufw; then
        print_step "Installing UFW..."
        install_package ufw
    fi
    
    print_step "Configuring firewall rules..."
    
    # Default policies
    ufw --force default deny incoming
    ufw --force default allow outgoing
    
    # Allow SSH
    ufw --force allow 22/tcp comment 'SSH'
    print_success "SSH (22) allowed"
    
    # Allow HTTP/HTTPS
    ufw --force allow 80/tcp comment 'HTTP'
    ufw --force allow 443/tcp comment 'HTTPS'
    print_success "HTTP (80) and HTTPS (443) allowed"
    
    # Enable firewall
    print_step "Enabling firewall..."
    ufw --force enable
    
    if ufw status | grep -q "Status: active"; then
        print_success "Firewall enabled"
    else
        print_error "Failed to enable firewall"
    fi
    
    # Show status
    echo ""
    print_info "Firewall status:"
    ufw status numbered
    
    echo ""
}

configure_ssh() {
    print_header "SSH Hardening"
    
    local sshd_config="/etc/ssh/sshd_config"
    local backup="/etc/ssh/sshd_config.backup.$(date +%Y%m%d)"
    
    # Backup original config
    print_step "Backing up SSH config..."
    cp "$sshd_config" "$backup"
    print_success "Backup created: $backup"
    
    print_warning "═══════════════════════════════════════"
    print_warning "SSH Security Configuration"
    echo ""
    echo "Recommended changes:"
    echo "  • Disable root login"
    echo "  • Disable password authentication (use keys only)"
    echo "  • Limit max authentication attempts"
    echo ""
    print_warning "═══════════════════════════════════════"
    echo ""
    
    # Ask about root login
    local disable_root="no"
    if confirm "Disable root SSH login? (Recommended: yes)"; then
        disable_root="yes"
    fi
    
    # Ask about password authentication
    local password_auth="yes"
    if [ "$disable_root" = "yes" ]; then
        print_warning "Make sure SSH keys are set up before disabling passwords!"
        if confirm "Disable password authentication? (Use SSH keys only)"; then
            password_auth="no"
        fi
    fi
    
    print_step "Applying SSH configuration..."
    
    # Apply settings
    sed -i "s/^#*PermitRootLogin.*/PermitRootLogin $disable_root/" "$sshd_config"
    sed -i "s/^#*PasswordAuthentication.*/PasswordAuthentication $password_auth/" "$sshd_config"
    sed -i "s/^#*MaxAuthTries.*/MaxAuthTries 3/" "$sshd_config"
    sed -i "s/^#*X11Forwarding.*/X11Forwarding no/" "$sshd_config"
    
    # Add if not exists
    grep -q "^MaxAuthTries" "$sshd_config" || echo "MaxAuthTries 3" >> "$sshd_config"
    
    print_success "SSH configuration updated"
    
    # Test configuration
    print_step "Testing SSH configuration..."
    if sshd -t; then
        print_success "SSH configuration valid"
        
        # Restart SSH
        print_step "Restarting SSH service..."
        systemctl restart sshd
        
        if systemctl is-active --quiet sshd; then
            print_success "SSH service restarted"
        else
            print_error "SSH restart failed, restoring backup"
            cp "$backup" "$sshd_config"
            systemctl restart sshd
        fi
    else
        print_error "Invalid SSH configuration, restoring backup"
        cp "$backup" "$sshd_config"
    fi
    
    echo ""
    
    if [ "$password_auth" = "no" ]; then
        print_warning "═══════════════════════════════════════"
        print_warning "IMPORTANT: Password authentication disabled!"
        echo "  • Make sure you can login with SSH keys"
        echo "  • Test in a new terminal before closing this one"
        echo "  • Backup config: $backup"
        print_warning "═══════════════════════════════════════"
        echo ""
    fi
}

setup_fail2ban() {
    print_header "Fail2Ban Installation"
    
    if ! command_exists fail2ban-client; then
        print_step "Installing Fail2Ban..."
        install_package fail2ban
    else
        print_success "Fail2Ban already installed"
    fi
    
    # Configure Fail2Ban
    print_step "Configuring Fail2Ban..."
    
    local jail_local="/etc/fail2ban/jail.local"
    
    cat > "$jail_local" << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
destemail = root@localhost
sendername = Fail2Ban
action = %(action_)s

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
EOF
    
    print_success "Fail2Ban configured"
    
    # Start and enable
    systemctl start fail2ban
    systemctl enable fail2ban
    
    if systemctl is-active --quiet fail2ban; then
        print_success "Fail2Ban started"
    else
        print_error "Failed to start Fail2Ban"
    fi
    
    echo ""
}

run_security_setup() {
    check_root
    
    setup_firewall
    
    print_warning "About to configure SSH security..."
    if confirm "Continue with SSH hardening?"; then
        configure_ssh
    else
        print_info "SSH hardening skipped"
    fi
    
    if confirm "Install Fail2Ban intrusion prevention?"; then
        setup_fail2ban
    else
        print_info "Fail2Ban skipped"
    fi
    
    success_message "Security setup completed"
}

# Export functions
export -f setup_firewall configure_ssh setup_fail2ban run_security_setup