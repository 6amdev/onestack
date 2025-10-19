#!/bin/bash
# OneStack - Safe Uninstaller
# Removes OneStack installation with safety checks

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Print functions
print_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════${NC}\n"
}

print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_info() { echo -e "${CYAN}ℹ${NC} $1"; }
print_step() { echo -e "${MAGENTA}▶${NC} $1"; }

confirm() {
    local message=${1:-"Continue?"}
    read -p "$message (Y/n): " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Nn]$ ]]
}

# Parse arguments
DRY_RUN=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --help|-h)
            cat << 'EOF'
OneStack Uninstaller

Usage: sudo bash uninstall.sh [OPTIONS]

Options:
  --dry-run    Show what would be removed without actually removing
  --force      Skip confirmations (dangerous!)
  --help       Show this help message

Examples:
  sudo bash uninstall.sh                # Interactive removal
  sudo bash uninstall.sh --dry-run      # Preview what will be removed
  sudo bash uninstall.sh --force        # Remove without confirmations

EOF
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Run with --help for usage information"
            exit 1
            ;;
    esac
done

# Banner
clear
cat << 'BANNER'
╔═══════════════════════════════════════════════╗
║                                               ║
║           🗑️  OneStack Uninstaller            ║
║                                               ║
║            Remove Installation                ║
║                                               ║
╚═══════════════════════════════════════════════╝
BANNER

echo ""

if [ "$DRY_RUN" = true ]; then
    print_info "DRY RUN MODE - Nothing will be removed"
    echo ""
fi

if [ "$FORCE" = true ]; then
    print_warning "FORCE MODE - Confirmations will be skipped"
    echo ""
fi

print_warning "This will remove OneStack installation"
echo ""

# Check root
if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root"
    echo "Run: sudo bash uninstall.sh"
    exit 1
fi

# Load utilities if available
if [ -f "$SCRIPT_DIR/lib/utils.sh" ]; then
    source "$SCRIPT_DIR/lib/utils.sh"
fi

# Load installation state
INSTALL_DIR=""
ADMIN_USER=""
ONESTACK_USER=""
PRIMARY_DOMAIN=""

if [ -f "/root/.onestack_install_state" ]; then
    # Safe load - handle dates with spaces and special characters
    set +e  # Don't exit on error
    
    while IFS='=' read -r key value; do
        # Skip empty lines and comments
        [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
        
        # Remove quotes and extra whitespace
        value=$(echo "$value" | sed 's/^["'\''[:space:]]*//' | sed 's/["'\''[:space:]]*$//' | tr -d '\n')
        
        # Export only known safe variables
        case "$key" in
            INSTALL_DIR|ADMIN_USER|ONESTACK_USER|PRIMARY_DOMAIN|SSL_EMAIL|SSL_MODE|\
            INSTALL_PARSE|INSTALL_MONITORING|INSTALL_ADMINER|\
            PHASE_*|INSTALLATION_*|DEPLOYMENT_*)
                eval "$key=\"$value\""
                ;;
        esac
    done < "/root/.onestack_install_state"
    
    set -e  # Re-enable exit on error
    
    print_success "Found installation state"
    [ -n "$INSTALL_DIR" ] && print_info "Install directory: $INSTALL_DIR"
    [ -n "$ONESTACK_USER" ] && print_info "Service user: $ONESTACK_USER"
else
    print_warning "No installation state found"
    
    # Set defaults if no state file
    INSTALL_DIR="/opt/onestack"
    ONESTACK_USER="onestack"
    ADMIN_USER="admin"
fi

echo ""

# ════════════════════════════════════════════════
# SCAN SYSTEM
# ════════════════════════════════════════════════

print_header "Scanning System"

# Find OneStack directories
ONESTACK_DIRS=()

if [ -n "$INSTALL_DIR" ] && [ -d "$INSTALL_DIR" ]; then
    ONESTACK_DIRS+=("$INSTALL_DIR")
fi

# Common locations
for dir in "/opt/onestack" "/home/onestack/onestack" "/root/onestack"; do
    if [ -d "$dir" ] && [ -f "$dir/docker-compose.yml" ]; then
        if [[ ! " ${ONESTACK_DIRS[@]} " =~ " ${dir} " ]]; then
            ONESTACK_DIRS+=("$dir")
        fi
    fi
done

if [ ${#ONESTACK_DIRS[@]} -eq 0 ]; then
    print_warning "No OneStack installation found"
    echo ""
    print_info "Possible reasons:"
    echo "  • OneStack not installed yet"
    echo "  • Installation directory moved"
    echo "  • Already uninstalled"
    echo ""
    
    if [ "$FORCE" = false ]; then
        if ! confirm "Continue anyway? (clean up orphaned resources)"; then
            exit 0
        fi
    fi
else
    print_success "Found ${#ONESTACK_DIRS[@]} installation(s):"
    for dir in "${ONESTACK_DIRS[@]}"; do
        echo "  • $dir"
    done
fi

# Check Docker containers
ONESTACK_CONTAINERS=""
CONTAINER_COUNT=0

if command -v docker &>/dev/null; then
    ONESTACK_CONTAINERS=$(docker ps -a --filter "name=onestack" --format "{{.Names}}" 2>/dev/null || true)
    CONTAINER_COUNT=$(echo "$ONESTACK_CONTAINERS" | grep -c . 2>/dev/null || echo 0)
    
    if [ "$CONTAINER_COUNT" -gt 0 ]; then
        print_success "Found $CONTAINER_COUNT OneStack container(s)"
    else
        print_info "No OneStack containers found"
    fi
fi

# Check Docker volumes
ONESTACK_VOLUMES=""
VOLUME_COUNT=0
TOTAL_SIZE_BYTES=0

if command -v docker &>/dev/null; then
    ONESTACK_VOLUMES=$(docker volume ls --filter "name=onestack" --format "{{.Name}}" 2>/dev/null || true)
    VOLUME_COUNT=$(echo "$ONESTACK_VOLUMES" | grep -c . 2>/dev/null || echo 0)
    
    if [ "$VOLUME_COUNT" -gt 0 ]; then
        print_success "Found $VOLUME_COUNT OneStack volume(s)"
        
        # Calculate total size
        for vol in $ONESTACK_VOLUMES; do
            VOL_SIZE=$(docker system df -v 2>/dev/null | grep "$vol" | awk '{print $3}' | sed 's/[^0-9.]//g' || echo "0")
            # Simple size calculation (rough estimate)
            if [ -n "$VOL_SIZE" ] && [ "$VOL_SIZE" != "0" ]; then
                TOTAL_SIZE_BYTES=$(echo "$TOTAL_SIZE_BYTES + $VOL_SIZE" | bc 2>/dev/null || echo "$TOTAL_SIZE_BYTES")
            fi
        done
        
        if [ "$TOTAL_SIZE_BYTES" != "0" ]; then
            # Convert to human readable
            if command -v numfmt &>/dev/null; then
                TOTAL_SIZE=$(echo "$TOTAL_SIZE_BYTES" | numfmt --to=iec-i --suffix=B 2>/dev/null || echo "${TOTAL_SIZE_BYTES}B")
            else
                TOTAL_SIZE="${TOTAL_SIZE_BYTES}MB"
            fi
            echo "  Total data: $TOTAL_SIZE"
        fi
    else
        print_info "No OneStack volumes found"
    fi
fi

# Check Docker networks
ONESTACK_NETWORKS=""
NETWORK_COUNT=0

if command -v docker &>/dev/null; then
    ONESTACK_NETWORKS=$(docker network ls --filter "name=onestack" --format "{{.Name}}" 2>/dev/null || true)
    NETWORK_COUNT=$(echo "$ONESTACK_NETWORKS" | grep -c . 2>/dev/null || echo 0)
    
    if [ "$NETWORK_COUNT" -gt 0 ]; then
        print_success "Found $NETWORK_COUNT OneStack network(s)"
    else
        print_info "No OneStack networks found"
    fi
fi

# Check SSL certificates
SSL_CERT_DIRS=()
CERT_COUNT=0

if [ -d "/etc/letsencrypt/live" ]; then
    CERT_COUNT=$(find /etc/letsencrypt/live -maxdepth 1 -type d | grep -v "^/etc/letsencrypt/live$" | wc -l)
    if [ "$CERT_COUNT" -gt 0 ]; then
        SSL_CERT_DIRS+=("/etc/letsencrypt")
        print_success "Found $CERT_COUNT SSL certificate(s)"
    fi
fi

# Check for orphaned resources
ORPHANED_CONFIGS=()

# Nginx configs
if [ -d "/etc/nginx/sites-enabled" ]; then
    for conf in /etc/nginx/sites-enabled/onestack-*; do
        [ -f "$conf" ] && ORPHANED_CONFIGS+=("$conf")
    done
fi

if [ ${#ORPHANED_CONFIGS[@]} -gt 0 ]; then
    print_warning "Found ${#ORPHANED_CONFIGS[@]} orphaned config file(s)"
fi

echo ""

# ════════════════════════════════════════════════
# REMOVAL OPTIONS
# ════════════════════════════════════════════════

print_header "Removal Options"

if [ "$FORCE" = true ]; then
    # Force mode: full removal
    REMOVAL_OPTION=3
    print_warning "Force mode: Complete removal selected"
else
    echo "What would you like to remove?"
    echo ""
    echo "  1) Containers only (keep data, keep configs)"
    echo "  2) Containers + Volumes (⚠️  DELETE ALL DATA)"
    echo "  3) Complete removal (containers + volumes + configs)"
    echo "  4) Nuclear option (everything + Docker + users)"
    echo "  5) Cancel"
    echo ""
    
    read -p "Select option [1-5]: " REMOVAL_OPTION
fi

case $REMOVAL_OPTION in
    1)
        REMOVE_CONTAINERS=true
        REMOVE_VOLUMES=false
        REMOVE_CONFIGS=false
        REMOVE_DOCKER=false
        REMOVE_USERS=false
        REMOVE_SSL=false
        REMOVE_LOGS=false
        MODE="Containers Only"
        ;;
    2)
        REMOVE_CONTAINERS=true
        REMOVE_VOLUMES=true
        REMOVE_CONFIGS=false
        REMOVE_DOCKER=false
        REMOVE_USERS=false
        REMOVE_SSL=false
        REMOVE_LOGS=false
        MODE="Containers + Volumes"
        ;;
    3)
        REMOVE_CONTAINERS=true
        REMOVE_VOLUMES=true
        REMOVE_CONFIGS=true
        REMOVE_DOCKER=false
        REMOVE_USERS=false
        REMOVE_SSL=false
        REMOVE_LOGS=false
        MODE="Complete Removal"
        ;;
    4)
        REMOVE_CONTAINERS=true
        REMOVE_VOLUMES=true
        REMOVE_CONFIGS=true
        REMOVE_DOCKER=true
        REMOVE_USERS=true
        REMOVE_SSL=false
        REMOVE_LOGS=true
        MODE="Nuclear Option"
        ;;
    5|*)
        print_info "Cancelled"
        exit 0
        ;;
esac

# ════════════════════════════════════════════════
# SSL CERTIFICATE HANDLING
# ════════════════════════════════════════════════

if [ ${#SSL_CERT_DIRS[@]} -gt 0 ] && [ "$FORCE" = false ]; then
    echo ""
    print_warning "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_warning "SSL Certificates Found"
    print_warning "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Let's Encrypt has rate limits:"
    echo "  • 5 certificates per domain per week"
    echo "  • 50 certificates per account per week"
    echo ""
    print_info "Keep certificates to avoid rate limits"
    echo ""
    
    if confirm "Remove SSL certificates? (NOT recommended)"; then
        REMOVE_SSL=true
    else
        REMOVE_SSL=false
        print_success "SSL certificates will be preserved"
    fi
fi

# Log cleanup option
if [ "$REMOVE_CONFIGS" = true ] && [ "$FORCE" = false ]; then
    echo ""
    if confirm "Remove log files? (saves disk space)"; then
        REMOVE_LOGS=true
    else
        REMOVE_LOGS=false
    fi
fi

# ════════════════════════════════════════════════
# BACKUP OPTION
# ════════════════════════════════════════════════

BACKUP_DIR=""

if [ "$REMOVE_VOLUMES" = true ] || [ "$REMOVE_CONFIGS" = true ]; then
    if [ "$FORCE" = false ]; then
        echo ""
        print_header "Backup Option"
        
        print_warning "You are about to delete data/configs"
        echo ""
        
        if confirm "Create backup before removal? (Recommended)"; then
            BACKUP_DIR="/root/onestack-backup-$(date +%Y%m%d-%H%M%S)"
            mkdir -p "$BACKUP_DIR"
            
            print_step "Creating backup..."
            
            # Backup configs
            if [ "$REMOVE_CONFIGS" = true ] && [ ${#ONESTACK_DIRS[@]} -gt 0 ]; then
                for dir in "${ONESTACK_DIRS[@]}"; do
                    if [ -d "$dir" ]; then
                        print_info "Backing up: $dir"
                        DIR_NAME=$(basename "$dir")
                        if [ "$DRY_RUN" = false ]; then
                            cp -r "$dir" "$BACKUP_DIR/$DIR_NAME" 2>/dev/null || print_warning "Failed to backup: $dir"
                        fi
                    fi
                done
            fi
            
            # Backup volumes (export as tar.gz)
            if [ "$REMOVE_VOLUMES" = true ] && [ -n "$ONESTACK_VOLUMES" ]; then
                print_info "Backing up volumes (this may take a while)..."
                for vol in $ONESTACK_VOLUMES; do
                    print_info "  • $vol"
                    if [ "$DRY_RUN" = false ]; then
                        docker run --rm \
                            -v "$vol":/data \
                            -v "$BACKUP_DIR":/backup \
                            alpine tar czf "/backup/${vol}.tar.gz" -C /data . 2>/dev/null || \
                            print_warning "Failed to backup volume: $vol"
                    fi
                done
            fi
            
            # Backup state files
            if [ "$REMOVE_CONFIGS" = true ]; then
                [ -f "/root/.onestack_install_state" ] && cp "/root/.onestack_install_state" "$BACKUP_DIR/" 2>/dev/null
                [ -f "/root/.onestack_vars" ] && cp "/root/.onestack_vars" "$BACKUP_DIR/" 2>/dev/null
            fi
            
            # Create backup info file
            if [ "$DRY_RUN" = false ]; then
                cat > "$BACKUP_DIR/backup-info.txt" << EOF
OneStack Backup
Created: $(date)
Mode: $MODE

Directories backed up: ${#ONESTACK_DIRS[@]}
Volumes backed up: $VOLUME_COUNT

Restore instructions:
1. Copy backup to new server
2. Extract configs: cp -r $BACKUP_DIR/onestack /opt/
3. Restore volumes:
   docker volume create onestack_<name>
   docker run --rm -v onestack_<name>:/data -v $BACKUP_DIR:/backup alpine tar xzf /backup/<volume>.tar.gz -C /data

EOF
            fi
            
            if [ "$DRY_RUN" = false ]; then
                print_success "Backup created: $BACKUP_DIR"
                
                # Calculate backup size
                BACKUP_SIZE=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
                print_info "Backup size: $BACKUP_SIZE"
            else
                print_info "[DRY RUN] Backup would be created: $BACKUP_DIR"
            fi
            
            echo ""
        else
            print_warning "No backup will be created"
            echo ""
        fi
    fi
fi

# ════════════════════════════════════════════════
# CONFIRMATION
# ════════════════════════════════════════════════

if [ "$FORCE" = false ]; then
    echo ""
    print_header "Confirmation Required"
    
    echo "Mode: $MODE"
    echo ""
    echo "This will remove:"
    
    if [ "$REMOVE_CONTAINERS" = true ] && [ "$CONTAINER_COUNT" -gt 0 ]; then
        echo "  ✓ Docker containers ($CONTAINER_COUNT containers)"
    fi
    
    if [ "$REMOVE_VOLUMES" = true ] && [ "$VOLUME_COUNT" -gt 0 ]; then
        echo "  ✓ Docker volumes ($VOLUME_COUNT volumes)"
        print_warning "    ⚠️  ALL DATA WILL BE LOST"
    fi
    
    if [ "$REMOVE_CONTAINERS" = true ] && [ "$NETWORK_COUNT" -gt 0 ]; then
        echo "  ✓ Docker networks ($NETWORK_COUNT networks)"
    fi
    
    if [ "$REMOVE_CONFIGS" = true ] && [ ${#ONESTACK_DIRS[@]} -gt 0 ]; then
        echo "  ✓ Configuration files (${#ONESTACK_DIRS[@]} directories)"
        for dir in "${ONESTACK_DIRS[@]}"; do
            echo "    - $dir"
        done
    fi
    
    if [ "$REMOVE_CONFIGS" = true ] && [ ${#ORPHANED_CONFIGS[@]} -gt 0 ]; then
        echo "  ✓ Orphaned config files (${#ORPHANED_CONFIGS[@]} files)"
    fi
    
    if [ "$REMOVE_DOCKER" = true ]; then
        echo "  ✓ Docker & Docker Compose"
    fi
    
    if [ "$REMOVE_USERS" = true ]; then
        echo "  ✓ Users: $ONESTACK_USER"
        if [ -n "$ADMIN_USER" ] && [ "$ADMIN_USER" != "root" ]; then
            echo "    ⚠️  Admin user ($ADMIN_USER) will NOT be removed"
        fi
    fi
    
    if [ "$REMOVE_SSL" = true ]; then
        echo "  ✓ SSL certificates ($CERT_COUNT certificates)"
    fi
    
    if [ "$REMOVE_LOGS" = true ]; then
        echo "  ✓ Log files"
    fi
    
    echo ""
    echo "This will keep:"
    
    if [ "$REMOVE_VOLUMES" = false ] && [ "$VOLUME_COUNT" -gt 0 ]; then
        echo "  ✓ Data volumes (can be reused)"
    fi
    
    if [ "$REMOVE_CONFIGS" = false ] && [ ${#ONESTACK_DIRS[@]} -gt 0 ]; then
        echo "  ✓ Configuration files"
    fi
    
    if [ "$REMOVE_SSL" = false ] && [ ${#SSL_CERT_DIRS[@]} -gt 0 ]; then
        echo "  ✓ SSL certificates"
    fi
    
    if [ "$REMOVE_DOCKER" = false ] && command -v docker &>/dev/null; then
        echo "  ✓ Docker & Docker Compose"
    fi
    
    if [ -n "$BACKUP_DIR" ]; then
        echo "  ✓ Backup: $BACKUP_DIR"
    fi
    
    echo ""
    print_warning "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_warning "THIS ACTION CANNOT BE UNDONE"
    print_warning "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    if [ "$REMOVE_VOLUMES" = true ]; then
        echo "Type 'DELETE MY DATA' to confirm:"
        read -r CONFIRM
        if [ "$CONFIRM" != "DELETE MY DATA" ]; then
            print_error "Incorrect confirmation"
            exit 1
        fi
    else
        if ! confirm "Continue with removal?"; then
            print_info "Cancelled"
            exit 0
        fi
    fi
    
    # Final countdown
    echo ""
    print_warning "Starting removal in:"
    for i in 5 4 3 2 1; do
        echo -n "$i... "
        sleep 1
    done
    echo ""
    echo ""
fi

# ════════════════════════════════════════════════
# REMOVAL PROCESS
# ════════════════════════════════════════════════

print_header "Removing OneStack"

REMOVED_CONTAINERS=0
REMOVED_VOLUMES=0
REMOVED_NETWORKS=0
REMOVED_CONFIGS=0

# 1. Stop and remove containers
if [ "$REMOVE_CONTAINERS" = true ]; then
    print_step "Stopping containers..."
    
    for dir in "${ONESTACK_DIRS[@]}"; do
        if [ -f "$dir/docker-compose.yml" ]; then
            cd "$dir"
            if [ "$DRY_RUN" = false ]; then
                if docker compose down 2>/dev/null; then
                    print_success "Stopped services in: $dir"
                else
                    print_warning "Could not stop services in: $dir"
                fi
            else
                print_info "[DRY RUN] Would stop services in: $dir"
            fi
        fi
    done
    
    # Remove any remaining containers
    if [ -n "$ONESTACK_CONTAINERS" ]; then
        print_step "Removing remaining containers..."
        for container in $ONESTACK_CONTAINERS; do
            if [ "$DRY_RUN" = false ]; then
                if docker rm -f "$container" 2>/dev/null; then
                    print_success "Removed: $container"
                    REMOVED_CONTAINERS=$((REMOVED_CONTAINERS + 1))
                fi
            else
                print_info "[DRY RUN] Would remove: $container"
            fi
        done
    fi
fi

# 2. Remove Docker networks
if [ "$REMOVE_CONTAINERS" = true ] && [ -n "$ONESTACK_NETWORKS" ]; then
    print_step "Removing Docker networks..."
    
    for network in $ONESTACK_NETWORKS; do
        if [ "$DRY_RUN" = false ]; then
            if docker network rm "$network" 2>/dev/null; then
                print_success "Removed network: $network"
                REMOVED_NETWORKS=$((REMOVED_NETWORKS + 1))
            else
                print_warning "Could not remove network: $network (may be in use)"
            fi
        else
            print_info "[DRY RUN] Would remove network: $network"
        fi
    done
fi

# 3. Remove volumes
if [ "$REMOVE_VOLUMES" = true ] && [ -n "$ONESTACK_VOLUMES" ]; then
    print_step "Removing data volumes..."
    
    for volume in $ONESTACK_VOLUMES; do
        if [ "$DRY_RUN" = false ]; then
            if docker volume rm "$volume" 2>/dev/null; then
                print_success "Removed: $volume"
                REMOVED_VOLUMES=$((REMOVED_VOLUMES + 1))
            else
                print_warning "Could not remove: $volume (may be in use)"
            fi
        else
            print_info "[DRY RUN] Would remove volume: $volume"
        fi
    done
else
    [ "$REMOVE_VOLUMES" = false ] && [ -n "$ONESTACK_VOLUMES" ] && print_info "Data volumes preserved (can be reused)"
fi

# 4. Remove configuration files
if [ "$REMOVE_CONFIGS" = true ]; then
    print_step "Removing configuration files..."
    
    # Remove OneStack directories
    for dir in "${ONESTACK_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            if [ "$DRY_RUN" = false ]; then
                if rm -rf "$dir"; then
                    print_success "Removed: $dir"
                    REMOVED_CONFIGS=$((REMOVED_CONFIGS + 1))
                else
                    print_error "Could not remove: $dir"
                fi
            else
                print_info "[DRY RUN] Would remove: $dir"
            fi
        fi
    done
    
    # Remove state files
    if [ "$DRY_RUN" = false ]; then
        [ -f "/root/.onestack_install_state" ] && rm -f "/root/.onestack_install_state"
        [ -f "/root/.onestack_vars" ] && rm -f "/root/.onestack_vars"
    fi
    
    # Remove orphaned configs
    if [ ${#ORPHANED_CONFIGS[@]} -gt 0 ]; then
        print_step "Removing orphaned config files..."
        for conf in "${ORPHANED_CONFIGS[@]}"; do
            if [ "$DRY_RUN" = false ]; then
                rm -f "$conf" && print_success "Removed: $conf"
            else
                print_info "[DRY RUN] Would remove: $conf"
            fi
        done
    fi
    
    # Remove systemd services (if any)
    if [ -d "/etc/systemd/system" ]; then
        for service in /etc/systemd/system/onestack-*.service; do
            if [ -f "$service" ]; then
                if [ "$DRY_RUN" = false ]; then
                    systemctl stop "$(basename $service)" 2>/dev/null || true
                    systemctl disable "$(basename $service)" 2>/dev/null || true
                    rm -f "$service"
                    print_success "Removed service: $(basename $service)"
                else
                    print_info "[DRY RUN] Would remove service: $(basename $service)"
                fi
            fi
        done
        [ "$DRY_RUN" = false ] && systemctl daemon-reload 2>/dev/null || true
    fi
    
    # Remove cron jobs
    if crontab -l 2>/dev/null | grep -q "onestack"; then
        print_step "Removing cron jobs..."
        if [ "$DRY_RUN" = false ]; then
            crontab -l 2>/dev/null | grep -v "onestack" | crontab - 2>/dev/null || true
            print_success "Cron jobs removed"
        else
            print_info "[DRY RUN] Would remove cron jobs"
        fi
    fi
    
    print_success "Configuration files removed"
fi

# 5. Remove SSL certificates
if [ "$REMOVE_SSL" = true ]; then
    print_step "Removing SSL certificates..."
    
    for dir in "${SSL_CERT_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            if [ "$DRY_RUN" = false ]; then
                if rm -rf "$dir"; then
                    print_success "Removed: $dir"
                else
                    print_error "Could not remove: $dir"
                fi
            else
                print_info "[DRY RUN] Would remove: $dir"
            fi
        fi
    done
fi

# 6. Remove log files
if [ "$REMOVE_LOGS" = true ]; then
    print_step "Removing log files..."
    
    LOG_DIRS=(
        "/var/log/onestack"
        "/var/log/onestack-install.log"
    )
    
    for log in "${LOG_DIRS[@]}"; do
        if [ -e "$log" ]; then
            if [ "$DRY_RUN" = false ]; then
                rm -rf "$log" && print_success "Removed: $log"
            else
                print_info "[DRY RUN] Would remove: $log"
            fi
        fi
    done
fi

# 7. Remove users
if [ "$REMOVE_USERS" = true ]; then
    print_step "Removing users..."
    
    if [ -n "$ONESTACK_USER" ] && id "$ONESTACK_USER" &>/dev/null; then
        if [ "$DRY_RUN" = false ]; then
            if userdel -r "$ONESTACK_USER" 2>/dev/null; then
                print_success "Removed user: $ONESTACK_USER"
            else
                print_warning "Could not remove user: $ONESTACK_USER"
            fi
        else
            print_info "[DRY RUN] Would remove user: $ONESTACK_USER"
        fi
    fi
    
    # Don't remove admin user for safety
    if [ -n "$ADMIN_USER" ] && [ "$ADMIN_USER" != "root" ]; then
        print_info "Admin user preserved: $ADMIN_USER"
    fi
fi

# 8. Remove Docker (if requested)
if [ "$REMOVE_DOCKER" = true ]; then
    print_step "Removing Docker..."
    
    print_warning "This will remove Docker completely!"
    
    if [ "$FORCE" = false ]; then
        if ! confirm "Are you absolutely sure?"; then
            print_info "Docker removal skipped"
            REMOVE_DOCKER=false
        fi
    fi
    
    if [ "$REMOVE_DOCKER" = true ]; then
        if [ "$DRY_RUN" = false ]; then
            systemctl stop docker 2>/dev/null || true
            apt-get purge -y docker-ce docker-ce-cli containerd.io docker-compose-plugin 2>/dev/null || true
            rm -rf /var/lib/docker
            rm -rf /etc/docker
            print_success "Docker removed"
        else
            print_info "[DRY RUN] Would remove Docker"
        fi
    fi
fi

# 9. Clean up Docker system (if Docker still installed)
if command -v docker &>/dev/null && [ "$REMOVE_DOCKER" = false ] && [ "$REMOVE_CONTAINERS" = true ]; then
    print_step "Cleaning Docker system..."
    
    if [ "$FORCE" = false ]; then
        if confirm "Run 'docker system prune' to free up space?"; then
            if [ "$DRY_RUN" = false ]; then
                docker system prune -af --volumes
                print_success "Docker system cleaned"
            else
                print_info "[DRY RUN] Would clean Docker system"
            fi
        fi
    elif [ "$FORCE" = true ]; then
        if [ "$DRY_RUN" = false ]; then
            docker system prune -af --volumes >/dev/null 2>&1
            print_success "Docker system cleaned"
        fi
    fi
fi

# ════════════════════════════════════════════════
# SUMMARY REPORT
# ════════════════════════════════════════════════

echo ""
print_header "Removal Summary"

if [ "$DRY_RUN" = true ]; then
    print_info "DRY RUN - Nothing was actually removed"
    echo ""
fi

echo "Removed:"

if [ "$REMOVE_CONTAINERS" = true ]; then
    echo "  ✓ Containers: $CONTAINER_COUNT"
fi

if [ "$REMOVE_NETWORKS" = true ] && [ "$NETWORK_COUNT" -gt 0 ]; then
    echo "  ✓ Networks: $NETWORK_COUNT"
fi

if [ "$REMOVE_VOLUMES" = true ]; then
    echo "  ✓ Volumes: $VOLUME_COUNT"
fi

if [ "$REMOVE_CONFIGS" = true ]; then
    echo "  ✓ Configuration directories: ${#ONESTACK_DIRS[@]}"
    if [ ${#ORPHANED_CONFIGS[@]} -gt 0 ]; then
        echo "  ✓ Orphaned configs: ${#ORPHANED_CONFIGS[@]}"
    fi
fi

if [ "$REMOVE_SSL" = true ]; then
    echo "  ✓ SSL certificates: $CERT_COUNT"
fi

if [ "$REMOVE_LOGS" = true ]; then
    echo "  ✓ Log files"
fi

if [ "$REMOVE_USERS" = true ]; then
    echo "  ✓ Users: $ONESTACK_USER"
fi

if [ "$REMOVE_DOCKER" = true ]; then
    echo "  ✓ Docker & Docker Compose"
fi

if [ -n "$BACKUP_DIR" ] && [ "$DRY_RUN" = false ]; then
    echo ""
    print_success "Backup saved to: $BACKUP_DIR"
    BACKUP_SIZE=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
    echo "  Size: $BACKUP_SIZE"
    echo ""
    print_info "To restore from backup:"
    echo "  1. Copy $BACKUP_DIR to new server"
    echo "  2. See $BACKUP_DIR/backup-info.txt for instructions"
fi

# Calculate freed space (approximate)
if [ "$REMOVE_VOLUMES" = true ] && [ "$DRY_RUN" = false ]; then
    echo ""
    if command -v docker &>/dev/null; then
        print_success "Docker volumes cleaned"
    fi
    
    # Show remaining Docker usage
    if [ "$REMOVE_DOCKER" = false ] && command -v docker &>/dev/null; then
        echo ""
        print_info "Docker disk usage:"
        docker system df 2>/dev/null || true
    fi
fi

echo ""

# ════════════════════════════════════════════════
# COMPLETION
# ════════════════════════════════════════════════

print_header "Uninstallation Complete"

if [ "$DRY_RUN" = true ]; then
    echo "This was a dry run - nothing was removed"
    echo ""
    print_info "To actually remove, run without --dry-run:"
    echo "  sudo bash uninstall.sh"
else
    echo "OneStack has been removed"
fi

echo ""

if [ "$REMOVE_VOLUMES" = false ] && [ "$VOLUME_COUNT" -gt 0 ]; then
    print_info "Data volumes preserved ($VOLUME_COUNT volumes)"
    echo "  • You can reinstall OneStack and reuse existing data"
    echo "  • Or manually remove with: docker volume ls | grep onestack"
    echo ""
fi

if [ "$REMOVE_SSL" = false ] && [ ${#SSL_CERT_DIRS[@]} -gt 0 ]; then
    print_success "SSL certificates preserved ($CERT_COUNT certificates)"
    echo "  • Can be reused in new installation"
    echo "  • Location: /etc/letsencrypt"
    echo ""
fi

if [ "$REMOVE_DOCKER" = false ] && command -v docker &>/dev/null; then
    print_success "Docker still installed"
    echo "  • Ready for new OneStack installation"
    echo "  • Run: sudo bash install.sh"
    echo ""
fi

if [ -n "$BACKUP_DIR" ] && [ "$DRY_RUN" = false ]; then
    print_success "Backup available at: $BACKUP_DIR"
    echo ""
fi

if [ "$DRY_RUN" = false ]; then
    print_success "Uninstallation completed successfully! ✓"
else
    print_success "Dry run completed! ✓"
fi

echo ""