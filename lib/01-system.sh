#!/bin/bash
# OneStack - System Preparation

source "$(dirname "$0")/utils.sh"

system_prepare() {
    print_header "System Preparation"
    
    # Check OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        print_success "OS: $PRETTY_NAME"
        
        if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
            print_warning "This installer is optimized for Ubuntu/Debian"
            if ! confirm "Continue anyway?"; then
                exit 0
            fi
        fi
    fi
    
    # Check resources
    local total_ram=$(free -m | awk 'NR==2 {print $2}')
    local available_disk=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    
    if [ "$total_ram" -lt 2000 ]; then
        print_warning "RAM: ${total_ram}MB (2GB+ recommended)"
    else
        print_success "RAM: ${total_ram}MB"
    fi
    
    if [ "$available_disk" -lt 20 ]; then
        print_warning "Disk: ${available_disk}GB (20GB+ recommended)"
    else
        print_success "Disk: ${available_disk}GB"
    fi
    
    # Get server IP
    local server_ip=$(get_server_ip)
    print_success "Server IP: $server_ip"
    save_var "SERVER_IP" "$server_ip"
    
    echo ""
}

system_update() {
    print_header "Updating System"
    
    print_step "Updating package lists..."
    export DEBIAN_FRONTEND=noninteractive
    
    if apt-get update -qq 2>&1 | tee -a /var/log/onestack-install.log; then
        print_success "Package lists updated"
    else
        error_exit "Failed to update package lists"
    fi
    
    print_step "Upgrading packages..."
    if apt-get upgrade -y -qq 2>&1 | tee -a /var/log/onestack-install.log; then
        print_success "Packages upgraded"
    else
        print_warning "Package upgrade had issues (continuing)"
    fi
    
    echo ""
}

system_install_essentials() {
    print_header "Installing Essential Tools"
    
    local packages=(
        "curl"
        "wget"
        "git"
        "nano"
        "vim"
        "ufw"
        "fail2ban"
        "openssl"
        "ca-certificates"
        "gnupg"
        "lsb-release"
        "software-properties-common"
    )
    
    print_step "Installing: ${packages[*]}"
    
    if install_package "${packages[@]}"; then
        print_success "Essential tools installed"
    else
        error_exit "Failed to install essential tools"
    fi
    
    echo ""
}

system_check() {
    print_header "System Checks"
    
    # Check if already installed
    if [ -d "$INSTALL_DIR" ] && [ "$(ls -A $INSTALL_DIR 2>/dev/null)" ]; then
        print_warning "OneStack directory already exists: $INSTALL_DIR"
        
        if confirm "Remove existing installation?"; then
            print_step "Cleaning existing installation..."
            
            # Stop services if running
            if [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
                cd "$INSTALL_DIR"
                docker compose down -v 2>/dev/null || true
            fi
            
            # Remove directory
            rm -rf "$INSTALL_DIR"
            print_success "Existing installation removed"
        else
            error_exit "Installation cancelled"
        fi
    fi
    
    echo ""
}

# Run all system preparation steps
run_system_preparation() {
    check_root
    system_prepare
    
    if confirm "Continue with system update?"; then
        system_update
        system_install_essentials
    else
        print_info "Skipping system update"
    fi
    
    system_check
    
    success_message "System preparation completed"
}

# Export functions
export -f system_prepare system_update system_install_essentials system_check run_system_preparation