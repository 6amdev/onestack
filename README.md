# OneStack 🚀

[English](#english) | [ภาษาไทย](#thai)

<div align="center">
  <img src="https://img.shields.io/badge/version-1.0.0-blue.svg" alt="Version">
  <img src="https://img.shields.io/badge/license-MIT-green.svg" alt="License">
  <img src="https://img.shields.io/badge/docker-ready-brightgreen.svg" alt="Docker">
  <img src="https://img.shields.io/badge/parse-6.4.0-orange.svg" alt="Parse Server">
</div>

<div align="center">
  <h3>Production-Ready Parse Platform with One-Click Deployment</h3>
  <p>Deploy your complete backend infrastructure in under 5 minutes</p>
</div>

---

<a name="english"></a>

## 🌐 English

### 📋 Table of Contents
- [Features](#features)
- [Quick Start](#quick-start)
- [Architecture](#architecture)
- [Documentation](#documentation)
- [API Usage](#api-usage)
- [Management](#management)
- [Security](#security)
- [Contributing](#contributing)
- [Support](#support)

### ✨ Features

#### Core Services
- **Parse Server 6.4.0** - Scalable REST & GraphQL API
- **Parse Dashboard** - Visual data management interface  
- **MongoDB 7.0** - Primary database with authentication
- **Redis 7** - High-performance caching & session management
- **Nginx** - Reverse proxy with SSL/TLS support

#### Security & Performance
- 🔒 **Secure by Default** - No exposed databases, auto-generated passwords
- 🌐 **Multi-Domain Support** - Host multiple apps with single backend
- 📱 **Mobile Ready** - Full support for iOS, Android, Flutter
- ⚡ **Auto-Scaling Ready** - Horizontal scaling capability
- 🔄 **Live Queries** - Real-time data synchronization
- 📊 **Built-in Monitoring** - Health checks and metrics

#### Developer Experience
- 🎯 **5-Minute Setup** - From zero to production
- 🔧 **Modular Architecture** - Add/remove services easily
- 📦 **Docker Native** - Consistent environments everywhere
- 🔄 **Hot Reload** - Development with live updates
- 📚 **Extensive Documentation** - Clear guides and examples

### 🚀 Quick Start

#### Prerequisites
- Ubuntu 20.04+ / Debian 11+ / CentOS 8+
- 2GB RAM minimum (4GB recommended)
- 20GB available storage
- Port 80, 443 available

#### Installation
```bash

1. Clone repository
git clone https://github.com/yourusername/onestack.git
cd onestack2. Run installer
chmod +x install.sh
./install.sh3. Access your services
API: http://your-server-ip/parse
Dashboard: http://your-server-ip/dashboard

That's it! Your backend is ready. 🎉

### 🏗️ Architecture┌─────────────────┐
│         External Clients            │
│   (Web, Mobile, IoT, Postman)       │
└──────────────┬──────────────────────┘
│ HTTPS/WSS
┌──────────────▼──────────────────────┐
│      Nginx (Reverse Proxy)          │
│   • SSL Termination                 │
│   • Load Balancing                  │
│   • Rate Limiting                   │
└──────────────┬──────────────────────┘
│ Internal Network
┌──────────────▼──────────────────────┐
│        Parse Platform               │
├─────────────────────────────────────┤
│  Parse Server │ Dashboard │ Custom  │
│  • REST API   │ • Admin UI│ Services│
│  • GraphQL    │ • Analytics│        │
│  • Live Query │           │         │
└──────────────┬──────────────────────┘
│ Isolated Network
┌──────────────▼──────────────────────┐
│         Data Layer                  │
├─────────────────────────────────────┤
│   MongoDB    │    Redis             │
│  • Database  │  • Cache             │
│  • GridFS    │  • Sessions          │
└─────────────────────────────────────┘