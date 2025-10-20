#!/bin/bash
# OneStack - Service Deployment (FINAL FIX)

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LIB_DIR/utils.sh"

# ════════════════════════════════════════════════
# CHECK NGINX CONFLICT
# ════════════════════════════════════════════════

check_nginx_conflict() {
    print_header "Checking for Port Conflicts"
    
    # Check if port 80 is in use
    if ss -tulpn | grep -q ":80 "; then
        print_warning "Port 80 is already in use!"
        echo ""
        echo "Services using port 80:"
        ss -tulpn | grep ":80 " || true
        echo ""
        
        # Check if it's system nginx
        if systemctl is-active --quiet nginx 2>/dev/null; then
            print_warning "System Nginx is running"
            echo ""
            
            if confirm "Stop system Nginx? (Recommended)"; then
                print_step "Stopping system Nginx..."
                systemctl stop nginx
                systemctl disable nginx
                print_success "System Nginx stopped and disabled"
            else
                print_error "Cannot proceed with port 80 in use"
                echo ""
                print_info "Options:"
                echo "  1. Stop nginx: sudo systemctl stop nginx"
                echo "  2. Use different ports for OneStack"
                exit 1
            fi
        else
            print_error "Port 80 is in use by another service"
            echo ""
            print_info "Free port 80 first, then run installer again"
            exit 1
        fi
    else
        print_success "Port 80 is available"
    fi
    
    # Check port 443
    if ss -tulpn | grep -q ":443 "; then
        print_warning "Port 443 is already in use"
        if systemctl is-active --quiet nginx 2>/dev/null; then
            systemctl stop nginx
            print_success "Stopped system Nginx"
        fi
    fi
    
    echo ""
}

# ════════════════════════════════════════════════
# DIRECTORY STRUCTURE
# ════════════════════════════════════════════════

create_directory_structure() {
    print_header "Creating Directory Structure"
    
    local base_dir="$INSTALL_DIR"
    
    print_step "Creating directories in: $base_dir"
    
    local dirs=(
        "nginx/conf.d"
        "nginx/ssl"
        "nginx/logs"
        "databases/postgres/init"
        "databases/mongodb/init"
        "databases/redis"
        "frontends/main"
        "frontends/app"
        "frontends/admin"
        "backends/parse-server/cloud"
        "backends/nodejs-api"
        "backends/python-rag"
        "monitoring/prometheus"
        "monitoring/grafana/provisioning/datasources"
        "monitoring/grafana/provisioning/dashboards"
        "backups"
        "logs"
        "config"
        "scripts"
        "parse-dashboard"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$base_dir/$dir"
    done
    
    print_success "Directory structure created"
    chown -R "$ONESTACK_USER:$ONESTACK_USER" "$base_dir" 2>/dev/null || true
    
    echo ""
}

# ════════════════════════════════════════════════
# PASSWORD GENERATION
# ════════════════════════════════════════════════

generate_passwords() {
    print_header "Generating Secure Passwords"
    
    print_step "Creating secure credentials..."
    
    export POSTGRES_PASSWORD=$(generate_password 32)
    export MONGODB_PASSWORD=$(generate_password 32)
    export REDIS_PASSWORD=$(generate_password 32)
    export MINIO_ROOT_PASSWORD=$(generate_password 32)
    export GRAFANA_PASSWORD=$(generate_password 24)
    
    if [ "$INSTALL_PARSE" = "true" ]; then
        export PARSE_APP_ID=$(generate_password 16)
        export PARSE_MASTER_KEY=$(generate_password 48)
        export PARSE_CLIENT_KEY=$(generate_password 32)
        export PARSE_DASHBOARD_PASSWORD=$(generate_password 24)
    fi
    
    print_success "Passwords generated"
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

PostgreSQL:
  Host: localhost:5432
  User: postgres
  Password: $POSTGRES_PASSWORD

MongoDB:
  Host: localhost:27017
  User: admin
  Password: $MONGODB_PASSWORD

Redis:
  Host: localhost:6379
  Password: $REDIS_PASSWORD

MinIO:
  Console: http://storage.$PRIMARY_DOMAIN
  S3 API: http://s3.$PRIMARY_DOMAIN
  User: minioadmin
  Password: $MINIO_ROOT_PASSWORD

EOF

    if [ "$INSTALL_MONITORING" = "true" ]; then
        cat >> "$cred_file" << EOF
Grafana:
  URL: http://monitor.$PRIMARY_DOMAIN
  User: admin
  Password: $GRAFANA_PASSWORD

Prometheus:
  URL: http://prometheus.$PRIMARY_DOMAIN

EOF
    fi

    if [ "$INSTALL_PARSE" = "true" ]; then
        cat >> "$cred_file" << EOF
Parse Server:
  API: http://api.$PRIMARY_DOMAIN/parse
  Dashboard: http://api.$PRIMARY_DOMAIN
  Dashboard User: admin
  Dashboard Password: $PARSE_DASHBOARD_PASSWORD
  App ID: $PARSE_APP_ID
  Master Key: $PARSE_MASTER_KEY
  Client Key: $PARSE_CLIENT_KEY

EOF
    fi

    if [ "$INSTALL_ADMINER" = "true" ]; then
        cat >> "$cred_file" << EOF
Adminer:
  URL: http://db.$PRIMARY_DOMAIN

EOF
    fi

    cat >> "$cred_file" << 'EOF'
═══════════════════════════════════════════════════
Keep this file secure!
═══════════════════════════════════════════════════
EOF
    
    chmod 600 "$cred_file"
    chown "$ONESTACK_USER:$ONESTACK_USER" "$cred_file"
}

# ════════════════════════════════════════════════
# .ENV FILE (FIXED - Use PRIMARY_DOMAIN correctly)
# ════════════════════════════════════════════════

create_env_file() {
    print_header "Creating Environment Configuration"
    
    local env_file="$INSTALL_DIR/.env"
    
    print_step "Generating .env file..."
    print_info "Domain: $PRIMARY_DOMAIN"
    
    cat > "$env_file" << EOF
# OneStack Environment Configuration
# Generated: $(date)

COMPOSE_PROJECT_NAME=onestack
TIMEZONE=${CONFIG_system_timezone:-Asia/Bangkok}
NODE_ENV=production

# DOMAIN (used by all services)
PRIMARY_DOMAIN=$PRIMARY_DOMAIN
DOMAIN=$PRIMARY_DOMAIN
SSL_EMAIL=$SSL_EMAIL

# POSTGRESQL
POSTGRES_VERSION=${CONFIG_database_postgres_version:-16}
POSTGRES_USER=postgres
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_DB=onestack_main
POSTGRES_DATABASES=onestack_main,parse_db

# MONGODB
MONGODB_VERSION=${CONFIG_database_mongodb_version:-7}
MONGODB_ROOT_USERNAME=admin
MONGODB_ROOT_PASSWORD=$MONGODB_PASSWORD

# REDIS
REDIS_VERSION=${CONFIG_database_redis_version:-alpine}
REDIS_PASSWORD=$REDIS_PASSWORD

# MINIO
MINIO_VERSION=latest
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=$MINIO_ROOT_PASSWORD

EOF

    if [ "$INSTALL_PARSE" = "true" ]; then
        cat >> "$env_file" << EOF
# PARSE SERVER
PARSE_SERVER_VERSION=latest
PARSE_APP_ID=$PARSE_APP_ID
PARSE_MASTER_KEY=$PARSE_MASTER_KEY
PARSE_CLIENT_KEY=$PARSE_CLIENT_KEY
PARSE_DATABASE_URI=postgres://postgres:$POSTGRES_PASSWORD@postgres:5432/parse_db
PARSE_SERVER_URL=http://parse-server:1337/parse
PARSE_PUBLIC_SERVER_URL=http://api.$PRIMARY_DOMAIN/parse

# PARSE DASHBOARD
PARSE_DASHBOARD_USER=admin
PARSE_DASHBOARD_PASSWORD=$PARSE_DASHBOARD_PASSWORD
PARSE_DASHBOARD_APP_NAME=OneStack

EOF
    fi

    if [ "$INSTALL_MONITORING" = "true" ]; then
        cat >> "$env_file" << EOF
# MONITORING
GRAFANA_VERSION=latest
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=$GRAFANA_PASSWORD
PROMETHEUS_VERSION=latest

EOF
    fi

    if [ "$INSTALL_ADMINER" = "true" ]; then
        cat >> "$env_file" << EOF
# ADMINER
ADMINER_VERSION=latest

EOF
    fi

    cat >> "$env_file" << EOF
# NETWORK
DOCKER_NETWORK_SUBNET=${CONFIG_advanced_docker_subnet:-172.20.0.0/16}
EOF
    
    chmod 600 "$env_file"
    chown "$ONESTACK_USER:$ONESTACK_USER" "$env_file"
    
    print_success ".env file created with domain: $PRIMARY_DOMAIN"
    echo ""
}

# ════════════════════════════════════════════════
# DOCKER COMPOSE
# ════════════════════════════════════════════════

create_docker_compose() {
    print_header "Creating Docker Compose Configuration"
    
    local compose_file="$INSTALL_DIR/docker-compose.yml"
    
    print_step "Generating docker-compose.yml..."
    
    cat > "$compose_file" << 'DCEOF'
networks:
  frontend:
  backend:

volumes:
  postgres_data:
  mongodb_data:
  redis_data:
  minio_data:
  grafana_data:
  prometheus_data:

services:
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
    networks:
      - backend
    ports:
      - "27017:27017"
    healthcheck:
      test: echo 'db.runCommand("ping").ok' | mongosh localhost:27017/test --quiet
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:${REDIS_VERSION}
    container_name: onestack-redis
    restart: unless-stopped
    command: redis-server --requirepass ${REDIS_PASSWORD}
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

  nginx:
    image: nginx:alpine
    container_name: onestack-nginx
    restart: unless-stopped
    environment:
      DOMAIN: ${PRIMARY_DOMAIN}
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./nginx/logs:/var/log/nginx
      - ./frontends:/var/www:ro
    networks:
      - frontend
      - backend
    ports:
      - "80:80"
      - "443:443"
DCEOF

    if [ "$INSTALL_PARSE" = "true" ]; then
        cat >> "$compose_file" << 'PARSEDC'

  parse-server:
    image: parseplatform/parse-server:${PARSE_SERVER_VERSION}
    container_name: onestack-parse-server
    restart: unless-stopped
    environment:
      PARSE_SERVER_APPLICATION_ID: ${PARSE_APP_ID}
      PARSE_SERVER_MASTER_KEY: ${PARSE_MASTER_KEY}
      PARSE_SERVER_DATABASE_URI: ${PARSE_DATABASE_URI}
      PARSE_SERVER_URL: ${PARSE_SERVER_URL}
      PARSE_PUBLIC_SERVER_URL: ${PARSE_PUBLIC_SERVER_URL}
      TZ: ${TIMEZONE}
    volumes:
      - ./backends/parse-server/cloud:/parse-server/cloud
    networks:
      - backend
    ports:
      - "1337:1337"
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:1337/parse/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  parse-dashboard:
    image: parseplatform/parse-dashboard:5.2.0
    container_name: onestack-parse-dashboard
    restart: unless-stopped
    volumes:
      - ./parse-dashboard/config.json:/src/Parse-Dashboard/parse-dashboard-config.json:ro
    environment:
      PARSE_DASHBOARD_ALLOW_INSECURE_HTTP: "true"
      PARSE_DASHBOARD_CONFIG: /src/Parse-Dashboard/parse-dashboard-config.json
      TZ: ${TIMEZONE}
    command: parse-dashboard --config /src/Parse-Dashboard/parse-dashboard-config.json --allowInsecureHTTP
    networks:
      - backend
    ports:
      - "4040:4040"
    depends_on:
      - parse-server
PARSEDC
    fi

    if [ "$INSTALL_MONITORING" = "true" ]; then
        cat >> "$compose_file" << 'MONDC'

  prometheus:
    image: prom/prometheus:${PROMETHEUS_VERSION}
    container_name: onestack-prometheus
    restart: unless-stopped
    command: ['--config.file=/etc/prometheus/prometheus.yml']
    volumes:
      - ./monitoring/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    networks:
      - backend
    ports:
      - "9090:9090"

  grafana:
    image: grafana/grafana:${GRAFANA_VERSION}
    container_name: onestack-grafana
    restart: unless-stopped
    environment:
      GF_SECURITY_ADMIN_USER: ${GRAFANA_ADMIN_USER}
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_ADMIN_PASSWORD}
      TZ: ${TIMEZONE}
    volumes:
      - grafana_data:/var/lib/grafana
      - ./monitoring/grafana/provisioning:/etc/grafana/provisioning:ro
    networks:
      - backend
    ports:
      - "3001:3000"
MONDC
    fi

    if [ "$INSTALL_ADMINER" = "true" ]; then
        cat >> "$compose_file" << 'ADMDC'

  adminer:
    image: adminer:${ADMINER_VERSION}
    container_name: onestack-adminer
    restart: unless-stopped
    environment:
      TZ: ${TIMEZONE}
    networks:
      - backend
    ports:
      - "8080:8080"
ADMDC
    fi

    chmod 644 "$compose_file"
    chown "$ONESTACK_USER:$ONESTACK_USER" "$compose_file"
    
    print_success "docker-compose.yml created"
    echo ""
}

# ════════════════════════════════════════════════
# DATABASE INIT
# ════════════════════════════════════════════════

create_database_init_scripts() {
    print_header "Creating Database Init Scripts"
    
    cat > "$INSTALL_DIR/databases/postgres/init/01-create-databases.sh" << 'PGINIT'
#!/bin/bash
set -e

if [ -n "$POSTGRES_MULTIPLE_DATABASES" ]; then
    for db in $(echo $POSTGRES_MULTIPLE_DATABASES | tr ',' ' '); do
        echo "Creating database: $db"
        psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
            CREATE DATABASE $db;
EOSQL
    done
fi
PGINIT

    chmod +x "$INSTALL_DIR/databases/postgres/init/01-create-databases.sh"
    
    print_success "Database init scripts created"
    echo ""
}

# ════════════════════════════════════════════════
# PARSE DASHBOARD CONFIG (FIXED - Use env vars)
# ════════════════════════════════════════════════

create_parse_dashboard_config() {
    if [ "$INSTALL_PARSE" != "true" ]; then
        return 0
    fi
    
    print_header "Creating Parse Dashboard Config"
    
    print_step "Generating Parse Dashboard configuration..."
    print_info "Using domain: $PRIMARY_DOMAIN"
    
    # Use variables from environment
    cat > "$INSTALL_DIR/parse-dashboard/config.json" << EOF
{
  "apps": [
    {
      "serverURL": "http://parse-server:1337/parse",
      "appId": "$PARSE_APP_ID",
      "masterKey": "$PARSE_MASTER_KEY",
      "appName": "OneStack",
      "production": false
    }
  ],
  "users": [
    {
      "user": "admin",
      "pass": "$PARSE_DASHBOARD_PASSWORD"
    }
  ],
  "useEncryptedPasswords": false,
  "trustProxy": 1
}
EOF
    
    chmod 644 "$INSTALL_DIR/parse-dashboard/config.json"
    chown "$ONESTACK_USER:$ONESTACK_USER" "$INSTALL_DIR/parse-dashboard/config.json"
    
    # Cloud code
    cat > "$INSTALL_DIR/backends/parse-server/cloud/main.js" << 'CLOUDCODE'
// Parse Cloud Code
Parse.Cloud.define('hello', async (request) => {
  return 'Hello from OneStack!';
});
CLOUDCODE
    
    print_success "Parse Dashboard config created"
    echo ""
}

# ════════════════════════════════════════════════
# NGINX CONFIG (FIXED - Use env variable)
# ════════════════════════════════════════════════

create_nginx_config() {
    print_header "Creating Nginx Configuration"
    
    print_step "Using domain: $PRIMARY_DOMAIN"
    
    cat > "$INSTALL_DIR/nginx/nginx.conf" << 'NGXMAIN'
user nginx;
worker_processes auto;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent"';
    
    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log warn;
    
    sendfile on;
    keepalive_timeout 65;
    client_max_body_size 100M;
    
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml;
    
    include /etc/nginx/conf.d/*.conf;
}
NGXMAIN

    # Use actual domain value, not variable
    cat > "$INSTALL_DIR/nginx/conf.d/onestack.conf" << EOF
# OneStack Nginx Configuration
# Domain: $PRIMARY_DOMAIN

# Main Site
server {
    listen 80;
    server_name $PRIMARY_DOMAIN www.$PRIMARY_DOMAIN;
    
    root /var/www/main;
    index index.html;
    
    location / {
        try_files \$uri \$uri/ /index.html;
    }
}

# MinIO Console
server {
    listen 80;
    server_name storage.$PRIMARY_DOMAIN minio.$PRIMARY_DOMAIN;
    
    location / {
        proxy_pass http://minio:9001;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

# MinIO S3 API
server {
    listen 80;
    server_name s3.$PRIMARY_DOMAIN cdn.$PRIMARY_DOMAIN;
    
    client_max_body_size 0;
    
    location / {
        proxy_pass http://minio:9000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}

EOF

    if [ "$INSTALL_PARSE" = "true" ]; then
        cat >> "$INSTALL_DIR/nginx/conf.d/onestack.conf" << EOF

# Parse Server & Dashboard
server {
    listen 80;
    server_name api.$PRIMARY_DOMAIN parse.$PRIMARY_DOMAIN;
    
    # Parse Server API
    location /parse {
        proxy_pass http://parse-server:1337;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_read_timeout 300s;
    }
    
    # Parse Dashboard
    location / {
        proxy_pass http://parse-dashboard:4040;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}

EOF
    fi

    if [ "$INSTALL_MONITORING" = "true" ]; then
        cat >> "$INSTALL_DIR/nginx/conf.d/onestack.conf" << EOF

# Grafana
server {
    listen 80;
    server_name monitor.$PRIMARY_DOMAIN grafana.$PRIMARY_DOMAIN;
    
    location / {
        proxy_pass http://grafana:3000;
        proxy_set_header Host \$host;
    }
}

# Prometheus
server {
    listen 80;
    server_name prometheus.$PRIMARY_DOMAIN metrics.$PRIMARY_DOMAIN;
    
    location / {
        proxy_pass http://prometheus:9090;
        proxy_set_header Host \$host;
    }
}

EOF
    fi

    if [ "$INSTALL_ADMINER" = "true" ]; then
        cat >> "$INSTALL_DIR/nginx/conf.d/onestack.conf" << EOF

# Adminer
server {
    listen 80;
    server_name db.$PRIMARY_DOMAIN adminer.$PRIMARY_DOMAIN;
    
    location / {
        proxy_pass http://adminer:8080;
        proxy_set_header Host \$host;
    }
}

EOF
    fi

    cat >> "$INSTALL_DIR/nginx/conf.d/onestack.conf" << 'DEFNX'

# Default server (health check)
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
DEFNX

    chown -R "$ONESTACK_USER:$ONESTACK_USER" "$INSTALL_DIR/nginx"
    print_success "Nginx configured for domain: $PRIMARY_DOMAIN"
    echo ""
}

# ════════════════════════════════════════════════
# MONITORING CONFIG
# ════════════════════════════════════════════════

create_monitoring_config() {
    if [ "$INSTALL_MONITORING" != "true" ]; then
        return 0
    fi
    
    print_header "Creating Monitoring Config"
    
    cat > "$INSTALL_DIR/monitoring/prometheus/prometheus.yml" << 'PROM'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
      
  - job_name: 'node'
    static_configs:
      - targets: ['host.docker.internal:9100']
PROM

    cat > "$INSTALL_DIR/monitoring/grafana/provisioning/datasources/prometheus.yml" << 'GRAF'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true
GRAF

    print_success "Monitoring configured"
    echo ""
}

# ════════════════════════════════════════════════
# DEFAULT FRONTEND
# ════════════════════════════════════════════════

create_default_frontend() {
    print_header "Creating Welcome Page"
    
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
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
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
            max-width: 900px;
            width: 100%;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            text-align: center;
        }
        .logo { font-size: 5em; margin-bottom: 20px; }
        h1 { font-size: 3.5em; color: #333; margin-bottom: 10px; }
        .version { color: #999; font-size: 1em; margin-bottom: 20px; }
        .status {
            display: inline-block;
            background: #10b981;
            color: white;
            padding: 12px 30px;
            border-radius: 50px;
            font-weight: bold;
            margin-bottom: 30px;
        }
        .domain {
            background: #f3f4f6;
            padding: 15px;
            border-radius: 10px;
            margin-bottom: 30px;
            font-family: monospace;
            color: #667eea;
            font-weight: bold;
        }
        .links {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin-top: 30px;
        }
        a {
            background: #f3f4f6;
            padding: 25px 15px;
            border-radius: 10px;
            text-decoration: none;
            color: #333;
            transition: 0.3s;
            display: block;
        }
        a:hover {
            transform: translateY(-5px);
            box-shadow: 0 10px 20px rgba(0,0,0,0.1);
            background: white;
        }
        .service-icon { font-size: 2em; margin-bottom: 10px; }
        .service-name { font-weight: bold; color: #667eea; margin-bottom: 5px; }
        .service-url { font-size: 0.85em; color: #999; }
    </style>
</head>
<body>
    <div class="container">
        <div class="logo">🚀</div>
        <h1>OneStack</h1>
        <div class="version">v2.0 Production</div>
        <div class="status">✓ System Running</div>
        
        <div class="domain">$PRIMARY_DOMAIN</div>
        
        <div class="links">
            <a href="http://storage.$PRIMARY_DOMAIN">
                <div class="service-icon">📦</div>
                <div class="service-name">MinIO Console</div>
                <div class="service-url">storage.$PRIMARY_DOMAIN</div>
            </a>
            
            <a href="http://s3.$PRIMARY_DOMAIN">
                <div class="service-icon">☁️</div>
                <div class="service-name">S3 API</div>
                <div class="service-url">s3.$PRIMARY_DOMAIN</div>
            </a>
EOF

    [ "$INSTALL_PARSE" = "true" ] && cat >> "$INSTALL_DIR/frontends/main/index.html" << EOF
            
            <a href="http://api.$PRIMARY_DOMAIN">
                <div class="service-icon">⚡</div>
                <div class="service-name">Parse Dashboard</div>
                <div class="service-url">api.$PRIMARY_DOMAIN</div>
            </a>
EOF

    [ "$INSTALL_MONITORING" = "true" ] && cat >> "$INSTALL_DIR/frontends/main/index.html" << EOF
            
            <a href="http://monitor.$PRIMARY_DOMAIN">
                <div class="service-icon">📊</div>
                <div class="service-name">Grafana</div>
                <div class="service-url">monitor.$PRIMARY_DOMAIN</div>
            </a>
EOF

    [ "$INSTALL_ADMINER" = "true" ] && cat >> "$INSTALL_DIR/frontends/main/index.html" << EOF
            
            <a href="http://db.$PRIMARY_DOMAIN">
                <div class="service-icon">🗄️</div>
                <div class="service-name">Adminer</div>
                <div class="service-url">db.$PRIMARY_DOMAIN</div>
            </a>
EOF

    cat >> "$INSTALL_DIR/frontends/main/index.html" << 'HTMLEND'
        </div>
    </div>
</body>
</html>
HTMLEND

    chown -R "$ONESTACK_USER:$ONESTACK_USER" "$INSTALL_DIR/frontends"
    print_success "Welcome page created"
    echo ""
}

# ════════════════════════════════════════════════
# DEPLOY SERVICES
# ════════════════════════════════════════════════

deploy_services() {
    print_header "Deploying Services"
    
    cd "$INSTALL_DIR"
    
    print_step "Pulling Docker images..."
    
    if docker compose pull 2>&1 | tee -a "${LOG_FILE:-/var/log/onestack-install.log}"; then
        print_success "Images pulled"
    else
        print_warning "Some images may have failed"
    fi
    
    echo ""
    print_step "Starting services..."
    
    if docker compose up -d 2>&1 | tee -a "${LOG_FILE:-/var/log/onestack-install.log}"; then
        print_success "Services started"
    else
        print_error "Failed to start services"
        return 1
    fi
    
    print_step "Setting permissions..."
    chown -R "$ONESTACK_USER:$ONESTACK_USER" "$INSTALL_DIR" 2>/dev/null || true
    
    echo ""
}

# ════════════════════════════════════════════════
# WAIT & VERIFY
# ════════════════════════════════════════════════

wait_for_services() {
    print_header "Waiting for Services"
    
    print_info "Waiting 30 seconds for services to initialize..."
    sleep 30
    
    cd "$INSTALL_DIR"
    
    print_step "Checking service status..."
    
    local services=(postgres mongodb redis minio nginx)
    [ "$INSTALL_PARSE" = "true" ] && services+=(parse-server parse-dashboard)
    [ "$INSTALL_MONITORING" = "true" ] && services+=(prometheus grafana)
    [ "$INSTALL_ADMINER" = "true" ] && services+=(adminer)
    
    for service in "${services[@]}"; do
        if docker compose ps "$service" 2>/dev/null | grep -q "Up"; then
            print_success "$service: ✓ Running"
        else
            print_warning "$service: ⚠ Check status"
        fi
    done
    
    echo ""
}

verify_services() {
    print_header "Service Status"
    
    cd "$INSTALL_DIR"
    docker compose ps
    
    echo ""
}

# ════════════════════════════════════════════════
# DISPLAY INFO
# ════════════════════════════════════════════════

display_access_info() {
    print_header "🎉 Installation Complete!"
    
    local server_ip=$(get_server_ip)
    
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "  Access URLs"
    echo "═══════════════════════════════════════════════════"
    echo ""
    echo "Main Site:"
    echo "  http://$PRIMARY_DOMAIN"
    echo ""
    echo "Services:"
    echo "  MinIO Console:  http://storage.$PRIMARY_DOMAIN"
    echo "  S3 API:         http://s3.$PRIMARY_DOMAIN"
    
    [ "$INSTALL_PARSE" = "true" ] && echo "  Parse Dashboard: http://api.$PRIMARY_DOMAIN"
    [ "$INSTALL_PARSE" = "true" ] && echo "  Parse API:       http://api.$PRIMARY_DOMAIN/parse"
    [ "$INSTALL_MONITORING" = "true" ] && echo "  Grafana:        http://monitor.$PRIMARY_DOMAIN"
    [ "$INSTALL_ADMINER" = "true" ] && echo "  Adminer:        http://db.$PRIMARY_DOMAIN"
    
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "  DNS Setup Required"
    echo "═══════════════════════════════════════════════════"
    echo ""
    echo "Add these DNS A records:"
    echo "  $PRIMARY_DOMAIN           → $server_ip"
    echo "  storage.$PRIMARY_DOMAIN   → $server_ip"
    echo "  s3.$PRIMARY_DOMAIN        → $server_ip"
    echo "  api.$PRIMARY_DOMAIN       → $server_ip"
    echo "  monitor.$PRIMARY_DOMAIN   → $server_ip"
    echo "  db.$PRIMARY_DOMAIN        → $server_ip"
    echo ""
    echo "Or add to /etc/hosts:"
    echo "  $server_ip  $PRIMARY_DOMAIN storage.$PRIMARY_DOMAIN s3.$PRIMARY_DOMAIN api.$PRIMARY_DOMAIN"
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo ""
    echo "Credentials: $INSTALL_DIR/.credentials"
    echo "Logs: $INSTALL_DIR/logs/"
    echo ""
}

# ════════════════════════════════════════════════
# MAIN FUNCTION
# ════════════════════════════════════════════════

run_onestack_setup() {
    check_root
    load_vars
    
    if [ -z "$INSTALL_DIR" ]; then
        error_exit "INSTALL_DIR not set"
    fi
    
    if [ -z "$PRIMARY_DOMAIN" ]; then
        error_exit "PRIMARY_DOMAIN not set"
    fi
    
    check_nginx_conflict
    create_directory_structure
    generate_passwords
    create_env_file
    create_database_init_scripts
    create_docker_compose
    create_parse_dashboard_config
    create_nginx_config
    create_monitoring_config
    create_default_frontend
    
    deploy_services
    wait_for_services
    verify_services
    display_access_info
    
    save_var "PHASE_2_COMPLETE" "true"
    
    success_message "OneStack deployed! 🎉"
}

export -f run_onestack_setup
