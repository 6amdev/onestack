# OneStack - Quick Start Guide

## 🚀 Installation in 3 Steps

### Step 1: Choose Configuration

Pick one based on what you have:

#### Option A: Have a Domain (Recommended)
```bash
# 1. Setup DNS first
#    Add A record: yourdomain.com → your_server_ip
#    Add A record: *.yourdomain.com → your_server_ip

# 2. Create config
cp config.domain.example.yml config.yml

# 3. Edit domain
nano config.yml
# Change: primary: onestack.6amdev.com
# To:     primary: yourdomain.com
```

#### Option B: Don't Have Domain (Testing)
```bash
# 1. Get your server IP
curl ifconfig.me

# 2. Create config
cp config.ip.example.yml config.yml

# 3. Edit IP
nano config.yml
# Change: primary: 159.223.73.110
# To:     primary: YOUR_SERVER_IP
```

#### Option C: Local Testing
```bash
# Use localhost
cp config.example.yml config.yml

nano config.yml
# Change: primary: yourdomain.com
# To:     primary: localhost
```

---

### Step 2: Install
```bash
# Run installer
sudo bash install.sh
```

**Installation time:** 15-25 minutes

**What happens:**
1. System preparation (update, install tools)
2. Create users (admin + onestack)
3. Install Docker
4. Setup security (firewall, SSH, Fail2Ban)
5. Deploy services (PostgreSQL, MongoDB, Redis, MinIO, Nginx, etc.)
6. Create welcome page

---

### Step 3: Access

#### If using Domain:
```
Main Site:    http://yourdomain.com
MinIO:        http://storage.yourdomain.com
Parse:        http://api.yourdomain.com
Grafana:      http://monitor.yourdomain.com
Adminer:      http://db.yourdomain.com
```

#### If using IP:
```
Main Site:    http://YOUR_IP
MinIO:        http://YOUR_IP:9001
Parse:        http://YOUR_IP:4040
Grafana:      http://YOUR_IP:3001
Adminer:      http://YOUR_IP:8080
```

#### View Credentials:
```bash
cat /opt/onestack/.credentials
```

---

## 🧪 Testing
```bash
# Check services
sudo bash test-install.sh

# Check specific service
cd /opt/onestack
docker compose ps
docker compose logs -f nginx
```

---

## 🗑️ Uninstall
```bash
# Preview what will be removed
sudo bash uninstall.sh --dry-run

# Remove (with backup)
sudo bash uninstall.sh
# Choose option 3 (Complete removal)
```

---

## 📚 Need Help?

- Full documentation: `ARCHITECTURE.md`
- Testing guide: `TESTING.md`
- Troubleshooting: `TESTING.md` (Troubleshooting section)

---

## 🎯 What's Next?

After installation:

1. **Setup SSL** (if using domain)
```bash
   sudo bash setup-ssl.sh  # Coming soon
```

2. **Deploy your app**
```bash
   # Copy your frontend build to:
   /opt/onestack/frontends/main/
   
   # Or use deployment script (coming soon)
   sudo bash deploy-frontend.sh ./dist
```

3. **Explore services**
   - Create database via Adminer
   - Setup Parse Server app
   - Create Grafana dashboards
   - Upload files to MinIO

---

## ⚡ Quick Commands
```bash
# View credentials
cat /opt/onestack/.credentials

# Check status
cd /opt/onestack && docker compose ps

# View logs
cd /opt/onestack && docker compose logs -f

# Restart service
cd /opt/onestack && docker compose restart nginx

# Stop all
cd /opt/onestack && docker compose stop

# Start all
cd /opt/onestack && docker compose start
```