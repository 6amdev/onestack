#!/bin/bash
# Setup Chatwoot (Customer Support Platform)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh" 2>/dev/null || {
    BLUE='\033[0;34m'; GREEN='\033[0;32m'; NC='\033[0m'
    print_header() { echo -e "\n${BLUE}=== $1 ===${NC}\n"; }
    print_step() { echo -e "${BLUE}▶${NC} $1"; }
    print_success() { echo -e "${GREEN}✓${NC} $1"; }
    generate_password() { openssl rand -base64 32 | tr -d "=+/" | cut -c1-${1:-32}; }
}

check_root

print_header "Chatwoot Customer Support Setup"

INSTALL_DIR="/opt/onestack"

# Generate secret
SECRET_KEY=$(generate_password 64)

# Add to docker-compose
if [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
    cat >> "$INSTALL_DIR/docker-compose.yml" << CHATWOOTCOMPOSE

  # Chatwoot (Customer Support)
  chatwoot:
    image: chatwoot/chatwoot:latest
    container_name: onestack-chatwoot
    restart: unless-stopped
    command: bundle exec rails s -p 3000 -b 0.0.0.0
    environment:
      RAILS_ENV: production
      SECRET_KEY_BASE: $SECRET_KEY
      POSTGRES_HOST: postgres
      POSTGRES_PORT: 5432
      POSTGRES_DATABASE: chatwoot_production
      POSTGRES_USERNAME: \${POSTGRES_USER}
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
      REDIS_URL: redis://:\${REDIS_PASSWORD}@redis:6379
      INSTALLATION_NAME: OneStack
    volumes:
      - chatwoot_data:/app/storage
    networks:
      - backend
    ports:
      - "3000:3000"
    depends_on:
      - postgres
      - redis
CHATWOOTCOMPOSE

    sed -i '/^volumes:/a\  chatwoot_data:' "$INSTALL_DIR/docker-compose.yml"
    
    # Add chatwoot_production to postgres databases
    sed -i 's/POSTGRES_DATABASES=onestack_main,parse_db/POSTGRES_DATABASES=onestack_main,parse_db,chatwoot_production/' "$INSTALL_DIR/.env"
fi

# Update Nginx
if [ -f "$INSTALL_DIR/nginx/conf.d/onestack.conf" ]; then
    cat >> "$INSTALL_DIR/nginx/conf.d/onestack.conf" << 'CHATWOTNGINX'

# Chatwoot Customer Support
server {
    listen 80;
    server_name chat.${DOMAIN} support.${DOMAIN};
    
    client_max_body_size 50M;
    
    location / {
        proxy_pass http://chatwoot:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
CHATWOTNGINX
fi

print_step "Starting Chatwoot..."
cd "$INSTALL_DIR"
docker compose up -d chatwoot

print_step "Waiting for Chatwoot to initialize (30 seconds)..."
sleep 30

print_success "Chatwoot installed!"
echo ""
echo "Access: http://chat.yourdomain.com"
echo "Or: http://localhost:3000"
echo ""
echo "First time setup:"
echo "  1. Go to http://localhost:3000"
echo "  2. Create your admin account"
echo "  3. Setup your first inbox"
