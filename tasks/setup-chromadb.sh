#!/bin/bash
# Setup ChromaDB (Vector Database)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh" 2>/dev/null || {
    BLUE='\033[0;34m'; GREEN='\033[0;32m'; NC='\033[0m'
    print_header() { echo -e "\n${BLUE}=== $1 ===${NC}\n"; }
    print_step() { echo -e "${BLUE}▶${NC} $1"; }
    print_success() { echo -e "${GREEN}✓${NC} $1"; }
}

check_root

print_header "ChromaDB Setup"

INSTALL_DIR="/opt/onestack"

# Add to docker-compose
if [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
    cat >> "$INSTALL_DIR/docker-compose.yml" << 'CHROMACOMPOSE'

  # ChromaDB (Vector Database)
  chromadb:
    image: chromadb/chroma:latest
    container_name: onestack-chromadb
    restart: unless-stopped
    volumes:
      - chromadb_data:/chroma/chroma
    environment:
      CHROMA_SERVER_AUTH_CREDENTIALS_PROVIDER: chromadb.auth.token_authn.TokenAuthenticationServerProvider
      CHROMA_SERVER_AUTH_TOKEN_TRANSPORT_HEADER: X-Chroma-Token
    networks:
      - backend
    ports:
      - "8002:8000"
CHROMACOMPOSE

    sed -i '/^volumes:/a\  chromadb_data:' "$INSTALL_DIR/docker-compose.yml"
fi

print_step "Starting ChromaDB..."
cd "$INSTALL_DIR"
docker compose up -d chromadb

print_success "ChromaDB installed!"
echo ""
echo "Access: http://localhost:8002"
echo ""
echo "Python usage:"
echo "  import chromadb"
echo "  client = chromadb.HttpClient(host='localhost', port=8002)"
