#!/bin/bash
# Setup Node.js API Template

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh" 2>/dev/null || {
    RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
    print_header() { echo -e "\n${BLUE}=== $1 ===${NC}\n"; }
    print_step() { echo -e "${BLUE}▶${NC} $1"; }
    print_success() { echo -e "${GREEN}✓${NC} $1"; }
    print_error() { echo -e "${RED}✗${NC} $1"; exit 1; }
}

check_root

print_header "Node.js API Template Setup"

INSTALL_DIR="/opt/onestack"
API_DIR="$INSTALL_DIR/backends/nodejs-api-v1"

# Create directory
print_step "Creating API directory..."
mkdir -p "$API_DIR"/{src/{routes,controllers,models,middleware,utils},tests}

# Create package.json
print_step "Creating package.json..."
cat > "$API_DIR/package.json" << 'PKGJSON'
{
  "name": "onestack-nodejs-api",
  "version": "1.0.0",
  "description": "OneStack Node.js API",
  "main": "src/app.js",
  "scripts": {
    "start": "node src/app.js",
    "dev": "nodemon src/app.js",
    "test": "jest"
  },
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "helmet": "^7.1.0",
    "dotenv": "^16.3.1",
    "pg": "^8.11.3",
    "mongodb": "^6.3.0",
    "redis": "^4.6.11",
    "joi": "^17.11.0",
    "jsonwebtoken": "^9.0.2",
    "bcrypt": "^5.1.1",
    "winston": "^3.11.0"
  },
  "devDependencies": {
    "nodemon": "^3.0.2",
    "jest": "^29.7.0",
    "supertest": "^6.3.3"
  }
}
PKGJSON

# Create .env.example
cat > "$API_DIR/.env.example" << 'ENVEX'
PORT=4000
NODE_ENV=production

# Database
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_DB=onestack_main
POSTGRES_USER=postgres
POSTGRES_PASSWORD=your_password

MONGODB_URI=mongodb://admin:password@mongodb:27017/onestack_main

REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=your_password

# JWT
JWT_SECRET=your_jwt_secret_key
JWT_EXPIRES_IN=24h

# CORS
CORS_ORIGIN=*
ENVEX

# Create main app.js
cat > "$API_DIR/src/app.js" << 'APPJS'
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
require('dotenv').config();

const app = express();

// Middleware
app.use(helmet());
app.use(cors({ origin: process.env.CORS_ORIGIN || '*' }));
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Health check
app.get('/health', (req, res) => {
    res.json({
        status: 'ok',
        timestamp: new Date().toISOString(),
        uptime: process.uptime()
    });
});

// API Routes
app.use('/api/v1/users', require('./routes/users'));
app.use('/api/v1/products', require('./routes/products'));

// 404 handler
app.use((req, res) => {
    res.status(404).json({ error: 'Route not found' });
});

// Error handler
app.use((err, req, res, next) => {
    console.error(err.stack);
    res.status(500).json({ error: 'Internal server error' });
});

const PORT = process.env.PORT || 4000;
app.listen(PORT, () => {
    console.log(`API server running on port ${PORT}`);
});
APPJS

# Create example route
cat > "$API_DIR/src/routes/users.js" << 'USERROUTE'
const express = require('express');
const router = express.Router();

// GET /api/v1/users
router.get('/', async (req, res) => {
    try {
        res.json({
            users: [
                { id: 1, name: 'John Doe', email: 'john@example.com' },
                { id: 2, name: 'Jane Smith', email: 'jane@example.com' }
            ]
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// GET /api/v1/users/:id
router.get('/:id', async (req, res) => {
    try {
        const { id } = req.params;
        res.json({
            id: parseInt(id),
            name: 'John Doe',
            email: 'john@example.com'
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// POST /api/v1/users
router.post('/', async (req, res) => {
    try {
        const { name, email } = req.body;
        res.status(201).json({
            id: Date.now(),
            name,
            email
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

module.exports = router;
USERROUTE

# Create products route
cat > "$API_DIR/src/routes/products.js" << 'PRODROUTE'
const express = require('express');
const router = express.Router();

router.get('/', async (req, res) => {
    res.json({
        products: [
            { id: 1, name: 'Product A', price: 100 },
            { id: 2, name: 'Product B', price: 200 }
        ]
    });
});

module.exports = router;
PRODROUTE

# Create Dockerfile
cat > "$API_DIR/Dockerfile" << 'DOCKERFILE'
FROM node:18-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci --only=production

COPY . .

EXPOSE 4000

CMD ["npm", "start"]
DOCKERFILE

# Create README
cat > "$API_DIR/README.md" << 'README'
# OneStack Node.js API

## Setup
```bash
cd /opt/onestack/backends/nodejs-api-v1
npm install
cp .env.example .env
# Edit .env with your credentials
npm start
```

## Development
```bash
npm run dev
```

## API Endpoints

- `GET /health` - Health check
- `GET /api/v1/users` - List users
- `GET /api/v1/users/:id` - Get user by ID
- `POST /api/v1/users` - Create user
- `GET /api/v1/products` - List products

## Docker
```bash
docker build -t onestack-api .
docker run -p 4000:4000 --env-file .env onestack-api
```
README

# Add to docker-compose
print_step "Updating docker-compose.yml..."

if [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
    cat >> "$INSTALL_DIR/docker-compose.yml" << 'COMPOSEADD'

  # Node.js API v1
  nodejs-api-v1:
    build: ./backends/nodejs-api-v1
    container_name: onestack-nodejs-api-v1
    restart: unless-stopped
    environment:
      PORT: 4000
      NODE_ENV: ${NODE_ENV:-production}
      POSTGRES_HOST: postgres
      POSTGRES_PORT: 5432
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      MONGODB_URI: mongodb://${MONGODB_ROOT_USERNAME}:${MONGODB_ROOT_PASSWORD}@mongodb:27017/onestack_main
      REDIS_HOST: redis
      REDIS_PORT: 6379
      REDIS_PASSWORD: ${REDIS_PASSWORD}
    volumes:
      - ./backends/nodejs-api-v1:/app
      - /app/node_modules
    networks:
      - backend
    ports:
      - "4000:4000"
    depends_on:
      - postgres
      - mongodb
      - redis
COMPOSEADD
fi

# Update Nginx
print_step "Updating Nginx configuration..."

if [ -f "$INSTALL_DIR/nginx/conf.d/onestack.conf" ]; then
    cat >> "$INSTALL_DIR/nginx/conf.d/onestack.conf" << 'NGINXADD'

# Node.js API v1
server {
    listen 80;
    server_name api.${DOMAIN};
    
    location /v1 {
        proxy_pass http://nodejs-api-v1:4000/api/v1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINXADD
fi

print_success "Node.js API template created!"
echo ""
print_header "Next Steps"
echo "1. cd $API_DIR"
echo "2. npm install"
echo "3. cp .env.example .env"
echo "4. Edit .env with your credentials"
echo "5. npm start"
echo ""
echo "Or build with Docker:"
echo "  cd $INSTALL_DIR && docker compose up -d nodejs-api-v1"
echo ""
echo "Access: http://api.yourdomain.com/v1/users"
