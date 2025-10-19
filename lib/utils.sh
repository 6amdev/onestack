#!/bin/bash
# OneStack - Utility Functions

# Colors
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export CYAN='\033[0;36m'
export MAGENTA='\033[0;35m'
export NC='\033[0m'

# Print functions
print_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${CYAN}ℹ${NC} $1"
}

print_step() {
    echo -e "${MAGENTA}▶${NC} $1"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root"
        echo "Run: sudo bash $0"
        exit 1
    fi
}

# Check if file exists
check_file() {
    if [ ! -f "$1" ]; then
        print_error "File not found: $1"
        return 1
    fi
    return 0
}

# Generate secure password
generate_password() {
    local length=${1:-16}
    openssl rand -hex "$length" 2>/dev/null || \
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w "$length" | head -n 1
}

# Parse YAML (simple parser)
parse_yaml() {
    local prefix=$2
    local s='[[:space:]]*'
    local w='[a-zA-Z0-9_]*'
    local fs=$(echo @|tr @ '\034')
    
    sed -ne "s|^\($s\):|\1|" \
        -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p" $1 |
    awk -F$fs '{
        indent = length($1)/2;
        vname[indent] = $2;
        for (i in vname) {if (i > indent) {delete vname[i]}}
        if (length($3) > 0) {
            vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
            printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
        }
    }'
}

# Load config from YAML
load_config() {
    local config_file=${1:-config.yml}
    
    if ! check_file "$config_file"; then
        print_error "Config file not found: $config_file"
        exit 1
    fi
    
    # Parse and export variables
    eval $(parse_yaml "$config_file" "CONFIG_")
    
    # Set defaults if not specified
    export ADMIN_USER="${CONFIG_system_admin_user:-admin}"
    export ONESTACK_USER="${CONFIG_system_onestack_user:-onestack}"
    export INSTALL_DIR="${CONFIG_system_install_dir:-/home/$ONESTACK_USER/onestack}"
    export PRIMARY_DOMAIN="${CONFIG_domain_primary:-localhost}"
    export SSL_EMAIL="${CONFIG_domain_ssl_email:-admin@$PRIMARY_DOMAIN}"
    export SSL_MODE="${CONFIG_domain_ssl_mode:-staging}"
    
    # Components
    export INSTALL_PARSE="${CONFIG_components_parse_server:-true}"
    export INSTALL_MONITORING="${CONFIG_components_monitoring:-true}"
    export INSTALL_ADMINER="${CONFIG_components_adminer:-true}"
    
    print_success "Configuration loaded"
}

# Save variable to file
save_var() {
    local var_name=$1
    local var_value=$2
    local file=${3:-/root/.onestack_vars}
    
    # Create or update variable in file
    if [ -f "$file" ]; then
        sed -i "/^export $var_name=/d" "$file"
    fi
    echo "export $var_name='$var_value'" >> "$file"
}

# Load saved variables
load_vars() {
    local file=${1:-/root/.onestack_vars}
    if [ -f "$file" ]; then
        source "$file"
    fi
}

# Create directory with proper ownership
create_dir() {
    local dir=$1
    local owner=${2:-root:root}
    local perms=${3:-755}
    
    mkdir -p "$dir"
    chown "$owner" "$dir"
    chmod "$perms" "$dir"
}

# Install package quietly
install_package() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y -qq "$@" > /dev/null 2>&1
}

# Check if command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Get server IP
get_server_ip() {
    curl -s -4 ifconfig.me 2>/dev/null || \
    ip route get 1 | awk '{print $7}' | head -1 || \
    hostname -I | awk '{print $1}' || \
    echo "N/A"
}

# Confirm action
confirm() {
    local message=${1:-"Continue?"}
    read -p "$message (Y/n): " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Nn]$ ]]
}

# Show progress
show_progress() {
    local pid=$1
    local message=$2
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) %10 ))
        printf "\r${CYAN}${spin:$i:1}${NC} $message"
        sleep 0.1
    done
    
    printf "\r${GREEN}✓${NC} $message\n"
}

# Log message to file
log_message() {
    local level=$1
    shift
    local message="$@"
    local log_file=${LOG_FILE:-/var/log/onestack-install.log}
    
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$log_file"
}

# Error handler
error_exit() {
    print_error "$1"
    log_message "ERROR" "$1"
    exit 1
}

# Success message
success_message() {
    print_success "$1"
    log_message "INFO" "$1"
}

# Export functions
export -f print_header print_success print_error print_warning print_info print_step
export -f check_root check_file generate_password parse_yaml load_config
export -f save_var load_vars create_dir install_package command_exists
export -f get_server_ip confirm show_progress log_message error_exit success_message