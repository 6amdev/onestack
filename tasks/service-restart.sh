#!/bin/bash
# ═══════════════════════════════════════════════════
# OneStack - Service Restart Task
# ═══════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

# ═══════════════════════════════════════════════════
# Main Service Restart
# ═══════════════════════════════════════════════════

main() {
    print_header "Restart Service"
    
    cd /opt/onestack || exit 1
    
    # Show current services
    echo ""
    print_info "Current services:"
    echo ""
    
    docker compose ps --format "table {{.Name}}\t{{.Status}}" | nl -w2 -s'. '
    
    echo ""
    
    # Get service selection
    read -p "Enter service number (or name): " selection
    
    # Get service name
    if [[ "$selection" =~ ^[0-9]+$ ]]; then
        SERVICE=$(docker compose ps --format "{{.Name}}" | sed -n "${selection}p")
    else
        SERVICE="$selection"
    fi
    
    # Validate
    if [ -z "$SERVICE" ]; then
        print_error "Invalid service selection"
        exit 1
    fi
    
    # Check if service exists
    if ! docker compose ps | grep -q "$SERVICE"; then
        print_error "Service not found: $SERVICE"
        exit 1
    fi
    
    # Confirm
    echo ""
    print_warning "This will restart: $SERVICE"
    read -p "Continue? (Y/n): " confirm
    
    [ "$confirm" = "n" ] && exit 0
    
    # Restart
    print_step "Restarting $SERVICE..."
    
    docker compose restart "$SERVICE"
    
    if [ $? -eq 0 ]; then
        print_success "Service restarted successfully"
        
        # Wait a moment
        sleep 3
        
        # Check status
        echo ""
        print_step "Checking service status..."
        echo ""
        
        docker compose ps "$SERVICE"
        
        # Check logs for errors
        echo ""
        print_step "Recent logs:"
        echo ""
        
        docker compose logs --tail=20 "$SERVICE"
        
    else
        print_error "Failed to restart service"
        echo ""
        print_info "Check logs:"
        print_info "  docker compose -f /opt/onestack/docker-compose.yml logs $SERVICE"
        exit 1
    fi
}

# Run
main