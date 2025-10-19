# 🚀 OneStack Architecture

> **Complete SME Platform - Self-Hosted, Modular, AI-Powered**

[![Version](https://img.shields.io/badge/version-1.0.0--alpha-blue.svg)](https://github.com/yourusername/onestack)
[![License](https://img.shields.io/badge/license-TBD-green.svg)](LICENSE)
[![Status](https://img.shields.io/badge/status-design%20phase-yellow.svg)](https://github.com/yourusername/onestack)

---

## 🎯 What is OneStack?

**OneStack** is a complete, self-hosted business platform that replaces 10+ SaaS subscriptions with a single, unified solution. Perfect for SMEs who want to:

- ✅ **Own their data** - Complete control, no vendor lock-in
- ✅ **Save costs** - $5,000+ per year vs. SaaS alternatives
- ✅ **Scale efficiently** - From startup to enterprise
- ✅ **Build faster** - Everything integrated and ready to use

---

## ⚡ Quick Overview
```
One Platform. Everything You Need.

🎨 Frontend Hosting     → Unlimited websites/apps
🚀 Backend Services     → APIs, BaaS, Custom logic
🤖 AI/ML Built-in      → RAG, LLM, Automation
💬 Customer Support     → Multi-channel chat
🗄️ All Databases       → PostgreSQL, MongoDB, Redis, Vector DBs
🎛️ Admin Dashboard     → Unified management
🛡️ Enterprise Security → WAF, SSL, Firewall, SSO
💾 Auto Backup         → Never lose data
📊 Full Monitoring     → Know everything, always
```

---

## 🌟 Key Features

### All-in-One Platform
- **Frontend Hosting** - Host unlimited React/Vue/Angular apps
- **Backend-as-a-Service** - Parse Server with user auth, database, files
- **Custom APIs** - Node.js and Python API templates
- **AI/ML Stack** - Local LLM (Ollama), RAG system, vector databases
- **Customer Support** - Chatwoot multi-channel chat
- **Workflow Automation** - n8n with 500+ integrations
- **Admin Dashboard** - Unified interface for everything

### Complete Database Suite
- PostgreSQL (with pgvector)
- MongoDB
- Redis
- Elasticsearch
- ChromaDB, Qdrant, Weaviate, Milvus (Vector DBs)
- MinIO (S3-compatible object storage)

### Enterprise-Grade Operations
- SSL certificates (Let's Encrypt + custom)
- Web Application Firewall (ModSecurity)
- Intrusion Prevention (Fail2Ban)
- Single Sign-On (Authentik)
- Secrets Management (Vault)
- Full monitoring (Prometheus + Grafana)
- Centralized logging (Loki/ELK)
- Automated backups with 3-2-1 strategy

---

## 💰 Cost Comparison

| Service | SaaS Cost/mo | OneStack |
|---------|--------------|----------|
| Hosting | $20-50 | ✅ Included |
| Backend (BaaS) | $30-100 | ✅ Included |
| Chat Support | $19-99 | ✅ Included |
| Automation | $20-50 | ✅ Included |
| Monitoring | $20-50 | ✅ Included |
| AI/LLM | $50-200 | ✅ Included |
| Databases | $30-100 | ✅ Included |
| **Total** | **$189-649/mo** | **$48-96/mo** |
| **Annual Savings** | - | **$1,692-6,636** |

---

## 🚀 Quick Start

### System Requirements (Minimum)
```
CPU:     4 cores
RAM:     8GB
Storage: 100GB SSD
OS:      Ubuntu 22.04 LTS
```

### Installation (Coming Soon)
```bash
# Clone the repository
git clone https://github.com/yourusername/onestack.git
cd onestack

# Run interactive installer
./install.sh

# Or use a template
./install.sh --template=ai-platform
```

**Installation time:** 15-20 minutes

---

## 📚 Documentation

- **[Architecture](ARCHITECTURE.md)** - Complete technical documentation
- **[Installation Guide](docs/installation.md)** - Step-by-step setup
- **[API Reference](docs/api/)** - API documentation
- **[Troubleshooting](docs/troubleshooting.md)** - Common issues and solutions

---

## 🏗️ Architecture Overview
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
   │ Frontend │    │ Backend  │    │  Admin   │
   │ Hosting  │    │ Services │    │Dashboard │
   └──────────┘    └────┬─────┘    └──────────┘
                        │
                   ┌────▼────┐
                   │  AI/ML  │
                   │  Stack  │
                   └────┬────┘
                        │
              ┌─────────▼──────────┐
              │   Databases        │
              └─────────┬──────────┘
                        │
              ┌─────────▼──────────┐
              │   Monitoring &     │
              │   Security         │
              └────────────────────┘
```

### 7 Layers Architecture

1. **Gateway** - Nginx, SSL, WAF, Load Balancing
2. **Frontend** - Unlimited websites and applications
3. **Backend** - Parse Server, Node.js APIs, Python services
4. **Admin** - Unified management dashboard
5. **AI/ML** - RAG, Ollama, Vector databases
6. **Data** - All databases you need
7. **Operations** - Monitoring, logging, backups, security

---

## 🎯 Use Cases

### E-Commerce Platform
Frontend + Backend + Payment APIs + AI Recommendations + Customer Support

### SaaS Application
Web App + User Management + Business APIs + Monitoring

### Content Platform
Multiple Sites + CMS + Search + Media Storage + AI Discovery

### AI-First Product
Simple UI + Python APIs + Local LLM + RAG + Vector Search

### Agency (Multi-Client)
Separate environments for each client, centralized management

---

## 🛠️ Technology Stack

### Infrastructure
- **Orchestration:** Docker Compose (Kubernetes-ready)
- **Gateway:** Nginx
- **SSL:** Certbot (Let's Encrypt)

### Backend
- **Parse Server** (Node.js BaaS)
- **APIs:** Node.js, Python (FastAPI)

### AI/ML
- **LLM:** Ollama
- **RAG:** LangChain, LlamaIndex
- **Vector DBs:** ChromaDB, Qdrant, Weaviate, Milvus

### Databases
- PostgreSQL 16 (with pgvector)
- MongoDB 7
- Redis
- Elasticsearch
- InfluxDB (optional)
- MinIO (S3-compatible)

### Operations
- **Monitoring:** Prometheus, Grafana
- **Logging:** Loki, Promtail (or ELK)
- **Security:** ModSecurity, Fail2Ban, Authentik, Vault

---

## 📈 Project Status

**Current:** v1.0.0-alpha (Architecture Design Phase)

**Roadmap:**
- ✅ Architecture design complete
- ⏳ Core installation scripts
- ⏳ Admin dashboard (basic)
- ⏳ Documentation
- 📅 v1.0 Release: Q4 2025

See [ROADMAP.md](docs/roadmap.md) for detailed plans.

---

## 🤝 Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

**Ways to contribute:**
- Report bugs and issues
- Suggest new features
- Improve documentation
- Submit pull requests
- Share your use case

---

## 📞 Support

- **Documentation:** [docs/](docs/)
- **GitHub Discussions:** [Discussions](https://github.com/yourusername/onestack/discussions)
- **Discord:** [Join our community](https://discord.gg/onestack)
- **Email:** support@onestack.io

---

## 📄 License

OneStack is open-source software. License: TBD

---

## 🙏 Acknowledgments

Built on amazing open-source projects:
- Docker, Nginx, PostgreSQL, MongoDB, Redis
- Parse Server, Chatwoot, n8n, Ollama
- Grafana, Prometheus, and many more

Thank you to all maintainers and contributors!

---

## ⭐ Show Your Support

If you find OneStack useful, please consider giving it a star! ⭐

---

**OneStack** - *One Stack. Everything.*

Made with ❤️ for the SME community