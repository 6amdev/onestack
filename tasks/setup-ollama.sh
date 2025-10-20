#!/bin/bash
# Setup Ollama (Run LLMs Locally)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh" 2>/dev/null || {
    BLUE='\033[0;34m'; GREEN='\033[0;32m'; NC='\033[0m'
    print_header() { echo -e "\n${BLUE}=== $1 ===${NC}\n"; }
    print_step() { echo -e "${BLUE}▶${NC} $1"; }
    print_success() { echo -e "${GREEN}✓${NC} $1"; }
}

check_root

print_header "Ollama Setup (Local LLM)"

INSTALL_DIR="/opt/onestack"

# Add to docker-compose
print_step "Adding Ollama to docker-compose.yml..."

if [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
    cat >> "$INSTALL_DIR/docker-compose.yml" << 'OLLAMACOMPOSE'

  # Ollama (Local LLM)
  ollama:
    image: ollama/ollama:latest
    container_name: onestack-ollama
    restart: unless-stopped
    volumes:
      - ollama_data:/root/.ollama
    networks:
      - backend
    ports:
      - "11434:11434"
OLLAMACOMPOSE

    # Add volume
    sed -i '/^volumes:/a\  ollama_data:' "$INSTALL_DIR/docker-compose.yml"
fi

# Start Ollama
print_step "Starting Ollama..."
cd "$INSTALL_DIR"
docker compose up -d ollama

# Wait for startup
print_step "Waiting for Ollama to start..."
sleep 10

# Pull models
print_step "Pulling Llama 3 model (this may take a while)..."
docker compose exec ollama ollama pull llama3

print_success "Ollama installed!"
echo ""
echo "Available commands:"
echo "  docker compose exec ollama ollama list              # List models"
echo "  docker compose exec ollama ollama pull mistral      # Pull Mistral"
echo "  docker compose exec ollama ollama pull codellama    # Pull CodeLlama"
echo "  docker compose exec ollama ollama run llama3        # Interactive chat"
echo ""
echo "API: http://localhost:11434"
echo ""
echo "Test:"
echo '  curl http://localhost:11434/api/generate -d '"'"'{"model":"llama3","prompt":"Hello!"}'"'"
