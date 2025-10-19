#!/bin/bash
# OneStack - User Management

source "$(dirname "$0")/utils.sh"

create_admin_user() {
    print_header "Creating Admin User"
    
    local admin_user="$ADMIN_USER"
    
    # Check if user exists
    if id "$admin_user" &>/dev/null; then
        print_warning "User '$admin_user' already exists"
        return 0
    fi
    
    print_step "Creating user: $admin_user"
    
    # Create user with home directory
    if useradd -m -s /bin/bash "$admin_user"; then
        print_success "User created: $admin_user"
    else
        error_exit "Failed to create user: $admin_user"
    fi
    
    # Add to sudo group
    if usermod -aG sudo "$admin_user"; then
        print_success "Added to sudo group"
    else
        error_exit "Failed to add sudo privileges"
    fi
    
    # Set password
    print_info "Set password for '$admin_user':"
    while ! passwd "$admin_user"; do
        print_error "Password setting failed, try again"
    done
    
    print_success "Password set successfully"
    
    # Save for later use
    save_var "ADMIN_USER_CREATED" "true"
    
    echo ""
}

create_onestack_user() {
    print_header "Creating OneStack Service User"
    
    local onestack_user="$ONESTACK_USER"
    
    # Check if user exists
    if id "$onestack_user" &>/dev/null; then
        print_warning "User '$onestack_user' already exists"
        return 0
    fi
    
    print_step "Creating service user: $onestack_user"
    
    # Create user without sudo privileges
    if useradd -m -s /bin/bash "$onestack_user"; then
        print_success "User created: $onestack_user"
    else
        error_exit "Failed to create user: $onestack_user"
    fi
    
    # No password needed (will use sudo -u or su)
    print_info "Service user created (no password, no sudo access)"
    
    # Create necessary directories
    local install_dir="/home/$onestack_user/onestack"
    create_dir "$install_dir" "$onestack_user:$onestack_user" "755"
    
    print_success "Installation directory: $install_dir"
    save_var "INSTALL_DIR" "$install_dir"
    save_var "ONESTACK_USER_CREATED" "true"
    
    echo ""
}

setup_ssh_keys() {
    print_header "SSH Key Setup"
    
    local admin_user="$ADMIN_USER"
    
    if confirm "Set up SSH key authentication for $admin_user?"; then
        print_step "Setting up SSH directory..."
        
        local ssh_dir="/home/$admin_user/.ssh"
        create_dir "$ssh_dir" "$admin_user:$admin_user" "700"
        
        if [ ! -f "$ssh_dir/authorized_keys" ]; then
            touch "$ssh_dir/authorized_keys"
            chmod 600 "$ssh_dir/authorized_keys"
            chown "$admin_user:$admin_user" "$ssh_dir/authorized_keys"
        fi
        
        print_success "SSH directory ready"
        print_info "Add your public key to: $ssh_dir/authorized_keys"
        
        echo ""
        print_warning "IMPORTANT: Test SSH key login before disabling password auth!"
        echo ""
    fi
}

add_user_to_docker() {
    print_header "Docker Group Membership"
    
    # Add both users to docker group
    for user in "$ADMIN_USER" "$ONESTACK_USER"; do
        if id "$user" &>/dev/null; then
            if usermod -aG docker "$user"; then
                print_success "$user added to docker group"
            else
                print_warning "Failed to add $user to docker group"
            fi
        fi
    done
    
    print_info "Users will need to log out and back in for docker access"
    
    echo ""
}

run_user_management() {
    check_root
    
    # Create admin user (with sudo)
    create_admin_user
    
    # Create OneStack service user (no sudo)
    create_onestack_user
    
    # Setup SSH keys
    setup_ssh_keys
    
    # Add to docker group (will be done after Docker installation)
    save_var "DOCKER_GROUP_PENDING" "true"
    
    success_message "User management completed"
    
    # Important note
    print_warning "═══════════════════════════════════════"
    print_warning "SECURITY NOTE:"
    echo "  • Admin user: $ADMIN_USER (has sudo access)"
    echo "  • Service user: $ONESTACK_USER (no sudo)"
    echo "  • All services will run as: $ONESTACK_USER"
    echo "  • Root login will be disabled after setup"
    print_warning "═══════════════════════════════════════"
    echo ""
}

# Export functions
export -f create_admin_user create_onestack_user setup_ssh_keys add_user_to_docker run_user_management