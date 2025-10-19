#!/bin/bash
# OneStack - User Management

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LIB_DIR/utils.sh"

create_admin_user() {
    print_header "Creating Admin User"
    
    local admin_user="$ADMIN_USER"
    
    # Check if user exists
    if id "$admin_user" &>/dev/null; then
        print_warning "User '$admin_user' already exists"
        
        # Check if user is in sudo group
        if groups "$admin_user" | grep -q sudo; then
            print_success "User already has sudo access"
        else
            print_step "Adding sudo privileges..."
            usermod -aG sudo "$admin_user"
            print_success "Added to sudo group"
        fi
        
        save_var "ADMIN_USER_CREATED" "true"
        return 0
    fi
    
    print_step "Creating user: $admin_user"
    
    # Check if group with same name exists
    if getent group "$admin_user" &>/dev/null; then
        print_info "Group '$admin_user' exists, using different group name"
        # Create user with default group, then add to sudo
        if useradd -m -s /bin/bash "$admin_user" 2>/dev/null; then
            print_success "User created: $admin_user"
        else
            # If still fails, try with explicit group
            if useradd -m -s /bin/bash -g users "$admin_user"; then
                print_success "User created: $admin_user (in users group)"
            else
                error_exit "Failed to create user: $admin_user"
            fi
        fi
    else
        # Normal creation
        if useradd -m -s /bin/bash "$admin_user"; then
            print_success "User created: $admin_user"
        else
            error_exit "Failed to create user: $admin_user"
        fi
    fi
    
    # Add to sudo group
    if usermod -aG sudo "$admin_user"; then
        print_success "Added to sudo group"
    else
        error_exit "Failed to add sudo privileges"
    fi
    
    # Set password
    print_info "Set password for '$admin_user':"
    local password_set=false
    local attempts=0
    local max_attempts=3
    
    while [ "$password_set" = false ] && [ $attempts -lt $max_attempts ]; do
        if passwd "$admin_user"; then
            password_set=true
            print_success "Password set successfully"
        else
            attempts=$((attempts + 1))
            if [ $attempts -lt $max_attempts ]; then
                print_error "Password setting failed, try again ($attempts/$max_attempts)"
            else
                error_exit "Failed to set password after $max_attempts attempts"
            fi
        fi
    done
    
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
        save_var "ONESTACK_USER_CREATED" "true"
        return 0
    fi
    
    print_step "Creating service user: $onestack_user"
    
    # Check if group with same name exists
    if getent group "$onestack_user" &>/dev/null; then
        print_info "Group '$onestack_user' exists, using different group name"
        # Create user with default group
        if useradd -m -s /bin/bash "$onestack_user" 2>/dev/null; then
            print_success "User created: $onestack_user"
        else
            # Try with explicit group
            if useradd -m -s /bin/bash -g users "$onestack_user"; then
                print_success "User created: $onestack_user (in users group)"
            else
                error_exit "Failed to create user: $onestack_user"
            fi
        fi
    else
        # Normal creation
        if useradd -m -s /bin/bash "$onestack_user"; then
            print_success "User created: $onestack_user"
        else
            error_exit "Failed to create user: $onestack_user"
        fi
    fi
    
    # No password needed (will use sudo -u or su)
    print_info "Service user created (no password, no sudo access)"
    
    # Create necessary directories
    local install_dir="/home/$onestack_user/onestack"
    if [ ! -d "$install_dir" ]; then
        create_dir "$install_dir" "$onestack_user:$onestack_user" "755"
        print_success "Installation directory: $install_dir"
    fi
    
    save_var "INSTALL_DIR" "$install_dir"
    save_var "ONESTACK_USER_CREATED" "true"
    
    echo ""
}

setup_ssh_keys() {
    print_header "SSH Key Setup"
    
    local admin_user="$ADMIN_USER"
    
    if ! id "$admin_user" &>/dev/null; then
        print_error "Admin user not found, skipping SSH setup"
        return 1
    fi
    
    if confirm "Set up SSH key authentication for $admin_user?"; then
        print_step "Setting up SSH directory..."
        
        local ssh_dir="/home/$admin_user/.ssh"
        local home_dir="/home/$admin_user"
        
        # Create .ssh directory
        if [ ! -d "$ssh_dir" ]; then
            mkdir -p "$ssh_dir"
            chmod 700 "$ssh_dir"
            chown "$admin_user:$admin_user" "$ssh_dir"
        fi
        
        # Create authorized_keys
        if [ ! -f "$ssh_dir/authorized_keys" ]; then
            touch "$ssh_dir/authorized_keys"
            chmod 600 "$ssh_dir/authorized_keys"
            chown "$admin_user:$admin_user" "$ssh_dir/authorized_keys"
        fi
        
        # Fix ownership
        chown -R "$admin_user:$admin_user" "$home_dir/.ssh"
        
        print_success "SSH directory ready"
        print_info "Add your public key to: $ssh_dir/authorized_keys"
        
        echo ""
        print_warning "IMPORTANT: Test SSH key login before disabling password auth!"
        echo ""
    fi
}

add_user_to_docker() {
    print_header "Docker Group Membership"
    
    # This will be called after Docker installation
    # For now, just save that it's pending
    save_var "DOCKER_GROUP_PENDING" "true"
    print_info "Docker group membership will be set after Docker installation"
    
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
    add_user_to_docker
    
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