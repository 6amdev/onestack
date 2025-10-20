#!/bin/bash
# ═══════════════════════════════════════════════════
# Task: Test All Services
# Description: Comprehensive service testing
# ═══════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

# Colors for test results
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNINGS=0

# ═══════════════════════════════════════════════════
# Test Result Functions
# ═══════════════════════════════════════════════════

test_pass() {
    echo -e "  ${GREEN}✓${NC} $1"
    ((PASSED_TESTS++))
    ((TOTAL_TESTS++))
}

test_fail() {
    echo -e "  ${RED}✗${NC} $1"
    if [ -n "$2" ]; then
        echo -e "    ${RED}└─${NC} $2"
    fi
    ((FAILED_TESTS++))
    ((TOTAL_TESTS++))
}

test_warn() {
    echo -e "  ${YELLOW}⚠${NC} $1"
    if [ -n "$2" ]; then
        echo -e "    ${YELLOW}└─${NC} $2"
    fi
    ((WARNINGS++))
}

test_info() {
    echo -e "  ${YELLOW}ℹ${NC} $1"
}

# ═══════════════════════════════════════════════════
# Docker Tests
# ═══════════════════════════════════════════════════

test_docker() {
    print_header "Testing Docker"
    
    # Docker installed
    if command -v docker &> /dev/null; then
        test_pass "Docker is installed"
        docker --version | sed 's/^/    /'
    else
        test_fail "Docker is not installed"
        return 1
    fi
    
    # Docker running
    if docker info &> /dev/null; then
        test_pass "Docker daemon is running"
    else
        test_fail "Docker daemon is not running"
        return 1
    fi
    
    # Docker Compose
    if docker compose version &> /dev/null; then
        test_pass "Docker Compose is available"
        docker compose version | sed 's/^/    /'
    else
        test_fail "Docker Compose is not available"
    fi
    
    echo ""
}

# ═══════════════════════════════════════════════════
# Container Tests
# ═══════════════════════════════════════════════════

test_containers() {
    print_header "Testing Containers"
    
    cd /opt/onestack
    
    # Get all services from docker-compose.yml
    local services=($(docker compose config --services 2>/dev/null))
    
    if [ ${#services[@]} -eq 0 ]; then
        test_fail "No services found in docker-compose.yml"
        return 1
    fi
    
    test_info "Found ${#services[@]} services in docker-compose.yml"
    echo ""
    
    for service in "${services[@]}"; do
        echo "Testing: $service"
        
        # Check if container exists
        local container=$(docker compose ps -q "$service" 2>/dev/null)
        if [ -z "$container" ]; then
            test_fail "$service: Container not found"
            continue
        fi
        
        # Check container status
        local status=$(docker compose ps "$service" --format '{{.Status}}' 2>/dev/null)
        
        if [[ "$status" == *"Up"* ]] || [[ "$status" == *"running"* ]]; then
            test_pass "$service: Running"
            
            # Check health (if healthcheck defined)
            local health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null)
            if [ "$health" = "healthy" ]; then
                test_pass "$service: Healthy"
            elif [ "$health" = "unhealthy" ]; then
                test_fail "$service: Unhealthy"
            fi
        else
            test_fail "$service: Not running" "$status"
        fi
        
        echo ""
    done
}

# ═══════════════════════════════════════════════════
# Database Tests
# ═══════════════════════════════════════════════════

test_databases() {
    print_header "Testing Databases"
    
    # PostgreSQL
    echo "Testing PostgreSQL..."
    if docker compose exec -T postgres pg_isready -U postgres &> /dev/null; then
        test_pass "PostgreSQL: Ready"
        
        # Test connection
        if docker compose exec -T postgres psql -U postgres -c "SELECT 1;" &> /dev/null; then
            test_pass "PostgreSQL: Connection successful"
            
            # List databases
            local dbs=$(docker compose exec -T postgres psql -U postgres -t -c "SELECT datname FROM pg_database WHERE datistemplate = false;" 2>/dev/null | grep -v "^$" | wc -l)
            test_info "PostgreSQL: $dbs databases found"
        else
            test_fail "PostgreSQL: Connection failed"
        fi
    else
        test_fail "PostgreSQL: Not ready"
    fi
    echo ""
    
    # MongoDB
    echo "Testing MongoDB..."
    if docker compose exec -T mongodb mongosh --eval "db.runCommand('ping').ok" --quiet &> /dev/null; then
        test_pass "MongoDB: Ready"
        
        # List databases
        local dbs=$(docker compose exec -T mongodb mongosh --eval "db.adminCommand('listDatabases').databases.length" --quiet 2>/dev/null)
        test_info "MongoDB: $dbs databases found"
    else
        test_fail "MongoDB: Not ready"
    fi
    echo ""
    
    # Redis
    echo "Testing Redis..."
    if docker compose exec -T redis redis-cli ping &> /dev/null; then
        test_pass "Redis: Ready"
        
        # Check memory
        local memory=$(docker compose exec -T redis redis-cli INFO memory | grep "used_memory_human" | cut -d: -f2 | tr -d '\r')
        test_info "Redis: Memory usage: $memory"
    else
        test_fail "Redis: Not ready"
    fi
    echo ""
}

# ═══════════════════════════════════════════════════
# Service-Specific Tests
# ═══════════════════════════════════════════════════

test_nginx() {
    print_header "Testing Nginx"
    
    # Nginx container
    if docker compose ps nginx --format '{{.Status}}' 2>/dev/null | grep -q "Up"; then
        test_pass "Nginx: Container running"
        
        # Config test
        if docker compose exec -T nginx nginx -t &> /dev/null; then
            test_pass "Nginx: Configuration valid"
        else
            test_fail "Nginx: Configuration invalid"
        fi
        
        # Port check
        if netstat -tuln | grep -q ":80 "; then
            test_pass "Nginx: Port 80 listening"
        else
            test_fail "Nginx: Port 80 not listening"
        fi
        
        if netstat -tuln | grep -q ":443 "; then
            test_pass "Nginx: Port 443 listening"
        else
            test_warn "Nginx: Port 443 not listening" "SSL may not be configured"
        fi
    else
        test_fail "Nginx: Container not running"
    fi
    
    echo ""
}

test_minio() {
    print_header "Testing MinIO"
    
    if docker compose ps minio --format '{{.Status}}' 2>/dev/null | grep -q "Up"; then
        test_pass "MinIO: Container running"
        
        # Health check
        local health=$(curl -sf http://localhost:9000/minio/health/live 2>/dev/null)
        if [ $? -eq 0 ]; then
            test_pass "MinIO: Health check passed"
        else
            test_fail "MinIO: Health check failed"
        fi
        
        # Console check
        if curl -sf http://localhost:9001 &> /dev/null; then
            test_pass "MinIO: Console accessible"
        else
            test_warn "MinIO: Console not accessible"
        fi
    else
        test_fail "MinIO: Container not running"
    fi
    
    echo ""
}

test_parse_server() {
    print_header "Testing Parse Server"
    
    if docker compose ps parse-server --format '{{.Status}}' 2>/dev/null | grep -q "Up"; then
        test_pass "Parse Server: Container running"
        
        # Health check
        local health=$(curl -sf http://localhost:1337/parse/health 2>/dev/null)
        if [ $? -eq 0 ]; then
            test_pass "Parse Server: Health check passed"
            echo "$health" | jq . 2>/dev/null | sed 's/^/    /' || echo "    $health"
        else
            test_fail "Parse Server: Health check failed"
        fi
    else
        test_fail "Parse Server: Container not running"
    fi
    
    echo ""
}

test_parse_dashboard() {
    print_header "Testing Parse Dashboard"
    
    if docker compose ps parse-dashboard --format '{{.Status}}' 2>/dev/null | grep -q "Up"; then
        test_pass "Parse Dashboard: Container running"
        
        # HTTP check
        local http_code=$(curl -sf -o /dev/null -w "%{http_code}" http://localhost:4040 2>/dev/null)
        if [ "$http_code" = "200" ] || [ "$http_code" = "302" ]; then
            test_pass "Parse Dashboard: Accessible (HTTP $http_code)"
        else
            test_fail "Parse Dashboard: Not accessible (HTTP $http_code)"
        fi
    else
        test_fail "Parse Dashboard: Container not running"
    fi
    
    echo ""
}

test_grafana() {
    print_header "Testing Grafana"
    
    if docker compose ps grafana --format '{{.Status}}' 2>/dev/null | grep -q "Up"; then
        test_pass "Grafana: Container running"
        
        # HTTP check
        local http_code=$(curl -sf -o /dev/null -w "%{http_code}" http://localhost:3001 2>/dev/null)
        if [ "$http_code" = "200" ] || [ "$http_code" = "302" ]; then
            test_pass "Grafana: Accessible (HTTP $http_code)"
        else
            test_fail "Grafana: Not accessible (HTTP $http_code)"
        fi
    else
        test_fail "Grafana: Container not running"
    fi
    
    echo ""
}

test_prometheus() {
    print_header "Testing Prometheus"
    
    if docker compose ps prometheus --format '{{.Status}}' 2>/dev/null | grep -q "Up"; then
        test_pass "Prometheus: Container running"
        
        # HTTP check
        local http_code=$(curl -sf -o /dev/null -w "%{http_code}" http://localhost:9090/-/healthy 2>/dev/null)
        if [ "$http_code" = "200" ]; then
            test_pass "Prometheus: Health check passed"
            
            # Check targets
            local targets=$(curl -sf http://localhost:9090/api/v1/targets 2>/dev/null | jq -r '.data.activeTargets | length' 2>/dev/null)
            if [ -n "$targets" ]; then
                test_info "Prometheus: $targets active targets"
            fi
        else
            test_fail "Prometheus: Health check failed"
        fi
    else
        test_fail "Prometheus: Container not running"
    fi
    
    echo ""
}

test_adminer() {
    print_header "Testing Adminer"
    
    if docker compose ps adminer --format '{{.Status}}' 2>/dev/null | grep -q "Up"; then
        test_pass "Adminer: Container running"
        
        # HTTP check
        local http_code=$(curl -sf -o /dev/null -w "%{http_code}" http://localhost:8080 2>/dev/null)
        if [ "$http_code" = "200" ]; then
            test_pass "Adminer: Accessible"
        else
            test_fail "Adminer: Not accessible (HTTP $http_code)"
        fi
    else
        test_fail "Adminer: Container not running"
    fi
    
    echo ""
}

# ═══════════════════════════════════════════════════
# Network Tests
# ═══════════════════════════════════════════════════

test_network() {
    print_header "Testing Network"
    
    # Check Docker networks
    local networks=($(docker network ls --filter "name=onestack" --format "{{.Name}}" 2>/dev/null))
    
    if [ ${#networks[@]} -gt 0 ]; then
        test_pass "Docker networks found: ${#networks[@]}"
        for net in "${networks[@]}"; do
            test_info "Network: $net"
        done
    else
        test_warn "No OneStack networks found"
    fi
    
    echo ""
    
    # Test inter-container connectivity
    echo "Testing inter-container connectivity..."
    
    # Parse to PostgreSQL
    if docker compose exec -T parse-server nc -zv postgres 5432 &> /dev/null; then
        test_pass "Parse Server → PostgreSQL: Connected"
    else
        test_fail "Parse Server → PostgreSQL: Cannot connect"
    fi
    
    # Parse to MongoDB
    if docker compose exec -T parse-server nc -zv mongodb 27017 &> /dev/null; then
        test_pass "Parse Server → MongoDB: Connected"
    else
        test_fail "Parse Server → MongoDB: Cannot connect"
    fi
    
    # Parse to Redis
    if docker compose exec -T parse-server nc -zv redis 6379 &> /dev/null; then
        test_pass "Parse Server → Redis: Connected"
    else
        test_fail "Parse Server → Redis: Cannot connect"
    fi
    
    echo ""
}

# ═══════════════════════════════════════════════════
# Volume Tests
# ═══════════════════════════════════════════════════

test_volumes() {
    print_header "Testing Volumes"
    
    # List volumes
    local volumes=($(docker volume ls --filter "name=onestack" --format "{{.Name}}" 2>/dev/null))
    
    if [ ${#volumes[@]} -gt 0 ]; then
        test_pass "Docker volumes found: ${#volumes[@]}"
        
        for vol in "${volumes[@]}"; do
            # Get size
            local size=$(docker system df -v 2>/dev/null | grep "$vol" | awk '{print $3}')
            if [ -n "$size" ]; then
                test_info "$vol: $size"
            else
                test_info "$vol"
            fi
        done
    else
        test_warn "No OneStack volumes found"
    fi
    
    echo ""
}

# ═══════════════════════════════════════════════════
# Disk Space Tests
# ═══════════════════════════════════════════════════

test_disk_space() {
    print_header "Testing Disk Space"
    
    # Check /opt/onestack
    local onestack_size=$(du -sh /opt/onestack 2>/dev/null | cut -f1)
    test_info "OneStack directory: $onestack_size"
    
    # Check /var/lib/docker
    if [ -d "/var/lib/docker" ]; then
        local docker_size=$(du -sh /var/lib/docker 2>/dev/null | cut -f1)
        test_info "Docker data: $docker_size"
    fi
    
    # Check available disk space
    local available=$(df -h /opt/onestack | tail -1 | awk '{print $4}')
    local used_percent=$(df -h /opt/onestack | tail -1 | awk '{print $5}' | tr -d '%')
    
    test_info "Available space: $available"
    
    if [ "$used_percent" -lt 80 ]; then
        test_pass "Disk usage: $used_percent% (Good)"
    elif [ "$used_percent" -lt 90 ]; then
        test_warn "Disk usage: $used_percent% (Warning)"
    else
        test_fail "Disk usage: $used_percent% (Critical)"
    fi
    
    echo ""
}

# ═══════════════════════════════════════════════════
# Summary Report
# ═══════════════════════════════════════════════════

show_summary() {
    print_header "Test Summary"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "  Total Tests:   $TOTAL_TESTS"
    echo -e "  ${GREEN}Passed:${NC}        $PASSED_TESTS"
    echo -e "  ${RED}Failed:${NC}        $FAILED_TESTS"
    echo -e "  ${YELLOW}Warnings:${NC}      $WARNINGS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Calculate success rate
    if [ $TOTAL_TESTS -gt 0 ]; then
        local success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
        
        if [ $success_rate -ge 90 ]; then
            echo -e "  ${GREEN}✓ Success Rate: ${success_rate}% - Excellent!${NC}"
        elif [ $success_rate -ge 70 ]; then
            echo -e "  ${YELLOW}⚠ Success Rate: ${success_rate}% - Needs attention${NC}"
        else
            echo -e "  ${RED}✗ Success Rate: ${success_rate}% - Critical issues${NC}"
        fi
    fi
    
    echo ""
    
    # Exit code
    if [ $FAILED_TESTS -gt 0 ]; then
        return 1
    else
        return 0
    fi
}

# ═══════════════════════════════════════════════════
# Main Test Runner
# ═══════════════════════════════════════════════════

main() {
    clear
    print_header "OneStack Service Tests"
    echo ""
    print_info "Starting comprehensive service tests..."
    echo ""
    
    # Check installation
    if [ ! -d "/opt/onestack" ]; then
        print_error "OneStack not installed"
        exit 1
    fi
    
    # Run tests
    test_docker
    test_containers
    test_databases
    test_nginx
    test_minio
    test_parse_server
    test_parse_dashboard
    test_grafana
    test_prometheus
    test_adminer
    test_network
    test_volumes
    test_disk_space
    
    # Show summary
    show_summary
    
    # Exit with appropriate code
    exit $?
}

main "$@"