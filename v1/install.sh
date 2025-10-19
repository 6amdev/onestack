#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Logo
echo -e "${GREEN}"
cat << "EOF"
  ___             ____  _             _    
 / _ \ _ __   ___/ ___|| |_ __ _  ___| | __
| | | | '_ \ / _ \___ \| __/ _` |/ __| |/ /
| |_| | | | |  __/___) | || (_| | (__|   < 
 \___/|_| |_|\___|____/ \__\__,_|\___|_|\_\

       Production Parse Platform v1.0
EOF
echo -e "${NC}"

# Check root
if [[ $EUID -eq 0 ]]; then
   echo -e "${YELLOW}Warning: Running as root${NC}"
fi

# Check system
echo -e "${GREEN}[1/8] System Check...${NC}"
if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    echo -e "${RED}Error: This script requires Linux${NC}"
    exit 1
fi

# Check Docker
echo -e "${GREEN}[2/8] Checking Docker...${NC}"
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    echo -e "${GREEN}✓ Docker installed${NC}"
else
    echo -e "${GREEN}✓ Docker found: $(docker --version)${NC}"
fi

# Check Docker Compose
echo -e "${GREEN}[3/8] Checking Docker Compose...${NC}"
if ! command -v docker-compose &> /dev/null; then
    echo "Installing Docker Compose..."
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    echo -e "${GREEN}✓ Docker Compose installed${NC}"
else
    echo -e "${GREEN}✓ Docker Compose found${NC}"
fi

# Generate secure passwords
echo -e "${GREEN}[4/8] Generating secure configuration...${NC}"
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

if [ ! -f .env ]; then
    cp .env.example .env
    
    # Generate secure values
    APP_ID=$(openssl rand -hex 32)
    MASTER_KEY=$(openssl rand -hex 64)
    MONGO_PASS=$(generate_password)
    REDIS_PASS=$(generate_password)
    DASHBOARD_PASS=$(generate_password)
    
    # Update .env
    sed -i "s/CHANGE_THIS_TO_RANDOM_STRING_MIN_32_CHARS/$APP_ID/" .env
    sed -i "s/CHANGE_THIS_TO_RANDOM_STRING_MIN_64_CHARS/$MASTER_KEY/" .env
    sed -i "s/CHANGE_THIS_TO_STRONG_PASSWORD/$MONGO_PASS/g" .env
    
    # Different passwords for each service
    sed -i "0,/REDIS_PASS=.*/s//REDIS_PASS=$REDIS_PASS/" .env
    sed -i "0,/DASHBOARD_PASS=.*/s//DASHBOARD_PASS=$DASHBOARD_PASS/" .env
    
    chmod 600 .env
    echo -e "${GREEN}✓ Configuration generated${NC}"
else
    echo -e "${YELLOW}✓ Using existing .env file${NC}"
    # Load existing values
    source .env
fi

# Generate Dashboard config
echo -e "${GREEN}[5/8] Generating Dashboard configuration...${NC}"
mkdir -p configs/dashboard

# Read values from .env if not already loaded
[ -z "$APP_ID" ] && source .env

cat > configs/dashboard/parse-dashboard-config.json << EOF
{
  "apps": [
    {
      "serverURL": "http://parse-server:1337/parse",
      "appId": "$APP_ID",
      "masterKey": "$MASTER_KEY",
      "appName": "OneStack"
    }
  ],
  "users": [
    {
      "user": "admin",
      "pass": "$DASHBOARD_PASS"
    }
  ]
}
EOF
echo -e "${GREEN}✓ Dashboard config generated${NC}"

# Create directories
echo -e "${GREEN}[6/8] Creating directories...${NC}"
mkdir -p data/{mongo,redis,ssl}
mkdir -p logs/{nginx,parse,mongo}
mkdir -p backups/mongo
mkdir -p configs/nginx
mkdir -p server/cloud

# Create cloud code if not exists
if [ ! -f server/cloud/main.js ]; then
    cat > server/cloud/main.js << 'EOF'
// Cloud Code
Parse.Cloud.define('hello', async (request) => {
  return 'Hello from OneStack!';
});
EOF
fi

# Pull images
echo -e "${GREEN}[7/8] Pulling Docker images...${NC}"
docker-compose pull

# Start services
echo -e "${GREEN}[8/8] Starting OneStack...${NC}"
docker-compose up -d

# Wait for services
echo -e "${YELLOW}Waiting for services to be healthy...${NC}"
sleep 15

# Check status
if docker-compose ps | grep -q "unhealthy\|Exit\|Restarting"; then
    echo -e "${RED}⚠ Some services failed to start${NC}"
    docker-compose ps
    echo "Check logs: docker-compose logs"
    exit 1
fi

# Get IP
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || echo "localhost")

# Success message
echo -e "${GREEN}"
echo "╔════════════════════════════════════════╗"
echo "║   ✅ OneStack Installation Complete!    ║"
echo "╚════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${GREEN}Access Points:${NC}"
echo "  API:       http://$SERVER_IP/parse"
echo "  Dashboard: http://$SERVER_IP/dashboard"
echo ""
echo -e "${YELLOW}Dashboard Login:${NC}"
echo "  Username: admin"
echo "  Password: $DASHBOARD_PASS"
echo ""
echo -e "${GREEN}API Credentials:${NC}"
echo "  App ID: $APP_ID"
echo ""
echo -e "${GREEN}Useful Commands:${NC}"
echo "  View logs:    docker-compose logs -f"
echo "  Stop:         docker-compose down"
echo "  Restart:      docker-compose restart"
echo "  Backup:       ./scripts/backup.sh"
echo ""
echo -e "${GREEN}Next Steps:${NC}"
echo "  1. Setup domain: ./scripts/setup-ssl.sh"
echo "  2. Configure firewall: ufw allow 80,443/tcp"
echo "  3. Enable monitoring: ./scripts/monitor.sh"

# Save install info
cat > install.info << EOF
Installation Date: $(date)
Server IP: $SERVER_IP
App ID: $APP_ID
Dashboard Password: $DASHBOARD_PASS
Version: 1.0.0
EOF

echo ""
echo -e "${GREEN}Happy coding! 🚀${NC}"