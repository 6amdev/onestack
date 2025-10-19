#!/bin/bash
# OneStack - Quick Test Script

echo "╔═══════════════════════════════════════════════╗"
echo "║     OneStack Installation Test                ║"
echo "╚═══════════════════════════════════════════════╝"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Please run as root"
    echo "Run: sudo bash test-install.sh"
    exit 1
fi

# Load state
if [ -f "/root/.onestack_install_state" ]; then
    source "/root/.onestack_install_state"
    echo "✓ Installation state found"
    echo "  Phase 1: ${PHASE_1_COMPLETE:-false}"
    echo "  Phase 2: ${PHASE_2_COMPLETE:-false}"
    echo ""
else
    echo "❌ No installation found"
    exit 1
fi

# Check install directory
if [ -d "$INSTALL_DIR" ]; then
    echo "✓ Install directory: $INSTALL_DIR"
else
    echo "❌ Install directory not found"
    exit 1
fi

cd "$INSTALL_DIR"

# Check Docker Compose file
if [ -f "docker-compose.yml" ]; then
    echo "✓ Docker Compose file exists"
else
    echo "❌ docker-compose.yml not found"
    exit 1
fi

# Check if services are running
echo ""
echo "Checking services..."
echo ""

SERVICES=(postgres mongodb redis minio nginx)

if [ "$INSTALL_PARSE" = "true" ]; then
    SERVICES+=(parse-server)
fi

if [ "$INSTALL_MONITORING" = "true" ]; then
    SERVICES+=(prometheus grafana)
fi

if [ "$INSTALL_ADMINER" = "true" ]; then
    SERVICES+=(adminer)
fi

ALL_RUNNING=true

for service in "${SERVICES[@]}"; do
    if docker compose ps "$service" 2>/dev/null | grep -q "Up"; then
        echo "  ✓ $service"
    else
        echo "  ❌ $service (not running)"
        ALL_RUNNING=false
    fi
done

echo ""

if [ "$ALL_RUNNING" = true ]; then
    echo "✓ All services are running!"
else
    echo "⚠ Some services are not running"
    echo ""
    echo "Try restarting:"
    echo "  cd $INSTALL_DIR && docker compose restart"
fi

echo ""
echo "Service Status:"
docker compose ps

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Access Information"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ "$PRIMARY_DOMAIN" = "localhost" ]; then
    echo "Main Site: http://localhost"
    echo "MinIO Console: http://localhost:9001"
    [ "$INSTALL_PARSE" = "true" ] && echo "Parse Dashboard: http://localhost:4040"
    [ "$INSTALL_MONITORING" = "true" ] && echo "Grafana: http://localhost:3001"
    [ "$INSTALL_ADMINER" = "true" ] && echo "Adminer: http://localhost:8080"
else
    SERVER_IP=$(curl -s ifconfig.me)
    echo "Main Site: http://$PRIMARY_DOMAIN (or http://$SERVER_IP)"
    echo "MinIO Console: http://storage.$PRIMARY_DOMAIN:9001"
    [ "$INSTALL_PARSE" = "true" ] && echo "Parse Dashboard: http://api.$PRIMARY_DOMAIN:1337/dashboard"
    [ "$INSTALL_MONITORING" = "true" ] && echo "Grafana: http://monitor.$PRIMARY_DOMAIN:3001"
    [ "$INSTALL_ADMINER" = "true" ] && echo "Adminer: http://db.$PRIMARY_DOMAIN:8080"
fi

echo ""
echo "Credentials: cat $INSTALL_DIR/.credentials"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Quick Commands"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "View logs:        cd $INSTALL_DIR && docker compose logs -f"
echo "Restart services: cd $INSTALL_DIR && docker compose restart"
echo "Stop services:    cd $INSTALL_DIR && docker compose stop"
echo "Start services:   cd $INSTALL_DIR && docker compose start"
echo "Check status:     cd $INSTALL_DIR && docker compose ps"
echo ""
echo "Uninstall:        sudo bash uninstall.sh"
echo ""