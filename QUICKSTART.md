# 🚀 Quick Start: Fix Nginx + SSL

**Domain:** sixamdev.com  
**Server:** 68.183.226.120  
**Date:** 2025-10-20

---

## ⚡ TL;DR (รันได้เลย)

```bash
# 1. SSH to server
ssh root@68.183.226.120

# 2. Download and run fix script
cd /opt/onestack
sudo bash fix-nginx-ssl-complete.sh

# 3. Restart services
./start-services.sh

# 4. Test
./test-nginx.sh

# Done! 🎉
```

---

## 📋 Step-by-Step Guide

### Step 1: Connect to Server
```bash
ssh root@68.183.226.120
# or
ssh admin@68.183.226.120
sudo su -
```

### Step 2: Go to OneStack Directory
```bash
cd /opt/onestack
```

### Step 3: Run Fix Script
```bash
# Option A: If you have the script
sudo bash fix-nginx-ssl-complete.sh

# Option B: Create it first (copy from outputs)
nano fix-nginx-ssl-complete.sh
# Paste content, save (Ctrl+X, Y, Enter)
chmod +x fix-nginx-ssl-complete.sh
sudo bash fix-nginx-ssl-complete.sh
```

**The script will:**
- ✅ Create backup automatically
- ✅ Fix upstream configuration
- ✅ Fix DNS resolver
- ✅ Fix SSL paths
- ✅ Update virtual host configs
- ✅ Create helper scripts

### Step 4: Restart Services (Proper Order)
```bash
# Use the generated script
./start-services.sh

# Or manually:
docker compose down
docker compose up -d postgres mongodb redis
sleep 10
docker compose up -d minio parse-server grafana prometheus adminer
sleep 10
docker compose up -d nginx
```

### Step 5: Verify Everything Works
```bash
# Run test script
./test-nginx.sh

# Check service status
docker compose ps

# View logs (real-time)
docker compose logs -f nginx
```

---

## ✅ What to Check

### 1. All Services Running
```bash
docker compose ps
```
**Expected:** All services should show "Up" or "running"

### 2. No Nginx Errors
```bash
docker compose logs nginx --tail=50
```
**Expected:** No "connection refused" or "no resolver" errors

### 3. HTTP Works
```bash
curl -I http://sixamdev.com
curl -I http://api.sixamdev.com/parse/health
```
**Expected:** HTTP 200 or 301 (redirect to HTTPS)

### 4. SSL Certificates
```bash
ls -la /etc/letsencrypt/live/sixamdev.com/
```
**Expected:** See fullchain.pem and privkey.pem

If no certificates yet:
```bash
sudo bash manage.sh
# Choose option 2 (SSL Setup)
```

---

## 🔧 If Something Goes Wrong

### Problem: Services won't start
```bash
# Check what's wrong
docker compose ps
docker compose logs --tail=100

# Restart specific service
docker compose restart nginx
docker compose restart parse-server
```

### Problem: Nginx config error
```bash
# Test config
docker compose exec nginx nginx -t

# View error
docker compose logs nginx --tail=50

# Rollback if needed
cd /opt/onestack/backups
ls -la  # Find latest backup
# Restore manually
```

### Problem: Can't connect to backend
```bash
# Test from inside nginx container
docker compose exec nginx sh
ping parse-server
wget http://parse-server:1337/parse/health

# Check DNS
docker compose exec nginx nslookup parse-server
```

### Problem: SSL not working
```bash
# Check certificates
ls -la /etc/letsencrypt/live/

# Check symlinks
ls -la /opt/onestack/nginx/ssl/live/sixamdev.com/

# Request new certificates
sudo bash manage.sh
# → Option 2 (SSL Setup)
```

---

## 📊 Success Checklist

After fix, verify:
- [ ] All Docker services show "Up"
- [ ] No errors in `docker compose logs nginx`
- [ ] HTTP sites accessible (http://sixamdev.com)
- [ ] Parse Server health check works (http://api.sixamdev.com/parse/health)
- [ ] Grafana accessible (http://monitor.sixamdev.com)
- [ ] SSL certificates exist (if already requested)
- [ ] Nginx config test passes (`docker compose exec nginx nginx -t`)

---

## 🎯 URLs to Test

### HTTP (Should work immediately)
```
✓ http://sixamdev.com
✓ http://api.sixamdev.com/parse/health
✓ http://monitor.sixamdev.com
✓ http://prometheus.sixamdev.com
✓ http://db.sixamdev.com
✓ http://storage.sixamdev.com
✓ http://s3.sixamdev.com
```

### HTTPS (After SSL setup)
```
✓ https://sixamdev.com
✓ https://api.sixamdev.com/parse/health
✓ https://monitor.sixamdev.com
✓ https://prometheus.sixamdev.com
✓ https://db.sixamdev.com
✓ https://storage.sixamdev.com
✓ https://s3.sixamdev.com
```

---

## 📝 Helper Commands

### View All Logs
```bash
cd /opt/onestack
docker compose logs --tail=100
```

### View Specific Service
```bash
docker compose logs nginx --tail=50 -f
docker compose logs parse-server --tail=50 -f
```

### Restart All Services
```bash
docker compose restart
```

### Restart Specific Service
```bash
docker compose restart nginx
docker compose restart parse-server
```

### Stop All Services
```bash
docker compose down
```

### Check Nginx Config
```bash
docker compose exec nginx nginx -t
```

### Reload Nginx (without restart)
```bash
docker compose exec nginx nginx -s reload
```

### Enter Nginx Container
```bash
docker compose exec nginx sh
```

---

## 🔄 If You Need to Rollback

### Restore from Backup
```bash
cd /opt/onestack

# Find backups
ls -la backups/

# Example: Restore nginx config
cd backups/nginx_20251020_123456
cp -r nginx /opt/onestack/
cd /opt/onestack

# Restart
docker compose restart nginx
```

---

## 💡 Pro Tips

### 1. Use manage.sh for Everything
```bash
sudo bash manage.sh
```
It has menu for:
- View status
- SSL management
- Add domains
- Service control
- System info

### 2. Monitor Logs in Real-time
```bash
# Terminal 1: Nginx
docker compose logs -f nginx

# Terminal 2: All services
docker compose logs -f

# Terminal 3: Commands
# Run your commands here
```

### 3. Test HTTP First, Then SSL
```bash
# Make sure HTTP works
curl http://api.sixamdev.com/parse/health

# Then request SSL
sudo bash manage.sh
# → Option 2 (SSL Setup)

# Then test HTTPS
curl https://api.sixamdev.com/parse/health
```

### 4. Use Helper Scripts
```bash
# Start services
./start-services.sh

# Test everything
./test-nginx.sh

# Troubleshoot
./troubleshoot-nginx.sh
```

---

## 🆘 Get Help

### Check Documentation
```bash
cd /opt/onestack
cat NGINX_SSL_SOLUTION.md  # Full documentation
cat README.md              # Project overview
cat PROJECT_STATUS.md      # Current status
```

### View System Status
```bash
sudo bash manage.sh
# Choose option 1 (Show Status)
```

### Check Firewall
```bash
sudo ufw status
# Should show: 22, 80, 443 allowed
```

### Check DNS
```bash
# From your computer
dig sixamdev.com
dig api.sixamdev.com

# Should point to: 68.183.226.120
```

---

## 📞 Emergency Commands

### Services Won't Start
```bash
docker compose down -v  # ⚠️ This removes volumes!
docker compose up -d
```

### Nginx Broken
```bash
# Stop Nginx
docker compose stop nginx

# Test backends directly
curl http://68.183.226.120:1337/parse/health

# Fix config
nano /opt/onestack/nginx/conf.d/api.sixamdev.com.conf

# Start Nginx
docker compose up -d nginx
```

### Complete Reset (DANGER!)
```bash
# ⚠️⚠️⚠️ This deletes everything! ⚠️⚠️⚠️
cd /opt/onestack
docker compose down -v
rm -rf nginx/conf.d/*
# Then re-run install or restore from backup
```

---

## ✅ Final Verification

Run this to verify everything:
```bash
cd /opt/onestack

echo "1. Docker services:"
docker compose ps

echo ""
echo "2. Nginx config:"
docker compose exec nginx nginx -t

echo ""
echo "3. HTTP test:"
curl -sI http://api.sixamdev.com/parse/health | head -n 1

echo ""
echo "4. SSL certificates:"
ls -la /etc/letsencrypt/live/ | grep sixamdev

echo ""
echo "5. Recent errors (if any):"
docker compose logs nginx --tail=20 | grep -i error || echo "No errors!"

echo ""
echo "✓ Verification complete!"
```

---

## 📚 Related Files

- `NGINX_SSL_SOLUTION.md` - Full technical documentation
- `fix-nginx-ssl-complete.sh` - Main fix script
- `start-services.sh` - Start services in order
- `test-nginx.sh` - Test everything
- `troubleshoot-nginx.sh` - Debug issues
- `manage.sh` - Management console

---

**Made with ❤️ for OneStack**  
**Last Updated:** 2025-10-20
