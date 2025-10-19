# OneStack Architecture

> **Complete SME Platform - Self-Hosted, Modular, AI-Powered**

Version: 1.0.0  
Last Updated: 2025-10-19  
Status: Architecture Design Phase

---

## 📚 Table of Contents

- [Overview](#overview)
- [Core Concept](#core-concept)
- [Architecture Layers](#architecture-layers)
- [Component Catalog](#component-catalog)
- [Technology Stack](#technology-stack)
- [System Requirements](#system-requirements)
- [Directory Structure](#directory-structure)
- [Installation System](#installation-system)
- [Domain Management](#domain-management)
- [Security Architecture](#security-architecture)
- [Monitoring & Observability](#monitoring--observability)
- [Backup & Recovery](#backup--recovery)
- [Scalability](#scalability)
- [Use Cases](#use-cases)
- [Comparison](#comparison)
- [Roadmap](#roadmap)

---

## Overview

### What is OneStack?

**OneStack** is a complete, self-hosted business platform designed for SMEs that combines:

- 🎨 **Multi-Frontend Hosting** - Host unlimited websites/applications
- 🚀 **Backend Services** - Complete API and service layer
- 🤖 **AI/ML Capabilities** - Built-in RAG, LLM, and automation
- 💬 **Customer Support** - Multi-channel communication system
- 🗄️ **Database Suite** - All databases you need
- 🎛️ **Admin Dashboard** - Unified management interface
- 🛡️ **Security** - Enterprise-grade protection
- 💾 **Backup System** - Automated data protection
- 📊 **Monitoring** - Full observability stack

### Key Benefits

```
✅ All-in-One Solution (Replace 10+ SaaS subscriptions)
✅ Self-Hosted (Own your data, control your costs)
✅ Open Source (No vendor lock-in, community-driven)
✅ Modular (Install only what you need)
✅ Production-Ready (Enterprise-grade, battle-tested components)
✅ AI-Ready (LLM and RAG built-in)
✅ Developer-Friendly (Full API access, customizable)
✅ Cost-Effective (Save $5,000+/year vs. SaaS)
```

### Quick Stats

- **Installation Time:** 15-20 minutes
- **Components:** 30+ modular services
- **Databases:** 7+ database engines
- **Languages:** Node.js, Python, (extensible)
- **Deployment:** Docker Compose (K8s ready)
- **License:** Open Source (TBD)

---

## Core Concept

### The Problem

Modern SMEs face several challenges:

1. **Fragmented Tools** - Multiple SaaS subscriptions that don't integrate
2. **High Costs** - $500+ per month for basic business tools
3. **No Data Ownership** - Critical data locked in SaaS platforms
4. **Integration Hell** - Manual work to connect different services
5. **Scaling Costs** - Exponential price increases as you grow
6. **Technical Complexity** - Need different expertise for each tool

### The Solution

OneStack provides a **unified platform** that:

```
One Installation     → All services deployed together
One Admin Dashboard  → Manage everything in one place
One Price           → Infrastructure cost only (no per-user fees)
One Stack           → All components work together seamlessly
```

### Design Principles

1. **Simplicity First** - Complex infrastructure, simple interface
2. **Modular Architecture** - Choose what you need, add more later
3. **Convention over Configuration** - Works out-of-box, customize if needed
4. **Security by Default** - Enterprise-grade security built-in
5. **Open Standards** - No proprietary lock-in
6. **Developer Empowerment** - Full access to everything
7. **Production-Ready** - Battle-tested, stable components
8. **Cost-Conscious** - Optimize for efficiency

---

## Architecture Layers

### High-Level Overview

```
┌─────────────────────────────────────────────────────────┐
│                     INTERNET (HTTPS)                     │
└────────────────────────┬────────────────────────────────┘
                         │
              ┌──────────▼──────────┐
              │   Layer 1: Gateway  │
              │   Nginx + SSL + WAF │
              └──────────┬──────────┘
                         │
        ┌────────────────┼────────────────┐
        │                │                │
   ┌────▼─────┐    ┌────▼─────┐    ┌────▼─────┐
   │ Layer 2  │    │ Layer 3  │    │ Layer 4  │
   │ Frontend │    │ Backend  │    │  Admin   │
   └────┬─────┘    └────┬─────┘    └────┬─────┘
        │               │               │
        │          ┌────▼────┐          │
        │          │ Layer 5 │          │
        │          │  AI/ML  │          │
        │          └────┬────┘          │
        │               │               │
        └───────────────┼───────────────┘
                        │
              ┌─────────▼──────────┐
              │   Layer 6: Data    │
              │   All Databases    │
              └─────────┬──────────┘
                        │
              ┌─────────▼──────────┐
              │   Layer 7: Ops     │
              │ Monitor + Security │
              │   + Backup         │
              └────────────────────┘
```

---

## Layer 1: Gateway & Security

### Purpose
Central entry point for all traffic with SSL termination, load balancing, and security filtering.

### Components

#### Nginx Reverse Proxy
- **Role:** HTTP/HTTPS gateway and reverse proxy
- **Features:**
  - Multi-domain routing
  - SSL/TLS termination
  - Load balancing
  - Rate limiting
  - Compression (gzip, brotli)
  - Static file serving
  - WebSocket support
- **Configuration:** `/nginx/nginx.conf` + `/nginx/conf.d/*.conf`
- **Port:** 80 (HTTP), 443 (HTTPS)

#### Certbot (Let's Encrypt)
- **Role:** Automated SSL certificate management
- **Features:**
  - Free SSL certificates
  - Automatic renewal
  - Wildcard support
  - Multi-domain support
- **Configuration:** `/certbot/conf/`
- **Schedule:** Renewal check every 12 hours

#### ModSecurity (WAF)
- **Role:** Web Application Firewall
- **Features:**
  - OWASP Core Rule Set
  - SQL injection protection
  - XSS protection
  - DDoS mitigation
  - Custom rules support
- **Configuration:** `/nginx/security/modsecurity.conf`

#### Fail2Ban
- **Role:** Intrusion prevention system
- **Features:**
  - Automatic IP banning
  - Multiple jail configurations
  - Email notifications
  - Whitelist management
- **Configuration:** `/security/fail2ban/`
- **Actions:** Ban after 5 failed attempts, 1-hour duration

### Domain Management

#### Multi-Domain Support
```
Primary Domains (Unlimited):
  ├── yourdomain.com
  ├── yourbrand.com
  └── custom.io

Subdomains per Domain (Unlimited):
  ├── api.{domain}        → Backend APIs
  ├── app.{domain}        → Customer application
  ├── admin.{domain}      → Admin dashboard
  ├── chat.{domain}       → Customer support
  ├── ai.{domain}         → AI services
  ├── monitor.{domain}    → Monitoring
  ├── docs.{domain}       → Documentation
  └── [custom].{domain}   → Any custom service
```

#### SSL Certificate Options
1. **Let's Encrypt (Default)**
   - Automated issuance
   - 90-day validity, auto-renewal
   - Wildcard support (`*.domain.com`)

2. **Custom Certificates**
   - Upload via admin UI
   - Support for paid certificates
   - Manual renewal

3. **Cloudflare (Optional)**
   - Proxy mode
   - Additional DDoS protection
   - Global CDN

### Routing Rules

```nginx
# Example routing configuration
api.domain.com/parse     → Parse Server (port 1337)
api.domain.com/v1        → Node.js API v1 (port 4001)
api.domain.com/v2        → Node.js API v2 (port 4002)
api.domain.com/rag       → Python RAG (port 8000)

app.domain.com           → Frontend App (static files)
admin.domain.com         → Admin Dashboard (static + API)
chat.domain.com          → Chatwoot (port 3000)
```

---

## Layer 2: Frontend Hosting

### Purpose
Host and serve multiple frontend applications with SPA routing support.

### Architecture

```
Frontend Layer
├── Static File Serving (Nginx)
├── SPA Routing Support
├── Asset Optimization
└── CDN Integration (MinIO)
```

### Supported Frameworks

- **React** (Create React App, Next.js, Vite)
- **Vue** (Vue CLI, Nuxt.js, Vite)
- **Angular** (Angular CLI)
- **Svelte** (SvelteKit)
- **Static HTML/CSS/JS**

### Deployment Process

```bash
# Build your frontend
npm run build

# Deploy via script
./deploy-frontend.sh ./dist app.yourdomain.com

# Or via Admin UI
admin.yourdomain.com/deployment → Upload build.zip
```

### Directory Structure

```
/var/www/
├── main/                    # yourdomain.com
│   ├── index.html
│   ├── assets/
│   └── ...
│
├── app/                     # app.yourdomain.com
│   ├── index.html
│   ├── static/
│   └── ...
│
├── admin/                   # admin.yourdomain.com
│   ├── index.html
│   └── ...
│
└── [custom]/                # custom.yourdomain.com
    └── ...
```

### Nginx Configuration for SPAs

```nginx
server {
    listen 443 ssl http2;
    server_name app.yourdomain.com;
    
    root /var/www/app;
    index index.html;
    
    # SPA routing - all requests go to index.html
    location / {
        try_files $uri $uri/ /index.html;
    }
    
    # Static assets with caching
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # API proxy
    location /api {
        proxy_pass http://backend-service:4000;
        # ... proxy settings
    }
}
```

### CDN & Assets

#### MinIO Integration
- **Purpose:** S3-compatible object storage for assets
- **Access:** `cdn.yourdomain.com` or `storage.yourdomain.com`
- **Features:**
  - Unlimited file storage
  - Image optimization
  - Video streaming
  - Backup storage

---

## Layer 3: Backend Services

### Purpose
Provide backend APIs, business logic, and service layer.

### Components Overview

```
Backend Layer
├── Parse Server (BaaS)
├── Node.js APIs (Custom)
├── Python Services (AI/ML)
└── GraphQL Server (Optional)
```

---

### 3.1 Parse Server (Backend-as-a-Service)

#### Description
Complete backend platform with built-in user management, database, files, and cloud functions.

#### Features
- **User Authentication**
  - Email/password
  - Social login (Facebook, Google, Apple)
  - Session management
  - Role-based access control (RBAC)

- **Database API**
  - RESTful API
  - GraphQL support
  - Live Queries (real-time)
  - Relations and pointers

- **File Storage**
  - Upload/download
  - Image thumbnails
  - S3-compatible storage

- **Cloud Functions**
  - Server-side JavaScript
  - Triggers (beforeSave, afterSave)
  - Background jobs
  - Webhooks

- **Push Notifications**
  - iOS (APNS)
  - Android (FCM)
  - Web push

#### Configuration

```javascript
// Parse Server Config
{
  appId: 'YOUR_APP_ID',
  masterKey: 'YOUR_MASTER_KEY',
  databaseURI: 'mongodb://mongodb:27017/parse',
  serverURL: 'https://api.yourdomain.com/parse',
  
  // Cloud Code
  cloud: '/app/cloud/main.js',
  
  // File storage
  filesAdapter: {
    module: '@parse/s3-files-adapter',
    options: {
      bucket: 'parse-files'
    }
  },
  
  // Live Query
  liveQuery: {
    classNames: ['Message', 'Notification']
  }
}
```

#### Parse Dashboard
- **Access:** `admin.yourdomain.com/parse`
- **Features:**
  - Browse data
  - Run queries
  - Manage users
  - View logs
  - Configure cloud functions

#### Client SDKs
- JavaScript/TypeScript
- iOS (Swift)
- Android (Kotlin/Java)
- React Native
- Flutter

---

### 3.2 Node.js API Services

#### Purpose
Custom business logic and API endpoints.

#### Template Structure

```
nodejs-api/
├── src/
│   ├── routes/
│   │   ├── users.js
│   │   ├── products.js
│   │   └── orders.js
│   │
│   ├── controllers/
│   │   ├── userController.js
│   │   └── ...
│   │
│   ├── models/
│   │   ├── User.js
│   │   └── ...
│   │
│   ├── middleware/
│   │   ├── auth.js
│   │   ├── validation.js
│   │   └── errorHandler.js
│   │
│   ├── utils/
│   │   ├── db.js
│   │   └── helpers.js
│   │
│   └── app.js
│
├── tests/
├── package.json
└── Dockerfile
```

#### Tech Stack
- **Framework:** Express.js / Fastify / NestJS
- **Language:** TypeScript (recommended) or JavaScript
- **Validation:** Joi / Zod
- **ORM:** Prisma / TypeORM / Mongoose
- **Testing:** Jest / Mocha

#### Multiple API Versions

```
nodejs-api-v1/    → Legacy API (Express)
nodejs-api-v2/    → Current API (NestJS + TypeScript)
nodejs-api-v3/    → Beta API (Fastify)
```

Each API can run independently and route via:
```
api.domain.com/v1/*  → nodejs-api-v1:4001
api.domain.com/v2/*  → nodejs-api-v2:4002
api.domain.com/v3/*  → nodejs-api-v3:4003
```

---

### 3.3 Python Services

#### Purpose
AI/ML workloads, data processing, RAG systems.

#### Template Structure

```
python-service/
├── app/
│   ├── main.py           # FastAPI app
│   ├── routers/
│   │   ├── rag.py
│   │   └── ai.py
│   │
│   ├── services/
│   │   ├── llm.py
│   │   ├── vectordb.py
│   │   └── embedding.py
│   │
│   ├── models/
│   │   └── schemas.py
│   │
│   └── utils/
│       └── helpers.py
│
├── tests/
├── requirements.txt
└── Dockerfile
```

#### Tech Stack
- **Framework:** FastAPI (recommended) / Flask
- **AI/ML:** 
  - LangChain
  - LlamaIndex
  - Transformers
  - OpenAI SDK
- **Vector DBs:** ChromaDB / Qdrant clients
- **Testing:** pytest

---

## Layer 4: Admin & Management

### Purpose
Unified interface to manage all OneStack services.

### Super Admin Dashboard

#### Access
- **URL:** `admin.yourdomain.com`
- **Auth:** SSO (Authentik) or built-in auth
- **Tech:** React/Vue + Node.js backend

#### Features Overview

```
Admin Dashboard
├── 📊 Overview Dashboard
├── 🔧 Service Control
├── 🗄️ Database Admin
├── 👥 User Management
├── 🌐 Domain Manager
├── 🔐 SSL Manager
├── 🛡️ Security Center
├── 💾 Backup Manager
├── 📈 Monitoring Hub
├── 📝 Log Viewer
├── ⚙️ System Settings
├── 🚀 Deployment
└── 📚 Documentation
```

---

#### 4.1 Overview Dashboard

**Displays:**
- System health status
- Resource usage (CPU, RAM, Disk)
- Active services count
- Recent alerts
- User statistics
- API request metrics
- Quick actions

**Widgets:**
- Real-time metrics graphs
- Service status indicators
- Alert timeline
- Resource gauges

---

#### 4.2 Service Control

**Features:**
- Start/Stop/Restart services
- View service logs (real-time)
- Check service health
- Resource usage per service
- Container management
- Auto-restart settings

**Actions:**
```bash
# Via UI or API
POST /api/services/chatwoot/restart
POST /api/services/postgres/stop
GET  /api/services/nginx/logs?tail=100
```

---

#### 4.3 Database Administration

**Unified DB Interface:**
- PostgreSQL browser
- MongoDB explorer
- MySQL/MariaDB admin
- Redis commander
- Elasticsearch queries

**Features:**
- Query builder
- Data browser
- Import/Export
- Index management
- Performance stats
- Backup/Restore

**Tools Integrated:**
- Adminer (universal SQL)
- Mongo Express
- Redis Commander
- pgAdmin (optional)

---

#### 4.4 User Management

**Capabilities:**
- CRUD operations
- Role-based access control
- Permission management
- Activity logs
- Session management
- Bulk operations
- CSV import/export

**User Types:**
- Super Admin (full access)
- Admin (service management)
- Developer (read-only + deployments)
- Viewer (read-only)

---

#### 4.5 Domain Manager

**Features:**
- Add/Remove domains
- Configure subdomains
- DNS configuration helper
- Domain verification
- Redirect rules (www → non-www)
- CORS settings

**Add Domain Flow:**
```
1. Enter domain name
2. Verify DNS records
3. Request SSL certificate
4. Configure Nginx
5. Test and activate
```

**DNS Helper:**
```
Required DNS Records:
├── A      @     → 159.223.73.110
├── A      *     → 159.223.73.110 (wildcard)
└── CNAME  www   → @
```

---

#### 4.6 SSL Manager

**Features:**
- View all certificates
- Request new certificates (Let's Encrypt)
- Upload custom certificates
- Auto-renewal status
- Expiry notifications
- Certificate backup

**Certificate Types:**
1. **Let's Encrypt (Automated)**
   - One-click request
   - Auto-renewal enabled by default
   - Wildcard support

2. **Custom Upload**
   - Upload .crt and .key files
   - Manual renewal reminders

**UI Example:**
```
┌────────────────────────────────────────┐
│ SSL Certificates                       │
├────────────────────────────────────────┤
│ yourdomain.com                         │
│ Type: Let's Encrypt                    │
│ Expires: 2025-12-01                    │
│ Auto-renew: ✅                         │
│ [Renew Now] [Revoke] [Download]       │
├────────────────────────────────────────┤
│ [+ Request New Certificate]            │
│ [+ Upload Custom Certificate]          │
└────────────────────────────────────────┘
```

---

#### 4.7 Security Center

**Features:**
- Firewall rules (UFW management)
- WAF rules (ModSecurity)
- Failed login attempts log
- Blocked IPs list
- IP whitelist/blacklist
- Security scan results
- Vulnerability reports
- SSL/TLS configuration
- Password policies

**Security Dashboard:**
- Active threats
- Blocked requests (24h)
- Failed auth attempts
- Open ports
- SSL grade
- Security score

---

#### 4.8 Backup Manager

**Features:**
- Create manual backup
- Schedule automated backups
- Backup history
- Restore interface
- Backup verification
- Storage management
- Remote backup sync

**Backup Configuration:**
```yaml
Schedule:
  - Daily @ 2:00 AM
  - Weekly @ Sunday 3:00 AM
  - Monthly @ 1st 4:00 AM

Retention:
  - Daily: 7 days
  - Weekly: 4 weeks
  - Monthly: 12 months

Targets:
  - All databases
  - Application volumes
  - Configuration files
  - SSL certificates

Storage:
  - Local: /backups (7 days)
  - Remote: MinIO/S3 (30 days)
  - Archive: Glacier (1 year)
```

---

#### 4.9 Monitoring Hub

**Embedded Tools:**
- Grafana dashboards
- Prometheus metrics
- Log viewer (Loki/ELK)
- Uptime status

**Pre-built Dashboards:**
- System overview
- Container metrics
- Nginx performance
- Database performance
- Application metrics
- Business KPIs (custom)

**Alerting:**
- Email notifications
- Slack integration
- Webhook support
- Alert rules management

---

#### 4.10 Log Viewer

**Features:**
- Unified log aggregation
- Multi-service search
- Filter by:
  - Service
  - Level (error, warn, info)
  - Time range
  - Keywords
- Real-time streaming
- Export logs (CSV, JSON)
- Log analysis

**Log Sources:**
- Application logs
- Nginx access/error logs
- Database logs
- System logs
- Security logs
- Audit logs

---

#### 4.11 System Settings

**Configuration Sections:**

**General:**
- Site name/title
- Timezone
- Language
- Date/time format

**Email/SMTP:**
- SMTP server
- Port, username, password
- From address
- Test email button

**API Keys:**
- OpenAI API key
- Cloud service credentials
- Third-party integrations
- Webhook secrets

**Feature Flags:**
- Enable/disable features
- Beta features
- Maintenance mode
- Debug mode

**Environment Variables:**
- View all env vars
- Edit (with validation)
- Add custom vars
- Secure secrets

---

#### 4.12 Deployment

**Features:**
- Deploy frontend builds
- Pull Docker images
- Update services
- Rollback deployments
- CI/CD triggers
- Deployment history

**Deployment Methods:**

1. **Upload Build (ZIP)**
   ```
   Upload → Extract → Deploy → Reload Nginx
   ```

2. **Git Integration**
   ```
   Connect repo → Webhook → Auto-deploy on push
   ```

3. **Docker Registry**
   ```
   Pull image → Update compose → Restart service
   ```

**Rollback:**
- View deployment history
- One-click rollback to previous version
- Compare versions

---

### Specialized Admin Tools

These tools are integrated into the main admin dashboard but can also be accessed directly:

#### Parse Dashboard
- **Path:** `admin.domain.com/parse`
- **Purpose:** Parse Server administration

#### Adminer
- **Path:** `admin.domain.com/db`
- **Purpose:** Universal database admin (SQL)

#### Mongo Express
- **Path:** `admin.domain.com/mongo`
- **Purpose:** MongoDB administration

#### Redis Commander
- **Path:** `admin.domain.com/redis`
- **Purpose:** Redis data browser

#### Portainer
- **Path:** `admin.domain.com/docker`
- **Purpose:** Docker container management

#### Bull Board
- **Path:** `admin.domain.com/queue`
- **Purpose:** Redis queue dashboard

#### MinIO Console
- **Path:** `storage.domain.com`
- **Purpose:** Object storage management

---

## Layer 5: AI & Automation

### Purpose
Provide AI/ML capabilities and workflow automation.

### Components

```
AI/ML Layer
├── Python RAG System
├── Ollama (Local LLM)
├── Vector Databases
├── n8n (Automation)
└── Cloud LLM APIs (Optional)
```

---

### 5.1 Python RAG System

#### Description
Retrieval-Augmented Generation system for intelligent Q&A.

#### Architecture

```
User Question
     ↓
Embedding Generation (vectorize query)
     ↓
Vector Search (find relevant docs)
     ↓
Context Retrieval (get top K results)
     ↓
LLM Prompt (question + context)
     ↓
Generate Answer
     ↓
Return to User
```

#### Features
- **Document Ingestion**
  - PDF, DOCX, TXT, MD
  - Web scraping
  - API integration
  
- **Chunking**
  - Semantic chunking
  - Overlap handling
  - Metadata preservation

- **Embedding**
  - Local: sentence-transformers
  - Cloud: OpenAI embeddings
  - Multi-lingual support

- **Vector Storage**
  - Primary: ChromaDB
  - Backup: Qdrant
  - Optional: Weaviate, Milvus

- **LLM Integration**
  - Local: Ollama (Llama, Mistral)
  - Cloud: OpenAI, Claude, Gemini
  - Fallback mechanism

#### API Endpoints

```http
POST /rag/ingest
  - Upload documents for indexing

POST /rag/query
  - Ask questions

GET /rag/collections
  - List document collections

DELETE /rag/collection/:id
  - Remove a collection
```

#### Configuration

```python
# RAG Config
{
    "embedding_model": "all-MiniLM-L6-v2",
    "chunk_size": 512,
    "chunk_overlap": 50,
    "top_k": 5,
    "llm": {
        "provider": "ollama",
        "model": "llama3:8b",
        "temperature": 0.7,
        "max_tokens": 500
    },
    "vector_db": {
        "provider": "chromadb",
        "collection": "main"
    }
}
```

---

### 5.2 Ollama (Local LLM)

#### Description
Run large language models locally without API costs.

#### Supported Models
- **Llama 3** (8B, 70B)
- **Mistral** (7B, Mixtral 8x7B)
- **Gemma** (2B, 7B)
- **CodeLlama** (7B, 13B, 34B)
- **Phi-2** (2.7B)
- **Custom fine-tuned models**

#### Usage

```bash
# Pull a model
docker exec ollama ollama pull llama3

# List models
docker exec ollama ollama list

# Run inference
curl http://ollama:11434/api/generate -d '{
  "model": "llama3",
  "prompt": "Explain quantum computing"
}'
```

#### Integration

```python
# Python RAG integration
from ollama import Client

client = Client(host='http://ollama:11434')
response = client.generate(
    model='llama3',
    prompt=f"Context: {context}\n\nQuestion: {question}"
)
```

#### Resource Requirements
- **Small models (< 7B):** 8GB RAM
- **Medium models (7-13B):** 16GB RAM
- **Large models (70B+):** 64GB+ RAM, GPU recommended

---

### 5.3 Vector Databases

#### ChromaDB (Primary)

**Features:**
- Simple API
- Fast similarity search
- Metadata filtering
- Persistent storage
- Python/JS clients

**Usage:**
```python
import chromadb

client = chromadb.Client()
collection = client.create_collection("documents")

# Add documents
collection.add(
    documents=["doc1", "doc2"],
    embeddings=[[0.1, 0.2, ...], [0.3, 0.4, ...]],
    metadatas=[{"source": "pdf"}, {"source": "web"}],
    ids=["id1", "id2"]
)

# Query
results = collection.query(
    query_embeddings=[[0.1, 0.2, ...]],
    n_results=5
)
```

#### Qdrant (Secondary)

**Features:**
- High performance
- Advanced filtering
- Sharding support
- Payload support
- gRPC API

**Use Cases:**
- Large-scale deployments
- Complex filtering needs
- High-throughput scenarios

#### Weaviate (Advanced - Optional)

**Features:**
- GraphQL API
- Hybrid search (vector + keyword)
- Multi-tenancy
- Built-in modules (text2vec, etc.)

**Use Cases:**
- Complex data relationships
- Enterprise features
- Advanced search requirements

#### Milvus (High-Performance - Optional)

**Features:**
- Distributed architecture
- GPU acceleration
- Billion-scale vectors
- Multiple index types

**Use Cases:**
- Very large datasets (millions+ vectors)
- Real-time search at scale
- GPU-accelerated inference

---

### 5.4 n8n (Workflow Automation)

#### Description
Visual workflow automation tool connecting OneStack services.

#### Access
- **URL:** `flow.yourdomain.com` or `n8n.yourdomain.com`
- **Auth:** Admin credentials or SSO

#### Key Features
- **500+ Integrations**
- **Visual workflow builder**
- **Webhook triggers**
- **Scheduled workflows**
- **Error handling**
- **Version control**

#### Common Workflows

**1. AI-Powered Customer Support:**
```
Chatwoot (new message)
  ↓
n8n (receive webhook)
  ↓
Python RAG API (get answer)
  ↓
Chatwoot (send response)
```

**2. Automated Backups:**
```
Schedule (daily 2 AM)
  ↓
n8n (trigger backup script)
  ↓
Database backup
  ↓
Upload to S3/MinIO
  ↓
Slack notification
```

**3. User Onboarding:**
```
Parse Server (new user)
  ↓
n8n (webhook)
  ↓
Send welcome email
  ↓
Create Chatwoot contact
  ↓
Add to CRM
  ↓
Slack notification to sales
```

**4. Content Pipeline:**
```
Google Docs (new doc)
  ↓
n8n (poll for changes)
  ↓
Convert to markdown
  ↓
Store in database
  ↓
Trigger frontend rebuild
  ↓
Deploy to CDN
```

#### Integration with OneStack

```javascript
// n8n can call any OneStack service
{
  "nodes": [
    {
      "type": "n8n-nodes-base.httpRequest",
      "name": "Call RAG API",
      "parameters": {
        "url": "http://python-rag:8000/rag/query",
        "method": "POST",
        "body": {
          "question": "={{$json.message}}"
        }
      }
    }
  ]
}
```

---

### 5.5 Cloud LLM APIs (Optional)

When local LLM is not sufficient, integrate cloud providers:

#### OpenAI
```python
from openai import OpenAI

client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))
response = client.chat.completions.create(
    model="gpt-4",
    messages=[{"role": "user", "content": prompt}]
)
```

#### Anthropic Claude
```python
from anthropic import Anthropic

client = Anthropic(api_key=os.getenv("ANTHROPIC_API_KEY"))
response = client.messages.create(
    model="claude-3-opus-20240229",
    max_tokens=1024,
    messages=[{"role": "user", "content": prompt}]
)
```

#### Google Gemini
```python
import google.generativeai as genai

genai.configure(api_key=os.getenv("GOOGLE_API_KEY"))
model = genai.GenerativeModel('gemini-pro')
response = model.generate_content(prompt)
```

#### Groq (Fast & Free Tier)
```python
from groq import Groq

client = Groq(api_key=os.getenv("GROQ_API_KEY"))
response = client.chat.completions.create(
    model="mixtral-8x7b-32768",
    messages=[{"role": "user", "content": prompt}]
)
```

---

## Layer 6: Data Storage

### Purpose
Provide persistent storage for all data types.

### Database Overview

```
Data Layer
├── Relational (PostgreSQL, MySQL)
├── Document (MongoDB)
├── Key-Value (Redis)
├── Search (Elasticsearch)
├── Vector (ChromaDB, Qdrant, Weaviate, Milvus)
├── Time-Series (InfluxDB - Optional)
└── Object Storage (MinIO)
```

---

### 6.1 PostgreSQL

#### Purpose
Primary relational database for structured data.

#### Version
- **Image:** `pgvector/pgvector:pg16`
- **Includes:** pgvector extension for vector operations

#### Databases

```
postgres
├── chatwoot_production   # Chatwoot data
├── n8n_db               # n8n workflows
├── parse_db             # Parse Server (optional)
├── app_main_db          # Application data
└── authentik_db         # SSO data
```

#### Features
- ACID compliance
- Advanced querying
- Full-text search
- JSON support (JSONB)
- Vector similarity (pgvector)
- Replication support
- Point-in-time recovery

#### Configuration

```yaml
postgres:
  image: pgvector/pgvector:pg16
  environment:
    POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    POSTGRES_MULTIPLE_DATABASES: chatwoot_production,n8n_db,parse_db
  volumes:
    - postgres_data:/var/lib/postgresql/data
  networks:
    - backend
  healthcheck:
    test: ["CMD-SHELL", "pg_isready -U postgres"]
```

#### Access
- **Port:** 5432 (internal only)
- **Admin:** Via Adminer (`admin.domain.com/db`)
- **Backup:** Automated with `pg_dump`

---

### 6.2 MongoDB

#### Purpose
Document database for flexible schemas and nested data.

#### Version
- **Image:** `mongo:7`

#### Databases

```
mongodb
├── parse_main       # Parse Server main data
├── app_data        # Application collections
├── logs            # Application logs
├── sessions        # User sessions
└── analytics       # Analytics data
```

#### Features
- Flexible schemas
- Nested documents
- High write throughput
- Horizontal scaling (sharding)
- Aggregation pipeline
- Change streams (real-time)

#### Configuration

```yaml
mongodb:
  image: mongo:7
  environment:
    MONGO_INITDB_ROOT_USERNAME: admin
    MONGO_INITDB_ROOT_PASSWORD: ${MONGODB_PASSWORD}
  volumes:
    - mongodb_data:/data/db
  networks:
    - backend
  healthcheck:
    test: echo 'db.runCommand("ping").ok' | mongosh --quiet
```

#### Access
- **Port:** 27017 (internal only)
- **Admin:** Via Mongo Express (`admin.domain.com/mongo`)
- **Backup:** Automated with `mongodump`

---

### 6.3 Redis

#### Purpose
In-memory data store for caching, sessions, and queues.

#### Version
- **Image:** `redis:alpine`

#### Use Cases

```
Redis
├── Cache Layer
│   ├── API response caching
│   ├── Database query caching
│   └── Computed results
│
├── Session Store
│   ├── User sessions
│   ├── JWT tokens
│   └── CSRF tokens
│
├── Message Queue
│   ├── Job queues (Bull)
│   ├── Pub/Sub
│   └── Rate limiting
│
└── Real-time Data
    ├── Live counters
    ├── Leaderboards
    └── Presence tracking
```

#### Configuration

```yaml
redis:
  image: redis:alpine
  command: redis-server --requirepass ${REDIS_PASSWORD}
  volumes:
    - redis_data:/data
  networks:
    - backend
  healthcheck:
    test: ["CMD", "redis-cli", "ping"]
```

#### Access
- **Port:** 6379 (internal only)
- **Admin:** Via Redis Commander (`admin.domain.com/redis`)
- **Backup:** RDB snapshots (automatic)

---

### 6.4 MySQL/MariaDB (Optional)

#### Purpose
Alternative relational database for legacy systems or specific needs.

#### Use Cases
- Legacy application compatibility
- WordPress/PHP applications
- Specific tool requirements

#### Configuration

```yaml
mysql:
  image: mysql:8.0  # or mariadb:11
  environment:
    MYSQL_ROOT_PASSWORD: ${MYSQL_PASSWORD}
    MYSQL_DATABASE: app_db
  volumes:
    - mysql_data:/var/lib/mysql
  networks:
    - backend
```

---

### 6.5 Elasticsearch (Optional)

#### Purpose
Full-text search engine and log storage.

#### Features
- Full-text search
- Fuzzy matching
- Aggregations
- Real-time indexing
- Distributed architecture

#### Use Cases
- Application search
- Log aggregation (ELK stack)
- Analytics
- Business intelligence

#### Configuration

```yaml
elasticsearch:
  image: docker.elastic.co/elasticsearch/elasticsearch:8.11.0
  environment:
    - discovery.type=single-node
    - xpack.security.enabled=false
  volumes:
    - elasticsearch_data:/usr/share/elasticsearch/data
  networks:
    - backend
```

---

### 6.6 InfluxDB (Optional)

#### Purpose
Time-series database for metrics and IoT data.

#### Use Cases
- Application metrics
- Server metrics
- IoT sensor data
- Financial time-series

#### Configuration

```yaml
influxdb:
  image: influxdb:2.7
  environment:
    INFLUXDB_DB: metrics
    INFLUXDB_ADMIN_USER: admin
    INFLUXDB_ADMIN_PASSWORD: ${INFLUXDB_PASSWORD}
  volumes:
    - influxdb_data:/var/lib/influxdb2
  networks:
    - backend
```

---

### 6.7 MinIO (Object Storage)

#### Purpose
S3-compatible object storage for files, backups, and assets.

#### Features
- S3-compatible API
- Unlimited storage (disk-based)
- Bucket management
- Access control
- Encryption
- Versioning

#### Use Cases
- User uploads (images, videos, documents)
- Backup storage
- Static assets (CDN)
- ML model storage
- Large file storage

#### Configuration

```yaml
minio:
  image: minio/minio:latest
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
    - "9000:9000"  # API
    - "9001:9001"  # Console
```

#### Access
- **API:** `http://minio:9000` (internal)
- **Console:** `storage.yourdomain.com`
- **SDK:** AWS S3 SDK compatible

---

## Layer 7: Operations & Observability

### Purpose
Monitor, secure, and maintain the entire platform.

### Components

```
Ops Layer
├── Monitoring (Prometheus + Grafana)
├── Logging (Loki + ELK)
├── Uptime (Uptime Kuma)
├── Security (Fail2Ban, Vault, Authentik)
└── Backup (Automated system)
```

---

### 7.1 Monitoring Stack

#### Prometheus (Metrics Collection)

**Purpose:** Collect and store time-series metrics.

**Features:**
- Pull-based model
- Multi-dimensional data
- PromQL query language
- Alerting rules
- Service discovery

**Metrics Collected:**
- System metrics (CPU, RAM, Disk, Network)
- Container metrics (per service)
- Application metrics (custom)
- Database metrics
- Nginx metrics

**Configuration:**

```yaml
# prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
  
  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']
  
  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']
  
  - job_name: 'nginx'
    static_configs:
      - targets: ['nginx-exporter:9113']
```

#### Grafana (Visualization)

**Purpose:** Visualize metrics with dashboards and alerts.

**Access:** `monitor.yourdomain.com`

**Pre-built Dashboards:**
1. **System Overview**
   - CPU, RAM, Disk usage
   - Network I/O
   - Load average
   - Uptime

2. **Container Stats**
   - Resource usage per container
   - Restart counts
   - Health status

3. **Nginx Performance**
   - Request rate
   - Response times
   - Status codes
   - Bandwidth

4. **Database Performance**
   - Query performance
   - Connection pools
   - Cache hit rates
   - Slow queries

5. **Application Metrics**
   - API response times
   - Error rates
   - Active users
   - Custom business metrics

**Alerting:**
- Email notifications
- Slack integration
- Webhook support
- PagerDuty integration

---

### 7.2 Logging Stack

#### Option A: Loki + Promtail (Lightweight)

**Loki (Log Aggregation):**
- Like Prometheus but for logs
- Label-based indexing
- Low resource usage
- Integrates with Grafana

**Promtail (Log Shipper):**
- Collects logs from containers
- Parses and labels
- Sends to Loki

**Configuration:**

```yaml
# promtail-config.yml
server:
  http_listen_port: 9080

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: containers
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
    relabel_configs:
      - source_labels: ['__meta_docker_container_name']
        target_label: 'container'
```

#### Option B: ELK Stack (Full-Featured)

**Elasticsearch:** Log storage and search  
**Logstash:** Log processing and enrichment  
**Kibana:** Log visualization and analysis

**Access:** `logs.yourdomain.com`

**Features:**
- Advanced search
- Full-text queries
- Log correlation
- Anomaly detection
- Custom visualizations

---

### 7.3 Uptime Monitoring

#### Uptime Kuma

**Purpose:** Monitor service availability and uptime.

**Access:** `status.yourdomain.com` (public status page)

**Features:**
- HTTP/HTTPS monitoring
- TCP port monitoring
- Ping monitoring
- Keyword monitoring
- Certificate monitoring
- Multi-notification channels
- Public status page
- Incident management

**Monitored Services:**
```
Frontend Sites
  ├── yourdomain.com
  ├── app.yourdomain.com
  └── admin.yourdomain.com

Backend APIs
  ├── api.yourdomain.com/v1
  ├── api.yourdomain.com/v2
  └── api.yourdomain.com/rag

Support Services
  ├── chat.yourdomain.com
  ├── flow.yourdomain.com
  └── monitor.yourdomain.com
```

**Notifications:**
- Email
- Slack
- Telegram
- Discord
- Webhook

---

### 7.4 Security Operations

#### HashiCorp Vault (Secrets Management)

**Purpose:** Securely store and manage secrets.

**Stored Secrets:**
- Database passwords
- API keys
- SSL certificates
- Service credentials
- OAuth tokens

**Features:**
- Encryption at rest
- Dynamic secrets
- Secret rotation
- Access control
- Audit logging

**Usage:**

```bash
# Store secret
vault kv put secret/database password=supersecret

# Retrieve secret
vault kv get secret/database

# In application
DATABASE_PASSWORD=$(vault kv get -field=password secret/database)
```

#### Authentik (SSO & Identity)

**Purpose:** Single Sign-On and identity provider.

**Access:** `sso.yourdomain.com`

**Features:**
- OAuth2/OIDC provider
- SAML support
- User management
- Multi-factor authentication
- Social logins
- Password policies
- Session management

**Protected Services:**
- Admin dashboard
- Grafana
- Kibana
- Portainer
- n8n

**User Flow:**
```
User → Login to Admin Dashboard
  ↓
Redirect to Authentik
  ↓
Enter credentials + MFA
  ↓
Redirect back with token
  ↓
Access granted
```

#### ClamAV (Antivirus - Optional)

**Purpose:** Scan uploaded files for malware.

**Integration:**
- Parse Server file uploads
- User uploads via API
- Scheduled scans

---

### 7.5 Backup System

#### Automated Backup Service

**Schedule:**
```
Daily:   2:00 AM (7-day retention)
Weekly:  Sunday 3:00 AM (4-week retention)
Monthly: 1st of month 4:00 AM (12-month retention)
```

**Backup Targets:**

1. **Databases**
   ```bash
   # PostgreSQL
   pg_dumpall -U postgres | gzip > postgres.sql.gz
   
   # MongoDB
   mongodump --uri="mongodb://..." --gzip --archive=mongodb.gz
   
   # MySQL
   mysqldump --all-databases | gzip > mysql.sql.gz
   
   # Redis
   redis-cli --rdb /backup/dump.rdb
   ```

2. **Volumes**
   ```bash
   # Application data
   tar -czf volumes.tar.gz /var/lib/docker/volumes/
   ```

3. **Configuration**
   ```bash
   # Nginx configs, .env files, etc.
   tar -czf configs.tar.gz ~/onestack/{nginx,*.env}
   ```

4. **SSL Certificates**
   ```bash
   tar -czf ssl.tar.gz /etc/letsencrypt/
   ```

**Storage Locations:**

1. **Local** (`/backups`)
   - Fast access
   - 7-day retention
   - Quick restore

2. **Remote** (MinIO/S3)
   - Off-server backup
   - 30-day retention
   - Disaster recovery

3. **Archive** (Glacier/Cold Storage)
   - Long-term storage
   - 1-year retention
   - Compliance/audit

**Backup Verification:**
```bash
# Daily verification
1. Calculate SHA256 checksum
2. Test file integrity
3. Log verification status
4. Alert on failure
```

**Restore Process:**

```bash
# Via CLI
./restore.sh /backups/onestack-backup-20251019.tar.gz

# Via Admin UI
admin.domain.com/backups → Select backup → Restore
```

---

## Technology Stack

### Infrastructure
- **Orchestration:** Docker Compose (Kubernetes-ready)
- **Gateway:** Nginx
- **SSL:** Certbot (Let's Encrypt)
- **OS:** Ubuntu 22.04 LTS (recommended)

### Backend
- **Parse Server:** Node.js (Backend-as-a-Service)
- **APIs:** Node.js (Express/Fastify/NestJS), Python (FastAPI)
- **Languages:** JavaScript/TypeScript, Python

### AI/ML
- **LLM Runtime:** Ollama
- **RAG Framework:** LangChain / LlamaIndex
- **Vector DBs:** ChromaDB, Qdrant, Weaviate, Milvus
- **Embeddings:** sentence-transformers, OpenAI

### Databases
- **Relational:** PostgreSQL 16 (with pgvector)
- **Document:** MongoDB 7
- **Key-Value:** Redis (Alpine)
- **Search:** Elasticsearch 8.11
- **Time-Series:** InfluxDB 2.7 (optional)
- **Object Storage:** MinIO

### Customer Support
- **Chat Platform:** Chatwoot
- **Automation:** n8n

### Monitoring
- **Metrics:** Prometheus
- **Visualization:** Grafana
- **Logs:** Loki + Promtail (or ELK)
- **Uptime:** Uptime Kuma

### Security
- **WAF:** ModSecurity
- **IPS:** Fail2Ban
- **SSO:** Authentik
- **Secrets:** HashiCorp Vault
- **Antivirus:** ClamAV (optional)

### Admin
- **Dashboard:** React/Vue + Node.js (custom-built)
- **DB Admin:** Adminer, Mongo Express, Redis Commander
- **Container:** Portainer

---

## System Requirements

### Minimum Configuration (Development/Testing)

```
CPU:     4 cores
RAM:     8GB
Storage: 100GB SSD
Network: 10 Mbps
OS:      Ubuntu 22.04 LTS

Suitable for:
- Development
- Testing
- < 100 users
- Basic features only
```

### Recommended Configuration (Small Production)

```
CPU:     8 cores
RAM:     16GB
Storage: 200GB NVMe SSD
Network: 100 Mbps
OS:      Ubuntu 22.04 LTS

Suitable for:
- Small production
- < 5,000 users
- All features
- Light AI workloads
```

### Production Configuration (Medium Business)

```
CPU:     16 cores
RAM:     32GB
Storage: 500GB NVMe SSD
Network: 1 Gbps
OS:      Ubuntu 22.04 LTS

Suitable for:
- Medium production
- < 50,000 users
- All features + AI
- Multiple services
```

### Enterprise Configuration (Large Scale)

```
CPU:     32+ cores
RAM:     64GB+
Storage: 1TB+ NVMe SSD
Network: 10 Gbps
OS:      Ubuntu 22.04 LTS

Suitable for:
- Large production
- 100,000+ users
- Heavy AI workloads
- Multiple replicas
```

### Special Considerations

**For AI/ML workloads:**
- Add GPU (NVIDIA) for:
  - Faster LLM inference
  - Large model training
  - Real-time processing
- Recommended: NVIDIA T4 or better

**For High Availability:**
- Multi-server setup
- Load balancer
- Database replication
- Shared storage (NFS/Ceph)

---

## Directory Structure

```
onestack/
│
├── 📄 Core Configuration
│   ├── docker-compose.yml              # Main orchestration
│   ├── docker-compose.prod.yml         # Production overrides
│   ├── docker-compose.dev.yml          # Development overrides
│   ├── .env.global                     # Global environment variables
│   ├── .env.example                    # Example configuration
│   ├── README.md                       # Project overview
│   ├── ARCHITECTURE.md                 # This file
│   ├── CONTRIBUTING.md                 # Contribution guide
│   └── LICENSE                         # Open-source license
│
├── 📜 Management Scripts
│   ├── install.sh                      # Interactive installer
│   ├── uninstall.sh                    # Complete removal
│   ├── manage.sh                       # Add/remove components
│   ├── update.sh                       # Update services
│   ├── backup.sh                       # Create backup
│   ├── restore.sh                      # Restore from backup
│   ├── health-check.sh                 # System health
│   ├── add-domain.sh                   # Add new domain
│   ├── ssl-setup.sh                    # Setup SSL
│   └── deploy-frontend.sh              # Deploy frontend build
│
├── 🌐 Nginx (Gateway & Proxy)
│   ├── nginx.conf                      # Main Nginx config
│   ├── conf.d/                         # Site configurations
│   │   ├── 00-default.conf
│   │   ├── api.conf
│   │   ├── admin.conf
│   │   ├── chat.conf
│   │   ├── ai.conf
│   │   ├── monitor.conf
│   │   └── frontends.conf
│   │
│   ├── security/                       # Security configs
│   │   ├── modsecurity.conf
│   │   ├── rate-limit.conf
│   │   ├── ssl-params.conf
│   │   └── security-headers.conf
│   │
│   ├── includes/                       # Reusable configs
│   │   ├── proxy-params.conf
│   │   └── spa-routing.conf
│   │
│   └── ssl/                            # SSL certificates
│       ├── certbot/
│       │   ├── www/
│       │   └── conf/
│       └── custom/
│           ├── domain1.crt
│           └── domain1.key
│
├── 🎨 Frontends (Static Sites)
│   ├── main/                           # yourdomain.com
│   │   ├── dist/
│   │   └── README.md
│   │
│   ├── app/                            # app.yourdomain.com
│   │   ├── build/
│   │   └── README.md
│   │
│   ├── admin-dashboard/                # admin.yourdomain.com
│   │   ├── frontend/
│   │   │   ├── src/
│   │   │   │   ├── pages/
│   │   │   │   │   ├── Dashboard.jsx
│   │   │   │   │   ├── Services.jsx
│   │   │   │   │   ├── Databases.jsx
│   │   │   │   │   ├── Users.jsx
│   │   │   │   │   ├── DomainManager.jsx
│   │   │   │   │   ├── SSLManager.jsx
│   │   │   │   │   ├── Security.jsx
│   │   │   │   │   ├── Backups.jsx
│   │   │   │   │   ├── Monitoring.jsx
│   │   │   │   │   ├── Logs.jsx
│   │   │   │   │   ├── Settings.jsx
│   │   │   │   │   └── Deployment.jsx
│   │   │   │   └── components/
│   │   │   └── dist/
│   │   │
│   │   └── backend/                    # Admin API
│   │       ├── src/
│   │       │   ├── routes/
│   │       │   │   ├── domains.js
│   │       │   │   ├── ssl.js
│   │       │   │   ├── services.js
│   │       │   │   ├── databases.js
│   │       │   │   └── docker.js
│   │       │   ├── controllers/
│   │       │   └── utils/
│   │       │       ├── domain-manager.js
│   │       │       ├── ssl-manager.js
│   │       │       └── docker-api.js
│   │       └── Dockerfile
│   │
│   ├── docs/                           # docs.yourdomain.com
│   └── _templates/                     # Starter templates
│       ├── react-spa/
│       ├── vue-spa/
│       └── static-html/
│
├── 🚀 Backends (API Services)
│   ├── parse-server/
│   │   ├── cloud/
│   │   │   ├── main.js
│   │   │   └── triggers.js
│   │   └── config.json
│   │
│   ├── python-rag/                     # Python RAG System
│   │   ├── app/
│   │   │   ├── main.py
│   │   │   ├── routers/
│   │   │   │   ├── rag.py
│   │   │   │   └── ai.py
│   │   │   ├── services/
│   │   │   │   ├── llm.py
│   │   │   │   ├── vectordb.py
│   │   │   │   └── embedding.py
│   │   │   ├── models/
│   │   │   └── utils/
│   │   ├── tests/
│   │   ├── requirements.txt
│   │   └── Dockerfile
│   │
│   ├── nodejs-api-v1/                  # Node.js API v1
│   │   ├── src/
│   │   │   ├── routes/
│   │   │   ├── controllers/
│   │   │   ├── models/
│   │   │   ├── middleware/
│   │   │   └── utils/
│   │   ├── tests/
│   │   ├── package.json
│   │   └── Dockerfile
│   │
│   ├── nodejs-api-v2/                  # Node.js API v2
│   └── custom-services/                # Add your services
│
├── 💬 Customer Support
│   └── chatwoot/
│       └── .env                        # Chatwoot config
│
├── 🤖 Automation
│   └── n8n/
│       └── workflows/                  # n8n workflows
│           ├── chatwoot-to-rag.json
│           └── backup-automation.json
│
├── 🗄️ Databases (Configurations)
│   ├── postgres/
│   │   ├── init/
│   │   │   ├── 01-create-dbs.sql
│   │   │   └── 02-create-users.sql
│   │   └── pg_hba.conf
│   │
│   ├── mongodb/
│   │   ├── init/
│   │   │   └── init-mongo.js
│   │   └── mongod.conf
│   │
│   ├── mysql/
│   │   ├── init/
│   │   │   └── init-mysql.sql
│   │   └── my.cnf
│   │
│   ├── redis/
│   │   └── redis.conf
│   │
│   └── vector-dbs/
│       ├── chromadb/
│       ├── qdrant/
│       └── weaviate/
│
├── 🛡️ Security
│   ├── fail2ban/
│   │   ├── jail.local
│   │   └── filter.d/
│   │
│   ├── modsecurity/
│   │   ├── modsecurity.conf
│   │   └── crs/                        # OWASP rules
│   │
│   ├── vault/
│   │   ├── config.hcl
│   │   └── policies/
│   │
│   ├── clamav/
│   │   └── clamd.conf
│   │
│   └── authentik/
│       └── config.yml
│
├── 💾 Backups
│   ├── scripts/
│   │   ├── backup-databases.sh
│   │   ├── backup-volumes.sh
│   │   ├── backup-configs.sh
│   │   └── verify-backup.sh
│   │
│   ├── schedule/
│   │   └── crontab
│   │
│   ├── retention/
│   │   └── policy.yml
│   │
│   └── storage/
│       ├── local/                      # Local backups
│       └── remote/                     # Remote backups
│
├── 📊 Monitoring
│   ├── prometheus/
│   │   ├── prometheus.yml
│   │   ├── rules/
│   │   │   ├── alerts.yml
│   │   │   └── recording-rules.yml
│   │   └── targets/
│   │
│   ├── grafana/
│   │   ├── provisioning/
│   │   │   ├── datasources/
│   │   │   │   ├── prometheus.yml
│   │   │   │   ├── loki.yml
│   │   │   │   └── elasticsearch.yml
│   │   │   └── dashboards/
│   │   │       ├── dashboard.yml
│   │   │       └── dashboards/
│   │   │           ├── system.json
│   │   │           ├── containers.json
│   │   │           ├── nginx.json
│   │   │           └── application.json
│   │   └── grafana.ini
│   │
│   ├── loki/
│   │   └── loki-config.yml
│   │
│   ├── promtail/
│   │   └── promtail-config.yml
│   │
│   ├── elasticsearch/
│   │   └── elasticsearch.yml
│   │
│   ├── logstash/
│   │   └── logstash.conf
│   │
│   ├── kibana/
│   │   └── kibana.yml
│   │
│   └── uptime-kuma/
│       └── config/
│
├── 🧪 Testing
│   ├── unit/
│   │   ├── jest.config.js
│   │   └── tests/
│   │
│   ├── integration/
│   │   ├── supertest/
│   │   └── postman/
│   │
│   ├── e2e/
│   │   ├── cypress/
│   │   └── playwright/
│   │
│   ├── load/
│   │   ├── k6/
│   │   └── artillery/
│   │
│   └── quality/
│       ├── sonarqube/
│       └── eslint/
│
├── 🔄 CI/CD
│   ├── .gitlab-ci.yml
│   ├── .github/
│   │   └── workflows/
│   │       ├── deploy.yml
│   │       ├── test.yml
│   │       └── security-scan.yml
│   │
│   └── jenkins/
│       └── Jenkinsfile
│
├── 📚 Documentation
│   ├── architecture/
│   │   ├── overview.md
│   │   ├── security.md
│   │   └── disaster-recovery.md
│   │
│   ├── api/
│   │   ├── openapi.yml
│   │   └── postman/
│   │
│   ├── deployment/
│   │   ├── installation.md
│   │   ├── configuration.md
│   │   └── troubleshooting.md
│   │
│   └── operations/
│       ├── backup-restore.md
│       ├── monitoring.md
│       └── scaling.md
│
├── 🔧 Utilities
│   ├── lib/                            # Shared script functions
│   │   ├── ui.sh                       # UI helpers
│   │   ├── docker.sh                   # Docker operations
│   │   ├── nginx.sh                    # Nginx management
│   │   ├── ssl.sh                      # SSL management
│   │   ├── deps.sh                     # Dependency checker
│   │   └── utils.sh                    # General utilities
│   │
│   ├── components/                     # Component installers
│   │   ├── core.sh
│   │   ├── chatwoot.sh
│   │   ├── n8n.sh
│   │   ├── python-rag.sh
│   │   ├── parse.sh
│   │   ├── admin.sh
│   │   ├── monitoring.sh
│   │   └── security.sh
│   │
│   └── templates/                      # Installation templates
│       ├── ai-platform.yaml
│       ├── support-hub.yaml
│       ├── api-platform.yaml
│       └── full-stack.yaml
│
└── 📝 Logs (Runtime)
    ├── nginx/
    ├── applications/
    ├── databases/
    └── security/
```

---

## Installation System

### Overview

OneStack provides a **modular, interactive installer** that allows users to choose exactly what they want to install.

### Installation Modes

#### 1. Interactive Mode (Recommended)

```bash
./install.sh

# User is presented with:
# 1. Component selection menu
# 2. Configuration prompts
# 3. Progress feedback
# 4. Installation summary
```

**Features:**
- Visual component selection
- Real-time validation
- Progress indicators
- Error handling
- Rollback on failure

#### 2. Command-line Mode

```bash
# Full installation
./install.sh --full

# Minimal installation
./install.sh --minimal

# Custom components
./install.sh --core --chatwoot --n8n --python-rag

# From template
./install.sh --template=ai-platform
```

#### 3. Config File Mode

```bash
# Create installation config
cat > install-config.yaml <<EOF
installation:
  type: custom
  components:
    core: true
    chatwoot: true
    n8n: true
    python-rag: true
    monitoring: basic
EOF

# Install from config
./install.sh --config install-config.yaml
```

### Component Groups

#### Core (Always Installed)
```yaml
- Docker & Docker Compose
- Nginx (Reverse Proxy)
- Certbot (SSL)
- PostgreSQL
- MongoDB
- Redis
```

#### Optional Components

**Backend Services:**
```yaml
- Parse Server (Backend-as-a-Service)
- Node.js API Template
- Python FastAPI Template
- GraphQL Server
```

**AI/ML Suite:**
```yaml
- Python RAG System
- Ollama (Local LLM)
- Vector Databases:
  - ChromaDB (default)
  - Qdrant
  - Weaviate
  - Milvus
```

**Customer Support:**
```yaml
- Chatwoot (Multi-channel chat)
- n8n (Workflow automation)
```

**Monitoring:**
```yaml
- Basic: Prometheus + Grafana
- Advanced: + Loki + Promtail
- Full: + ELK Stack + Uptime Kuma
```

**Admin Tools:**
```yaml
- Super Admin Dashboard
- Portainer (Docker UI)
- Database Admin Tools
- All Specialized Tools
```

**Security:**
```yaml
- Basic: Fail2Ban
- Advanced: + ModSecurity WAF
- Enterprise: + Vault + Authentik + ClamAV
```

**Additional Databases:**
```yaml
- MySQL/MariaDB
- Elasticsearch
- InfluxDB
```

**Backup System:**
```yaml
- Automated Backups
- Remote Storage (MinIO/S3)
```

### Installation Templates

#### Template 1: AI Platform
```yaml
name: "AI Platform"
description: "AI/ML focused with RAG and automation"
components:
  - core
  - python-rag
  - ollama
  - chromadb
  - qdrant
  - n8n
  - admin-dashboard
  - monitoring-basic
```

#### Template 2: Customer Support Hub
```yaml
name: "Support Hub"
description: "Complete customer support solution"
components:
  - core
  - chatwoot
  - n8n
  - parse-server
  - admin-dashboard
  - monitoring-basic
```

#### Template 3: API Platform
```yaml
name: "API Platform"
description: "Backend APIs and services"
components:
  - core
  - parse-server
  - nodejs-api
  - admin-dashboard
  - monitoring-basic
```

#### Template 4: Full Stack
```yaml
name: "Complete Platform"
description: "Everything included"
components:
  - all
```

### Installation Flow

```
┌─────────────────────────────────────┐
│ Step 1: System Check                │
│ ✓ Ubuntu version                    │
│ ✓ Available resources               │
│ ✓ Internet connection               │
│ ✓ Docker availability               │
└─────────────────────────────────────┘
         ↓
┌─────────────────────────────────────┐
│ Step 2: Component Selection         │
│ → Interactive menu or flags         │
│ → Dependency checking               │
└─────────────────────────────────────┘
         ↓
┌─────────────────────────────────────┐
│ Step 3: Configuration               │
│ → Domain name (optional)            │
│ → Email for SSL                     │
│ → Generate passwords                │
│ → Resource allocation               │
└─────────────────────────────────────┘
         ↓
┌─────────────────────────────────────┐
│ Step 4: Review & Confirm            │
│ → Show selected components          │
│ → Estimated disk space              │
│ → Estimated RAM usage               │
│ → Time estimate                     │
└─────────────────────────────────────┘
         ↓
┌─────────────────────────────────────┐
│ Step 5: Installation                │
│ → Pull Docker images                │
│ → Create configurations             │
│ → Initialize databases              │
│ → Start services                    │
│ → Configure SSL                     │
│ [████████░░] 80%                    │
└─────────────────────────────────────┘
         ↓
┌─────────────────────────────────────┐
│ Step 6: Post-Install                │
│ → Health checks                     │
│ → Generate credentials file         │
│ → Show access URLs                  │
│ → Next steps guide                  │
└─────────────────────────────────────┘
         ↓
┌─────────────────────────────────────┐
│ 🎉 Installation Complete!           │
│                                     │
│ Access URLs:                        │
│ • Admin: https://admin.domain.com   │
│ • API: https://api.domain.com       │
│                                     │
│ Credentials: ~/.onestack/creds.txt  │
└─────────────────────────────────────┘
```

### State Management

**Installation State File:**
```json
// ~/.onestack/installed.json
{
  "version": "1.0.0",
  "installation_date": "2025-10-19T14:30:00Z",
  "components": {
    "core": {
      "installed": true,
      "version": "latest",
      "services": ["nginx", "postgres", "redis", "mongodb"]
    },
    "chatwoot": {
      "installed": true,
      "version": "3.0.0",
      "url": "https://chat.yourdomain.com"
    },
    "python-rag": {
      "installed": true,
      "version": "custom",
      "url": "https://api.yourdomain.com/rag"
    },
    "n8n": {
      "installed": false
    }
  },
  "domains": {
    "primary": "yourdomain.com",
    "additional": []
  },
  "ssl": {
    "provider": "letsencrypt",
    "auto_renew": true
  }
}
```

### Adding Components Later

```bash
# Interactive
./manage.sh add

# Or specify components
./manage.sh add chatwoot n8n monitoring

# Add from admin UI
admin.yourdomain.com/system → Add Components
```

---

## Uninstall System

### Safety-First Uninstallation

OneStack provides a **safe, multi-confirmation uninstall system** to prevent accidental data loss.

### Uninstall Modes

#### 1. Services Only (Keep Data)
```
Remove:
  ✓ Docker containers
  ✓ Docker images
  ✗ Data volumes (keep)
  ✗ Configs (keep)
```

#### 2. Services + Configs (Keep Data)
```
Remove:
  ✓ Docker containers
  ✓ Docker images
  ✓ Configuration files
  ✗ Data volumes (keep)
```

#### 3. Complete Wipe
```
Remove:
  ✓ Docker containers
  ✓ Docker images
  ✓ Configuration files
  ✓ ALL data volumes
  ✓ Logs
  ? Docker itself (optional)
```

### Safety Features

**Multi-Level Confirmation:**
1. Choose uninstall mode
2. Review what will be deleted
3. Type "CONFIRM" (case-sensitive)
4. Final yes/no confirmation
5. 5-second countdown (Ctrl+C to cancel)

**Automatic Backup Offer:**
```bash
Before deletion:
  "Create backup first? [Y/n]"
  → Backup to /backups/onestack-backup-TIMESTAMP.tar.gz
  → Verify backup integrity
  → Proceed with uninstall
```

**Dry Run Mode:**
```bash
./uninstall.sh --dry-run

# Shows what WOULD be deleted without actually deleting
```

### Uninstall Flow

```bash
./uninstall.sh

╔═══════════════════════════════════════════╗
║  ⚠️  OneStack Uninstaller                 ║
╚═══════════════════════════════════════════╝

Scanning system...
Found components:
  ✓ Core Services
  ✓ Chatwoot
  ✓ Python RAG
  ✓ Admin Dashboard

Data: 12 volumes (45.3 GB)
Images: 15 images (8.2 GB)

Select mode:
  1) Services Only
  2) Services + Configs
  3) Complete Wipe ⚠️
  4) Cancel

Choice [1-4]: 3

⚠️  WARNING: Complete Wipe
This will PERMANENTLY delete:
  • All containers
  • All data (45.3 GB)
  • All configurations

Create backup? [Y/n]: y
Backing up... ████████████ Done!

To confirm, type: CONFIRM
> CONFIRM

Final confirmation [yes/NO]: yes

Starting in 5... 4... 3... 2... 1...

Uninstalling...
████████████████████ 100%

✓ Complete! Freed 54 GB
Backup: /backups/onestack-backup-20251019.tar.gz
```

---

## Domain Management

### Multi-Domain Architecture

OneStack supports **unlimited domains and subdomains**, each with independent SSL certificates.

### Domain Structure

```
Primary Domains (Unlimited):
├── yourdomain.com
├── yourbrand.com
├── yourcustom.io
└── [more...]

Subdomains per Domain (Unlimited):
├── api.{domain}          → Backend APIs
├── app.{domain}          → Customer app
├── admin.{domain}        → Admin dashboard
├── chat.{domain}         → Customer support
├── flow.{domain}         → n8n automation
├── ai.{domain}           → AI services
├── monitor.{domain}      → Grafana
├── logs.{domain}         → Kibana
├── status.{domain}       → Uptime Kuma
├── storage.{domain}      → MinIO
├── docs.{domain}         → Documentation
└── [custom].{domain}     → Any service
```

### Adding a Domain

#### Via Script

```bash
./add-domain.sh newdomain.com

# Script will:
# 1. Verify DNS records
# 2. Create Nginx configuration
# 3. Request SSL certificate
# 4. Test configuration
# 5. Reload Nginx
```

#### Via Admin UI

```
admin.yourdomain.com/domains → [+ Add Domain]

1. Enter domain name
2. Select subdomains to create
3. Choose SSL method (Let's Encrypt / Custom)
4. Review DNS requirements
5. Click "Add Domain"
```

### DNS Configuration

**Required DNS Records:**
```
Type    Name    Value               TTL
────────────────────────────────────────
A       @       159.223.73.110      3600
A       *       159.223.73.110      3600
CNAME   www     @                   3600
```

**Optional (Email):**
```
MX      @       mail.domain.com     3600
TXT     @       "v=spf1 ..."        3600
```

### SSL Certificate Management

#### Let's Encrypt (Automated)

**Single Domain:**
```bash
certbot certonly --nginx -d yourdomain.com -d www.yourdomain.com
```

**Wildcard:**
```bash
certbot certonly --dns-cloudflare \
  -d "*.yourdomain.com" \
  -d "yourdomain.com"
```

**Auto-Renewal:**
```bash
# Cron job (runs twice daily)
0 */12 * * * certbot renew --quiet
```

#### Custom Certificates

**Upload via Admin UI:**
```
admin.domain.com/ssl → Upload Certificate

Files required:
  - certificate.crt (public certificate)
  - private.key (private key)
  - ca_bundle.crt (optional, CA bundle)
```

**Manual Installation:**
```bash
# Copy files
cp certificate.crt /etc/nginx/ssl/custom/domain.crt
cp private.key /etc/nginx/ssl/custom/domain.key

# Update Nginx config
nano /etc/nginx/conf.d/domain.conf

# Test and reload
nginx -t && nginx -s reload
```

---

## Security Architecture

### Defense in Depth

OneStack implements **multiple layers of security** to protect against various threats.

### Security Layers

```
1. Network Layer
   ├── Firewall (UFW)
   ├── DDoS mitigation
   └── Geographic restrictions

2. Application Layer
   ├── WAF (ModSecurity)
   ├── Rate limiting
   └── Input validation

3. Authentication Layer
   ├── SSO (Authentik)
   ├── MFA
   └── Password policies

4. Data Layer
   ├── Encryption at rest
   ├── Encryption in transit
   └── Backup encryption

5. Monitoring Layer
   ├── Security logs
   ├── Intrusion detection
   └── Audit trails
```

### Firewall Configuration

**Default Rules (UFW):**
```bash
# Allow essential ports
ufw allow 22/tcp      # SSH
ufw allow 80/tcp      # HTTP
ufw allow 443/tcp     # HTTPS

# Deny all other incoming
ufw default deny incoming

# Allow all outgoing
ufw default allow outgoing

# Enable firewall
ufw enable
```

### WAF (ModSecurity)

**OWASP Core Rule Set:**
- SQL injection protection
- XSS protection
- CSRF protection
- Path traversal protection
- File upload validation
- Protocol enforcement

**Custom Rules:**
```nginx
# Block suspicious user agents
SecRule REQUEST_HEADERS:User-Agent "badbot" "id:1001,deny,status:403"

# Rate limiting
SecAction "id:1002,phase:1,nolog,pass,initcol:ip=%{REMOTE_ADDR}"
SecRule IP:REQUESTS "@gt 100" "id:1003,deny,status:429"
```

### Fail2Ban Configuration

**Jails:**
```ini
# SSH protection
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
bantime = 3600

# Nginx authentication
[nginx-auth]
enabled = true
filter = nginx-auth
logpath = /var/log/nginx/error.log
maxretry = 3
bantime = 3600

# Nginx limit-req
[nginx-limit-req]
enabled = true
filter = nginx-limit-req
logpath = /var/log/nginx/error.log
maxretry = 10
bantime = 600
```

### SSL/TLS Configuration

**Best Practices:**
```nginx
# Modern configuration
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256';
ssl_prefer_server_ciphers off;

# HSTS
add_header Strict-Transport-Security "max-age=63072000" always;

# OCSP Stapling
ssl_stapling on;
ssl_stapling_verify on;
ssl_trusted_certificate /path/to/ca-bundle.crt;

# Session cache
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 10m;
```

### Security Headers

```nginx
# XSS Protection
add_header X-XSS-Protection "1; mode=block" always;

# Prevent clickjacking
add_header X-Frame-Options "SAMEORIGIN" always;

# MIME type sniffing
add_header X-Content-Type-Options "nosniff" always;

# Referrer policy
add_header Referrer-Policy "strict-origin-when-cross-origin" always;

# Content Security Policy
add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'" always;

# Permissions Policy
add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
```

### Secrets Management

**HashiCorp Vault:**
```bash
# Store secret
vault kv put secret/database/postgres password="supersecret"

# Retrieve in application
DB_PASSWORD=$(vault kv get -field=password secret/database/postgres)
```

**Environment Variables:**
```bash
# Never commit .env files
# Use .env.example as template
# Store real .env securely
# Rotate secrets regularly
```

### Access Control

**Role-Based Access Control (RBAC):**
```
Super Admin:
  ✓ Full system access
  ✓ User management
  ✓ Service control
  ✓ Configuration changes

Admin:
  ✓ Service management
  ✓ View logs
  ✓ Database access (read/write)
  ✗ System configuration

Developer:
  ✓ Deploy applications
  ✓ View logs
  ✓ Database access (read-only)
  ✗ Service control

Viewer:
  ✓ View dashboards
  ✓ View logs (limited)
  ✗ No write access
```

---

## Monitoring & Observability

### Monitoring Stack

OneStack provides **comprehensive observability** across all layers.

### What We Monitor

#### System Metrics
```
- CPU usage (per core, overall)
- RAM usage (used, available, cache)
- Disk usage (per volume)
- Disk I/O (read/write rates)
- Network I/O (bandwidth, packets)
- Load average (1m, 5m, 15m)
- Swap usage
- File descriptors
```

#### Container Metrics
```
- Resource usage per container
- Restart counts
- Health status
- Network usage
- Log output rate
```

#### Application Metrics
```
- Request rates (per endpoint)
- Response times (p50, p95, p99)
- Error rates (per status code)
- Active users
- Database query performance
- Cache hit rates
```

#### Business Metrics
```
- User signups
- API calls by client
- Feature usage
- Revenue metrics (custom)
```

### Grafana Dashboards

#### System Overview
```
Panels:
  - CPU usage (gauge + graph)
  - RAM usage (gauge + graph)
  - Disk usage (gauge + graph)
  - Network traffic (graph)
  - Load average (graph)
  - Uptime
  - Service status (table)
```

#### Container Metrics
```
Panels:
  - Resource usage per container (bar chart)
  - Container status (table)
  - Restart history (graph)
  - Log volume (graph)
```

#### Nginx Performance
```
Panels:
  - Requests per second (graph)
  - Response time distribution (heatmap)
  - Status codes (pie chart)
  - Bandwidth (graph)
  - Active connections (gauge)
  - Top endpoints (table)
```

#### Database Performance
```
Panels:
  - Query performance (graph)
  - Connection pool usage (gauge)
  - Cache hit rate (graph)
  - Slow queries (table)
  - Deadlocks (counter)
```

### Alerting Rules

**Critical Alerts:**
```yaml
- High CPU (> 90% for 5 min)
- High RAM (> 90% for 5 min)
- Disk full (> 90%)
- Service down
- Database connection failed
```

**Warning Alerts:**
```yaml
- Elevated CPU (> 75% for 15 min)
- Elevated RAM (> 75% for 15 min)
- Disk filling (> 80%)
- High error rate (> 5%)
- Slow response time (> 2s p95)
```

**Notification Channels:**
```
- Email (SMTP)
- Slack (webhook)
- Telegram (bot)
- Discord (webhook)
- PagerDuty (API)
- Custom webhook
```

### Log Management

#### Log Sources

```
Application Logs:
  - OneStack services
  - Custom applications
  - Parse Server
  - Python RAG

System Logs:
  - Nginx access/error
  - Database logs
  - Docker logs
  - Systemd logs

Security Logs:
  - Auth logs
  - Fail2Ban logs
  - Firewall logs
  - WAF logs
```

#### Log Levels

```
ERROR   - Critical issues requiring immediate attention
WARN    - Warning conditions that should be reviewed
INFO    - Informational messages about normal operation
DEBUG   - Detailed debugging information
TRACE   - Very detailed tracing information
```

#### Log Retention

```
Hot storage (Loki/Elasticsearch):
  - 7 days (fast access, expensive)

Warm storage (Compressed):
  - 30 days (slower access, cheaper)

Cold storage (Archive):
  - 1 year (slow access, very cheap)
```

---

## Backup & Recovery

### Backup Strategy

OneStack implements **3-2-1 backup strategy**:
- **3** copies of data
- **2** different media types
- **1** copy offsite

### Automated Backup Schedule

```
Daily Backups:
  - Time: 2:00 AM local time
  - Retention: 7 days
  - Storage: Local + Remote

Weekly Backups:
  - Time: Sunday 3:00 AM
  - Retention: 4 weeks
  - Storage: Remote + Archive

Monthly Backups:
  - Time: 1st of month, 4:00 AM
  - Retention: 12 months
  - Storage: Archive (cold storage)
```

### What Gets Backed Up

#### Databases
```bash
# PostgreSQL (all databases)
pg_dumpall -U postgres | gzip > postgres_$(date +%Y%m%d).sql.gz

# MongoDB (all databases)
mongodump --uri="mongodb://..." --gzip --archive=mongodb_$(date +%Y%m%d).gz

# MySQL (all databases)
mysqldump --all-databases | gzip > mysql_$(date +%Y%m%d).sql.gz

# Redis
redis-cli --rdb dump_$(date +%Y%m%d).rdb
```

#### Docker Volumes
```bash
# All application data
docker run --rm \
  -v postgres_data:/data \
  -v $(pwd):/backup \
  ubuntu tar czf /backup/postgres_data.tar.gz /data
```

#### Configuration Files
```bash
# Nginx, .env files, docker-compose
tar czf configs_$(date +%Y%m%d).tar.gz \
  ~/onestack/nginx \
  ~/onestack/.env* \
  ~/onestack/docker-compose*.yml
```

#### SSL Certificates
```bash
tar czf ssl_$(date +%Y%m%d).tar.gz /etc/letsencrypt
```

### Backup Storage Locations

#### Local Storage
```
Path: /backups
Retention: 7 days
Use: Quick recovery
Size: Depends on data
```

#### Remote Storage (MinIO/S3)
```
Path: s3://onestack-backups/
Retention: 30 days
Use: Disaster recovery
Encryption: AES-256
```

#### Archive Storage (Glacier)
```
Path: glacier://onestack-archive/
Retention: 1 year
Use: Compliance, long-term
Cost: Very low (cold storage)
```

### Backup Verification

```bash
# Daily verification process
1. Calculate SHA256 checksum
2. Verify archive integrity (test extraction)
3. Check backup size (reasonable?)
4. Log verification result
5. Alert if verification fails
```

### Restore Process

#### Full System Restore

```bash
./restore.sh /backups/onestack-full-20251019.tar.gz

# Script will:
# 1. Stop all services
# 2. Extract backup
# 3. Restore databases
# 4. Restore volumes
# 5. Restore configurations
# 6. Start services
# 7. Verify health
```

#### Selective Restore

```bash
# Restore only database
./restore.sh --database=postgres /backups/postgres_20251019.sql.gz

# Restore specific volume
./restore.sh --volume=chatwoot_storage /backups/chatwoot_data.tar.gz

# Restore configurations
./restore.sh --configs /backups/configs_20251019.tar.gz
```

#### Point-in-Time Recovery

```bash
# For PostgreSQL
1. Restore base backup
2. Apply WAL logs up to desired point
3. Recover to timestamp

# Via admin UI
admin.domain.com/backups → Select backup → PITR → Choose timestamp
```

### Disaster Recovery Plan

**Scenarios:**

**1. Single Service Failure**
```
Time to Recovery: 5-10 minutes
Action: Restart failed service
Data Loss: None
```

**2. Database Corruption**
```
Time to Recovery: 15-30 minutes
Action: Restore from last backup
Data Loss: Max 24 hours (daily backup)
```

**3. Complete Server Failure**
```
Time to Recovery: 2-4 hours
Action: 
  1. Provision new server
  2. Install OneStack
  3. Restore from remote backup
Data Loss: Max 24 hours
```

**4. Regional Disaster**
```
Time to Recovery: 4-8 hours
Action:
  1. Provision server in different region
  2. Install OneStack
  3. Restore from offsite backup
Data Loss: Max 24-48 hours
```

---

## Scalability

### Scaling Strategies

OneStack supports **vertical and horizontal scaling** as your needs grow.

### Phase 1: Single Server (Start Here)

```
Server: 8-16GB RAM, 4-8 CPU
Users: Up to 5,000
Cost: $48-96/month

All services on one server
Docker Compose orchestration
Suitable for: Most SMEs
```

### Phase 2: Separated Services

```
Server 1: Frontend + Nginx (4GB RAM)
Server 2: Backend + APIs (8GB RAM)
Server 3: Databases (16GB RAM)
Server 4: AI/ML (16GB RAM + GPU)

Users: Up to 50,000
Cost: $200-400/month

Services on dedicated servers
Still Docker Compose
Suitable for: Growing businesses
```

### Phase 3: Load Balanced

```
Load Balancer (Nginx/HAProxy)
├── Frontend Servers (2-4 instances)
├── Backend Servers (2-4 instances)
├── Database Cluster (Primary + Replicas)
└── Shared Storage (NFS/Ceph)

Users: Up to 500,000
Cost: $500-1000/month

High availability
Auto-failover
Suitable for: Larger enterprises
```

### Phase 4: Kubernetes

```
Kubernetes Cluster
├── Multiple nodes
├── Auto-scaling
├── Rolling updates
├── Advanced networking (Service Mesh)
└── Multi-region (optional)

Users: Millions
Cost: $1000+/month

Enterprise-grade
Global scale
Suitable for: Large scale operations
```

### Database Scaling

**PostgreSQL:**
```
1. Vertical: Increase resources
2. Read replicas: Scale reads
3. Connection pooling (PgBouncer)
4. Partitioning: Split large tables
5. Sharding: Split across servers
```

**MongoDB:**
```
1. Vertical: Increase resources
2. Replica set: High availability
3. Sharding: Horizontal scaling
4. Read preference: Route to secondaries
```

**Redis:**
```
1. Vertical: Increase RAM
2. Redis Cluster: Distributed
3. Read replicas: Scale reads
4. Separate by use case (cache, session, queue)
```

### Application Scaling

**Stateless Services:**
```
Easy to scale horizontally
Just add more containers
Use load balancer to distribute
```

**Stateful Services:**
```
Use shared storage (NFS, S3)
Or sticky sessions
Or externalize state (Redis, Database)
```

### Performance Optimization

**Caching:**
```
1. CDN (Cloudflare) for static assets
2. Redis for application cache
3. Nginx for response caching
4. Database query caching
```

**Database Optimization:**
```
1. Proper indexing
2. Query optimization
3. Connection pooling
4. Regular VACUUM (PostgreSQL)
```

**Code Optimization:**
```
1. Async operations
2. Batch processing
3. Lazy loading
4. Code profiling
```

---

## Use Cases

### 1. E-Commerce Platform

**Stack:**
```
Frontend: React (product catalog, checkout)
Backend: Parse Server (user auth, orders)
APIs: Node.js (payment, inventory)
AI: Product recommendations
Support: Chatwoot (customer service)
```

**Benefits:**
- Complete solution in one platform
- Customer support integrated
- AI-powered recommendations
- Own all customer data

### 2. SaaS Application

**Stack:**
```
Frontend: Vue.js (web app)
Backend: Parse Server (user management)
APIs: Node.js (business logic)
Database: PostgreSQL (relational data)
Monitoring: Full observability
```

**Benefits:**
- Backend-as-a-Service accelerates development
- Easy user management
- Built-in monitoring
- Cost-effective scaling

### 3. Content Platform

**Stack:**
```
Frontend: Multiple sites (Hugo/Next.js)
Backend: Node.js (CMS API)
Search: Elasticsearch
Storage: MinIO (media files)
AI: Content recommendations
```

**Benefits:**
- Host unlimited content sites
- Advanced search
- Media management
- AI-powered discovery

### 4. AI-First Product

**Stack:**
```
Frontend: Simple React UI
Backend: Python FastAPI
AI: Ollama + RAG + Multiple models
Vector DB: Qdrant
Queue: Redis (job processing)
```

**Benefits:**
- Local LLM (no API costs)
- Full AI stack included
- Vector search built-in
- Scale to millions of queries

### 5. Agency (Multi-Client)

**Stack:**
```
Client 1: Full stack
Client 2: Frontend + API only
Client 3: AI service only
Shared: Monitoring, backup

Each client isolated in separate setup
```

**Benefits:**
- One platform, multiple clients
- Isolated environments
- Centralized management
- Predictable costs

---

## Comparison

### vs. Individual SaaS Services

```
┌────────────────────────────────────────────────┐
│ Service          │ SaaS Cost    │ OneStack     │
├────────────────────────────────────────────────┤
│ Hosting          │ $20-50/mo    │ ✓ Included   │
│ Backend (Parse)  │ $30-100/mo   │ ✓ Included   │
│ Chat Support     │ $19-99/mo    │ ✓ Included   │
│ Automation       │ $20-50/mo    │ ✓ Included   │
│ Monitoring       │ $20-50/mo    │ ✓ Included   │
│ AI/LLM          │ $50-200/mo   │ ✓ Included   │
│ Databases        │ $30-100/mo   │ ✓ Included   │
├────────────────────────────────────────────────┤
│ Total            │ $189-649/mo  │ $48-96/mo    │
│ Annual Savings   │ -            │ $1,692-6,636 │
└────────────────────────────────────────────────┘
```

### vs. AWS/Cloud Native

```
AWS Typical Stack:
  - EC2 (servers)
  - RDS (database)
  - ElastiCache (Redis)
  - S3 (storage)
  - CloudWatch (monitoring)
  - Load Balancer
  - WAF
  - Certificate Manager
  
Cost: $500-2,000/month
Complexity: High (many services to manage)

OneStack:
  - Single platform
  - All included
  - Simple management
  
Cost: $48-200/month
Complexity: Low (unified interface)

Savings: $452-1,800/month ($5,424-21,600/year)
```

### vs. Building from Scratch

```
Build Yourself:
  Time: 3-6 months
  Developer Cost: $30,000-100,000
  Ongoing Maintenance: Significant
  Expertise Required: Full-stack + DevOps
  
OneStack:
  Time: 15-20 minutes installation
  Cost: FREE (open-source)
  Maintenance: Minimal (updates via script)
  Expertise: Basic sysadmin
  
Savings: $30,000-100,000 + 3-6 months
```

---

## Roadmap

### Current: v1.0 (Foundation)

**Status:** Architecture Design Phase

**Goals:**
- ✅ Complete architecture design
- ✅ Component selection
- ⏳ Core installation scripts
- ⏳ Admin dashboard (basic)
- ⏳ Documentation

**Timeline:** Q4 2025

### Next: v1.1 (Enhancement)

**Goals:**
- One-click installation templates
- Enhanced admin dashboard
- More pre-built workflows
- Improved monitoring
- Performance optimization

**Timeline:** Q1 2026

### v1.2 (Expansion)

**Goals:**
- Marketplace (community plugins)
- More AI models support
- Advanced automation
- Mobile admin app
- Multi-language support

**Timeline:** Q2 2026

### v2.0 (Scale)

**Goals:**
- Kubernetes support
- Multi-region deployment
- Advanced HA features
- Enterprise SSO integrations
- White-label option

**Timeline:** Q3-Q4 2026

### Future (Community-Driven)

**Potential Features:**
- Visual workflow builder (low-code)
- Integrated IDE
- App marketplace
- Team collaboration features
- Advanced analytics

---

## Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

**Ways to contribute:**
- Report bugs
- Suggest features
- Improve documentation
- Submit pull requests
- Create tutorials
- Share your use case

---

## Support

**Documentation:**
- Architecture: This file
- Installation: [docs/installation.md](docs/installation.md)
- API Reference: [docs/api/](docs/api/)
- Troubleshooting: [docs/troubleshooting.md](docs/troubleshooting.md)

**Community:**
- GitHub Discussions
- Discord Server
- Stack Overflow Tag: [onestack]

**Commercial Support:**
- Email: support@onestack.io
- Consulting available
- Custom development
- Training sessions

---

## License

OneStack is open-source software licensed under [LICENSE_TBD].

---

## Acknowledgments

OneStack is built on top of amazing open-source projects:
- Docker
- Nginx
- PostgreSQL
- MongoDB
- Redis
- Parse Server
- Chatwoot
- n8n
- Ollama
- Grafana
- Prometheus
- And many more...

Thank you to all the maintainers and contributors of these projects!

---

**OneStack** - *One Stack. Everything.*

Last Updated: 2025-10-19
Version: 1.0.0-alpha