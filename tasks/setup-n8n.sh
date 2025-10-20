#!/bin/bash
# Setup n8n (Workflow Automation)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh" 2>/dev/null || {
    BLUE='\033[0;34m'; GREEN='\033[0;32m'; NC='\033[0m'
    print_header() { echo -e "\n${BLUE}=== $1 ===${NC}\n"; }
    print_step() { echo -e "${BLUE}▶${NC} $1"; }
    print_success() { echo -e "${GREEN}✓${NC} $1"; }
}

check_root

print_header "n8n Workflow Automation Setup"

INSTALL_DIR="/opt/onestack"

# Add to docker-compose
if [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
    cat >> "$INSTALL_DIR/docker-compose.yml" << 'N8NCOMPOSE'

  # n8n (Workflow Automation)
  n8n:
    image: n8nio/n8n:latest
    container_name: onestack-n8n
    restart: unless-stopped
    environment:
      N8N_BASIC_AUTH_ACTIVE: "true"
      N8N_BASIC_AUTH_USER: admin
      N8N_BASIC_AUTH_PASSWORD: ${N8N_PASSWORD:-onestack123}
      N8N_HOST: ${DOMAIN}
      N8N_PORT: 5678
      N8N_PROTOCOL: http
      WEBHOOK_URL: http://${DOMAIN}:5678/
      GENERIC_TIMEZONE: ${TIMEZONE}
    volumes:
      - n8n_data:/home/node/.n8n
    networks:
      - backend
    ports:
      - "5678:5678"
N8NCOMPOSE

    sed -i '/^volumes:/a\  n8n_data:' "$INSTALL_DIR/docker-compose.yml"
fi

# Update Nginx
if [ -f "$INSTALL_DIR/nginx/conf.d/onestack.conf" ]; then
    cat >> "$INSTALL_DIR/nginx/conf.d/onestack.conf" << 'N8NNGINX'

# n8n Workflow Automation
server {
    listen 80;
    server_name flow.${DOMAIN} n8n.${DOMAIN};
    
    location / {
        proxy_pass http://n8n:5678;
        proxy_set_header Host $host;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
N8NNGINX
fi

print_step "Starting n8n..."
cd "$INSTALL_DIR"
docker compose up -d n8n

print_success "n8n installed!"
echo ""
echo "Access: http://flow.yourdomain.com"
echo "Or: http://localhost:5678"
echo ""
echo "Login:"
echo "  Username: admin"
echo "  Password: onestack123"
