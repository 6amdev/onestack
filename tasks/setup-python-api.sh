#!/bin/bash
# Setup Python FastAPI Template

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh" 2>/dev/null || {
    GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
    print_header() { echo -e "\n${BLUE}=== $1 ===${NC}\n"; }
    print_step() { echo -e "${BLUE}▶${NC} $1"; }
    print_success() { echo -e "${GREEN}✓${NC} $1"; }
}

check_root

print_header "Python FastAPI Template Setup"

INSTALL_DIR="/opt/onestack"
API_DIR="$INSTALL_DIR/backends/python-api-v1"

# Create directory
print_step "Creating API directory..."
mkdir -p "$API_DIR"/{app/{routers,models,services,utils},tests}

# Create requirements.txt
cat > "$API_DIR/requirements.txt" << 'REQS'
fastapi==0.104.1
uvicorn[standard]==0.24.0
pydantic==2.5.0
pydantic-settings==2.1.0
python-multipart==0.0.6
python-jose[cryptography]==3.3.0
passlib[bcrypt]==1.7.4
python-dotenv==1.0.0
psycopg2-binary==2.9.9
pymongo==4.6.0
redis==5.0.1
sqlalchemy==2.0.23
alembic==1.13.0
REQS

# Create .env.example
cat > "$API_DIR/.env.example" << 'PYENV'
APP_NAME=OneStack Python API
VERSION=1.0.0
DEBUG=False

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

# Security
SECRET_KEY=your-secret-key-here
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=30
PYENV

# Create main.py
cat > "$API_DIR/app/main.py" << 'MAINPY'
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.routers import users, products
import os
from dotenv import load_dotenv

load_dotenv()

app = FastAPI(
    title=os.getenv("APP_NAME", "OneStack API"),
    version=os.getenv("VERSION", "1.0.0")
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Health check
@app.get("/health")
async def health_check():
    return {
        "status": "ok",
        "version": os.getenv("VERSION", "1.0.0")
    }

# Include routers
app.include_router(users.router, prefix="/api/v1/users", tags=["users"])
app.include_router(products.router, prefix="/api/v1/products", tags=["products"])

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
MAINPY

# Create users router
cat > "$API_DIR/app/routers/users.py" << 'USERSPY'
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Optional

router = APIRouter()

class User(BaseModel):
    id: int
    name: str
    email: str

class UserCreate(BaseModel):
    name: str
    email: str

# In-memory storage (replace with database)
users_db = [
    User(id=1, name="John Doe", email="john@example.com"),
    User(id=2, name="Jane Smith", email="jane@example.com")
]

@router.get("/", response_model=List[User])
async def get_users():
    return users_db

@router.get("/{user_id}", response_model=User)
async def get_user(user_id: int):
    user = next((u for u in users_db if u.id == user_id), None)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user

@router.post("/", response_model=User, status_code=201)
async def create_user(user: UserCreate):
    new_user = User(
        id=len(users_db) + 1,
        name=user.name,
        email=user.email
    )
    users_db.append(new_user)
    return new_user
USERSPY

# Create products router
cat > "$API_DIR/app/routers/products.py" << 'PRODPY'
from fastapi import APIRouter
from pydantic import BaseModel
from typing import List

router = APIRouter()

class Product(BaseModel):
    id: int
    name: str
    price: float

@router.get("/", response_model=List[Product])
async def get_products():
    return [
        Product(id=1, name="Product A", price=100.0),
        Product(id=2, name="Product B", price=200.0)
    ]
PRODPY

# Create Dockerfile
cat > "$API_DIR/Dockerfile" << 'PYDOCKER'
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
PYDOCKER

# Create README
cat > "$API_DIR/README.md" << 'PYREADME'
# OneStack Python FastAPI

## Setup
```bash
cd /opt/onestack/backends/python-api-v1
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
# Edit .env
uvicorn app.main:app --reload
```

## API Documentation

Once running, visit:
- Swagger UI: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc

## Endpoints

- `GET /health` - Health check
- `GET /api/v1/users` - List users
- `GET /api/v1/users/{id}` - Get user
- `POST /api/v1/users` - Create user
- `GET /api/v1/products` - List products

## Docker
```bash
docker build -t onestack-python-api .
docker run -p 8000:8000 --env-file .env onestack-python-api
```
PYREADME

# Add to docker-compose
print_step "Updating docker-compose.yml..."

if [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
    cat >> "$INSTALL_DIR/docker-compose.yml" << 'PYCOMPOSE'

  # Python FastAPI v1
  python-api-v1:
    build: ./backends/python-api-v1
    container_name: onestack-python-api-v1
    restart: unless-stopped
    environment:
      POSTGRES_HOST: postgres
      POSTGRES_PORT: 5432
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      MONGODB_URI: mongodb://${MONGODB_ROOT_USERNAME}:${MONGODB_ROOT_PASSWORD}@mongodb:27017
      REDIS_HOST: redis
      REDIS_PORT: 6379
      REDIS_PASSWORD: ${REDIS_PASSWORD}
    volumes:
      - ./backends/python-api-v1:/app
    networks:
      - backend
    ports:
      - "8000:8000"
    depends_on:
      - postgres
      - mongodb
      - redis
PYCOMPOSE
fi

print_success "Python FastAPI template created!"
echo ""
print_header "Next Steps"
echo "1. cd $API_DIR"
echo "2. python3 -m venv venv && source venv/bin/activate"
echo "3. pip install -r requirements.txt"
echo "4. cp .env.example .env"
echo "5. uvicorn app.main:app --reload"
echo ""
echo "Swagger UI: http://localhost:8000/docs"
