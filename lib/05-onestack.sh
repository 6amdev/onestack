#!/bin/bash
# OneStack - Service Deployment (FIXED Docker Permission)

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LIB_DIR/utils.sh"

# ════════════════════════════════════════════════
# DIRECTORY STRUCTURE
# ════════════════════════════════════════════════

create_directory_structure() {
    print_header "Creating Directory Structure"
    
    local base_dir="$INSTALL_DIR"
    
    print_step "Creating directories in: $base_dir"
    
    # Main directories
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
  API: http://api.$PRIMARY_DOMAIN/parse
  Dashboard: http://api.$PRIMARY_DOMAIN
  Dashboard User: admin
  Dashboard Password: $PARSE_DASHBOARD_PASSWORD
  App ID: $PARSE_APP_ID
  Master Key: $PARSE_MASTER_KEY

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
# .ENV FILE
# ════════════════════════════════════════════════

create_env_file() {
    print_header "Creating Environment Configuration"
    
    local env_file="$INSTALL_DIR/.env"
    
    print_step "Generating .env file..."
    
    cat > "$env_file" << EOF
COMPOSE_PROJECT_NAME=onestack
TIMEZONE=${CONFIG_system_timezone:-Asia/Bangkok}
NODE_ENV=production

PRIMARY_DOMAIN=$PRIMARY_DOMAIN
SSL_EMAIL=$SSL_EMAIL

POSTGRES_VERSION=${CONFIG_database_postgres_version:-16}
POSTGRES_USER=postgres
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_DB=onestack_main
POSTGRES_DATABASES=onestack_main,parse_db

MONGODB_VERSION=${CONFIG_database_mongodb_version:-7}
MONGODB_ROOT_USERNAME=admin
MONGODB_ROOT_PASSWORD=$MONGODB_PASSWORD

REDIS_VERSION=${CONFIG_database_redis_version:-alpine}
REDIS_PASSWORD=$REDIS_PASSWORD

MINIO_VERSION=latest
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=$MINIO_ROOT_PASSWORD

EOF

    if [ "$INSTALL_PARSE" = "true" ]; then
        cat >> "$env_file" << EOF
PARSE_SERVER_VERSION=latest
PARSE_APP_ID=$PARSE_APP_ID
PARSE_MASTER_KEY=$PARSE_MASTER_KEY
PARSE_CLIENT_KEY=$PARSE_CLIENT_KEY
PARSE_DATABASE_URI=postgres://postgres:$POSTGRES_PASSWORD@postgres:5432/parse_db
PARSE_DASHBOARD_USER=admin
PARSE_DASHBOARD_PASSWORD=$PARSE_DASHBOARD_PASSWORD

EOF
    fi

    if [ "$INSTALL_MONITORING" = "true" ]; then
        cat >> "$env_file" << EOF
GRAFANA_VERSION=latest
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=$GRAFANA_PASSWORD
PROMETHEUS_VERSION=latest

EOF
    fi

    if [ "$INSTALL_ADMINER" = "true" ]; then
        cat >> "$env_file" << EOF
ADMINER_VERSION=latest

EOF
    fi

    cat >> "$env_file" << EOF
DOCKER_NETWORK_SUBNET=${CONFIG_advanced_docker_subnet:-172.20.0.0/16}
EOF
    
    chmod 600 "$env_file"
    chown "$ONESTACK_USER:$ONESTACK_USER" "$env_file"
    
    print_success ".env file created"
    echo ""
}

# ════════════════════════════════════════════════
# DOCKER COMPOSE (ย่อให้สั้นเพื่อความกระชับ)
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

  minio:
    image: minio/minio:${MINIO_VERSION}
    container_name: onestack-minio
    restart: unless-stopped
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD}
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
    image: parseplatform/parse-server:latest
    container_name: onestack-parse-server
    restart: unless-stopped
    environment:
      PARSE_SERVER_APPLICATION_ID: ${PARSE_APP_ID}
      PARSE_SERVER_MASTER_KEY: ${PARSE_MASTER_KEY}
      PARSE_SERVER_DATABASE_URI: ${PARSE_DATABASE_URI}
      PARSE_SERVER_URL: http://parse-server:1337/parse
    volumes:
      - ./backends/parse-server/cloud:/parse-server/cloud
    networks:
      - backend
    ports:
      - "1337:1337"
    depends_on:
      - postgres

  parse-dashboard:
    image: parseplatform/parse-dashboard:latest
    container_name: onestack-parse-dashboard
    restart: unless-stopped
    volumes:
      - ./parse-dashboard/config.json:/parse-dashboard/config.json:ro
    environment:
      PARSE_DASHBOARD_CONFIG: /parse-dashboard/config.json
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
    image: prom/prometheus:latest
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
    image: grafana/grafana:latest
    container_name: onestack-grafana
    restart: unless-stopped
    environment:
      GF_SECURITY_ADMIN_USER: admin
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_ADMIN_PASSWORD}
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
    image: adminer:latest
    container_name: onestack-adminer
    restart: unless-stopped
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
# DATABASE INIT SCRIPTS
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
# PARSE DASHBOARD CONFIG
# ════════════════════════════════════════════════

create_parse_dashboard_config() {
    if [ "$INSTALL_PARSE" != "true" ]; then
        return 0
    fi
    
    print_header "Creating Parse Dashboard Config"
    
    cat > "$INSTALL_DIR/parse-dashboard/config.json" << EOF
{
  "apps": [{
    "serverURL": "http://parse-server:1337/parse",
    "appId": "${PARSE_APP_ID}",
    "masterKey": "${PARSE_MASTER_KEY}",
    "appName": "OneStack"
  }],
  "users": [{
    "user": "admin",
    "pass": "${PARSE_DASHBOARD_PASSWORD}"
  }]
}
EOF
    
    chmod 644 "$INSTALL_DIR/parse-dashboard/config.json"
    chown "$ONESTACK_USER:$ONESTACK_USER" "$INSTALL_DIR/parse-dashboard/config.json"
    
    print_success "Parse Dashboard config created"
    echo ""
}

# ════════════════════════════════════════════════
# NGINX CONFIG (ย่อ)
# ════════════════════════════════════════════════

create_nginx_config() {
    print_header "Creating Nginx Configuration"
    
    cat > "$INSTALL_DIR/nginx/nginx.conf" << 'NGXMAIN'
user nginx;
worker_processes auto;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    access_log /var/log/nginx/access.log;
    sendfile on;
    keepalive_timeout 65;
    client_max_body_size 100M;
    
    gzip on;
    
    include /etc/nginx/conf.d/*.conf;
}
NGXMAIN

    cat > "$INSTALL_DIR/nginx/conf.d/onestack.conf" << NGXSITE
server {
    listen 80;
    server_name $PRIMARY_DOMAIN;
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
    }
}

server {
    listen 80;
    server_name s3.$PRIMARY_DOMAIN;
    location / {
        proxy_pass http://minio:9000;
        proxy_set_header Host \$host;
    }
}
NGXSITE

    if [ "$INSTALL_PARSE" = "true" ]; then
        cat >> "$INSTALL_DIR/nginx/conf.d/onestack.conf" << 'PARSENGX'

server {
    listen 80;
    server_name api.$PRIMARY_DOMAIN;
    location /parse {
        proxy_pass http://parse-server:1337;
        proxy_set_header Host $host;
    }
    location / {
        proxy_pass http://parse-dashboard:4040;
        proxy_set_header Host $host;
    }
}
PARSENGX
    fi

    if [ "$INSTALL_MONITORING" = "true" ]; then
        cat >> "$INSTALL_DIR/nginx/conf.d/onestack.conf" << 'MONGX'

server {
    listen 80;
    server_name monitor.$PRIMARY_DOMAIN;
    location / {
        proxy_pass http://grafana:3000;
        proxy_set_header Host $host;
    }
}
MONGX
    fi

    if [ "$INSTALL_ADMINER" = "true" ]; then
        cat >> "$INSTALL_DIR/nginx/conf.d/onestack.conf" << 'ADMNX'

server {
    listen 80;
    server_name db.$PRIMARY_DOMAIN;
    location / {
        proxy_pass http://adminer:8080;
        proxy_set_header Host $host;
    }
}
ADMNX
    fi

    cat >> "$INSTALL_DIR/nginx/conf.d/onestack.conf" << 'DEFNX'

server {
    listen 80 default_server;
    location /health {
        return 200 "ok\n";
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
<html>
<head>
    <title>OneStack</title>
    <style>
        body {
            font-family: system-ui;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            margin: 0;
        }
        .container {
            background: white;
            border-radius: 20px;
            padding: 60px;
            text-align: center;
            max-width: 800px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
        }
        h1 { font-size: 3em; color: #333; }
        .status { background: #10b981; color: white; padding: 10px 30px; border-radius: 50px; display: inline-block; margin: 20px 0; }
        .links { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 15px; margin-top: 30px; }
        a { background: #f3f4f6; padding: 20px; border-radius: 10px; text-decoration: none; color: #333; transition: 0.3s; }
        a:hover { transform: translateY(-5px); }
    </style>
</head>
<body>
    <div class="container">
        <div style="font-size: 5em;">🚀</div>
        <h1>OneStack</h1>
        <div class="status">✓ Running</div>
        <div class="links">
            <a href="http://storage.$PRIMARY_DOMAIN">📦 MinIO</a>
            <a href="http://s3.$PRIMARY_DOMAIN">☁️ S3</a>
EOF

    [ "$INSTALL_PARSE" = "true" ] && cat >> "$INSTALL_DIR/frontends/main/index.html" << 'PARSEHTML'
            <a href="http://api.$PRIMARY_DOMAIN">⚡ Parse</a>
PARSEHTML

    [ "$INSTALL_MONITORING" = "true" ] && cat >> "$INSTALL_DIR/frontends/main/index.html" << 'MONHTML'
            <a href="http://monitor.$PRIMARY_DOMAIN">📊 Grafana</a>
MONHTML

    [ "$INSTALL_ADMINER" = "true" ] && cat >> "$INSTALL_DIR/frontends/main/index.html" << 'ADMHTML'
            <a href="http://db.$PRIMARY_DOMAIN">🗄️ Adminer</a>
ADMHTML

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
# DEPLOY SERVICES (🔧 FIXED!)
# ════════════════════════════════════════════════

deploy_services() {
    print_header "Deploying Services"
    
    cd "$INSTALL_DIR"
    
    # ✅ FIX: Run as ROOT, not as onestack user
    print_step "Pulling Docker images..."
    
    if docker compose pull 2>&1 | tee -a "${LOG_FILE:-/var/log/onestack-install.log}"; then
        print_success "Images pulled"
    else
        print_warning "Some images may have failed"
    fi
    
    echo ""
    print_step "Starting services..."
    
    # ✅ FIX: Run as ROOT
    if docker compose up -d 2>&1 | tee -a "${LOG_FILE:-/var/log/onestack-install.log}"; then
        print_success "Services started"
    else
        print_error "Failed to start services"
        echo ""
        print_info "Try manually:"
        echo "  cd $INSTALL_DIR && docker compose up -d"
        return 1
    fi
    
    # Fix ownership after deployment
    print_step "Setting permissions..."
    chown -R "$ONESTACK_USER:$ONESTACK_USER" "$INSTALL_DIR" 2>/dev/null || true
    
    echo ""
}

# ════════════════════════════════════════════════
# WAIT FOR SERVICES
# ════════════════════════════════════════════════

wait_for_services() {
    print_header "Waiting for Services"
    
    print_info "Waiting 30 seconds for services to start..."
    sleep 30
    
    cd "$INSTALL_DIR"
    
    print_step "Checking service status..."
    
    local services=(postgres mongodb redis minio nginx)
    [ "$INSTALL_PARSE" = "true" ] && services+=(parse-server parse-dashboard)
    
    for service in "${services[@]}"; do
        if docker compose ps "$service" 2>/dev/null | grep -q "Up"; then
            print_success "$service: Running"
        else
            print_warning "$service: Check status"
        fi
    done
    
    echo ""
}

# ════════════════════════════════════════════════
# VERIFY SERVICES
# ════════════════════════════════════════════════

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
    
    echo ""
    echo "Access URLs:"
    echo "  Main: http://$PRIMARY_DOMAIN"
    echo "  MinIO: http://storage.$PRIMARY_DOMAIN"
    [ "$INSTALL_PARSE" = "true" ] && echo "  Parse: http://api.$PRIMARY_DOMAIN"
    [ "$INSTALL_MONITORING" = "true" ] && echo "  Grafana: http://monitor.$PRIMARY_DOMAIN"
    [ "$INSTALL_ADMINER" = "true" ] && echo "  Adminer: http://db.$PRIMARY_DOMAIN"
    echo ""
    echo "Credentials: $INSTALL_DIR/.credentials"
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
