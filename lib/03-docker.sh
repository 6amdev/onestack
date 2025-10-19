#!/bin/bash
# OneStack - Docker Installation

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LIB_DIR/utils.sh"

check_docker() {
    if command_exists docker; then
        local version=$(docker --version | cut -d' ' -f3 | cut -d',' -f1)
        print_success "Docker already installed: $version"
        return 0
    fi
    return 1
}

install_docker() {
    print_header "Docker Installation"
    
    if check_docker; then
        if confirm "Reinstall Docker?"; then
            print_step "Removing old Docker..."
            apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
        else
            return 0
        fi
    fi
    
    print_step "Installing Docker..."
    
    # Add Docker's GPG key
    print_info "Adding Docker repository..."
    mkdir -p /etc/apt/keyrings
    
    if curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
       gpg --dearmor -o /etc/apt/keyrings/docker.gpg; then
        print_success "GPG key added"
    else
        error_exit "Failed to add Docker GPG key"
    fi
    
    # Add Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Update and install
    print_step "Installing Docker packages..."
    apt-get update -qq
    
    if install_package docker-ce docker-ce-cli containerd.io docker-compose-plugin; then
        print_success "Docker installed"
    else
        error_exit "Failed to install Docker"
    fi
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    
    # Verify installation
    if docker --version &>/dev/null && docker compose version &>/dev/null; then
        print_success "Docker: $(docker --version | cut -d' ' -f3 | cut -d',' -f1)"
        print_success "Docker Compose: $(docker compose version --short)"
    else
        error_exit "Docker verification failed"
    fi
    
    save_var "DOCKER_INSTALLED" "true"
    
    echo ""
}

configure_docker() {
    print_header "Docker Configuration"
    
    # Create Docker daemon configuration
    local daemon_config="/etc/docker/daemon.json"
    
    print_step "Configuring Docker daemon..."
    
    cat > "$daemon_config" << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "live-restore": true
}
EOF
    
    if [ $? -eq 0 ]; then
        print_success "Docker daemon configured"
        
        # Restart Docker
        print_step "Restarting Docker..."
        systemctl restart docker
        sleep 2
        
        if systemctl is-active --quiet docker; then
            print_success "Docker restarted"
        else
            error_exit "Docker failed to restart"
        fi
    else
        print_warning "Failed to configure Docker daemon"
    fi
    
    echo ""
}

add_users_to_docker_group() {
    print_header "Docker Group Setup"
    
    # Check if pending from user management
    load_vars
    
    if [ "$DOCKER_GROUP_PENDING" = "true" ]; then
        for user in "$ADMIN_USER" "$ONESTACK_USER"; do
            if id "$user" &>/dev/null; then
                if usermod -aG docker "$user"; then
                    print_success "$user added to docker group"
                else
                    print_warning "Failed to add $user to docker group"
                fi
            fi
        done
        
        save_var "DOCKER_GROUP_PENDING" "false"
        
        print_info "Log out and back in for docker group to take effect"
    fi
    
    echo ""
}

test_docker() {
    print_header "Docker Test"
    
    print_step "Running test container..."
    
    if docker run --rm hello-world &>/dev/null; then
        print_success "Docker is working correctly"
    else
        print_error "Docker test failed"
        return 1
    fi
    
    echo ""
}

run_docker_installation() {
    check_root
    
    install_docker
    configure_docker
    add_users_to_docker_group
    test_docker
    
    success_message "Docker installation completed"
}

# Export functions
export -f check_docker install_docker configure_docker add_users_to_docker_group test_docker run_docker_installation