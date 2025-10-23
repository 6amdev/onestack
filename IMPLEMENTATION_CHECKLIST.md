# 📋 OneStack Nginx + SSL Implementation Checklist

**Domain:** sixamdev.com  
**Server:** 68.183.226.120  
**Date:** 2025-10-20  
**Estimated Time:** 30 minutes

---

## 🎯 Pre-Flight Checklist

### Before You Start:

- [ ] You have SSH access to the server
- [ ] You have sudo/root privileges
- [ ] You know the domain name (sixamdev.com)
- [ ] DNS records point to server IP (68.183.226.120)
- [ ] You have downloaded these files:
  - [ ] fix-nginx-ssl-complete.sh
  - [ ] NGINX_SSL_SOLUTION.md
  - [ ] QUICKSTART.md
  - [ ] PROJECT_STATUS_UPDATED.md

---

## 📦 Step 1: Connect to Server

```bash
# Connect via SSH
ssh root@68.183.226.120

# Or if using admin user:
ssh admin@68.183.226.120
sudo su -
```

**Verify:**
```bash
whoami  # Should show: root
pwd     # Should show: /root or similar
```

- [ ] Connected successfully
- [ ] Have root access

---

## 📁 Step 2: Navigate to OneStack Directory

```bash
cd /opt/onestack
```

**Verify:**
```bash
ls -la
# Should see: docker-compose.yml, .env, nginx/, etc.
```

- [ ] In correct directory
- [ ] Can see docker-compose.yml
- [ ] Can see nginx directory

---

## 💾 Step 3: Upload Fix Script

### Option A: Create File Directly

```bash
nano fix-nginx-ssl-complete.sh
# Paste content from the file
# Press: Ctrl+X, then Y, then Enter

chmod +x fix-nginx-ssl-complete.sh
```

### Option B: Use SCP (from your computer)

```bash
# From your local machine:
scp fix-nginx-ssl-complete.sh root@68.183.226.120:/opt/onestack/

# Then on server:
chmod +x fix-nginx-ssl-complete.sh
```

### Option C: Download from GitHub (if uploaded)

```bash
wget https://raw.githubusercontent.com/YOUR_REPO/fix-nginx-ssl-complete.sh
chmod +x fix-nginx-ssl-complete.sh
```

**Verify:**
```bash
ls -la fix-nginx-ssl-complete.sh
# Should show: -rwxr-xr-x (executable)

head -n 5 fix-nginx-ssl-complete.sh
# Should show the script header
```

- [ ] Script file exists
- [ ] Script is executable
- [ ] Script content looks correct

---

## 🔍 Step 4: Pre-Check Current Status

```bash
# Check services
docker compose ps

# Check nginx logs
docker compose logs nginx --tail=20

# Check SSL certificates
ls -la /etc/letsencrypt/live/ 2>/dev/null || echo "No SSL yet"
```

**Take note of current state:**
- [ ] Services running: _____ / _____
- [ ] Nginx status: ____________
- [ ] SSL certificates: [ ] Yes [ ] No
- [ ] Any critical errors: ____________

---

## 🚀 Step 5: Run Fix Script

```bash
# Make sure you're in /opt/onestack
cd /opt/onestack

# Run the fix script
sudo bash fix-nginx-ssl-complete.sh
```

**Watch for:**
- Backup creation message
- Configuration updates
- Success messages
- Any errors (should be none)

**Expected output:**
```
═══════════════════════════════════════════════
  OneStack Nginx + SSL Fix
═══════════════════════════════════════════════

Domain: sixamdev.com
Install Directory: /opt/onestack

▶ Creating backup...
✓ Nginx config backed up to: /opt/onestack/backups/nginx_TIMESTAMP
✓ docker-compose.yml backed up

═══════════════════════════════════════════════
  Part 1: Upstream Configuration
═══════════════════════════════════════════════
✓ Upstream configuration created

[... more output ...]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ All fixes applied successfully!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Checklist:**
- [ ] Script completed without errors
- [ ] Backup created successfully
- [ ] All configuration files updated
- [ ] Helper scripts created

---

## 🔄 Step 6: Restart Services

### Option A: Use Helper Script (Recommended)

```bash
./start-services.sh
```

### Option B: Manual Restart (Proper Order)

```bash
# Stop all
docker compose down

# Start databases
docker compose up -d postgres mongodb redis
echo "Waiting 10 seconds..."
sleep 10

# Start backends
docker compose up -d minio parse-server grafana prometheus adminer
echo "Waiting 15 seconds..."
sleep 15

# Start Nginx
docker compose up -d nginx
```

**Wait for services to stabilize (1-2 minutes)**

**Verify:**
```bash
docker compose ps
```

**Expected:** All services should show "Up" or "running"

**Checklist:**
- [ ] All services started successfully
- [ ] No services in "Exit" or "Restarting" state
- [ ] Nginx is running
- [ ] Backends are running

---

## ✅ Step 7: Test HTTP (Before SSL)

```bash
# Run test script
./test-nginx.sh
```

**Or manual tests:**
```bash
# Test 1: Nginx config
docker compose exec nginx nginx -t
# Expected: "syntax is ok" and "test is successful"

# Test 2: HTTP main site
curl -I http://sixamdev.com
# Expected: HTTP 200 or 301

# Test 3: Parse Server health
curl -I http://api.sixamdev.com/parse/health
# Expected: HTTP 200

# Test 4: Grafana
curl -I http://monitor.sixamdev.com
# Expected: HTTP 200 or 302

# Test 5: Backend connectivity (from inside nginx)
docker compose exec nginx wget -q -O- http://parse-server:1337/parse/health
# Expected: {"status":"ok"}
```

**Checklist:**
- [ ] Nginx config test passed
- [ ] HTTP main site accessible
- [ ] Parse Server health check works
- [ ] Grafana accessible
- [ ] Backend connectivity works
- [ ] No "connection refused" errors

**If HTTP doesn't work, STOP HERE and troubleshoot:**
```bash
./troubleshoot-nginx.sh
docker compose logs nginx --tail=50
```

---

## 🔐 Step 8: Setup SSL Certificates

### Check If Certificates Already Exist

```bash
ls -la /etc/letsencrypt/live/sixamdev.com/ 2>/dev/null
```

### If NO certificates exist:

```bash
# Use management console
sudo bash manage.sh
```

**In the menu:**
1. Choose option `2` (Setup/Manage SSL Certificates)
2. Choose option `1` (Setup SSL for first time)
3. Confirm when prompted
4. Wait for certificate request to complete

**Expected output:**
```
Requesting certificates for:
  - sixamdev.com
  - *.sixamdev.com (wildcard)
  - www.sixamdev.com

Requesting certificate...
✓ Certificate obtained successfully
✓ Nginx reloaded
```

### If certificates already exist:

```bash
# Just update nginx configs
sudo bash manage.sh
# → Option 2
# → Option 2 (Re-scan and update)
```

**Checklist:**
- [ ] SSL certificates requested successfully
- [ ] Certificates exist in /etc/letsencrypt/live/sixamdev.com/
- [ ] Symlinks created in /opt/onestack/nginx/ssl/
- [ ] Nginx reloaded without errors

---

## 🌐 Step 9: Test HTTPS

```bash
# Test 1: HTTPS main site
curl -I https://sixamdev.com
# Expected: HTTP 200

# Test 2: HTTPS API
curl -I https://api.sixamdev.com/parse/health
# Expected: HTTP 200

# Test 3: HTTPS Grafana
curl -I https://monitor.sixamdev.com
# Expected: HTTP 200 or 302

# Test 4: Certificate info
openssl s_client -connect sixamdev.com:443 -servername sixamdev.com < /dev/null 2>/dev/null | grep -A 2 "Subject:"
# Expected: Should show certificate details

# Test 5: All subdomains
for subdomain in api monitor prometheus db storage s3; do
    echo "Testing ${subdomain}.sixamdev.com..."
    curl -sI https://${subdomain}.sixamdev.com | head -n 1
done
```

**Checklist:**
- [ ] HTTPS main site works
- [ ] HTTPS API works
- [ ] HTTPS Grafana works
- [ ] All subdomains accessible via HTTPS
- [ ] No SSL certificate warnings
- [ ] HTTP redirects to HTTPS (test with browser)

---

## 🔍 Step 10: Final Verification

### Run Complete Test Suite

```bash
./test-nginx.sh
```

### Check Nginx Logs

```bash
docker compose logs nginx --tail=50
```

**Look for:**
- ✅ No "connection refused" errors
- ✅ No "SSL certificate" errors
- ✅ No "no resolver" errors
- ✅ Successful requests to backends

### Verify All Services

```bash
docker compose ps
```

**All services should be "Up"**

### Test From Browser

**Open in browser:**
- [ ] https://sixamdev.com (main site)
- [ ] https://api.sixamdev.com/parse/health (Parse Server)
- [ ] https://monitor.sixamdev.com (Grafana)
- [ ] https://prometheus.sixamdev.com (Prometheus)
- [ ] https://db.sixamdev.com (Adminer)
- [ ] https://storage.sixamdev.com (MinIO Console)

**Verify:**
- [ ] No SSL warnings
- [ ] Lock icon in browser
- [ ] All sites load correctly

---

## 📊 Step 11: Review Status

```bash
# Services status
docker compose ps

# System status
sudo bash manage.sh
# → Choose option 1 (Show Status)
```

**Document your results:**
```
Date: _______________
Time: _______________
Services Running: _____ / _____
SSL Status: [ ] Working [ ] Issues
HTTP→HTTPS Redirect: [ ] Working [ ] Not Working
Any Errors: _____________________
```

---

## 🎉 Step 12: Celebrate Success!

### If Everything Works:

✅ **Congratulations!** Your OneStack installation is now:
- Running all services successfully
- Secured with SSL/HTTPS
- Properly configured with health checks
- Ready for production use

### Next Steps:

1. **Change SSL to Production Mode**
   ```bash
   nano /opt/onestack/config.yml
   # Change: ssl_mode: production
   ```

2. **Request Production Certificates**
   ```bash
   sudo bash manage.sh
   # → Option 2 → Option 1 (Re-request)
   ```

3. **Setup Monitoring Alerts**
   - Configure Grafana notifications
   - Test alerting

4. **Enable Auto-renewal**
   ```bash
   # Test renewal
   certbot renew --dry-run
   
   # Should show: "Congratulations, all renewals succeeded"
   ```

5. **Regular Maintenance**
   - Check logs weekly
   - Update services monthly
   - Test backups regularly

---

## 🆘 Troubleshooting

### If Something Went Wrong:

#### Issue: Services won't start

```bash
# Check what's wrong
docker compose ps
docker compose logs --tail=100

# Check specific service
docker compose logs nginx --tail=50
docker compose logs parse-server --tail=50

# Restart
docker compose restart nginx
```

#### Issue: Nginx config error

```bash
# Test config
docker compose exec nginx nginx -t

# View specific error
docker compose logs nginx --tail=50

# Rollback
cd /opt/onestack/backups
ls -la  # Find latest backup
cp -r nginx_TIMESTAMP/nginx /opt/onestack/
docker compose restart nginx
```

#### Issue: SSL not working

```bash
# Check certificates
ls -la /etc/letsencrypt/live/sixamdev.com/

# Check symlinks
ls -la /opt/onestack/nginx/ssl/live/sixamdev.com/

# Re-request
sudo bash manage.sh
# → Option 2 → Option 1
```

#### Issue: Can't connect to backend

```bash
# Test from inside nginx
docker compose exec nginx sh
ping parse-server
wget http://parse-server:1337/parse/health

# Check network
docker compose exec nginx nslookup parse-server
```

### Run Troubleshoot Script

```bash
./troubleshoot-nginx.sh
```

This will check:
- Service status
- Nginx configuration
- SSL certificates
- Backend connectivity
- Recent errors

---

## 📝 Rollback Procedure

### If You Need to Rollback:

```bash
cd /opt/onestack/backups

# Find latest backup
ls -la | grep nginx_

# Restore nginx config
cp -r nginx_YYYYMMDD_HHMMSS/nginx /opt/onestack/

# Restore docker-compose (if needed)
cp nginx_YYYYMMDD_HHMMSS/docker-compose.yml /opt/onestack/

# Restart
docker compose down
docker compose up -d
```

---

## 📞 Get Help

### Check Documentation

```bash
cd /opt/onestack
cat NGINX_SSL_SOLUTION.md
cat QUICKSTART.md
cat PROJECT_STATUS_UPDATED.md
```

### View Logs

```bash
# All services
docker compose logs --tail=100

# Specific service
docker compose logs nginx -f

# System logs
tail -f /var/log/nginx/error.log
```

### Management Console

```bash
sudo bash manage.sh
```

---

## ✅ Final Checklist

### System Health:
- [ ] All Docker services running
- [ ] No error messages in logs
- [ ] Nginx config test passes
- [ ] All HTTP URLs work
- [ ] All HTTPS URLs work
- [ ] SSL certificates valid
- [ ] Auto-renewal configured

### Services Working:
- [ ] Main site (sixamdev.com)
- [ ] Parse Server API
- [ ] Grafana dashboard
- [ ] Prometheus metrics
- [ ] Adminer database UI
- [ ] MinIO storage
- [ ] All subdomains

### Configuration:
- [ ] Upstream health checks active
- [ ] DNS resolver configured
- [ ] SSL paths correct
- [ ] Error handling in place
- [ ] Helper scripts created

### Security:
- [ ] SSL certificates valid
- [ ] HTTP → HTTPS redirect working
- [ ] Firewall rules correct (22, 80, 443)
- [ ] No exposed ports

### Maintenance:
- [ ] Backup created
- [ ] Rollback procedure tested
- [ ] Documentation updated
- [ ] Monitoring active

---

## 📈 Success Metrics

**You've succeeded when:**

1. ✅ `docker compose ps` shows all services "Up"
2. ✅ `docker compose logs nginx` has no errors
3. ✅ All URLs work with HTTPS
4. ✅ Browser shows lock icon (valid SSL)
5. ✅ No "connection refused" errors
6. ✅ No "SSL certificate" errors
7. ✅ No "no resolver" errors
8. ✅ Services start in proper order
9. ✅ Backups are in place
10. ✅ You understand how to troubleshoot

---

## 📅 Post-Implementation

### Today:
- [x] Fix Nginx issues
- [x] Setup SSL
- [ ] Test all services
- [ ] Document any issues

### This Week:
- [ ] Change to production SSL
- [ ] Setup monitoring alerts
- [ ] Test backup/restore
- [ ] Add more services

### This Month:
- [ ] Performance tuning
- [ ] Security audit
- [ ] Documentation completion
- [ ] User training

---

**Implementation Date:** _______________  
**Completed By:** _______________  
**Time Taken:** _______________  
**Status:** [ ] Success [ ] Partial [ ] Failed  
**Notes:** _____________________

---

**Made with ❤️ for OneStack**  
**Last Updated:** 2025-10-20  
**Version:** 1.0
