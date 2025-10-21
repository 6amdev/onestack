#!/bin/bash
# OneStack Extended Deployment Script
# Includes: n8n, Chatwoot, Node.js API, Frontend Examples

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
        "backends/nodejs-api/src/routes" "backends/nodejs-api/src/controllers"
        "backends/nodejs-api/src/middleware" "backends/nodejs-api/src/utils"
        "backends/python-rag"
        "monitoring/prometheus" "monitoring/grafana/provisioning/datasources"
        "monitoring/grafana/provisioning/dashboards"
        "backups" "logs" "config" "scripts"
        "parse-dashboard"
        "chatwoot" "n8n"
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
    
    # Database passwords
    export POSTGRES_PASSWORD=$(generate_password 32)
    export MONGODB_PASSWORD=$(generate_password 32)
    export REDIS_PASSWORD=$(generate_password 32)
    export MINIO_ROOT_PASSWORD=$(generate_password 32)
    export GRAFANA_PASSWORD=$(generate_password 24)
    
    # Parse credentials
    if [ "$INSTALL_PARSE" = "true" ]; then
        export PARSE_APP_ID=$(openssl rand -hex 16)
        export PARSE_MASTER_KEY=$(openssl rand -hex 32)
        export PARSE_CLIENT_KEY=$(openssl rand -hex 16)
        export PARSE_DASHBOARD_PASSWORD=$(generate_password 24)
    fi
    
    # n8n credentials
    export N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)
    export N8N_PASSWORD=$(generate_password 24)
    
    # Chatwoot credentials
    export CHATWOOT_SECRET_KEY_BASE=$(openssl rand -hex 64)
    export CHATWOOT_PASSWORD=$(generate_password 24)
    
    # Node.js API
    export JWT_SECRET=$(openssl rand -hex 32)
    
    print_success "All passwords generated"
    save_credentials
    
    echo ""
}

save_credentials() {
    local cred_file="$INSTALL_DIR/.credentials"
    
    cat > "$cred_file" << EOF
═══════════════════════════════════════════════════
OneStack Extended Credentials
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

EOF
    fi

    if [ "$INSTALL_ADMINER" = "true" ]; then
        cat >> "$cred_file" << EOF
Adminer:
  URL: http://db.$PRIMARY_DOMAIN

EOF
    fi

    cat >> "$cred_file" << EOF
n8n (Workflow Automation):
  URL: http://flow.$PRIMARY_DOMAIN
  Email: admin@$PRIMARY_DOMAIN
  Password: $N8N_PASSWORD
  
Chatwoot (Customer Support):
  URL: http://chat.$PRIMARY_DOMAIN
  Email: admin@$PRIMARY_DOMAIN
  Password: $CHATWOOT_PASSWORD
  
Node.js API:
  URL: http://api.$PRIMARY_DOMAIN/v1
  Health: http://api.$PRIMARY_DOMAIN/v1/health
  JWT Secret: $JWT_SECRET

═══════════════════════════════════════════════════
IMPORTANT: Keep this file secure!
═══════════════════════════════════════════════════
EOF
    
    chmod 600 "$cred_file"
    chown "$ONESTACK_USER:$ONESTACK_USER" "$cred_file"
}

# ════════════════════════════════════════════════
# .ENV FILE (COMPLETE)
# ════════════════════════════════════════════════

create_env_file() {
    print_header "Creating Environment Configuration"
    
    local env_file="$INSTALL_DIR/.env"
    
    print_step "Generating .env file..."
    print_info "Domain: $PRIMARY_DOMAIN"
    
    cat > "$env_file" << EOF
# OneStack Extended Environment Configuration
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
POSTGRES_DATABASES=onestack_main,parse_db,n8n_db,chatwoot_production

# MONGODB
MONGODB_VERSION=${CONFIG_database_mongodb_version:-7}
MONGODB_ROOT_USERNAME=admin
MONGODB_ROOT_PASSWORD=$MONGODB_PASSWORD

# REDIS
REDIS_VERSION=${CONFIG_database_redis_version:-alpine}
REDIS_PASSWORD=$REDIS_PASSWORD
REDIS_URL=redis://:\${REDIS_PASSWORD}@redis:6379

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
PARSE_SERVER_APPLICATION_ID=$PARSE_APP_ID
PARSE_SERVER_MASTER_KEY=$PARSE_MASTER_KEY
PARSE_DATABASE_URI=postgres://postgres:$POSTGRES_PASSWORD@postgres:5432/parse_db
PARSE_SERVER_URL=http://parse-server:1337/parse
PARSE_PUBLIC_SERVER_URL=http://api.$PRIMARY_DOMAIN/parse
PARSE_SERVER_MOUNT_PATH=/parse
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
# N8N (Workflow Automation)
N8N_VERSION=latest
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=admin@$PRIMARY_DOMAIN
N8N_BASIC_AUTH_PASSWORD=$N8N_PASSWORD
N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY
N8N_HOST=flow.$PRIMARY_DOMAIN
N8N_PORT=5678
N8N_PROTOCOL=http
WEBHOOK_URL=http://flow.$PRIMARY_DOMAIN
GENERIC_TIMEZONE=${CONFIG_system_timezone:-Asia/Bangkok}

# CHATWOOT (Customer Support)
CHATWOOT_VERSION=v3.11.0
RAILS_ENV=production
RAILS_MAX_THREADS=5
SECRET_KEY_BASE=$CHATWOOT_SECRET_KEY_BASE
FRONTEND_URL=http://chat.$PRIMARY_DOMAIN
FORCE_SSL=false
POSTGRES_HOST=postgres
POSTGRES_USERNAME=postgres
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_DATABASE=chatwoot_production
REDIS_HOST=redis
REDIS_PASSWORD=$REDIS_PASSWORD
REDIS_PORT=6379
ENABLE_ACCOUNT_SIGNUP=true
DEFAULT_LOCALE=en

# NODE.JS API
NODEJS_API_VERSION=latest
JWT_SECRET=$JWT_SECRET
API_PORT=4000

# NETWORK
DOCKER_NETWORK_SUBNET=${CONFIG_advanced_docker_subnet:-172.20.0.0/16}
EOF
    
    chmod 600 "$env_file"
    chown "$ONESTACK_USER:$ONESTACK_USER" "$env_file"
    
    print_success ".env file created"
    echo ""
}

# ════════════════════════════════════════════════
# DOCKER COMPOSE (COMPLETE WITH ALL SERVICES)
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
  n8n_data:
  chatwoot_storage:

services:
  # ══════════════════════════════════════════════════════════
  # CORE DATABASES
  # ══════════════════════════════════════════════════════════
  
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

  # ══════════════════════════════════════════════════════════
  # NGINX GATEWAY
  # ══════════════════════════════════════════════════════════
  
  nginx:
    image: nginx:alpine
    container_name: onestack-nginx
    restart: unless-stopped
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./nginx/logs:/var/log/nginx
      - ./frontends:/var/www:ro
      - /etc/letsencrypt:/etc/letsencrypt:ro
    networks:
      - frontend
      - backend
    ports:
      - "80:80"
      - "443:443"
    depends_on:
      - minio
DCEOF

    if [ "$INSTALL_PARSE" = "true" ]; then
        cat >> "$compose_file" << 'PARSEDC'

  # ══════════════════════════════════════════════════════════
  # PARSE SERVER
  # ══════════════════════════════════════════════════════════
  
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

    cat >> "$compose_file" << 'N8NDC'

  # ══════════════════════════════════════════════════════════
  # N8N WORKFLOW AUTOMATION
  # ══════════════════════════════════════════════════════════
  
  n8n:
    image: n8nio/n8n:${N8N_VERSION}
    container_name: onestack-n8n
    restart: unless-stopped
    environment:
      DB_TYPE: postgresdb
      DB_POSTGRESDB_HOST: postgres
      DB_POSTGRESDB_PORT: 5432
      DB_POSTGRESDB_DATABASE: n8n_db
      DB_POSTGRESDB_USER: ${POSTGRES_USER}
      DB_POSTGRESDB_PASSWORD: ${POSTGRES_PASSWORD}
      N8N_BASIC_AUTH_ACTIVE: ${N8N_BASIC_AUTH_ACTIVE}
      N8N_BASIC_AUTH_USER: ${N8N_BASIC_AUTH_USER}
      N8N_BASIC_AUTH_PASSWORD: ${N8N_BASIC_AUTH_PASSWORD}
      N8N_ENCRYPTION_KEY: ${N8N_ENCRYPTION_KEY}
      N8N_HOST: ${N8N_HOST}
      N8N_PORT: ${N8N_PORT}
      N8N_PROTOCOL: ${N8N_PROTOCOL}
      WEBHOOK_URL: ${WEBHOOK_URL}
      GENERIC_TIMEZONE: ${GENERIC_TIMEZONE}
      TZ: ${TIMEZONE}
    volumes:
      - n8n_data:/home/node/.n8n
      - ./n8n:/n8n/custom
    networks:
      - backend
      - frontend
    ports:
      - "5678:5678"
    depends_on:
      postgres:
        condition: service_healthy

  # ══════════════════════════════════════════════════════════
  # CHATWOOT CUSTOMER SUPPORT
  # ══════════════════════════════════════════════════════════
  
  chatwoot-rails:
    image: chatwoot/chatwoot:${CHATWOOT_VERSION}
    container_name: onestack-chatwoot-rails
    restart: unless-stopped
    environment:
      RAILS_ENV: ${RAILS_ENV}
      RAILS_MAX_THREADS: ${RAILS_MAX_THREADS}
      SECRET_KEY_BASE: ${SECRET_KEY_BASE}
      FRONTEND_URL: ${FRONTEND_URL}
      FORCE_SSL: ${FORCE_SSL}
      POSTGRES_HOST: ${POSTGRES_HOST}
      POSTGRES_USERNAME: ${POSTGRES_USERNAME}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DATABASE: ${POSTGRES_DATABASE}
      REDIS_URL: ${REDIS_URL}
      ENABLE_ACCOUNT_SIGNUP: ${ENABLE_ACCOUNT_SIGNUP}
      DEFAULT_LOCALE: ${DEFAULT_LOCALE}
      TZ: ${TIMEZONE}
    volumes:
      - chatwoot_storage:/app/storage
    networks:
      - backend
      - frontend
    ports:
      - "3000:3000"
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    command: ["bundle", "exec", "rails", "s", "-p", "3000", "-b", "0.0.0.0"]

  chatwoot-sidekiq:
    image: chatwoot/chatwoot:${CHATWOOT_VERSION}
    container_name: onestack-chatwoot-sidekiq
    restart: unless-stopped
    environment:
      RAILS_ENV: ${RAILS_ENV}
      SECRET_KEY_BASE: ${SECRET_KEY_BASE}
      POSTGRES_HOST: ${POSTGRES_HOST}
      POSTGRES_USERNAME: ${POSTGRES_USERNAME}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DATABASE: ${POSTGRES_DATABASE}
      REDIS_URL: ${REDIS_URL}
      TZ: ${TIMEZONE}
    volumes:
      - chatwoot_storage:/app/storage
    networks:
      - backend
    depends_on:
      - chatwoot-rails
    command: ["bundle", "exec", "sidekiq", "-C", "config/sidekiq.yml"]

  # ══════════════════════════════════════════════════════════
  # NODE.JS API
  # ══════════════════════════════════════════════════════════
  
  nodejs-api:
    build:
      context: ./backends/nodejs-api
      dockerfile: Dockerfile
    container_name: onestack-nodejs-api
    restart: unless-stopped
    environment:
      NODE_ENV: ${NODE_ENV}
      PORT: ${API_PORT}
      JWT_SECRET: ${JWT_SECRET}
      MONGODB_URI: mongodb://${MONGODB_ROOT_USERNAME}:${MONGODB_ROOT_PASSWORD}@mongodb:27017/app_data?authSource=admin
      POSTGRES_URI: postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/onestack_main
      REDIS_URL: ${REDIS_URL}
      TZ: ${TIMEZONE}
    volumes:
      - ./backends/nodejs-api:/app
      - /app/node_modules
    networks:
      - backend
    ports:
      - "4000:4000"
    depends_on:
      postgres:
        condition: service_healthy
      mongodb:
        condition: service_healthy
      redis:
        condition: service_healthy
N8NDC

    if [ "$INSTALL_MONITORING" = "true" ]; then
        cat >> "$compose_file" << 'MONDC'

  # ══════════════════════════════════════════════════════════
  # MONITORING STACK
  # ══════════════════════════════════════════════════════════
  
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

  # ══════════════════════════════════════════════════════════
  # ADMINER DATABASE UI
  # ══════════════════════════════════════════════════════════
  
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
# DATABASE INIT SCRIPTS
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
# PARSE DASHBOARD CONFIG
# ════════════════════════════════════════════════

create_parse_dashboard_config() {
    if [ "$INSTALL_PARSE" != "true" ]; then
        return 0
    fi
    
    print_header "Creating Parse Dashboard Config"
    
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
    
    cat > "$INSTALL_DIR/backends/parse-server/cloud/main.js" << 'CLOUDCODE'
// Parse Cloud Code

Parse.Cloud.define('hello', async (request) => {
  return { message: 'Hello from OneStack Parse Server!' };
});

Parse.Cloud.define('version', async (request) => {
  return { version: '2.0.0', platform: 'OneStack Extended' };
});

Parse.Cloud.beforeSave('TestObject', (request) => {
  const object = request.object;
  if (!object.get('name')) {
    throw new Error('Name is required');
  }
});
CLOUDCODE
    
    print_success "Parse Dashboard config created"
    echo ""
}

# ════════════════════════════════════════════════
# NODE.JS API (COMPLETE EXAMPLE)
# ════════════════════════════════════════════════

create_nodejs_api() {
    print_header "Creating Node.js API Template"
    
    local api_dir="$INSTALL_DIR/backends/nodejs-api"
    
    # package.json
    cat > "$api_dir/package.json" << 'PKGJSON'
{
  "name": "onestack-nodejs-api",
  "version": "1.0.0",
  "description": "OneStack Node.js API Template",
  "main": "src/app.js",
  "scripts": {
    "start": "node src/app.js",
    "dev": "nodemon src/app.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "dotenv": "^16.3.1",
    "helmet": "^7.1.0",
    "morgan": "^1.10.0",
    "jsonwebtoken": "^9.0.2",
    "bcryptjs": "^2.4.3",
    "joi": "^17.11.0",
    "mongodb": "^6.3.0",
    "pg": "^8.11.3",
    "redis": "^4.6.12"
  },
  "devDependencies": {
    "nodemon": "^3.0.2"
  }
}
PKGJSON

    # Dockerfile
    cat > "$api_dir/Dockerfile" << 'DOCKERFILE'
FROM node:20-alpine

WORKDIR /app

COPY package*.json ./
RUN npm install --production

COPY . .

EXPOSE 4000

CMD ["npm", "start"]
DOCKERFILE

    # Main app.js
    cat > "$api_dir/src/app.js" << 'APPJS'
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 4000;

// Middleware
app.use(helmet());
app.use(cors());
app.use(express.json());
app.use(morgan('combined'));

// Routes
const healthRoute = require('./routes/health');
const usersRoute = require('./routes/users');
const productsRoute = require('./routes/products');

app.use('/v1/health', healthRoute);
app.use('/v1/users', usersRoute);
app.use('/v1/products', productsRoute);

// Root
app.get('/', (req, res) => {
  res.json({
    message: 'OneStack Node.js API',
    version: '1.0.0',
    endpoints: {
      health: '/v1/health',
      users: '/v1/users',
      products: '/v1/products'
    }
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({ error: 'Not found' });
});

// Error handler
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ error: 'Internal server error' });
});

app.listen(PORT, () => {
  console.log(`🚀 API running on port ${PORT}`);
});
APPJS

    # Health route
    cat > "$api_dir/src/routes/health.js" << 'HEALTHJS'
const express = require('express');
const router = express.Router();

router.get('/', (req, res) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    environment: process.env.NODE_ENV || 'development'
  });
});

module.exports = router;
HEALTHJS

    # Users route
    cat > "$api_dir/src/routes/users.js" << 'USERSJS'
const express = require('express');
const router = express.Router();

// Mock data
let users = [
  { id: 1, name: 'John Doe', email: 'john@example.com' },
  { id: 2, name: 'Jane Smith', email: 'jane@example.com' }
];

// GET all users
router.get('/', (req, res) => {
  res.json({ users });
});

// GET user by ID
router.get('/:id', (req, res) => {
  const user = users.find(u => u.id === parseInt(req.params.id));
  if (!user) return res.status(404).json({ error: 'User not found' });
  res.json({ user });
});

// POST create user
router.post('/', (req, res) => {
  const { name, email } = req.body;
  if (!name || !email) {
    return res.status(400).json({ error: 'Name and email required' });
  }
  
  const user = {
    id: users.length + 1,
    name,
    email
  };
  
  users.push(user);
  res.status(201).json({ user });
});

// PUT update user
router.put('/:id', (req, res) => {
  const user = users.find(u => u.id === parseInt(req.params.id));
  if (!user) return res.status(404).json({ error: 'User not found' });
  
  const { name, email } = req.body;
  if (name) user.name = name;
  if (email) user.email = email;
  
  res.json({ user });
});

// DELETE user
router.delete('/:id', (req, res) => {
  const index = users.findIndex(u => u.id === parseInt(req.params.id));
  if (index === -1) return res.status(404).json({ error: 'User not found' });
  
  users.splice(index, 1);
  res.json({ message: 'User deleted' });
});

module.exports = router;
USERSJS

    # Products route
    cat > "$api_dir/src/routes/products.js" << 'PRODUCTSJS'
const express = require('express');
const router = express.Router();

let products = [
  { id: 1, name: 'Laptop', price: 999.99, stock: 50 },
  { id: 2, name: 'Mouse', price: 29.99, stock: 200 },
  { id: 3, name: 'Keyboard', price: 79.99, stock: 150 }
];

router.get('/', (req, res) => {
  res.json({ products });
});

router.get('/:id', (req, res) => {
  const product = products.find(p => p.id === parseInt(req.params.id));
  if (!product) return res.status(404).json({ error: 'Product not found' });
  res.json({ product });
});

router.post('/', (req, res) => {
  const { name, price, stock } = req.body;
  if (!name || !price) {
    return res.status(400).json({ error: 'Name and price required' });
  }
  
  const product = {
    id: products.length + 1,
    name,
    price: parseFloat(price),
    stock: stock || 0
  };
  
  products.push(product);
  res.status(201).json({ product });
});

module.exports = router;
PRODUCTSJS

    # .dockerignore
    cat > "$api_dir/.dockerignore" << 'DOCKERIGNORE'
node_modules
npm-debug.log
.env
.git
.gitignore
README.md
DOCKERIGNORE

    print_success "Node.js API created"
    echo ""
}

# ════════════════════════════════════════════════
# NGINX CONFIGURATION (COMPLETE)
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
# OneStack Extended Nginx Configuration
# Domain: $PRIMARY_DOMAIN

# Main Website
server {
    listen 80;
    server_name $PRIMARY_DOMAIN www.$PRIMARY_DOMAIN;
    root /var/www/main;
    index index.html;
    location / {
        try_files \$uri \$uri/ /index.html;
    }
}

# Example App Frontend
server {
    listen 80;
    server_name app.$PRIMARY_DOMAIN;
    root /var/www/app;
    index index.html;
    location / {
        try_files \$uri \$uri/ /index.html;
    }
}

# MinIO Console
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

# MinIO S3 API
server {
    listen 80;
    server_name s3.$PRIMARY_DOMAIN;
    client_max_body_size 0;
    location / {
        proxy_pass http://minio:9000;
        proxy_set_header Host \$host;
    }
}

# Node.js API
server {
    listen 80;
    server_name api.$PRIMARY_DOMAIN;
    
    # Node.js API
    location /v1 {
        proxy_pass http://nodejs-api:4000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
EOF

    if [ "$INSTALL_PARSE" = "true" ]; then
        cat >> "$INSTALL_DIR/nginx/conf.d/onestack.conf" << EOF
    
    # Parse Server
    location /parse {
        proxy_pass http://parse-server:1337;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_read_timeout 300s;
        proxy_connect_timeout 300s;
    }
    
    # Parse Dashboard
    location / {
        proxy_pass http://parse-dashboard:4040;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF
    else
        echo "}" >> "$INSTALL_DIR/nginx/conf.d/onestack.conf"
    fi

    cat >> "$INSTALL_DIR/nginx/conf.d/onestack.conf" << EOF

# n8n Workflow Automation
server {
    listen 80;
    server_name flow.$PRIMARY_DOMAIN;
    location / {
        proxy_pass http://n8n:5678;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

# Chatwoot Customer Support
server {
    listen 80;
    server_name chat.$PRIMARY_DOMAIN;
    location / {
        proxy_pass http://chatwoot-rails:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

    if [ "$INSTALL_MONITORING" = "true" ]; then
        cat >> "$INSTALL_DIR/nginx/conf.d/onestack.conf" << EOF

# Grafana Monitoring
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

# Adminer Database UI
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

# Default server (health check)
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
# FRONTEND EXAMPLES
# ════════════════════════════════════════════════

create_frontend_examples() {
    print_header "Creating Frontend Examples"
    
    # Main landing page (updated with all services)
    cat > "$INSTALL_DIR/frontends/main/index.html" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>OneStack Extended - Complete SME Platform</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        .container {
            max-width: 1400px;
            margin: 0 auto;
        }
        .header {
            background: white;
            border-radius: 20px;
            padding: 40px;
            text-align: center;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            margin-bottom: 30px;
        }
        .logo { font-size: 4em; margin-bottom: 10px; }
        h1 { font-size: 3em; color: #333; margin-bottom: 10px; }
        .tagline { font-size: 1.2em; color: #666; }
        .status { 
            background: #10b981; 
            color: white; 
            padding: 10px 25px; 
            border-radius: 50px; 
            margin: 15px 0; 
            display: inline-block;
            font-weight: bold;
        }
        .domain { 
            background: #f3f4f6; 
            padding: 12px; 
            border-radius: 10px; 
            margin: 15px 0; 
            font-family: monospace; 
            color: #667eea;
            font-size: 1.1em;
        }
        
        .section {
            background: white;
            border-radius: 20px;
            padding: 30px;
            margin-bottom: 20px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
        }
        .section h2 {
            color: #667eea;
            margin-bottom: 20px;
            font-size: 1.8em;
        }
        
        .services {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 15px;
        }
        
        .service {
            background: linear-gradient(135deg, #f3f4f6 0%, #e5e7eb 100%);
            padding: 25px;
            border-radius: 15px;
            text-decoration: none;
            color: #333;
            transition: all 0.3s;
            border: 2px solid transparent;
        }
        .service:hover {
            transform: translateY(-5px);
            box-shadow: 0 10px 25px rgba(0,0,0,0.15);
            border-color: #667eea;
        }
        
        .service-icon { font-size: 3em; margin-bottom: 10px; }
        .service-name { 
            font-weight: bold; 
            color: #667eea; 
            font-size: 1.3em;
            margin: 10px 0 5px 0;
        }
        .service-desc { 
            color: #666; 
            font-size: 0.9em;
            line-height: 1.4;
        }
        
        .features {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-top: 20px;
        }
        .feature {
            padding: 20px;
            background: #f9fafb;
            border-radius: 10px;
            border-left: 4px solid #667eea;
        }
        .feature h3 {
            color: #667eea;
            margin-bottom: 10px;
        }
        .feature p {
            color: #666;
            line-height: 1.6;
        }
        
        footer {
            text-align: center;
            color: white;
            padding: 20px;
            margin-top: 30px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <div class="logo">🚀</div>
            <h1>OneStack Extended</h1>
            <p class="tagline">Complete SME Platform - All Services Deployed</p>
            <div class="status">✓ All Systems Operational</div>
            <div class="domain">$PRIMARY_DOMAIN</div>
        </div>

        <div class="section">
            <h2>🎯 Core Services</h2>
            <div class="services">
                <a href="http://storage.$PRIMARY_DOMAIN" class="service" target="_blank">
                    <div class="service-icon">📦</div>
                    <div class="service-name">MinIO Storage</div>
                    <div class="service-desc">S3-compatible object storage for files and backups</div>
                </a>
                
                <a href="http://s3.$PRIMARY_DOMAIN" class="service" target="_blank">
                    <div class="service-icon">☁️</div>
                    <div class="service-name">S3 API</div>
                    <div class="service-desc">Direct S3 API access for integrations</div>
                </a>
EOF

    [ "$INSTALL_PARSE" = "true" ] && cat >> "$INSTALL_DIR/frontends/main/index.html" << EOF
                <a href="http://api.$PRIMARY_DOMAIN" class="service" target="_blank">
                    <div class="service-icon">⚡</div>
                    <div class="service-name">Parse Server</div>
                    <div class="service-desc">Backend-as-a-Service with dashboard</div>
                </a>
EOF

    [ "$INSTALL_MONITORING" = "true" ] && cat >> "$INSTALL_DIR/frontends/main/index.html" << EOF
                <a href="http://monitor.$PRIMARY_DOMAIN" class="service" target="_blank">
                    <div class="service-icon">📊</div>
                    <div class="service-name">Grafana</div>
                    <div class="service-desc">System monitoring and dashboards</div>
                </a>
EOF

    [ "$INSTALL_ADMINER" = "true" ] && cat >> "$INSTALL_DIR/frontends/main/index.html" << EOF
                <a href="http://db.$PRIMARY_DOMAIN" class="service" target="_blank">
                    <div class="service-icon">🗄️</div>
                    <div class="service-name">Adminer</div>
                    <div class="service-desc">Database management interface</div>
                </a>
EOF

    cat >> "$INSTALL_DIR/frontends/main/index.html" << EOF
            </div>
        </div>

        <div class="section">
            <h2>🚀 Extended Services</h2>
            <div class="services">
                <a href="http://flow.$PRIMARY_DOMAIN" class="service" target="_blank">
                    <div class="service-icon">🔄</div>
                    <div class="service-name">n8n Workflows</div>
                    <div class="service-desc">Workflow automation and integrations</div>
                </a>
                
                <a href="http://chat.$PRIMARY_DOMAIN" class="service" target="_blank">
                    <div class="service-icon">💬</div>
                    <div class="service-name">Chatwoot</div>
                    <div class="service-desc">Customer support and live chat</div>
                </a>
                
                <a href="http://api.$PRIMARY_DOMAIN/v1" class="service" target="_blank">
                    <div class="service-icon">🔌</div>
                    <div class="service-name">Node.js API</div>
                    <div class="service-desc">Custom REST API endpoints</div>
                </a>
                
                <a href="http://app.$PRIMARY_DOMAIN" class="service" target="_blank">
                    <div class="service-icon">🎨</div>
                    <div class="service-name">Example App</div>
                    <div class="service-desc">Sample frontend application</div>
                </a>
            </div>
        </div>

        <div class="section">
            <h2>✨ Platform Features</h2>
            <div class="features">
                <div class="feature">
                    <h3>🎯 Complete Solution</h3>
                    <p>All essential services deployed and ready to use: databases, storage, APIs, monitoring, and customer support.</p>
                </div>
                <div class="feature">
                    <h3>🔐 Production Ready</h3>
                    <p>Enterprise-grade security, automated backups, monitoring, and health checks built-in.</p>
                </div>
                <div class="feature">
                    <h3>🚀 Fully Integrated</h3>
                    <p>All services work together seamlessly. Connect n8n to Chatwoot, APIs to databases, everything unified.</p>
                </div>
                <div class="feature">
                    <h3>💰 Cost Effective</h3>
                    <p>Replace \$500+/month in SaaS subscriptions with one self-hosted platform. Own your data.</p>
                </div>
            </div>
        </div>

        <footer>
            <p><strong>OneStack Extended v2.0</strong> - Complete SME Platform</p>
            <p>Generated: $(date)</p>
        </footer>
    </div>
</body>
</html>
EOF

    # Example App Frontend
    cat > "$INSTALL_DIR/frontends/app/index.html" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Example App - OneStack</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #f3f4f6;
            min-height: 100vh;
        }
        
        .navbar {
            background: white;
            padding: 20px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .navbar h1 {
            color: #667eea;
        }
        
        .container {
            max-width: 1200px;
            margin: 40px auto;
            padding: 0 20px;
        }
        
        .card {
            background: white;
            border-radius: 10px;
            padding: 30px;
            margin-bottom: 20px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        
        h2 {
            color: #333;
            margin-bottom: 20px;
        }
        
        .api-demo {
            display: grid;
            gap: 15px;
        }
        
        button {
            background: #667eea;
            color: white;
            border: none;
            padding: 12px 24px;
            border-radius: 6px;
            cursor: pointer;
            font-size: 16px;
            transition: background 0.3s;
        }
        button:hover {
            background: #5568d3;
        }
        
        .response {
            background: #f9fafb;
            border: 1px solid #e5e7eb;
            border-radius: 6px;
            padding: 15px;
            margin-top: 10px;
            font-family: monospace;
            font-size: 14px;
            max-height: 300px;
            overflow-y: auto;
        }
        
        .loading {
            color: #667eea;
            font-style: italic;
        }
        
        .error {
            color: #ef4444;
        }
        
        .success {
            color: #10b981;
        }
    </style>
</head>
<body>
    <div class="navbar">
        <h1>🎨 Example App</h1>
    </div>
    
    <div class="container">
        <div class="card">
            <h2>API Integration Demo</h2>
            <p style="margin-bottom: 20px; color: #666;">
                This is a sample frontend that demonstrates API integration with the Node.js backend.
            </p>
            
            <div class="api-demo">
                <div>
                    <button onclick="testHealth()">Test API Health</button>
                    <div id="health-response" class="response" style="display:none;"></div>
                </div>
                
                <div>
                    <button onclick="getUsers()">Get Users</button>
                    <div id="users-response" class="response" style="display:none;"></div>
                </div>
                
                <div>
                    <button onclick="getProducts()">Get Products</button>
                    <div id="products-response" class="response" style="display:none;"></div>
                </div>
            </div>
        </div>
        
        <div class="card">
            <h2>About This Example</h2>
            <p style="color: #666; line-height: 1.6;">
                This is a starter template for building your own application. 
                It demonstrates how to connect a frontend to the Node.js API backend.
                You can replace this with your own React, Vue, or Angular application.
            </p>
        </div>
    </div>
    
    <script>
        const API_URL = 'http://api.$PRIMARY_DOMAIN/v1';
        
        async function testHealth() {
            const el = document.getElementById('health-response');
            el.style.display = 'block';
            el.innerHTML = '<div class="loading">Loading...</div>';
            
            try {
                const response = await fetch(\`\${API_URL}/health\`);
                const data = await response.json();
                el.innerHTML = '<div class="success">✓ API is healthy!</div><pre>' + 
                    JSON.stringify(data, null, 2) + '</pre>';
            } catch (error) {
                el.innerHTML = '<div class="error">✗ Error: ' + error.message + '</div>';
            }
        }
        
        async function getUsers() {
            const el = document.getElementById('users-response');
            el.style.display = 'block';
            el.innerHTML = '<div class="loading">Loading...</div>';
            
            try {
                const response = await fetch(\`\${API_URL}/users\`);
                const data = await response.json();
                el.innerHTML = '<div class="success">✓ Users loaded!</div><pre>' + 
                    JSON.stringify(data, null, 2) + '</pre>';
            } catch (error) {
                el.innerHTML = '<div class="error">✗ Error: ' + error.message + '</div>';
            }
        }
        
        async function getProducts() {
            const el = document.getElementById('products-response');
            el.style.display = 'block';
            el.innerHTML = '<div class="loading">Loading...</div>';
            
            try {
                const response = await fetch(\`\${API_URL}/products\`);
                const data = await response.json();
                el.innerHTML = '<div class="success">✓ Products loaded!</div><pre>' + 
                    JSON.stringify(data, null, 2) + '</pre>';
            } catch (error) {
                el.innerHTML = '<div class="error">✗ Error: ' + error.message + '</div>';
            }
        }
    </script>
</body>
</html>
EOF

    chown -R "$ONESTACK_USER:$ONESTACK_USER" "$INSTALL_DIR/frontends"
    print_success "Frontend examples created"
    echo ""
}

# ════════════════════════════════════════════════
# DEPLOY ALL SERVICES
# ════════════════════════════════════════════════

deploy_services() {
    print_header "Deploying All Services"
    
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
# WAIT FOR SERVICES & INITIALIZE
# ════════════════════════════════════════════════

wait_for_services() {
    print_header "Waiting for Services to Initialize"
    
    print_info "This may take 60-90 seconds for all services..."
    echo ""
    
    # Wait for databases first
    print_step "Waiting for databases..."
    sleep 20
    
    cd "$INSTALL_DIR"
    
    local max_wait=120
    local elapsed=0
    
    while [ $elapsed -lt $max_wait ]; do
        if docker compose ps postgres | grep -q "Up" && \
           docker compose ps mongodb | grep -q "Up" && \
           docker compose ps redis | grep -q "Up"; then
            print_success "Databases ready!"
            break
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo -n "."
    done
    
    echo ""
    
    # Wait additional time for application services
    print_step "Waiting for application services..."
    sleep 30
    
    # Initialize Chatwoot database
    print_step "Initializing Chatwoot database..."
    docker compose exec -T chatwoot-rails bundle exec rails db:chatwoot_prepare 2>/dev/null || {
        print_warning "Chatwoot database initialization pending..."
        print_info "Run manually: docker compose exec chatwoot-rails bundle exec rails db:chatwoot_prepare"
    }
    
    echo ""
}

verify_services() {
    print_header "Service Status"
    
    cd "$INSTALL_DIR"
    
    print_step "Checking all services..."
    echo ""
    
    local services=(postgres mongodb redis minio nginx n8n chatwoot-rails nodejs-api)
    [ "$INSTALL_PARSE" = "true" ] && services+=(parse-server parse-dashboard)
    [ "$INSTALL_MONITORING" = "true" ] && services+=(prometheus grafana)
    [ "$INSTALL_ADMINER" = "true" ] && services+=(adminer)
    
    for service in "${services[@]}"; do
        if docker compose ps "$service" 2>/dev/null | grep -q "Up"; then
            print_success "$service: ✓ Running"
        else
            print_warning "$service: ⚠ Check logs (docker compose logs $service)"
        fi
    done
    
    echo ""
    
    # Test key endpoints
    print_step "Testing endpoints..."
    sleep 5
    
    # Test Node.js API
    if curl -sf http://localhost:4000/v1/health >/dev/null 2>&1; then
        print_success "Node.js API: ✓ Responding"
    else
        print_warning "Node.js API: ⚠ Not ready yet"
    fi
    
    # Test n8n
    if curl -sf http://localhost:5678 >/dev/null 2>&1; then
        print_success "n8n: ✓ Responding"
    else
        print_warning "n8n: ⚠ Not ready yet"
    fi
    
    # Test Chatwoot
    if curl -sf http://localhost:3000 >/dev/null 2>&1; then
        print_success "Chatwoot: ✓ Responding"
    else
        print_warning "Chatwoot: ⚠ Initializing (may take 2-3 minutes)"
    fi
    
    # Test Parse if enabled
    if [ "$INSTALL_PARSE" = "true" ]; then
        if curl -sf http://localhost:1337/parse/health >/dev/null 2>&1; then
            print_success "Parse Server: ✓ Responding"
        else
            print_warning "Parse Server: ⚠ Not ready yet"
        fi
    fi
    
    echo ""
}

# ════════════════════════════════════════════════
# POST-INSTALL SETUP
# ════════════════════════════════════════════════

create_chatwoot_admin() {
    print_header "Setting up Chatwoot Admin Account"
    
    print_step "Creating Chatwoot admin account..."
    
    cd "$INSTALL_DIR"
    
    # Wait for Chatwoot to be fully ready
    sleep 10
    
    docker compose exec -T chatwoot-rails bundle exec rails runner "
      user = User.find_or_create_by!(email: 'admin@$PRIMARY_DOMAIN') do |u|
        u.password = '$CHATWOOT_PASSWORD'
        u.password_confirmation = '$CHATWOOT_PASSWORD'
        u.name = 'OneStack Admin'
        u.confirmed_at = Time.now
      end
      
      if user.persisted?
        account = Account.find_or_create_by!(name: 'OneStack')
        AccountUser.find_or_create_by!(account: account, user: user, role: :administrator)
        puts 'Admin account created successfully'
      end
    " 2>/dev/null || {
        print_warning "Chatwoot admin setup will complete on first access"
        print_info "Visit http://chat.$PRIMARY_DOMAIN to complete setup"
    }
    
    print_success "Chatwoot ready"
    echo ""
}

create_helper_scripts() {
    print_header "Creating Management Scripts"
    
    local scripts_dir="$INSTALL_DIR/scripts"
    
    # Service management script
    cat > "$scripts_dir/manage-services.sh" << 'MANAGESH'
#!/bin/bash
# OneStack Service Management

cd "$(dirname "$0")/.."

case "$1" in
    start)
        echo "Starting all services..."
        docker compose up -d
        ;;
    stop)
        echo "Stopping all services..."
        docker compose down
        ;;
    restart)
        echo "Restarting all services..."
        docker compose restart
        ;;
    status)
        docker compose ps
        ;;
    logs)
        docker compose logs -f "${2:-}"
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs [service]}"
        exit 1
        ;;
esac
MANAGESH

    # Backup script
    cat > "$scripts_dir/backup.sh" << 'BACKUPSH'
#!/bin/bash
# OneStack Backup Script

BACKUP_DIR="/backups/onestack"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="onestack_backup_${DATE}.tar.gz"

mkdir -p "$BACKUP_DIR"

echo "Starting OneStack backup..."
cd "$(dirname "$0")/.."

# Backup databases
echo "Backing up PostgreSQL..."
docker compose exec -T postgres pg_dumpall -U postgres | gzip > "$BACKUP_DIR/postgres_${DATE}.sql.gz"

echo "Backing up MongoDB..."
docker compose exec -T mongodb mongodump --archive --gzip > "$BACKUP_DIR/mongodb_${DATE}.gz"

echo "Backing up Redis..."
docker compose exec -T redis redis-cli --rdb /data/dump.rdb
docker cp onestack-redis:/data/dump.rdb "$BACKUP_DIR/redis_${DATE}.rdb"

# Backup volumes
echo "Backing up Docker volumes..."
docker run --rm \
    -v onestack_postgres_data:/data/postgres \
    -v onestack_mongodb_data:/data/mongodb \
    -v onestack_n8n_data:/data/n8n \
    -v onestack_chatwoot_storage:/data/chatwoot \
    -v "$BACKUP_DIR:/backup" \
    ubuntu tar czf "/backup/volumes_${DATE}.tar.gz" /data

# Backup configs
echo "Backing up configurations..."
tar czf "$BACKUP_DIR/configs_${DATE}.tar.gz" \
    .env \
    docker-compose.yml \
    nginx/ \
    backends/ \
    frontends/

echo "✓ Backup completed: $BACKUP_FILE"
echo "Location: $BACKUP_DIR"

# Keep only last 7 backups
cd "$BACKUP_DIR"
ls -t onestack_backup_*.tar.gz | tail -n +8 | xargs -r rm

echo "✓ Old backups cleaned"
BACKUPSH

    # Database shell scripts
    cat > "$scripts_dir/psql.sh" << 'PSQLSH'
#!/bin/bash
# Connect to PostgreSQL
cd "$(dirname "$0")/.."
docker compose exec postgres psql -U postgres "$@"
PSQLSH

    cat > "$scripts_dir/mongo.sh" << 'MONGOSH'
#!/bin/bash
# Connect to MongoDB
cd "$(dirname "$0")/.."
docker compose exec mongodb mongosh -u admin -p "$MONGODB_ROOT_PASSWORD" "$@"
MONGOSH

    cat > "$scripts_dir/redis-cli.sh" << 'REDISCLI'
#!/bin/bash
# Connect to Redis
cd "$(dirname "$0")/.."
docker compose exec redis redis-cli -a "$REDIS_PASSWORD" "$@"
REDISCLI

    # Make all scripts executable
    chmod +x "$scripts_dir"/*.sh
    chown -R "$ONESTACK_USER:$ONESTACK_USER" "$scripts_dir"
    
    print_success "Management scripts created"
    echo ""
}

# ════════════════════════════════════════════════
# DISPLAY FINAL INFORMATION
# ════════════════════════════════════════════════

display_access_info() {
    clear
    print_header "🎉 OneStack Extended Installation Complete!"
    
    local server_ip=$(get_server_ip)
    
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  🌐 Access URLs"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "Main Website:"
    echo "  http://$PRIMARY_DOMAIN"
    echo ""
    echo "Core Services:"
    echo "  • MinIO Storage:     http://storage.$PRIMARY_DOMAIN"
    echo "  • S3 API:            http://s3.$PRIMARY_DOMAIN"
    
    [ "$INSTALL_PARSE" = "true" ] && echo "  • Parse Dashboard:   http://api.$PRIMARY_DOMAIN"
    [ "$INSTALL_PARSE" = "true" ] && echo "  • Parse API:         http://api.$PRIMARY_DOMAIN/parse"
    [ "$INSTALL_MONITORING" = "true" ] && echo "  • Grafana:           http://monitor.$PRIMARY_DOMAIN"
    [ "$INSTALL_ADMINER" = "true" ] && echo "  • Adminer:           http://db.$PRIMARY_DOMAIN"
    
    echo ""
    echo "Extended Services:"
    echo "  • n8n Workflows:     http://flow.$PRIMARY_DOMAIN"
    echo "  • Chatwoot:          http://chat.$PRIMARY_DOMAIN"
    echo "  • Node.js API:       http://api.$PRIMARY_DOMAIN/v1"
    echo "  • Example App:       http://app.$PRIMARY_DOMAIN"
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  🔐 Credentials"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "Saved to: $INSTALL_DIR/.credentials"
    echo ""
    echo "Quick Access:"
    echo "  cat $INSTALL_DIR/.credentials"
    echo ""
    echo "Key Credentials:"
    echo ""
    
    if [ "$INSTALL_PARSE" = "true" ]; then
        echo "Parse Dashboard:"
        echo "  Username: admin"
        echo "  Password: (see credentials file)"
        echo ""
    fi
    
    echo "n8n Workflow Automation:"
    echo "  Email:    admin@$PRIMARY_DOMAIN"
    echo "  Password: (see credentials file)"
    echo ""
    
    echo "Chatwoot Customer Support:"
    echo "  Email:    admin@$PRIMARY_DOMAIN"
    echo "  Password: (see credentials file)"
    echo "  Note:     Complete setup on first visit"
    echo ""
    
    echo "═══════════════════════════════════════════════════════════"
    echo "  🛠️  Management Commands"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "Service Management:"
    echo "  cd $INSTALL_DIR"
    echo "  docker compose ps                 # Check status"
    echo "  docker compose logs -f [service]  # View logs"
    echo "  docker compose restart [service]  # Restart service"
    echo ""
    echo "Helper Scripts:"
    echo "  cd $INSTALL_DIR/scripts"
    echo "  ./manage-services.sh status       # Service status"
    echo "  ./backup.sh                       # Create backup"
    echo "  ./psql.sh                         # PostgreSQL shell"
    echo "  ./mongo.sh                        # MongoDB shell"
    echo "  ./redis-cli.sh                    # Redis CLI"
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  📚 Next Steps"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "1. Visit main page to see all services:"
    echo "   http://$PRIMARY_DOMAIN"
    echo ""
    echo "2. Set up Chatwoot (first-time setup):"
    echo "   http://chat.$PRIMARY_DOMAIN"
    echo "   - Complete account setup wizard"
    echo "   - Create your first inbox"
    echo ""
    echo "3. Configure n8n workflows:"
    echo "   http://flow.$PRIMARY_DOMAIN"
    echo "   - Create automation workflows"
    echo "   - Connect services together"
    echo ""
    echo "4. Test Node.js API:"
    echo "   http://api.$PRIMARY_DOMAIN/v1/health"
    echo "   http://api.$PRIMARY_DOMAIN/v1/users"
    echo ""
    echo "5. Deploy your own frontend:"
    echo "   - Upload to: $INSTALL_DIR/frontends/[subdomain]/"
    echo "   - Configure Nginx in: $INSTALL_DIR/nginx/conf.d/"
    echo "   - Reload: docker compose restart nginx"
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  ⚠️  Important Notes"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "• Chatwoot may take 2-3 minutes to fully initialize"
    echo "• First visit to chat.$PRIMARY_DOMAIN will show setup wizard"
    echo "• All credentials are in: .credentials file (keep secure!)"
    echo "• Backups saved to: /backups/onestack/"
    echo "• Docker volumes contain all data (use docker volume commands)"
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  📊 System Resources"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "Run 'docker compose ps' for status"
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    print_success "Installation completed successfully! 🚀"
    echo ""
    print_info "Need help? Check documentation or logs:"
    echo "  docker compose logs [service-name]"
    echo ""
}

# ════════════════════════════════════════════════
# CREATE README
# ════════════════════════════════════════════════

create_readme() {
    cat > "$INSTALL_DIR/README.md" << EOF
# OneStack Extended Platform

Complete SME platform with all essential services deployed and configured.

## 🚀 Services Deployed

### Core Infrastructure
- **PostgreSQL** (Port 5432) - Primary database with pgvector
- **MongoDB** (Port 27017) - Document database
- **Redis** (Port 6379) - Cache and message broker
- **MinIO** (Ports 9000, 9001) - S3-compatible object storage
- **Nginx** (Ports 80, 443) - Reverse proxy and web server

### Extended Services
- **n8n** (Port 5678) - Workflow automation
- **Chatwoot** (Port 3000) - Customer support platform
- **Node.js API** (Port 4000) - Custom REST API
- **Parse Server** (Port 1337) - Backend-as-a-Service $([ "$INSTALL_PARSE" = "true" ] && echo "✓" || echo "✗")
- **Grafana** (Port 3001) - Monitoring dashboards $([ "$INSTALL_MONITORING" = "true" ] && echo "✓" || echo "✗")
- **Adminer** (Port 8080) - Database UI $([ "$INSTALL_ADMINER" = "true" ] && echo "✓" || echo "✗")

## 📋 Quick Commands

### Service Management
\`\`\`bash
docker compose ps                    # Check status
docker compose logs -f [service]     # View logs
docker compose restart [service]     # Restart service
docker compose up -d                 # Start all
docker compose down                  # Stop all
\`\`\`

### Database Access
\`\`\`bash
./scripts/psql.sh                    # PostgreSQL shell
./scripts/mongo.sh                   # MongoDB shell
./scripts/redis-cli.sh               # Redis CLI
\`\`\`

### Backup & Restore
\`\`\`bash
./scripts/backup.sh                  # Create full backup
\`\`\`

## 🔐 Security

Credentials stored in: \`.credentials\` (keep secure!)

**Important:** Change default passwords in production!

## 📚 Documentation

- Architecture: See ARCHITECTURE.md
- API Docs: http://api.$PRIMARY_DOMAIN/v1
- n8n Docs: https://docs.n8n.io
- Chatwoot Docs: https://www.chatwoot.com/docs

## 🆘 Troubleshooting

### Service not starting?
\`\`\`bash
docker compose logs [service-name]
docker compose restart [service-name]
\`\`\`

### Chatwoot initialization
\`\`\`bash
docker compose exec chatwoot-rails bundle exec rails db:chatwoot_prepare
\`\`\`

### Clear all data (dangerous!)
\`\`\`bash
docker compose down -v
\`\`\`

## 📞 Support

- GitHub Issues: [Your repo]
- Documentation: [Your docs]
- Community: [Your community]

---

**OneStack Extended** - Complete SME Platform
Generated: $(date)
EOF

    chown "$ONESTACK_USER:$ONESTACK_USER" "$INSTALL_DIR/README.md"
    print_success "README.md created"
}

# ════════════════════════════════════════════════
# MAIN EXECUTION FUNCTION
# ════════════════════════════════════════════════

run_onestack_setup() {
    check_root
    load_vars
    
    if [ -z "$INSTALL_DIR" ] || [ -z "$PRIMARY_DOMAIN" ]; then
        error_exit "INSTALL_DIR or PRIMARY_DOMAIN not set"
    fi
    
    # Execute all setup steps
    check_nginx_conflict
    create_directory_structure
    generate_passwords
    create_env_file
    create_database_init_scripts
    create_docker_compose
    
    # Service-specific configs
    create_parse_dashboard_config
    create_nodejs_api
    create_nginx_config
    create_monitoring_config
    create_frontend_examples
    
    # Deploy and initialize
    deploy_services
    wait_for_services
    verify_services
    
    # Post-install
    create_chatwoot_admin
    create_helper_scripts
    create_readme
    
    # Final info
    display_access_info
    
    save_var "PHASE_2_COMPLETE" "true"
    
    success_message "OneStack Extended deployed successfully! 🎉"
}

# Export function for use in main installer
export -f run_onestack_setup