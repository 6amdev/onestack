#!/bin/bash

# OneStack v2 - Interactive Installer
# Complete SME Platform Installation Script

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/onestack"

print_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════${NC}\n"
}

print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_info() { echo -e "${CYAN}ℹ${NC} $1"; }

# Banner
clear
cat << 'BANNER'
╔═══════════════════════════════════════════════╗
║                                               ║
║           🚀 OneStack v2 Installer            ║
║                                               ║
║     Complete Self-Hosted SME Platform         ║
║                                               ║
╚═══════════════════════════════════════════════╝
BANNER

echo ""
print_info "This will install:"
echo "  • Docker & Docker Compose"
echo "  • PostgreSQL + MongoDB + Redis"
echo "  • Nginx Reverse Proxy"
echo "  • MinIO Object Storage"
echo "  • Parse Server (Optional)"
echo "  • Monitoring Stack (Optional)"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    print_error "Please run as root"
    echo "Run: sudo bash install.sh"
    exit 1
fi

# System requirements check
print_header "System Requirements Check"

# Check OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    print_success "OS: $PRETTY_NAME"
    
    if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
        print_warning "This script is optimized for Ubuntu/Debian"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
else
    print_error "Cannot detect OS"
    exit 1
fi

# Check resources
TOTAL_RAM=$(free -m | awk 'NR==2 {print $2}')
AVAILABLE_DISK=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')

if [ "$TOTAL_RAM" -lt 2000 ]; then
    print_warning "RAM: ${TOTAL_RAM}MB (Minimum 2GB recommended)"
else
    print_success "RAM: ${TOTAL_RAM}MB"
fi

if [ "$AVAILABLE_DISK" -lt 20 ]; then
    print_warning "Disk: ${AVAILABLE_DISK}GB (Minimum 20GB recommended)"
else
    print_success "Disk: ${AVAILABLE_DISK}GB available"
fi

echo ""
read -p "Continue with installation? (Y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    exit 0
fi

# Docker Installation
print_header "Docker Installation"

if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version | cut -d' ' -f3 | cut -d',' -f1)
    print_success "Docker already installed: $DOCKER_VERSION"
    
    read -p "Reinstall Docker? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        INSTALL_DOCKER=true
    else
        INSTALL_DOCKER=false
    fi
else
    print_info "Docker not found"
    read -p "Install Docker now? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        INSTALL_DOCKER=true
    else
        print_error "Docker is required"
        exit 1
    fi
fi

if [ "$INSTALL_DOCKER" = true ]; then
    print_info "Installing Docker..."
    
    # Remove old versions
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Update packages
    apt-get update -qq
    
    # Install dependencies
    apt-get install -y -qq \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    # Add Docker's GPG key
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # Add Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    # Start Docker
    systemctl start docker
    systemctl enable docker
    
    print_success "Docker installed: $(docker --version)"
fi

# Check Docker Compose
if docker compose version &> /dev/null; then
    print_success "Docker Compose: $(docker compose version --short)"
else
    print_error "Docker Compose not found"
    exit 1
fi

# User Management
print_header "User Management"

read -p "Create 'onestack' user? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    if id "onestack" &>/dev/null; then
        print_warning "User 'onestack' already exists"
    else
        useradd -m -s /bin/bash onestack
        usermod -aG docker onestack
        print_success "User 'onestack' created"
        
        echo ""
        print_info "Set password for 'onestack' user:"
        passwd onestack
    fi
fi

# Installation Directory
print_header "Installation Directory"

print_info "Default: $INSTALL_DIR"
read -p "Use default directory? (Y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    read -p "Enter custom path: " INSTALL_DIR
fi

if [ -d "$INSTALL_DIR" ] && [ "$(ls -A $INSTALL_DIR)" ]; then
    print_warning "Directory $INSTALL_DIR is not empty"
    read -p "Remove existing files? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf $INSTALL_DIR/*
        print_success "Directory cleaned"
    else
        print_error "Installation cancelled"
        exit 1
    fi
fi

mkdir -p $INSTALL_DIR
cd $INSTALL_DIR

print_success "Installation directory: $INSTALL_DIR"

# Component Selection
print_header "Component Selection"

echo "Select components to install:"
echo ""
echo "Core Components (Required):"
echo "  [✓] Nginx Reverse Proxy"
echo "  [✓] PostgreSQL Database"
echo "  [✓] MongoDB Database"
echo "  [✓] Redis Cache"
echo "  [✓] MinIO Object Storage"
echo ""

read -p "Install Parse Server? (Y/n): " -n 1 -r
echo
INSTALL_PARSE=$([[ ! $REPLY =~ ^[Nn]$ ]] && echo "true" || echo "false")

read -p "Install Monitoring (Grafana + Prometheus)? (Y/n): " -n 1 -r
echo
INSTALL_MONITORING=$([[ ! $REPLY =~ ^[Nn]$ ]] && echo "true" || echo "false")

read -p "Install Adminer (Database UI)? (Y/n): " -n 1 -r
echo
INSTALL_ADMINER=$([[ ! $REPLY =~ ^[Nn]$ ]] && echo "true" || echo "false")

# Domain Configuration
print_header "Domain Configuration"

print_info "For local testing, use 'localhost'"
print_info "For production, use your domain name"
echo ""
read -p "Enter domain name [localhost]: " PRIMARY_DOMAIN
PRIMARY_DOMAIN=${PRIMARY_DOMAIN:-localhost}

if [ "$PRIMARY_DOMAIN" != "localhost" ]; then
    read -p "Enter email for SSL certificates: " SSL_EMAIL
else
    SSL_EMAIL="admin@localhost"
fi

print_success "Domain: $PRIMARY_DOMAIN"

# Generate Passwords
print_header "Security Configuration"

print_info "Generating secure passwords..."

POSTGRES_PASSWORD=$(openssl rand -hex 16)
MONGODB_PASSWORD=$(openssl rand -hex 16)
REDIS_PASSWORD=$(openssl rand -hex 16)
MINIO_PASSWORD=$(openssl rand -hex 16)
GRAFANA_PASSWORD=$(openssl rand -hex 16)

if [ "$INSTALL_PARSE" = true ]; then
    PARSE_APP_ID=$(openssl rand -hex 16)
    PARSE_MASTER_KEY=$(openssl rand -hex 32)
fi

print_success "Secure passwords generated"

# Create Configuration
print_header "Creating Configuration Files"

# Create .env
cat > .env << EOF
# OneStack Configuration
# Generated: $(date)

COMPOSE_PROJECT_NAME=onestack
TIMEZONE=Asia/Bangkok
PRIMARY_DOMAIN=$PRIMARY_DOMAIN
SSL_EMAIL=$SSL_EMAIL

# PostgreSQL
POSTGRES_VERSION=16
POSTGRES_USER=postgres
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_DB=onestack_main

# MongoDB
MONGODB_VERSION=7
MONGODB_ROOT_USERNAME=admin
MONGODB_ROOT_PASSWORD=$MONGODB_PASSWORD

# Redis
REDIS_VERSION=alpine
REDIS_PASSWORD=$REDIS_PASSWORD

# MinIO
MINIO_VERSION=latest
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=$MINIO_PASSWORD

# Grafana
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=$GRAFANA_PASSWORD

# Parse Server
PARSE_APP_ID=$PARSE_APP_ID
PARSE_MASTER_KEY=$PARSE_MASTER_KEY
PARSE_DATABASE_URI=postgres://postgres:$POSTGRES_PASSWORD@postgres:5432/parse_db

# Feature Flags
INSTALL_PARSE=$INSTALL_PARSE
INSTALL_MONITORING=$INSTALL_MONITORING
INSTALL_ADMINER=$INSTALL_ADMINER
EOF

chmod 600 .env
print_success ".env created"

# Save credentials
cat > .credentials << EOF
═══════════════════════════════════════
OneStack Credentials
Generated: $(date)
═══════════════════════════════════════

Domain: $PRIMARY_DOMAIN
Email: $SSL_EMAIL

PostgreSQL:
  Host: postgres (internal) or localhost:5432
  User: postgres
  Password: $POSTGRES_PASSWORD
  Database: onestack_main

MongoDB:
  Host: mongodb (internal) or localhost:27017
  User: admin
  Password: $MONGODB_PASSWORD

Redis:
  Host: redis (internal) or localhost:6379
  Password: $REDIS_PASSWORD

MinIO:
  Console: http://$PRIMARY_DOMAIN:9001
  User: minioadmin
  Password: $MINIO_PASSWORD

Grafana:
  URL: http://monitor.$PRIMARY_DOMAIN
  User: admin
  Password: $GRAFANA_PASSWORD

Parse Server:
  URL: http://api.$PRIMARY_DOMAIN/parse
  App ID: $PARSE_APP_ID
  Master Key: $PARSE_MASTER_KEY

═══════════════════════════════════════
IMPORTANT: Keep this file secure!
═══════════════════════════════════════
EOF

chmod 600 .credentials
print_success ".credentials created"

# Directory Structure
print_info "Creating directory structure..."

mkdir -p {nginx/{conf.d,security},databases/{postgres/init,mongodb/init,redis},frontends/{main,app,admin},backends/{parse-server/cloud,nodejs-api,python-rag},monitoring/{prometheus,grafana/provisioning},backups/{postgres,mongodb,redis,minio},logs/{nginx,applications}}

print_success "Directory structure created"

# Summary
print_header "Installation Summary"

echo "Installation Path: $INSTALL_DIR"
echo "Domain: $PRIMARY_DOMAIN"
echo ""
echo "Components:"
echo "  ✓ Nginx Reverse Proxy"
echo "  ✓ PostgreSQL"
echo "  ✓ MongoDB"
echo "  ✓ Redis"
echo "  ✓ MinIO"
[ "$INSTALL_PARSE" = true ] && echo "  ✓ Parse Server"
[ "$INSTALL_MONITORING" = true ] && echo "  ✓ Monitoring Stack"
[ "$INSTALL_ADMINER" = true ] && echo "  ✓ Adminer"
echo ""

read -p "Continue with file creation? (Y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    print_warning "Installation paused"
    print_info "Run this script again to continue"
    exit 0
fi

print_info "Creating configuration files..."
print_info "This will take a moment..."

# Next step indicator
echo ""
print_success "Configuration complete!"
echo ""
print_info "Next: Run './create-configs.sh' to generate all configuration files"
print_info "Then: Run 'docker compose up -d' to start services"
echo ""