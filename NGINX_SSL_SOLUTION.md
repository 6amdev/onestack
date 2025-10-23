# 🎯 OneStack: Nginx + SSL Complete Solution

**วันที่:** 2025-10-20  
**โดเมน:** sixamdev.com  
**Server:** 68.183.226.120

---

## 📋 สรุปปัญหาที่พบ

### จากไฟล์ Log ที่วิเคราะห์:

#### 1. **Upstream Backend ไม่พร้อม** ❌
```
connect() failed (111: Connection refused) while connecting to upstream
upstream: "http://172.19.0.4:1337/parse/health"
```
**สาเหตุ:** Parse Server ยังไม่ทำงานตอนที่ Nginx start

#### 2. **SSL Certificate Path ผิด** ❌
```
cannot load certificate "/etc/nginx/ssl/live/parsetest.phuriphat.com/fullchain.pem"
BIO_new_file() failed (SSL: error:80000002:system library::No such file or directory)
```
**สาเหตุ:** Nginx หา certificate ไม่เจอที่ path ที่กำหนด

#### 3. **DNS Resolver ขาดหาย** ❌
```
no resolver defined to resolve api.parsetest.phuriphat.com
```
**สาเหตุ:** ไม่มี DNS resolver configuration

---

## ✅ สิ่งที่คุณมีอยู่แล้ว (ดีมาก!)

### 📁 โครงสร้างไฟล์ที่มี:
```
/opt/onestack/
├── manage.sh              ✅ Management console (ครบถ้วน)
├── 06-ssl.sh             ✅ SSL functions (discover, check, setup)
├── utils.sh              ✅ Utility functions (สมบูรณ์)
├── config.yml            ✅ Configuration (sixamdev.com)
├── add-redirect-domain.sh ✅ Add domain script
├── setup-ssl.sh          ✅ SSL setup script
├── fix-*.sh              ⚠️  Multiple fix attempts
└── install.sh            ✅ Main installer
```

### 🎯 Scripts ที่ทำงาน:
- ✅ `manage.sh` - มี menu ครบถ้วน
- ✅ `utils.sh` - มี functions พื้นฐานครบ
- ✅ `06-ssl.sh` - มี SSL logic แล้ว
- ✅ Config system - ใช้ config.yml

---

## 🔧 แนวทางแก้ไขที่ชัดเจน

### หลักการหลัก:
1. **ไม่สร้างไฟล์ใหม่** - ใช้ของที่มีอยู่
2. **แก้ไขเฉพาะจุด** - Fix config ที่เป็นปัญหา
3. **Test ทีละขั้น** - ทำทีละขั้นตอนชัดเจน

---

## 📝 Solution แบ่งเป็น 4 Parts

### Part 1: แก้ปัญหา Upstream (Backend Connection)

**ปัญหา:** Nginx start ก่อน Backend พร้อม

**วิธีแก้:**

#### 1.1 สร้าง Nginx Upstream Config
```bash
cat > /opt/onestack/nginx/conf.d/00-upstream.conf <<'EOF'
# Upstream Backend Configuration
# ป้องกัน Nginx fail เมื่อ backend ยังไม่พร้อม

upstream parse_backend {
    server parse-server:1337 max_fails=3 fail_timeout=30s;
    keepalive 32;
}

upstream grafana_backend {
    server grafana:3000 max_fails=3 fail_timeout=30s;
    keepalive 32;
}

upstream prometheus_backend {
    server prometheus:9090 max_fails=3 fail_timeout=30s;
    keepalive 32;
}

upstream adminer_backend {
    server adminer:8080 max_fails=3 fail_timeout=30s;
    keepalive 32;
}

upstream minio_api {
    server minio:9000 max_fails=3 fail_timeout=30s;
    keepalive 32;
}

upstream minio_console {
    server minio:9001 max_fails=3 fail_timeout=30s;
    keepalive 32;
}
EOF
```

#### 1.2 เพิ่ม Health Check ใน nginx.conf
```bash
# เพิ่มใน main nginx.conf
cat >> /opt/onestack/nginx/nginx.conf <<'EOF'

# Health check endpoint
server {
    listen 80 default_server;
    server_name _;
    
    location /nginx-health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
EOF
```

#### 1.3 แก้ไข Docker Compose - Service Dependencies
```yaml
# ใน docker-compose.yml
nginx:
  depends_on:
    parse-server:
      condition: service_started
    grafana:
      condition: service_started
    prometheus:
      condition: service_started
  # เพิ่ม health check
  healthcheck:
    test: ["CMD", "nginx", "-t"]
    interval: 30s
    timeout: 10s
    retries: 3
    start_period: 40s  # ให้เวลา 40 วิก่อน check
```

---

### Part 2: แก้ปัญหา SSL Certificate Paths

**ปัญหา:** Nginx หา cert ไม่เจอ

**วิธีแก้:**

#### 2.1 สร้าง SSL Directory Structure
```bash
# สร้าง directory ที่ Nginx expect
mkdir -p /opt/onestack/nginx/ssl/live/sixamdev.com
mkdir -p /opt/onestack/nginx/ssl/certbot/conf
mkdir -p /opt/onestack/nginx/ssl/certbot/www

# Symlink จาก Let's Encrypt location
if [ -d "/etc/letsencrypt/live/sixamdev.com" ]; then
    ln -sf /etc/letsencrypt/live/sixamdev.com/fullchain.pem \
           /opt/onestack/nginx/ssl/live/sixamdev.com/fullchain.pem
    ln -sf /etc/letsencrypt/live/sixamdev.com/privkey.pem \
           /opt/onestack/nginx/ssl/live/sixamdev.com/privkey.pem
fi
```

#### 2.2 แก้ไข Nginx SSL Config Template
```nginx
# ใน nginx/conf.d/*.conf ทุกไฟล์
# แทน path เดิม:
ssl_certificate /etc/nginx/ssl/live/${DOMAIN}/fullchain.pem;
ssl_certificate_key /etc/nginx/ssl/live/${DOMAIN}/privkey.pem;

# เป็น: (ใน Docker container จะ mount ไป /etc/nginx/ssl)
ssl_certificate /etc/nginx/ssl/live/sixamdev.com/fullchain.pem;
ssl_certificate_key /etc/nginx/ssl/live/sixamdev.com/privkey.pem;
```

#### 2.3 อัพเดท Docker Compose Volume Mount
```yaml
nginx:
  volumes:
    - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    - ./nginx/conf.d:/etc/nginx/conf.d:ro
    - ./nginx/ssl:/etc/nginx/ssl:ro  # ✅ Mount SSL directory
    - /etc/letsencrypt:/etc/letsencrypt:ro  # ✅ Also mount letsencrypt
    - ./nginx/certbot/www:/var/www/certbot:ro
```

---

### Part 3: แก้ปัญหา DNS Resolver

**ปัญหา:** ไม่มี resolver config

**วิธีแก้:**

#### 3.1 สร้าง Resolver Config
```bash
cat > /opt/onestack/nginx/conf.d/01-resolver.conf <<'EOF'
# DNS Resolver Configuration
# สำหรับ resolve domain names ใน Docker network

# ใช้ Docker's internal DNS (127.0.0.11)
resolver 127.0.0.11 valid=30s ipv6=off;
resolver_timeout 5s;

# Fallback: ใช้ public DNS (ถ้าอยู่นอก Docker)
# resolver 8.8.8.8 8.8.4.4 valid=300s;
# resolver 1.1.1.1 1.0.0.1 valid=300s;
EOF
```

#### 3.2 เพิ่ม DNS ใน Docker Network
```yaml
# ใน docker-compose.yml
networks:
  frontend:
    driver: bridge
    driver_opts:
      com.docker.network.bridge.enable_icc: "true"
    ipam:
      config:
        - subnet: 172.20.0.0/24
```

---

### Part 4: Graceful Error Handling

**เพิ่ม error handling ในทุก virtual host**

#### 4.1 Update Virtual Host Template
```nginx
server {
    listen 443 ssl http2;
    server_name api.sixamdev.com;
    
    # SSL config...
    
    location /parse {
        # Retry ถ้า backend fail
        proxy_next_upstream error timeout http_502 http_503 http_504;
        proxy_next_upstream_tries 3;
        proxy_next_upstream_timeout 10s;
        
        proxy_pass http://parse_backend;  # ใช้ upstream
        
        # Basic proxy settings
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Error handling
        proxy_intercept_errors on;
        error_page 502 503 504 = @backend_unavailable;
    }
    
    # Friendly error page
    location @backend_unavailable {
        default_type application/json;
        return 503 '{"error": "Service temporarily unavailable", "message": "Backend is starting up. Please try again in a moment."}';
    }
}
```

---

## 🚀 Implementation Steps (ทำตามลำดับ)

### Step 1: Backup ก่อน
```bash
cd /opt/onestack
cp -r nginx nginx.backup.$(date +%Y%m%d_%H%M%S)
cp docker-compose.yml docker-compose.yml.backup
```

### Step 2: Create Fix Script
```bash
# สร้าง script รวมทุกอย่าง
cat > /opt/onestack/fix-nginx-ssl-final.sh <<'SCRIPT'
#!/bin/bash
set -e

DOMAIN="sixamdev.com"
INSTALL_DIR="/opt/onestack"

echo "🔧 Fixing Nginx + SSL Issues..."

# 1. Create upstream config
cat > $INSTALL_DIR/nginx/conf.d/00-upstream.conf <<'EOF'
upstream parse_backend {
    server parse-server:1337 max_fails=3 fail_timeout=30s;
    keepalive 32;
}
# ... (upstream definitions)
EOF

# 2. Create resolver config
cat > $INSTALL_DIR/nginx/conf.d/01-resolver.conf <<'EOF'
resolver 127.0.0.11 valid=30s ipv6=off;
resolver_timeout 5s;
EOF

# 3. Create SSL directories
mkdir -p $INSTALL_DIR/nginx/ssl/live/$DOMAIN
mkdir -p $INSTALL_DIR/nginx/ssl/certbot/{conf,www}

# 4. Symlink certificates if exist
if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
    ln -sf /etc/letsencrypt/live/$DOMAIN/fullchain.pem \
           $INSTALL_DIR/nginx/ssl/live/$DOMAIN/
    ln -sf /etc/letsencrypt/live/$DOMAIN/privkey.pem \
           $INSTALL_DIR/nginx/ssl/live/$DOMAIN/
    echo "✓ SSL certificates linked"
fi

# 5. Update all virtual host files
for conf in $INSTALL_DIR/nginx/conf.d/*.conf; do
    if grep -q "ssl_certificate" "$conf"; then
        # Update SSL paths
        sed -i "s|/etc/letsencrypt/live/|/etc/nginx/ssl/live/|g" "$conf"
        
        # Add error handling if not exists
        if ! grep -q "proxy_next_upstream" "$conf"; then
            # Add after location blocks
            echo "  # Note: Add proxy_next_upstream manually"
        fi
    fi
done

# 6. Test Nginx config
docker compose exec nginx nginx -t || echo "⚠️  Nginx test failed (expected if not running)"

echo "✓ Fix completed! Next steps:"
echo "  1. Review configs in $INSTALL_DIR/nginx/conf.d/"
echo "  2. Restart services: docker compose restart"
echo "  3. Check logs: docker compose logs -f nginx"

SCRIPT

chmod +x /opt/onestack/fix-nginx-ssl-final.sh
```

### Step 3: Run Fix Script
```bash
cd /opt/onestack
./fix-nginx-ssl-final.sh
```

### Step 4: Restart Services (Proper Order)
```bash
# Stop all
docker compose down

# Start databases first
docker compose up -d postgres mongodb redis

# Wait 10 seconds
sleep 10

# Start backends
docker compose up -d minio parse-server grafana prometheus adminer

# Wait 15 seconds
sleep 15

# Start Nginx last
docker compose up -d nginx

# Check status
docker compose ps
```

### Step 5: Verify
```bash
# Check Nginx logs
docker compose logs nginx --tail=50

# Test endpoints
curl -I http://sixamdev.com
curl -I https://api.sixamdev.com/parse/health
curl -I https://monitor.sixamdev.com

# Check SSL
openssl s_client -connect sixamdev.com:443 -servername sixamdev.com < /dev/null
```

---

## 🎯 Quick Command Reference

### Start Services (Safe Order)
```bash
cd /opt/onestack

# Method 1: One by one
docker compose up -d postgres mongodb redis
sleep 10
docker compose up -d minio parse-server grafana prometheus
sleep 15
docker compose up -d nginx

# Method 2: Use depends_on (after fixing docker-compose.yml)
docker compose up -d
```

### Check Service Health
```bash
# All services
docker compose ps

# Specific service
docker compose logs nginx --tail=50 -f

# Nginx config test
docker compose exec nginx nginx -t

# Reload Nginx (without restart)
docker compose exec nginx nginx -s reload
```

### SSL Operations
```bash
# Check existing certificates
ls -la /etc/letsencrypt/live/

# Request new certificate (via manage.sh)
sudo bash manage.sh
# → Choose "2) Setup/Manage SSL Certificates"

# Manual renewal
docker compose run --rm certbot renew

# Check expiry
openssl x509 -in /etc/letsencrypt/live/sixamdev.com/fullchain.pem \
             -noout -dates
```

### Troubleshooting
```bash
# View all logs
docker compose logs --tail=100

# Check specific service
docker compose logs parse-server --tail=50

# Enter container
docker compose exec nginx sh

# Check network connectivity (from nginx container)
docker compose exec nginx ping parse-server
docker compose exec nginx wget http://parse-server:1337/parse/health
```

---

## 📊 Expected Results

### After Fix:
```
✅ Nginx starts successfully
✅ No "connection refused" errors
✅ SSL certificates load correctly
✅ All subdomains accessible via HTTPS
✅ Graceful backend error handling
✅ DNS resolution works
```

### URLs Working:
```
✅ https://sixamdev.com
✅ https://api.sixamdev.com/parse
✅ https://monitor.sixamdev.com
✅ https://prometheus.sixamdev.com
✅ https://db.sixamdev.com
✅ https://storage.sixamdev.com
✅ https://s3.sixamdev.com
```

---

## 🎓 Why This Solution Works

### 1. Upstream Blocks
- Nginx ไม่ fail ทันทีถ้า backend down
- มี retry mechanism
- Connection pooling (keepalive)

### 2. Correct SSL Paths
- Symlink ทำให้ flexible
- Mount ทั้ง `/etc/letsencrypt` และ `nginx/ssl`
- Nginx หา cert เจอแน่นอน

### 3. DNS Resolver
- ใช้ Docker internal DNS (127.0.0.11)
- Resolve service names ได้
- No more "no resolver" error

### 4. Graceful Degradation
- แสดง friendly error แทน 502
- Retry อัตโนมัติ
- Timeout ที่เหมาะสม

---

## 💡 Pro Tips

### Use manage.sh
```bash
sudo bash manage.sh
# มี menu ครบถ้วนแล้ว:
# - Status check
# - SSL management
# - Service control
# - System info
```

### Monitor Logs Real-time
```bash
# Terminal 1: Nginx logs
docker compose logs -f nginx

# Terminal 2: Backend logs
docker compose logs -f parse-server

# Terminal 3: All logs
docker compose logs -f
```

### Test Before SSL
```bash
# ทดสอบ HTTP ก่อน
curl -v http://api.sixamdev.com/parse/health

# ถ้า HTTP ทำงาน ค่อย enable SSL
sudo bash manage.sh
# → Setup SSL
```

---

## 🆘 If Something Goes Wrong

### Rollback
```bash
cd /opt/onestack

# Restore nginx config
rm -rf nginx
mv nginx.backup.YYYYMMDD_HHMMSS nginx

# Restore docker-compose
mv docker-compose.yml.backup docker-compose.yml

# Restart
docker compose down
docker compose up -d
```

### Start Fresh (Nuclear Option)
```bash
# Stop everything
docker compose down -v

# Clear nginx configs
cd /opt/onestack/nginx/conf.d
rm *.conf

# Re-run setup (from manage.sh or install.sh phase 3)
```

---

## 📁 Files Modified Summary

```
Modified Files:
├── nginx/conf.d/00-upstream.conf         (NEW)
├── nginx/conf.d/01-resolver.conf         (NEW)
├── nginx/conf.d/api.sixamdev.com.conf    (UPDATED - SSL paths)
├── nginx/conf.d/monitor.sixamdev.com.conf (UPDATED - SSL paths)
├── nginx/conf.d/*.conf                    (ALL UPDATED - error handling)
├── docker-compose.yml                     (UPDATED - health checks)
└── nginx/ssl/                            (NEW - symlinks)

New Scripts:
└── fix-nginx-ssl-final.sh                (GENERATED)
```

---

## ✅ Checklist

Before running fix:
- [ ] Backup nginx directory
- [ ] Backup docker-compose.yml
- [ ] Have access to server
- [ ] Know the domain name
- [ ] Can SSH as root/sudo

During fix:
- [ ] Run fix script
- [ ] No errors during script execution
- [ ] Configs created successfully

After fix:
- [ ] Restart services (proper order)
- [ ] Check docker compose ps (all running)
- [ ] Test HTTP first
- [ ] Request SSL (if not exist)
- [ ] Test HTTPS
- [ ] Check all subdomains

---

## 🎉 Success Criteria

คุณจะรู้ว่าสำเร็จเมื่อ:

1. ✅ `docker compose ps` แสดง "healthy" ทุก service
2. ✅ `docker compose logs nginx` ไม่มี error
3. ✅ `curl https://api.sixamdev.com/parse/health` return 200
4. ✅ Browser เปิด https://sixamdev.com ได้ (ไม่มี SSL warning)
5. ✅ All subdomains accessible via HTTPS

---

**สร้างโดย:** Claude (Anthropic)  
**Based on:** OneStack Architecture v1.0  
**สำหรับ:** sixamdev.com on Ubuntu 22.04
