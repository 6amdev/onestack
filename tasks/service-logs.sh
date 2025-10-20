#!/bin/bash
# ═══════════════════════════════════════════════════
# OneStack - Service Logs Viewer Task
# ═══════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

# ═══════════════════════════════════════════════════
# Main Log Viewer
# ═══════════════════════════════════════════════════

main() {
    print_header "View Service Logs"
    
    cd /opt/onestack || exit 1
    
    # Show services
    echo ""
    print_info "Available services:"
    echo ""
    
    docker compose ps --format "table {{.Name}}\t{{.Status}}" | nl -w2 -s'. '
    
    echo ""
    echo "Special options:"
    echo "  0. All services"
    echo ""
    
    # Get selection
    read -p "Enter service number (or name): " selection
    
    # Handle "all" option
    if [ "$selection" = "0" ]; then
        SERVICE="all"
    elif [[ "$selection" =~ ^[0-9]+$ ]]; then
        SERVICE=$(docker compose ps --format "{{.Name}}" | sed -n "${selection}p")
    else
        SERVICE="$selection"
    fi
    
    # Get number of lines
    echo ""
    read -p "Number of lines to show (default: 50): " lines
    lines=${lines:-50}
    
    # Ask for follow mode
    echo ""
    read -p "Follow logs in real-time? (y/N): " follow
    
    echo ""
    
    # Show logs
    if [ "$SERVICE" = "all" ]; then
        print_info "Showing logs for all services..."
        echo ""
        
        if [ "$follow" = "y" ]; then
            docker compose logs -f --tail="$lines"
        else
            docker compose logs --tail="$lines"
        fi
    else
        if [ -z "$SERVICE" ]; then
            print_error "Invalid service"
            exit 1
        fi
        
        print_info "Showing logs for: $SERVICE"
        echo ""
        
        if [ "$follow" = "y" ]; then
            docker compose logs -f --tail="$lines" "$SERVICE"
        else
            docker compose logs --tail="$lines" "$SERVICE"
        fi
    fi
}

# Run
main