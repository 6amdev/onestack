#!/bin/bash
# ═══════════════════════════════════════════════════
# Task: Validate Installation
# Description: Validate OneStack installation completeness
# ═══════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Validation results
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNINGS=0

# ═══════════════════════════════════════════════════
# Check Functions
# ═══════════════════════════════════════════════════

check_pass() {
    echo -e "  ${GREEN}✓${NC} $1"
    ((PASSED_CHECKS++))
    ((TOTAL_CHECKS++))
}

check_fail() {
    echo -e "  ${RED}✗${NC} $1"
    if [ -n "$2" ]; then
        echo -e "    ${RED}└─${NC} $2"
    fi
    ((FAILED_CHECKS++))
    ((TOTAL_CHECKS++))
}

check_warn() {
    echo -e "  ${YELLOW}⚠${NC} $1"
    if [ -n "$2" ]; then
        echo -e "    ${YELLOW}└─${NC} $2"
    fi
    ((WARNINGS++))
}

# ═══════════════════════════════════════════════════
# Validate Directory Structure
# ═══════════════════════════════════════════════════

validate_directories() {
    print_header "Validating Directory Structure"
    
    local required_dirs=(
        "/opt/onestack"
        "/opt/onestack/nginx"
        "/opt/onestack/nginx/conf.d"
        "/opt/onestack/databases"
        "/opt/onestack/frontends"
        "/opt/onestack/monitoring"
        "/opt/onestack/backups"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [ -d "$dir" ]; then
            check_pass "Directory exists: $dir"
        else
            check_fail "Directory missing: $dir"
        fi
    done
    
    echo ""
}

# ═══════════════════════════════════════════════════
# Validate Configuration Files
# ═══════════════════════════════════════════════════

validate_config_files() {
    print_header "Validating Configuration Files"
    
    # Critical files
    local critical_files=(
        "/opt/onestack/docker-compose.yml"
        "/opt/onestack/.env"
    )
    
    for file in "${critical_files[@]}"; do
        if [ -f "$file" ]; then
            check_pass "File exists: $file"
            
            # Check if readable
            if [ -r "$file" ]; then
                check_pass "File readable: $(basename $file)"
            else
                check_fail "File not readable: $(basename $file)"
            fi
        else
            check_fail "File missing: $file" "Installation may be incomplete"
        fi
    done
    
    echo ""
    
    # Validate .env file content
    if [ -f "/opt/onestack/.env" ]; then
        print_header "Validating .env Configuration"
        
        local required_vars=(
            "DOMAIN"
            "POSTGRES_PASSWORD"
            "MONGODB_PASSWORD"
            "REDIS_PASSWORD"
            "MINIO_ROOT_PASSWORD"
        )
        
        for var in "${required_vars[@]}"; do
            if grep -q "^${var}=" /opt/onestack/.env; then
                local value=$(grep "^${var}=" /opt/onestack/.env | cut -d= -f2)
                if [ -n "$value" ]; then
                    check_pass "$var is set"
                else
                    check_fail "$var is empty"
                fi
            else
                check_fail "$var not found in .env"
            fi
        done
        
        echo ""
    fi
}

# ═══════════════════════════════════════════════════
# Validate Docker Compose
# ═══════════════════════════════════════════════════

validate_docker_compose() {
    print_header "Validating Docker Compose"
    
    cd /opt/onestack
    
    # Validate syntax
    if docker compose config &> /dev/null; then
        check_pass "docker-compose.yml syntax is valid"
    else
        check_fail "docker-compose.yml syntax is invalid"
        echo ""
        print_info "Run: docker compose config"
        return 1
    fi
    
    # Count services
    local service_count=$(docker compose config --services 2>/dev/null | wc -l)
    if [ "$service_count" -gt 0 ]; then
        check_pass "Found $service_count services defined"
    else
        check_fail "No services found in docker-compose.yml"
    fi
    
    # Expected services
    local expected_services=(
        "nginx"
        "postgres"
        "mongodb"
        "redis"
        "minio"
        "parse-server"
        "parse-dashboard"
        "grafana"
        "prometheus"
        "adminer"
    )
    
    echo ""
    print_info "Checking expected services..."
    
    for service in "${expected_services[@]}"; do
        if docker compose config --services 2>/dev/null | grep -q "^${service}$"; then
            check_pass "Service defined: $service"
        else
            check_warn "Service not defined: $service" "May be optional"
        fi
    done
    
    echo ""
}

# ═══════════════════════════════════════════════════
# Validate Running Containers
# ═══════════════════════════════════════════════════

validate_containers() {
    print_header "Validating Running Containers"
    
    cd /opt/onestack
    
    # Get defined services
    local services=($(docker compose config --services 2>/dev/null))
    
    if [ ${#services[@]} -eq 0 ]; then
        check_fail "No services found"
        return 1
    fi
    
    local running=0
    local stopped=0
    
    for service in "${services[@]}"; do
        local status=$(docker compose ps "$service" --format '{{.Status}}' 2>/dev/null)
        
        if [[ "$status" == *"Up"* ]] || [[ "$status" == *"running"* ]]; then
            check_pass "$service is running"
            ((running++))
        else
            check_fail "$service is not running" "$status"
            ((stopped++))
        fi
    done
    
    echo ""
    print_info "Summary: $running running, $stopped stopped"
    echo ""
}

# ═══════════════════════════════════════════════════
# Validate Network
# ═══════════════════════════════════════════════════

validate_network() {
    print_header "Validating Docker Network"
    
    # Check for OneStack networks
    local networks=($(docker network ls --filter "name=onestack" --format "{{.Name}}" 2>/dev/null))
    
    if [ ${#networks[@]} -gt 0 ]; then
        check_pass "Found ${#networks[@]} Docker network(s)"
        for net in "${networks[@]}"; do
            print_info "  - $net"
        done
    else
        check_warn "No OneStack networks found" "Networks may be created on first start"
    fi
    
    echo ""
}

# ═══════════════════════════════════════════════════
# Validate Volumes
# ═══════════════════════════════════════════════════

validate_volumes() {
    print_header "Validating Docker Volumes"
    
    # Check for OneStack volumes
    local volumes=($(docker volume ls --filter "name=onestack" --format "{{.Name}}" 2>/dev/null))
    
    if [ ${#volumes[@]} -gt 0 ]; then
        check_pass "Found ${#volumes[@]} Docker volume(s)"
        
        # Expected volumes
        local expected_volumes=(
            "postgres_data"
            "mongodb_data"
            "redis_data"
            "minio_data"
        )
        
        echo ""
        print_info "Checking critical volumes..."
        
        for vol in "${expected_volumes[@]}"; do
            if docker volume ls --format "{{.Name}}" 2>/dev/null | grep -q "$vol"; then
                check_pass "Volume exists: $vol"
            else
                check_warn "Volume not found: $vol" "Will be created on first start"
            fi
        done
    else
        check_warn "No OneStack volumes found" "Volumes will be created on first start"
    fi
    
    echo ""
}

# ═══════════════════════════════════════════════════
# Validate Ports
# ═══════════════════════════════════════════════════

validate_ports() {
    print_header "Validating Port Availability"
    
    local critical_ports=(
        "80:HTTP"
        "443:HTTPS"
    )
    
    for port_info in "${critical_ports[@]}"; do
        local port=$(echo "$port_info" | cut -d: -f1)
        local name=$(echo "$port_info" | cut -d: -f2)
        
        if netstat -tuln 2>/dev/null | grep -q ":${port} "; then
            check_pass "Port $port ($name) is in use"
        else
            check_warn "Port $port ($name) is not in use" "Service may not be started"
        fi
    done
    
    echo ""
}

# ═══════════════════════════════════════════════════
# Validate SSL Configuration (if domain set)
# ═══════════════════════════════════════════════════

validate_ssl() {
    print_header "Validating SSL Configuration"
    
    local DOMAIN=$(grep "^DOMAIN=" /opt/onestack/.env 2>/dev/null | cut -d= -f2)
    
    if [ -z "$DOMAIN" ]; then
        check_warn "Domain not configured in .env"
        echo ""
        return
    fi
    
    print_info "Checking SSL for domain: $DOMAIN"
    echo ""
    
    # Check Let's Encrypt directory
    if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
        check_pass "SSL certificate directory exists"
        
        # Check certificate files
        local cert_files=(
            "cert.pem"
            "chain.pem"
            "fullchain.pem"
            "privkey.pem"
        )
        
        for file in "${cert_files[@]}"; do
            if [ -f "/etc/letsencrypt/live/$DOMAIN/$file" ]; then
                check_pass "Certificate file exists: $file"
            else
                check_fail "Certificate file missing: $file"
            fi
        done
        
        # Check expiry
        if [ -f "/etc/letsencrypt/live/$DOMAIN/cert.pem" ]; then
            local expiry=$(openssl x509 -in "/etc/letsencrypt/live/$DOMAIN/cert.pem" -noout -enddate 2>/dev/null | cut -d= -f2)
            
            if [ -n "$expiry" ]; then
                local expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null)
                local now_epoch=$(date +%s)
                local days_left=$(( ($expiry_epoch - $now_epoch) / 86400 ))
                
                if [ $days_left -gt 30 ]; then
                    check_pass "Certificate valid for $days_left days"
                elif [ $days_left -gt 7 ]; then
                    check_warn "Certificate expires in $days_left days" "Consider renewal"
                else
                    check_fail "Certificate expires in $days_left days" "Renewal required!"
                fi
            fi
        fi
    else
        check_warn "SSL not configured for $DOMAIN" "Run SSL setup if needed"
    fi
    
    echo ""
}

# ═══════════════════════════════════════════════════
# Validate System Resources
# ═══════════════════════════════════════════════════

validate_resources() {
    print_header "Validating System Resources"
    
    # Disk space
    local available=$(df -h /opt/onestack 2>/dev/null | tail -1 | awk '{print $4}')
    local used_percent=$(df -h /opt/onestack 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%')
    
    print_info "Disk space: $used_percent% used, $available available"
    
    if [ "$used_percent" -lt 80 ]; then
        check_pass "Sufficient disk space"
    elif [ "$used_percent" -lt 90 ]; then
        check_warn "Disk usage at $used_percent%" "Monitor disk space"
    else
        check_fail "Disk usage at $used_percent%" "Critical! Clean up required"
    fi
    
    # Memory
    local total_mem=$(free -m | awk 'NR==2{print $2}')
    local used_mem=$(free -m | awk 'NR==2{print $3}')
    local mem_percent=$((used_mem * 100 / total_mem))
    
    print_info "Memory: $mem_percent% used ($used_mem/$total_mem MB)"
    
    if [ "$mem_percent" -lt 80 ]; then
        check_pass "Sufficient memory"
    elif [ "$mem_percent" -lt 90 ]; then
        check_warn "Memory usage at $mem_percent%" "Monitor memory"
    else
        check_fail "Memory usage at $mem_percent%" "Consider adding more RAM"
    fi
    
    echo ""
}

# ═══════════════════════════════════════════════════
# Generate Installation Report
# ═══════════════════════════════════════════════════

generate_report() {
    print_header "Validation Report"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "  Total Checks:  $TOTAL_CHECKS"
    echo -e "  ${GREEN}Passed:${NC}        $PASSED_CHECKS"
    echo -e "  ${RED}Failed:${NC}        $FAILED_CHECKS"
    echo -e "  ${YELLOW}Warnings:${NC}      $WARNINGS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Calculate score
    if [ $TOTAL_CHECKS -gt 0 ]; then
        local score=$((PASSED_CHECKS * 100 / TOTAL_CHECKS))
        
        if [ $score -eq 100 ] && [ $WARNINGS -eq 0 ]; then
            echo -e "  ${GREEN}✓ Installation Status: PERFECT (100%)${NC}"
            echo ""
            echo "  🎉 OneStack is perfectly configured!"
            echo "  All systems operational and ready for production."
        elif [ $score -ge 90 ]; then
            echo -e "  ${GREEN}✓ Installation Status: EXCELLENT ($score%)${NC}"
            echo ""
            echo "  ✅ OneStack is properly installed and functional."
            if [ $WARNINGS -gt 0 ]; then
                echo "  ⚠️  Some minor warnings to review."
            fi
        elif [ $score -ge 70 ]; then
            echo -e "  ${YELLOW}⚠ Installation Status: GOOD ($score%)${NC}"
            echo ""
            echo "  ⚠️  Installation is functional but needs attention."
            echo "  Review failed checks and warnings above."
        elif [ $score -ge 50 ]; then
            echo -e "  ${YELLOW}⚠ Installation Status: FAIR ($score%)${NC}"
            echo ""
            echo "  ⚠️  Multiple issues detected."
            echo "  System may not function properly."
            echo "  Review and fix failed checks."
        else
            echo -e "  ${RED}✗ Installation Status: POOR ($score%)${NC}"
            echo ""
            echo "  ❌ Critical installation issues detected."
            echo "  System likely not functional."
            echo "  Consider re-installing or fixing issues manually."
        fi
    fi
    
    echo ""
    
    # Next steps
    if [ $FAILED_CHECKS -gt 0 ]; then
        print_header "Recommended Actions"
        echo ""
        echo "  1. Review failed checks above"
        echo "  2. Fix configuration issues"
        echo "  3. Restart affected services"
        echo "  4. Run validation again"
        echo ""
        echo "  For help: ./manage.sh or check documentation"
        echo ""
    fi
    
    # Return exit code based on failures
    if [ $FAILED_CHECKS -gt 0 ]; then
        return 1
    else
        return 0
    fi
}

# ═══════════════════════════════════════════════════
# Main Validation Runner
# ═══════════════════════════════════════════════════

main() {
    clear
    print_header "OneStack Installation Validation"
    echo ""
    print_info "Performing comprehensive installation validation..."
    echo ""
    
    # Check if OneStack is installed
    if [ ! -d "/opt/onestack" ]; then
        print_error "OneStack is not installed"
        print_info "Expected directory: /opt/onestack"
        exit 1
    fi
    
    # Run all validation checks
    validate_directories
    validate_config_files
    validate_docker_compose
    validate_containers
    validate_network
    validate_volumes
    validate_ports
    validate_ssl
    validate_resources
    
    # Generate final report
    generate_report
    
    # Exit with appropriate code
    exit $?
}

main "$@"