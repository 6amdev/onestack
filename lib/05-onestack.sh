#!/bin/bash
# OneStack - Service Deployment

source "$(dirname "$0")/utils.sh"

# ════════════════════════════════════════════════
# DIRECTORY STRUCTURE
# ════════════════════════════════════════════════

create_directory_structure() {
    print_header "Creating Directory Structure"
    
    local base_dir="$INSTALL_DIR"
    
    print_step "Creating directories in: $base_dir"
    
    # Main directories
    local dirs=(
        # Core
        "nginx/conf.d"
        "nginx/security"
        "nginx/ssl"
        "nginx/logs"
        
        # Databases
        "databases/postgres/init"
        "databases/mongodb/init"
        "databases/redis"
        
        # Frontends
        "frontends/main"
        "frontends/app"
        "frontends/admin"
        
        # Backends
        "backends/parse-server/cloud"
        "backends/nodejs-api"
        "backends/python-rag"
        
        # Monitoring
        "monitoring/prometheus"
        "monitoring/grafana/provisioning/datasources"
        "monitoring/grafana/provisioning/dashboards"
        
        # Backups
        "backups/postgres"
        "backups/mongodb"
        "backups/redis"
        "backups/minio"
        
        # Logs
        "logs/nginx"
        "logs/applications"
        
        # Config
        "config"
        "scripts"
    )
    
    for dir in "${dirs[@]}"; do
        local full_path="$base_dir/$dir"
        if mkdir -p "$full_path" 2>/dev/null; then
            # Set ownership to onestack user
            chown -R "$ONESTACK_USER:$ONESTACK_USER" "$full_path" 2>/dev/null || true
        else
            print_warning "Could not create: $full_path"
        fi
    done
    
    print_success "Directory structure created"
    
    # Set base directory ownership
    chown -R "$ONESTACK_USER:$ONESTACK_USER" "$base_dir" 2>/dev/null || true
    
    echo ""
}

# ════════════════════════════════════════════════
# PASSWORD GENERATION
# ════════════════════════════════════════════════

generate_passwords() {
    print_header "Generating Secure Passwords"
    
    print_step "Creating secure credentials..."
    
    # Database passwords
    export POSTGRES_PASSWORD=$(generate_password 32)
    export MONGODB_PASSWORD=$(generate_password 32)
    export REDIS_PASSWORD=$(generate_password 32)
    
    # Service passwords
    export MINIO_ROOT_PASSWORD=$(generate_password 32)
    export GRAFANA_PASSWORD=$(generate_password 24)
    
    # Parse Server (if enabled)
    if [ "$INSTALL_PARSE" = "true" ]; then
        export PARSE_APP_ID=$(generate_password 16)
        export PARSE_MASTER_KEY=$(generate_password 48)
        export PARSE_CLIENT_KEY=$(generate_password 32)
    fi
    
    # Adminer (if enabled)
    if [ "$INSTALL_ADMINER" = "true" ]; then
        export ADMINER_DESIGN="nette"
    fi
    
    print_success "Passwords generated"
    
    # Save to secure file
    save_credentials
    
    echo ""
}

save_credentials() {
    local cred_file="$INSTALL_DIR/.credentials"
    
    cat > "$cred_file" << EOF
═══════════════════════════════════════════════════
OneStack Credentials
Generated: $(date)
Domain: $PRIMARY_DOMAIN
═══════════════════════════════════════════════════

SYSTEM ACCESS
─────────────────────────────────────────────────
Server IP: $(get_server_ip)
Admin User: $ADMIN_USER
Service User: $ONESTACK_USER

DATABASES
─────────────────────────────────────────────────
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

SERVICES
─────────────────────────────────────────────────
MinIO Object Storage:
  Console: http://$PRIMARY_DOMAIN:9001
  API: http://$PRIMARY_DOMAIN:9000
  User: minioadmin
  Password: $MINIO_ROOT_PASSWORD

EOF

    if [ "$INSTALL_MONITORING" = "true" ]; then
        cat >> "$cred_file" << EOF
Grafana:
  URL: http://monitor.$PRIMARY_DOMAIN:3001
  User: admin
  Password: $GRAFANA_PASSWORD

Prometheus:
  URL: http://monitor.$PRIMARY_DOMAIN:9090

EOF
    fi

    if [ "$INSTALL_PARSE" = "true" ]; then
        cat >> "$cred_file" << EOF
Parse Server:
  URL: http://api.$PRIMARY_DOMAIN:1337/parse
  Dashboard: http://api.$PRIMARY_DOMAIN:1337/dashboard
  App ID: $PARSE_APP_ID
  Master Key: $PARSE_MASTER_KEY
  Client Key: $PARSE_CLIENT_KEY

EOF
    fi

    if [ "$INSTALL_ADMINER" = "true" ]; then
        cat >> "$cred_file" << EOF
Adminer (Database UI):
  URL: http://db.$PRIMARY_DOMAIN:8080
  System: PostgreSQL or MongoDB
  Username: (use database credentials above)

EOF
    fi

    cat >> "$cred_file" << EOF
═══════════════════════════════════════════════════
IMPORTANT NOTES
═══════════════════════════════════════════════════
- Keep this file secure and backed up
- Credentials saved at: $cred_file
- To view anytime: cat $cred_file

═══════════════════════════════════════════════════
EOF
    
    chmod 600 "$cred_file"
    chown "$ONESTACK_USER:$ONESTACK_USER" "$cred_file"
    
    print_success "Credentials saved to: $cred_file"
}

# ════════════════════════════════════════════════
# .ENV FILE CREATION
# ════════════════════════════════════════════════

create_env_file() {
    print_header "Creating Environment Configuration"
    
    local env_file="$INSTALL_DIR/.env"
    
    print_step "Generating .env file..."
    
    cat > "$env_file" << EOF
# OneStack Environment Configuration
# Generated: $(date)
# DO NOT COMMIT THIS FILE TO VERSION CONTROL

# ═══════════════════════════════════════════════════
# SYSTEM
# ═══════════════════════════════════════════════════
COMPOSE_PROJECT_NAME=onestack
TIMEZONE=${CONFIG_system_timezone:-Asia/Bangkok}
NODE_ENV=production

# ═══════════════════════════════════════════════════
# DOMAIN
# ═══════════════════════════════════════════════════
PRIMARY_DOMAIN=$PRIMARY_DOMAIN
SSL_EMAIL=$SSL_EMAIL

# ═══════════════════════════════════════════════════
# POSTGRESQL
# ═══════════════════════════════════════════════════
POSTGRES_VERSION=${CONFIG_database_postgres_version:-16}
POSTGRES_USER=postgres
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_DB=onestack_main
POSTGRES_HOST=postgres
POSTGRES_PORT=5432

# Additional databases
POSTGRES_DATABASES=onestack_main,parse_db,chatwoot_db

# ═══════════════════════════════════════════════════
# MONGODB
# ═══════════════════════════════════════════════════
MONGODB_VERSION=${CONFIG_database_mongodb_version:-7}
MONGODB_ROOT_USERNAME=admin
MONGODB_ROOT_PASSWORD=$MONGODB_PASSWORD
MONGODB_HOST=mongodb
MONGODB_PORT=27017

# ═══════════════════════════════════════════════════
# REDIS
# ═══════════════════════════════════════════════════
REDIS_VERSION=${CONFIG_database_redis_version:-alpine}
REDIS_PASSWORD=$REDIS_PASSWORD
REDIS_HOST=redis
REDIS_PORT=6379

# ═══════════════════════════════════════════════════
# MINIO (Object Storage)
# ═══════════════════════════════════════════════════
MINIO_VERSION=latest
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=$MINIO_ROOT_PASSWORD
MINIO_HOST=minio
MINIO_PORT=9000
MINIO_CONSOLE_PORT=9001

# ═══════════════════════════════════════════════════
# PARSE SERVER
# ═══════════════════════════════════════════════════
EOF

    if [ "$INSTALL_PARSE" = "true" ]; then
        cat >> "$env_file" << EOF
PARSE_SERVER_VERSION=latest
PARSE_APP_ID=$PARSE_APP_ID
PARSE_MASTER_KEY=$PARSE_MASTER_KEY
PARSE_CLIENT_KEY=$PARSE_CLIENT_KEY
PARSE_SERVER_URL=http://parse-server:1337/parse
PARSE_PUBLIC_SERVER_URL=http://api.$PRIMARY_DOMAIN:1337/parse
PARSE_DATABASE_URI=postgres://postgres:$POSTGRES_PASSWORD@postgres:5432/parse_db
PARSE_MOUNT_PATH=/parse

# Parse Dashboard
PARSE_DASHBOARD_USER=admin
PARSE_DASHBOARD_PASSWORD=$GRAFANA_PASSWORD
PARSE_DASHBOARD_APP_NAME=OneStack

EOF
    fi

    cat >> "$env_file" << EOF
# ═══════════════════════════════════════════════════
# MONITORING
# ═══════════════════════════════════════════════════
EOF

    if [ "$INSTALL_MONITORING" = "true" ]; then
        cat >> "$env_file" << EOF
GRAFANA_VERSION=latest
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=$GRAFANA_PASSWORD
GRAFANA_PORT=3001

PROMETHEUS_VERSION=latest
PROMETHEUS_PORT=9090

EOF
    fi

    cat >> "$env_file" << EOF
# ═══════════════════════════════════════════════════
# ADMINER
# ═══════════════════════════════════════════════════
EOF

    if [ "$INSTALL_ADMINER" = "true" ]; then
        cat >> "$env_file" << EOF
ADMINER_VERSION=latest
ADMINER_PORT=8080
ADMINER_DESIGN=$ADMINER_DESIGN

EOF
    fi

    cat >> "$env_file" << EOF
# ═══════════════════════════════════════════════════
# NETWORK
# ═══════════════════════════════════════════════════
DOCKER_NETWORK_SUBNET=${CONFIG_advanced_docker_subnet:-172.20.0.0/16}

EOF
    
    chmod 600 "$env_file"
    chown "$ONESTACK_USER:$ONESTACK_USER" "$env_file"
    
    print_success ".env file created"
    echo ""
}

# ════════════════════════════════════════════════
# DOCKER COMPOSE FILE
# ════════════════════════════════════════════════

create_docker_compose() {
    print_header "Creating Docker Compose Configuration"
    
    local compose_file="$INSTALL_DIR/docker-compose.yml"
    
    print_step "Generating docker-compose.yml..."
    
    cat > "$compose_file" << 'EOF'
version: '3.8'

# ═══════════════════════════════════════════════════
# NETWORKS
# ═══════════════════════════════════════════════════
networks:
  frontend:
    driver: bridge
  backend:
    driver: bridge
    ipam:
      config:
        - subnet: ${DOCKER_NETWORK_SUBNET}

# ═══════════════════════════════════════════════════
# VOLUMES
# ═══════════════════════════════════════════════════
volumes:
  postgres_data:
    driver: local
  mongodb_data:
    driver: local
  redis_data:
    driver: local
  minio_data:
    driver: local
  grafana_data:
    driver: local
  prometheus_data:
    driver: local

# ═══════════════════════════════════════════════════
# SERVICES
# ═══════════════════════════════════════════════════
services:

  # ─────────────────────────────────────────────────
  # PostgreSQL Database
  # ─────────────────────────────────────────────────
  postgres:
    image: pgvector/pgvector:pg${POSTGRES_VERSION}
    container_name: onestack-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_MULTIPLE_DATABASES: ${POSTGRES_DATABASES}
      TZ: ${TIMEZONE}
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./databases/postgres/init:/docker-entrypoint-initdb.d
    networks:
      - backend
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5

  # ─────────────────────────────────────────────────
  # MongoDB Database
  # ─────────────────────────────────────────────────
  mongodb:
    image: mongo:${MONGODB_VERSION}
    container_name: onestack-mongodb
    restart: unless-stopped
    environment:
      MONGO_INITDB_ROOT_USERNAME: ${MONGODB_ROOT_USERNAME}
      MONGO_INITDB_ROOT_PASSWORD: ${MONGODB_ROOT_PASSWORD}
      TZ: ${TIMEZONE}
    volumes:
      - mongodb_data:/data/db
      - ./databases/mongodb/init:/docker-entrypoint-initdb.d
    networks:
      - backend
    ports:
      - "27017:27017"
    healthcheck:
      test: echo 'db.runCommand("ping").ok' | mongosh localhost:27017/test --quiet
      interval: 10s
      timeout: 5s
      retries: 5

  # ─────────────────────────────────────────────────
  # Redis Cache
  # ─────────────────────────────────────────────────
  redis:
    image: redis:${REDIS_VERSION}
    container_name: onestack-redis
    restart: unless-stopped
    command: redis-server --requirepass ${REDIS_PASSWORD} --appendonly yes
    environment:
      TZ: ${TIMEZONE}
    volumes:
      - redis_data:/data
    networks:
      - backend
    ports:
      - "6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "--raw", "incr", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  # ─────────────────────────────────────────────────
  # MinIO Object Storage
  # ─────────────────────────────────────────────────
  minio:
    image: minio/minio:${MINIO_VERSION}
    container_name: onestack-minio
    restart: unless-stopped
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD}
      TZ: ${TIMEZONE}
    volumes:
      - minio_data:/data
    networks:
      - frontend
      - backend
    ports:
      - "9000:9000"
      - "9001:9001"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
      interval: 30s
      timeout: 20s
      retries: 3

  # ─────────────────────────────────────────────────
  # Nginx Reverse Proxy
  # ─────────────────────────────────────────────────
  nginx:
    image: nginx:alpine
    container_name: onestack-nginx
    restart: unless-stopped
    environment:
      TZ: ${TIMEZONE}
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./nginx/ssl:/etc/nginx/ssl:ro
      - ./nginx/logs:/var/log/nginx
      - ./frontends:/var/www:ro
    networks:
      - frontend
      - backend
    ports:
      - "80:80"
      - "443:443"
    depends_on:
      - postgres
      - mongodb
      - redis
      - minio
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost/health"]
      interval: 30s
      timeout: 10s
      retries: 3

EOF

    # Add Parse Server if enabled
    if [ "$INSTALL_PARSE" = "true" ]; then
        cat >> "$compose_file" << 'EOF'

  # ─────────────────────────────────────────────────
  # Parse Server (Backend-as-a-Service)
  # ─────────────────────────────────────────────────
  parse-server:
    image: parseplatform/parse-server:${PARSE_SERVER_VERSION}
    container_name: onestack-parse-server
    restart: unless-stopped
    environment:
      PARSE_SERVER_APPLICATION_ID: ${PARSE_APP_ID}
      PARSE_SERVER_MASTER_KEY: ${PARSE_MASTER_KEY}
      PARSE_SERVER_CLIENT_KEY: ${PARSE_CLIENT_KEY}
      PARSE_SERVER_DATABASE_URI: ${PARSE_DATABASE_URI}
      PARSE_SERVER_URL: ${PARSE_SERVER_URL}
      PARSE_PUBLIC_SERVER_URL: ${PARSE_PUBLIC_SERVER_URL}
      PARSE_SERVER_MOUNT_PATH: ${PARSE_MOUNT_PATH}
      TZ: ${TIMEZONE}
    volumes:
      - ./backends/parse-server/cloud:/parse-server/cloud
    networks:
      - backend
    ports:
      - "1337:1337"
    depends_on:
      - postgres
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:1337/parse/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  # Parse Dashboard
  parse-dashboard:
    image: parseplatform/parse-dashboard:latest
    container_name: onestack-parse-dashboard
    restart: unless-stopped
    environment:
      PARSE_DASHBOARD_USER_ID: ${PARSE_DASHBOARD_USER}
      PARSE_DASHBOARD_USER_PASSWORD: ${PARSE_DASHBOARD_PASSWORD}
      PARSE_DASHBOARD_APP_ID: ${PARSE_APP_ID}
      PARSE_DASHBOARD_MASTER_KEY: ${PARSE_MASTER_KEY}
      PARSE_DASHBOARD_SERVER_URL: ${PARSE_PUBLIC_SERVER_URL}
      PARSE_DASHBOARD_APP_NAME: ${PARSE_DASHBOARD_APP_NAME}
      TZ: ${TIMEZONE}
    networks:
      - backend
    ports:
      - "4040:4040"
    depends_on:
      - parse-server

EOF
    fi

    # Add Monitoring if enabled
    if [ "$INSTALL_MONITORING" = "true" ]; then
        cat >> "$compose_file" << 'EOF'

  # ─────────────────────────────────────────────────
  # Prometheus (Metrics)
  # ─────────────────────────────────────────────────
  prometheus:
    image: prom/prometheus:${PROMETHEUS_VERSION}
    container_name: onestack-prometheus
    restart: unless-stopped
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/usr/share/prometheus/console_libraries'
      - '--web.console.templates=/usr/share/prometheus/consoles'
    environment:
      TZ: ${TIMEZONE}
    volumes:
      - ./monitoring/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    networks:
      - backend
    ports:
      - "9090:9090"
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:9090/-/healthy"]
      interval: 30s
      timeout: 10s
      retries: 3

  # ─────────────────────────────────────────────────
  # Grafana (Visualization)
  # ─────────────────────────────────────────────────
  grafana:
    image: grafana/grafana:${GRAFANA_VERSION}
    container_name: onestack-grafana
    restart: unless-stopped
    environment:
      GF_SECURITY_ADMIN_USER: ${GRAFANA_ADMIN_USER}
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_ADMIN_PASSWORD}
      GF_INSTALL_PLUGINS: ""
      TZ: ${TIMEZONE}
    volumes:
      - grafana_data:/var/lib/grafana
      - ./monitoring/grafana/provisioning:/etc/grafana/provisioning:ro
    networks:
      - backend
    ports:
      - "3001:3000"
    depends_on:
      - prometheus
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:3000/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3

EOF
    fi

    # Add Adminer if enabled
    if [ "$INSTALL_ADMINER" = "true" ]; then
        cat >> "$compose_file" << 'EOF'

  # ─────────────────────────────────────────────────
  # Adminer (Database UI)
  # ─────────────────────────────────────────────────
  adminer:
    image: adminer:${ADMINER_VERSION}
    container_name: onestack-adminer
    restart: unless-stopped
    environment:
      ADMINER_DEFAULT_SERVER: postgres
      ADMINER_DESIGN: ${ADMINER_DESIGN}
      TZ: ${TIMEZONE}
    networks:
      - backend
    ports:
      - "8080:8080"
    depends_on:
      - postgres
      - mongodb

EOF
    fi

    print_success "docker-compose.yml created"
    
    chmod 644 "$compose_file"
    chown "$ONESTACK_USER:$ONESTACK_USER" "$compose_file"
    
    echo ""
}

# ════════════════════════════════════════════════
# DATABASE INIT SCRIPTS
# ════════════════════════════════════════════════

create_database_init_scripts() {
    print_header "Creating Database Initialization Scripts"
    
    # PostgreSQL - Create multiple databases
    print_step "PostgreSQL init script..."
    
    cat > "$INSTALL_DIR/databases/postgres/init/01-create-databases.sh" << 'EOF'
#!/bin/bash
set -e

# Create multiple databases from comma-separated list
if [ -n "$POSTGRES_MULTIPLE_DATABASES" ]; then
    echo "Creating multiple databases: $POSTGRES_MULTIPLE_DATABASES"
    for db in $(echo $POSTGRES_MULTIPLE_DATABASES | tr ',' ' '); do
        echo "  Creating database: $db"
        psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
            CREATE DATABASE $db;
            GRANT ALL PRIVILEGES ON DATABASE $db TO $POSTGRES_USER;
EOSQL
    done
fi
EOF

    chmod +x "$INSTALL_DIR/databases/postgres/init/01-create-databases.sh"
    
    # PostgreSQL - Enable pgvector
    cat > "$INSTALL_DIR/databases/postgres/init/02-enable-extensions.sql" << 'EOF'
-- Enable pgvector extension in main database
\c onestack_main
CREATE EXTENSION IF NOT EXISTS vector;

-- Enable in parse_db if exists
\c parse_db
CREATE EXTENSION IF NOT EXISTS vector;

EOF

    print_success "PostgreSQL init scripts created"
    
    # MongoDB init
    print_step "MongoDB init script..."
    
    cat > "$INSTALL_DIR/databases/mongodb/init/01-init.js" << 'EOF'
// MongoDB initialization script
print('OneStack MongoDB initialization started');

// Switch to admin database
db = db.getSiblingDB('admin');

// Create application database
db = db.getSiblingDB('onestack_main');
print('Created database: onestack_main');

// Create a collection to ensure database exists
db.createCollection('_init');
db._init.insertOne({ initialized: true, date: new Date() });

print('OneStack MongoDB initialization completed');
EOF

    print_success "MongoDB init scripts created"
    
    # Set ownership
    chown -R "$ONESTACK_USER:$ONESTACK_USER" "$INSTALL_DIR/databases"
    
    echo ""
}

# ════════════════════════════════════════════════
# NGINX CONFIGURATION
# ════════════════════════════════════════════════

create_nginx_config() {
    print_header "Creating Nginx Configuration"
    
    # Main nginx.conf
    print_step "Creating main nginx.conf..."
    
    cat > "$INSTALL_DIR/nginx/nginx.conf" << 'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Logging
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    
    access_log /var/log/nginx/access.log main;

    # Performance
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 100M;

    # Gzip
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript 
               application/json application/javascript application/xml+rss 
               application/rss+xml font/truetype font/opentype 
               application/vnd.ms-fontobject image/svg+xml;

    # Security Headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Health check endpoint
    server {
        listen 80 default_server;
        server_name _;
        
        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }
        
        location / {
            return 404;
        }
    }

    # Include site configurations
    include /etc/nginx/conf.d/*.conf;
}
EOF

    print_success "Main nginx.conf created"
    
    # Site configuration
    print_step "Creating site configuration..."
    
    cat > "$INSTALL_DIR/nginx/conf.d/onestack.conf" << EOF
# OneStack Site Configuration

# ─────────────────────────────────────────────────
# Main Site
# ─────────────────────────────────────────────────
server {
    listen 80;
    server_name $PRIMARY_DOMAIN www.$PRIMARY_DOMAIN;
    
    root /var/www/main;
    index index.html index.htm;
    
    location / {
        try_files \$uri \$uri/ /index.html;
    }
    
    # Static files caching
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}

# ─────────────────────────────────────────────────
# MinIO Object Storage
# ─────────────────────────────────────────────────
server {
    listen 80;
    server_name storage.$PRIMARY_DOMAIN cdn.$PRIMARY_DOMAIN;
    
    location / {
        proxy_pass http://minio:9000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # MinIO specific
        proxy_connect_timeout 300;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        chunked_transfer_encoding off;
        
        client_max_body_size 0;
    }
}

# MinIO Console
server {
    listen 80;
    server_name minio.$PRIMARY_DOMAIN;
    
    location / {
        proxy_pass http://minio:9001;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

EOF

    # Add Parse Server config if enabled
    if [ "$INSTALL_PARSE" = "true" ]; then
        cat >> "$INSTALL_DIR/nginx/conf.d/onestack.conf" << 'EOF'

# ─────────────────────────────────────────────────
# Parse Server API
# ─────────────────────────────────────────────────
server {
    listen 80;
    server_name api.$PRIMARY_DOMAIN;
    
    location /parse {
        proxy_pass http://parse-server:1337;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    location /dashboard {
        proxy_pass http://parse-dashboard:4040;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}

EOF
    fi

    # Add Monitoring config if enabled
    if [ "$INSTALL_MONITORING" = "true" ]; then
        cat >> "$INSTALL_DIR/nginx/conf.d/onestack.conf" << 'EOF'

# ─────────────────────────────────────────────────
# Monitoring
# ─────────────────────────────────────────────────
server {
    listen 80;
    server_name monitor.$PRIMARY_DOMAIN grafana.$PRIMARY_DOMAIN;
    
    location / {
        proxy_pass http://grafana:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}

server {
    listen 80;
    server_name prometheus.$PRIMARY_DOMAIN;
    
    location / {
        proxy_pass http://prometheus:9090;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}

EOF
    fi

    # Add Adminer config if enabled
    if [ "$INSTALL_ADMINER" = "true" ]; then
        cat >> "$INSTALL_DIR/nginx/conf.d/onestack.conf" << 'EOF'

# ─────────────────────────────────────────────────
# Adminer (Database UI)
# ─────────────────────────────────────────────────
server {
    listen 80;
    server_name db.$PRIMARY_DOMAIN adminer.$PRIMARY_DOMAIN;
    
    location / {
        proxy_pass http://adminer:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}

EOF
    fi

    print_success "Nginx configuration created"
    
    # Set ownership
    chown -R "$ONESTACK_USER:$ONESTACK_USER" "$INSTALL_DIR/nginx"
    
    echo ""
}

# ════════════════════════════════════════════════
# MONITORING CONFIGURATION
# ════════════════════════════════════════════════

create_monitoring_config() {
    if [ "$INSTALL_MONITORING" != "true" ]; then
        return 0
    fi
    
    print_header "Creating Monitoring Configuration"
    
    # Prometheus config
    print_step "Creating prometheus.yml..."
    
    cat > "$INSTALL_DIR/monitoring/prometheus/prometheus.yml" << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'onestack'
    environment: 'production'

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'postgres'
    static_configs:
      - targets: ['postgres:5432']

  - job_name: 'mongodb'
    static_configs:
      - targets: ['mongodb:27017']

  - job_name: 'redis'
    static_configs:
      - targets: ['redis:6379']

  - job_name: 'minio'
    static_configs:
      - targets: ['minio:9000']
EOF

    print_success "Prometheus configuration created"
    
    # Grafana datasource
    print_step "Creating Grafana datasource..."
    
    mkdir -p "$INSTALL_DIR/monitoring/grafana/provisioning/datasources"
    
    cat > "$INSTALL_DIR/monitoring/grafana/provisioning/datasources/prometheus.yml" << 'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true
EOF

    print_success "Grafana datasource created"
    
    # Set ownership
    chown -R "$ONESTACK_USER:$ONESTACK_USER" "$INSTALL_DIR/monitoring"
    
    echo ""
}

# ════════════════════════════════════════════════
# CREATE DEFAULT FRONTEND
# ════════════════════════════════════════════════

create_default_frontend() {
    print_header "Creating Default Frontend"
    
    print_step "Creating welcome page..."
    
    cat > "$INSTALL_DIR/frontends/main/index.html" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>OneStack - Welcome</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }
        .container {
            background: white;
            border-radius: 20px;
            padding: 60px 40px;
            max-width: 800px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            text-align: center;
        }
        h1 {
            font-size: 3em;
            color: #333;
            margin-bottom: 20px;
        }
        .emoji { font-size: 4em; margin-bottom: 20px; }
        p { font-size: 1.2em; color: #666; margin-bottom: 30px; line-height: 1.6; }
        .status { display: inline-block; background: #10b981; color: white; padding: 10px 20px; border-radius: 50px; font-weight: bold; margin-bottom: 30px; }
        .services {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin-top: 30px;
        }
        .service {
            background: #f9fafb;
            padding: 20px;
            border-radius: 10px;
            text-decoration: none;
            color: #333;
            transition: all 0.3s;
            border: 2px solid transparent;
        }
        .service:hover {
            transform: translateY(-5px);
            border-color: #667eea;
            box-shadow: 0 10px 20px rgba(0,0,0,0.1);
        }
        .service-name { font-weight: bold; margin-bottom: 5px; color: #667eea; }
        .service-desc { font-size: 0.9em; color: #666; }
        .footer { margin-top: 40px; font-size: 0.9em; color: #999; }
        .footer a { color: #667eea; text-decoration: none; }
    </style>
</head>
<body>
    <div class="container">
        <div class="emoji">🚀</div>
        <h1>OneStack</h1>
        <div class="status">✓ System Running</div>
        <p>Your self-hosted SME platform is up and running!<br>All services are operational.</p>
        
        <div class="services">
            <a href="http://storage.$PRIMARY_DOMAIN:9001" class="service" target="_blank">
                <div class="service-name">📦 MinIO Console</div>
                <div class="service-desc">Object Storage</div>
            </a>
EOF

    if [ "$INSTALL_PARSE" = "true" ]; then
        cat >> "$INSTALL_DIR/frontends/main/index.html" << EOF
            <a href="http://api.$PRIMARY_DOMAIN:1337/dashboard" class="service" target="_blank">
                <div class="service-name">🔧 Parse Dashboard</div>
                <div class="service-desc">Backend Management</div>
            </a>
EOF
    fi

    if [ "$INSTALL_MONITORING" = "true" ]; then
        cat >> "$INSTALL_DIR/frontends/main/index.html" << EOF
            <a href="http://monitor.$PRIMARY_DOMAIN:3001" class="service" target="_blank">
                <div class="service-name">📊 Grafana</div>
                <div class="service-desc">Monitoring Dashboard</div>
            </a>
            <a href="http://prometheus.$PRIMARY_DOMAIN:9090" class="service" target="_blank">
                <div class="service-name">📈 Prometheus</div>
                <div class="service-desc">Metrics</div>
            </a>
EOF
    fi

    if [ "$INSTALL_ADMINER" = "true" ]; then
        cat >> "$INSTALL_DIR/frontends/main/index.html" << EOF
            <a href="http://db.$PRIMARY_DOMAIN:8080" class="service" target="_blank">
                <div class="service-name">🗄️ Adminer</div>
                <div class="service-desc">Database UI</div>
            </a>
EOF
    fi

    cat >> "$INSTALL_DIR/frontends/main/index.html" << EOF
        </div>
        
        <div class="footer">
            <p>Installed: $(date)</p>
            <p>Domain: <strong>$PRIMARY_DOMAIN</strong></p>
            <p>Credentials: <code>cat $INSTALL_DIR/.credentials</code></p>
        </div>
    </div>
</body>
</html>
EOF

    print_success "Welcome page created"
    
    # Set ownership
    chown -R "$ONESTACK_USER:$ONESTACK_USER" "$INSTALL_DIR/frontends"
    
    echo ""
}

# ════════════════════════════════════════════════
# DEPLOY SERVICES
# ════════════════════════════════════════════════

deploy_services() {
    print_header "Deploying Services"
    
    print_step "Pulling Docker images..."
    cd "$INSTALL_DIR"
    
    # Pull images as onestack user
    if sudo -u "$ONESTACK_USER" docker compose pull 2>&1 | grep -E "(Pulling|Downloaded|up to date)"; then
        print_success "Docker images pulled"
    else
        print_warning "Some images may have failed to pull"
    fi
    
    echo ""
    print_step "Starting services..."
    
    # Start services
    if sudo -u "$ONESTACK_USER" docker compose up -d; then
        print_success "Services started"
    else
        error_exit "Failed to start services"
    fi
    
    echo ""
}

# ════════════════════════════════════════════════
# HEALTH CHECKS
# ════════════════════════════════════════════════

wait_for_services() {
    print_header "Waiting for Services"
    
    print_info "This may take 1-2 minutes..."
    echo ""
    
    local max_wait=120
    local waited=0
    local interval=5
    
    cd "$INSTALL_DIR"
    
    while [ $waited -lt $max_wait ]; do
        local healthy=true
        
        # Check each service
        for service in postgres mongodb redis minio nginx; do
            if ! docker compose ps "$service" 2>/dev/null | grep -q "Up"; then
                healthy=false
                break
            fi
        done
        
        if [ "$healthy" = true ]; then
            print_success "All core services are running!"
            return 0
        fi
        
        echo -n "."
        sleep $interval
        waited=$((waited + interval))
    done
    
    echo ""
    print_warning "Some services may not be fully ready yet"
    print_info "Check status with: docker compose ps"
    
    return 0
}

verify_services() {
    print_header "Service Status"
    
    cd "$INSTALL_DIR"
    
    # Show service status
    docker compose ps
    
    echo ""
}

# ════════════════════════════════════════════════
# DISPLAY ACCESS INFO
# ════════════════════════════════════════════════

display_access_info() {
    print_header "🎉 Installation Complete!"
    
    local server_ip=$(get_server_ip)
    
    echo ""
    print_success "OneStack is now running!"
    echo ""
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  ACCESS URLS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    if [ "$PRIMARY_DOMAIN" = "localhost" ]; then
        echo "Main Site:"
        echo "  http://localhost"
        echo ""
        echo "MinIO Console:"
        echo "  http://localhost:9001"
        echo ""
        
        if [ "$INSTALL_PARSE" = "true" ]; then
            echo "Parse Dashboard:"
            echo "  http://localhost:4040"
            echo ""
        fi
        
        if [ "$INSTALL_MONITORING" = "true" ]; then
            echo "Grafana:"
            echo "  http://localhost:3001"
            echo ""
            echo "Prometheus:"
            echo "  http://localhost:9090"
            echo ""
        fi
        
        if [ "$INSTALL_ADMINER" = "true" ]; then
            echo "Adminer:"
            echo "  http://localhost:8080"
            echo ""
        fi
    else
        echo "Main Site:"
        echo "  http://$PRIMARY_DOMAIN"
        echo "  http://$server_ip"
        echo ""
        echo "MinIO Console:"
        echo "  http://storage.$PRIMARY_DOMAIN:9001"
        echo ""
        
        if [ "$INSTALL_PARSE" = "true" ]; then
            echo "Parse Dashboard:"
            echo "  http://api.$PRIMARY_DOMAIN:1337/dashboard"
            echo ""
        fi
        
        if [ "$INSTALL_MONITORING" = "true" ]; then
            echo "Grafana:"
            echo "  http://monitor.$PRIMARY_DOMAIN:3001"
            echo ""
            echo "Prometheus:"
            echo "  http://prometheus.$PRIMARY_DOMAIN:9090"
            echo ""
        fi
        
        if [ "$INSTALL_ADMINER" = "true" ]; then
            echo "Adminer:"
            echo "  http://db.$PRIMARY_DOMAIN:8080"
            echo ""
        fi
        
        print_warning "Note: Update your DNS or /etc/hosts to point domains to $server_ip"
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  CREDENTIALS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    print_info "All credentials saved to:"
    echo "  $INSTALL_DIR/.credentials"
    echo ""
    print_info "View credentials:"
    echo "  cat $INSTALL_DIR/.credentials"
    echo ""
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  USEFUL COMMANDS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "View logs:"
    echo "  cd $INSTALL_DIR && docker compose logs -f"
    echo ""
    echo "Stop services:"
    echo "  cd $INSTALL_DIR && docker compose stop"
    echo ""
    echo "Start services:"
    echo "  cd $INSTALL_DIR && docker compose start"
    echo ""
    echo "Restart services:"
    echo "  cd $INSTALL_DIR && docker compose restart"
    echo ""
    echo "Check status:"
    echo "  cd $INSTALL_DIR && docker compose ps"
    echo ""
    echo "Uninstall:"
    echo "  sudo bash uninstall.sh"
    echo ""
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# ════════════════════════════════════════════════
# MAIN DEPLOYMENT FUNCTION
# ════════════════════════════════════════════════

run_onestack_setup() {
    print_header "OneStack Service Deployment"
    
    print_info "This will deploy OneStack services"
    echo ""
    
    # Must be run as root
    check_root
    
    # Load configuration
    load_vars
    
    # Verify installation directory
    if [ -z "$INSTALL_DIR" ] || [ ! -d "$INSTALL_DIR" ]; then
        error_exit "Installation directory not found. Run Phase 1 first."
    fi
    
    # Verify onestack user exists
    if ! id "$ONESTACK_USER" &>/dev/null; then
        error_exit "OneStack user not found. Run Phase 1 first."
    fi
    
    print_success "Prerequisites verified"
    echo ""
    
    if ! confirm "Continue with deployment?"; then
        print_info "Deployment cancelled"
        exit 0
    fi
    
    # Run deployment steps
    create_directory_structure
    generate_passwords
    create_env_file
    create_database_init_scripts
    create_docker_compose
    create_nginx_config
    create_monitoring_config
    create_default_frontend
    
    # Deploy
    deploy_services
    wait_for_services
    verify_services
    
    # Success
    display_access_info
    
    # Save completion state
    save_var "PHASE_2_COMPLETE" "true"
    save_var "DEPLOYMENT_DATE" "$(date)"
    
    success_message "OneStack deployment completed successfully! 🎉"
}

# Export functions
export -f create_directory_structure generate_passwords save_credentials
export -f create_env_file create_docker_compose create_database_init_scripts
export -f create_nginx_config create_monitoring_config create_default_frontend
export -f deploy_services wait_for_services verify_services
export -f display_access_info run_onestack_setup