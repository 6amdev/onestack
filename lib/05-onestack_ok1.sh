#!/bin/bash
# OneStack - Service Deployment (Parse Server Fixed)

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LIB_DIR/utils.sh"

# ════════════════════════════════════════════════
# CHECK NGINX CONFLICT
# ════════════════════════════════════════════════

check_nginx_conflict() {
    print_header "Checking for Port Conflicts"
    
    if ss -tulpn | grep -q ":80 "; then
        print_warning "Port 80 is already in use!"
        echo ""
        
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
                exit 1
            fi
        else
            print_error "Port 80 is in use by another service"
            exit 1
        fi
    else
        print_success "Port 80 is available"
    fi
    
    echo ""
}

# ════════════════════════════════════════════════
# DIRECTORY STRUCTURE
# ════════════════════════════════════════════════

create_directory_structure() {
    print_header "Creating Directory Structure"
    
    local base_dir="$INSTALL_DIR"
    
    print_step "Creating directories..."
    
    local dirs=(
        "nginx/conf.d" "nginx/ssl" "nginx/logs"
        "databases/postgres/init" "databases/mongodb/init" "databases/redis"
        "frontends/main" "frontends/app" "frontends/admin"
        "backends/parse-server/cloud"
        "backends/nodejs-api" "backends/python-rag"
        "monitoring/prometheus" "monitoring/grafana/provisioning/datasources"
        "monitoring/grafana/provisioning/dashboards"
        "backups" "logs" "config" "scripts"
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
# PASSWORD GENERATION (FIXED - Generate Parse credentials first)
# ════════════════════════════════════════════════

generate_passwords() {
    print_header "Generating Secure Passwords"
    
    print_step "Creating secure credentials..."
    
    # Database passwords
    export POSTGRES_PASSWORD=$(generate_password 32)
    export MONGODB_PASSWORD=$(generate_password 32)
    export REDIS_PASSWORD=$(generate_password 32)
    export MINIO_ROOT_PASSWORD=$(generate_password 32)
    export GRAFANA_PASSWORD=$(generate_password 24)
    
    # Parse credentials - MUST be generated here
    if [ "$INSTALL_PARSE" = "true" ]; then
        export PARSE_APP_ID=$(openssl rand -hex 16)
        export PARSE_MASTER_KEY=$(openssl rand -hex 32)
        export PARSE_CLIENT_KEY=$(openssl rand -hex 16)
        export PARSE_DASHBOARD_PASSWORD=$(generate_password 24)
        
        print_success "Parse credentials generated:"
        print_info "  App ID: $PARSE_APP_ID"
        print_info "  Master Key: ${PARSE_MASTER_KEY:0:20}..."
    fi
    
    print_success "All passwords generated"
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
  User: minioadmin
  Password: $MINIO_ROOT_PASSWORD

EOF

    if [ "$INSTALL_MONITORING" = "true" ]; then
        cat >> "$cred_file" << EOF
Grafana:
  URL: http://monitor.$PRIMARY_DOMAIN
  User: admin
  Password: $GRAFANA_PASSWORD

EOF
    fi

    if [ "$INSTALL_PARSE" = "true" ]; then
        cat >> "$cred_file" << EOF
Parse Server:
  API URL: http://api.$PRIMARY_DOMAIN/parse
  Dashboard: http://api.$PRIMARY_DOMAIN
  
  Dashboard Login:
    Username: admin
    Password: $PARSE_DASHBOARD_PASSWORD
  
  API Credentials:
    App ID: $PARSE_APP_ID
    Master Key: $PARSE_MASTER_KEY
    Client Key: $PARSE_CLIENT_KEY
  
  Database: postgres://postgres:***@postgres:5432/parse_db

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
IMPORTANT: Keep this file secure!
═══════════════════════════════════════════════════
EOF
    
    chmod 600 "$cred_file"
    chown "$ONESTACK_USER:$ONESTACK_USER" "$cred_file"
}

# ════════════════════════════════════════════════
# .ENV FILE (FIXED - All Parse variables)
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

# DOMAIN
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
        # CRITICAL: All Parse variables must be set here
        cat >> "$env_file" << EOF
# PARSE SERVER - All credentials
PARSE_SERVER_VERSION=latest
PARSE_APP_ID=$PARSE_APP_ID
PARSE_MASTER_KEY=$PARSE_MASTER_KEY
PARSE_CLIENT_KEY=$PARSE_CLIENT_KEY
PARSE_SERVER_APPLICATION_ID=$PARSE_APP_ID
PARSE_SERVER_MASTER_KEY=$PARSE_MASTER_KEY

# Parse Database
PARSE_DATABASE_URI=postgres://postgres:$POSTGRES_PASSWORD@postgres:5432/parse_db

# Parse Server URLs
PARSE_SERVER_URL=http://parse-server:1337/parse
PARSE_PUBLIC_SERVER_URL=http://api.$PRIMARY_DOMAIN/parse
PARSE_SERVER_MOUNT_PATH=/parse

# Parse Dashboard
PARSE_DASHBOARD_USER=admin
PARSE_DASHBOARD_PASSWORD=$PARSE_DASHBOARD_PASSWORD
PARSE_DASHBOARD_APP_NAME=OneStack
PARSE_DASHBOARD_ALLOW_INSECURE_HTTP=true

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
    
    print_success ".env file created"
    echo ""
}

# ════════════════════════════════════════════════
# DOCKER COMPOSE (FIXED - Parse Server environment)
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
      # CRITICAL: Use correct environment variable names
      PARSE_SERVER_APPLICATION_ID: ${PARSE_APP_ID}
      PARSE_SERVER_MASTER_KEY: ${PARSE_MASTER_KEY}
      PARSE_SERVER_DATABASE_URI: ${PARSE_DATABASE_URI}
      PARSE_SERVER_URL: ${PARSE_SERVER_URL}
      PARSE_PUBLIC_SERVER_URL: ${PARSE_PUBLIC_SERVER_URL}
      PARSE_SERVER_MOUNT_PATH: ${PARSE_SERVER_MOUNT_PATH}
      PARSE_SERVER_ALLOW_CLIENT_CLASS_CREATION: "false"
      PARSE_SERVER_ENABLE_ANON_USERS: "false"
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
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:1337${PARSE_SERVER_MOUNT_PATH}/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

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

echo "=== Creating PostgreSQL databases ==="

if [ -n "$POSTGRES_MULTIPLE_DATABASES" ]; then
    for db in $(echo $POSTGRES_MULTIPLE_DATABASES | tr ',' ' '); do
        echo "Creating database: $db"
        psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
            SELECT 'CREATE DATABASE $db'
            WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$db')\gexec
EOSQL
        echo "✓ Database $db ready"
    done
fi

echo "=== PostgreSQL initialization complete ==="
PGINIT

    chmod +x "$INSTALL_DIR/databases/postgres/init/01-create-databases.sh"
    
    print_success "Database init scripts created"
    echo ""
}

# ════════════════════════════════════════════════
# PARSE DASHBOARD CONFIG (FIXED - Must match .env exactly)
# ════════════════════════════════════════════════

create_parse_dashboard_config() {
    if [ "$INSTALL_PARSE" != "true" ]; then
        return 0
    fi
    
    print_header "Creating Parse Dashboard Config"
    
    print_step "Generating Parse Dashboard configuration..."
    print_info "App ID: $PARSE_APP_ID"
    print_info "Master Key: ${PARSE_MASTER_KEY:0:20}..."
    
    # CRITICAL: Must use same credentials as Parse Server
    cat > "$INSTALL_DIR/parse-dashboard/config.json" << EOF
{
  "apps": [
    {
      "serverURL": "http://parse-server:1337/parse",
      "appId": "$PARSE_APP_ID",
      "masterKey": "$PARSE_MASTER_KEY",
      "appName": "OneStack",
      "production": false,
      "iconName": "onestack.png"
    }
  ],
  "users": [
    {
      "user": "admin",
      "pass": "$PARSE_DASHBOARD_PASSWORD"
    }
  ],
  "useEncryptedPasswords": false,
  "trustProxy": 1,
  "allowInsecureHTTP": true
}
EOF
    
    chmod 644 "$INSTALL_DIR/parse-dashboard/config.json"
    chown "$ONESTACK_USER:$ONESTACK_USER" "$INSTALL_DIR/parse-dashboard/config.json"
    
    # Cloud code example
    cat > "$INSTALL_DIR/backends/parse-server/cloud/main.js" << 'CLOUDCODE'
// Parse Cloud Code
// Define your cloud functions here

Parse.Cloud.define('hello', async (request) => {
  return { message: 'Hello from OneStack Parse Server!' };
});

Parse.Cloud.define('version', async (request) => {
  return { version: '2.0.0', platform: 'OneStack' };
});

// Example: beforeSave trigger
Parse.Cloud.beforeSave('TestObject', (request) => {
  const object = request.object;
  if (!object.get('name')) {
    throw new Error('Name is required');
  }
});
CLOUDCODE
    
    print_success "Parse Dashboard config created"
    print_info "Config saved to: parse-dashboard/config.json"
    echo ""
}

# ════════════════════════════════════════════════
# NGINX CONFIG
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

    cat > "$INSTALL_DIR/nginx/conf.d/onestack.conf" << EOF
# OneStack Nginx Configuration
# Domain: $PRIMARY_DOMAIN

server {
    listen 80;
    server_name $PRIMARY_DOMAIN www.$PRIMARY_DOMAIN;
    root /var/www/main;
    index index.html;
    location / {
        try_files \$uri \$uri/ /index.html;
    }
}

server {
    listen 80;
    server_name storage.$PRIMARY_DOMAIN;
    location / {
        proxy_pass http://minio:9001;
        proxy_set_header Host \$host;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

server {
    listen 80;
    server_name s3.$PRIMARY_DOMAIN;
    client_max_body_size 0;
    location / {
        proxy_pass http://minio:9000;
        proxy_set_header Host \$host;
    }
}
EOF

    if [ "$INSTALL_PARSE" = "true" ]; then
        cat >> "$INSTALL_DIR/nginx/conf.d/onestack.conf" << EOF

server {
    listen 80;
    server_name api.$PRIMARY_DOMAIN;
    
    location /parse {
        proxy_pass http://parse-server:1337;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_read_timeout 300s;
        proxy_connect_timeout 300s;
    }
    
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

server {
    listen 80;
    server_name monitor.$PRIMARY_DOMAIN;
    location / {
        proxy_pass http://grafana:3000;
        proxy_set_header Host \$host;
    }
}
EOF
    fi

    if [ "$INSTALL_ADMINER" = "true" ]; then
        cat >> "$INSTALL_DIR/nginx/conf.d/onestack.conf" << EOF

server {
    listen 80;
    server_name db.$PRIMARY_DOMAIN;
    location / {
        proxy_pass http://adminer:8080;
        proxy_set_header Host \$host;
    }
}
EOF
    fi

    cat >> "$INSTALL_DIR/nginx/conf.d/onestack.conf" << 'DEFNX'

server {
    listen 80 default_server;
    location /health {
        return 200 "healthy\n";
    }
    location / {
        return 404;
    }
}
DEFNX

    chown -R "$ONESTACK_USER:$ONESTACK_USER" "$INSTALL_DIR/nginx"
    print_success "Nginx configured"
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
PROM

    cat > "$INSTALL_DIR/monitoring/grafana/provisioning/datasources/prometheus.yml" << 'GRAF'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
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
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            text-align: center;
        }
        .logo { font-size: 5em; margin-bottom: 20px; }
        h1 { font-size: 3.5em; color: #333; }
        .status { background: #10b981; color: white; padding: 12px 30px; border-radius: 50px; margin: 20px 0; display: inline-block; }
        .domain { background: #f3f4f6; padding: 15px; border-radius: 10px; margin: 20px 0; font-family: monospace; color: #667eea; }
        .links { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin-top: 30px; }
        a { background: #f3f4f6; padding: 25px; border-radius: 10px; text-decoration: none; color: #333; transition: 0.3s; }
        a:hover { transform: translateY(-5px); background: white; box-shadow: 0 10px 20px rgba(0,0,0,0.1); }
        .service-icon { font-size: 2em; }
        .service-name { font-weight: bold; color: #667eea; margin: 10px 0; }
    </style>
</head>
<body>
    <div class="container">
        <div class="logo">🚀</div>
        <h1>OneStack</h1>
        <div class="status">✓ Running</div>
        <div class="domain">$PRIMARY_DOMAIN</div>
        
        <div class="links">
            <a href="http://storage.$PRIMARY_DOMAIN">
                <div class="service-icon">📦</div>
                <div class="service-name">MinIO</div>
            </a>
            <a href="http://s3.$PRIMARY_DOMAIN">
                <div class="service-icon">☁️</div>
                <div class="service-name">S3 API</div>
            </a>
EOF

    [ "$INSTALL_PARSE" = "true" ] && cat >> "$INSTALL_DIR/frontends/main/index.html" << EOF
            <a href="http://api.$PRIMARY_DOMAIN">
                <div class="service-icon">⚡</div>
                <div class="service-name">Parse</div>
            </a>
EOF

    [ "$INSTALL_MONITORING" = "true" ] && cat >> "$INSTALL_DIR/frontends/main/index.html" << EOF
            <a href="http://monitor.$PRIMARY_DOMAIN">
                <div class="service-icon">📊</div>
                <div class="service-name">Grafana</div>
            </a>
EOF

    [ "$INSTALL_ADMINER" = "true" ] && cat >> "$INSTALL_DIR/frontends/main/index.html" << EOF
            <a href="http://db.$PRIMARY_DOMAIN">
                <div class="service-icon">🗄️</div>
                <div class="service-name">Adminer</div>
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
    docker compose pull 2>&1 | tee -a "${LOG_FILE:-/var/log/onestack-install.log}" || true
    print_success "Images pulled"
    
    echo ""
    print_step "Starting services..."
    docker compose up -d 2>&1 | tee -a "${LOG_FILE:-/var/log/onestack-install.log}"
    print_success "Services started"
    
    print_step "Setting permissions..."
    chown -R "$ONESTACK_USER:$ONESTACK_USER" "$INSTALL_DIR" 2>/dev/null || true
    
    echo ""
}

# ════════════════════════════════════════════════
# WAIT & VERIFY
# ════════════════════════════════════════════════

wait_for_services() {
    print_header "Waiting for Services"
    
    print_info "Waiting 40 seconds for services to initialize..."
    sleep 40
    
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
            print_warning "$service: ⚠ Check logs"
        fi
    done
    
    # Special check for Parse Server
    if [ "$INSTALL_PARSE" = "true" ]; then
        echo ""
        print_step "Testing Parse Server API..."
        sleep 5
        
        if curl -s http://localhost:1337/parse/health 2>/dev/null | grep -q "ok"; then
            print_success "Parse Server API: ✓ Responding"
        else
            print_warning "Parse Server API: ⚠ Not responding yet"
            print_info "Check logs: docker compose logs parse-server"
        fi
    fi
    
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
    echo "Main: http://$PRIMARY_DOMAIN"
    echo "MinIO: http://storage.$PRIMARY_DOMAIN"
    
    [ "$INSTALL_PARSE" = "true" ] && echo "Parse Dashboard: http://api.$PRIMARY_DOMAIN"
    [ "$INSTALL_PARSE" = "true" ] && echo "Parse API: http://api.$PRIMARY_DOMAIN/parse"
    [ "$INSTALL_MONITORING" = "true" ] && echo "Grafana: http://monitor.$PRIMARY_DOMAIN"
    [ "$INSTALL_ADMINER" = "true" ] && echo "Adminer: http://db.$PRIMARY_DOMAIN"
    
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "  Credentials"
    echo "═══════════════════════════════════════════════════"
    echo ""
    echo "Saved to: $INSTALL_DIR/.credentials"
    echo ""
    echo "View credentials:"
    echo "  cat $INSTALL_DIR/.credentials"
    echo ""
    
    if [ "$INSTALL_PARSE" = "true" ]; then
        echo "Parse Dashboard Login:"
        echo "  Username: admin"
        echo "  Password: (see .credentials file)"
        echo ""
    fi
    
    echo "═══════════════════════════════════════════════════"
    echo ""
}

# ════════════════════════════════════════════════
# MAIN FUNCTION
# ════════════════════════════════════════════════

run_onestack_setup() {
    check_root
    load_vars
    
    if [ -z "$INSTALL_DIR" ] || [ -z "$PRIMARY_DOMAIN" ]; then
        error_exit "INSTALL_DIR or PRIMARY_DOMAIN not set"
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
    
    success_message "OneStack deployed successfully! 🎉"
}

export -f run_onestack_setup
