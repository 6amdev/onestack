# OneStack Testing Guide

## 🧪 การทดสอบการติดตั้ง

### 1. เตรียม config.yml
```bash
# Copy example
cp config.example.yml config.yml

# แก้ไข config
nano config.yml
```

**สำหรับทดสอบ (localhost):**
```yaml
domain:
  primary: localhost
  ssl_email: test@localhost
  ssl_mode: staging

components:
  parse_server: true
  monitoring: true
  adminer: true
```

### 2. รัน Installer
```bash
# ติดตั้ง
sudo bash install.sh
```

**ระหว่างติดตั้ง:**
- ใช้เวลา 15-25 นาที
- จะถามยืนยันหลายครั้ง
- จะสร้าง admin user (ตั้งรหัสผ่าน)
- จะสร้าง onestack user (ไม่ต้องตั้งรหัสผ่าน)

### 3. ทดสอบหลังติดตั้ง
```bash
# รัน test script
sudo bash test-install.sh
```

### 4. เข้าใช้งาน

**เปิด browser:**
- Main: http://localhost
- MinIO: http://localhost:9001
- Parse: http://localhost:4040
- Grafana: http://localhost:3001
- Adminer: http://localhost:8080

**ดู credentials:**
```bash
# จาก root
sudo cat /opt/onestack/.credentials

# หรือ จาก onestack directory
cat /opt/onestack/.credentials
```

### 5. ทดสอบการทำงาน

**เช็ค services:**
```bash
cd /opt/onestack
docker compose ps
```

**ดู logs:**
```bash
cd /opt/onestack
docker compose logs -f nginx
docker compose logs -f postgres
```

**ทดสอบ database:**
```bash
# เข้า Adminer: http://localhost:8080
# System: PostgreSQL
# Server: postgres
# Username: postgres
# Password: (ดูจาก .credentials)
# Database: onestack_main
```

### 6. ทดสอบ Parse Server
```bash
# ทดสอบ API
curl http://localhost:1337/parse/health

# ตัวอย่าง response:
# {"status":"ok"}

# เข้า Parse Dashboard: http://localhost:4040
# Username: admin
# Password: (ดูจาก .credentials)
```

### 7. ทดสอบ Monitoring
```bash
# เข้า Grafana: http://localhost:3001
# Username: admin
# Password: (ดูจาก .credentials)

# เข้า Prometheus: http://localhost:9090
```

---

## 🗑️ การทดสอบ Uninstall

### 1. Dry Run (ดูก่อนว่าจะลบอะไร)
```bash
sudo bash uninstall.sh --dry-run
```

### 2. ลบแบบปลอดภัย (เก็บ data)
```bash
sudo bash uninstall.sh
# เลือก: 1) Containers only
```

### 3. ลบทั้งหมด (ลบ data ด้วย)
```bash
sudo bash uninstall.sh
# เลือก: 3) Complete removal
```

### 4. ติดตั้งใหม่
```bash
sudo bash install.sh
```

---

## 🐛 Troubleshooting

### Services ไม่ขึ้น
```bash
# เช็คว่า Docker ทำงานไหม
sudo systemctl status docker

# เช็ค compose file
cd /opt/onestack
docker compose config

# Restart services
docker compose restart

# ดู logs
docker compose logs --tail=100
```

### Port ติด
```bash
# เช็คว่า port ไหนถูกใช้
sudo netstat -tulpn | grep :80
sudo netstat -tulpn | grep :5432

# ถ้า port ติด ให้หยุด service ที่ขัดแย้ง
sudo systemctl stop apache2  # ถ้ามี Apache
sudo systemctl stop nginx     # ถ้ามี Nginx เดิม
```

### Permission Issues
```bash
# Fix ownership
sudo chown -R onestack:onestack /opt/onestack

# Fix permissions
sudo chmod -R 755 /opt/onestack
sudo chmod 600 /opt/onestack/.env
sudo chmod 600 /opt/onestack/.credentials
```

### Memory Issues
```bash
# เช็ค memory
free -h

# ถ้า RAM ไม่พอ ลด services:
# แก้ config.yml:
components:
  parse_server: false
  monitoring: false
```

---

## ✅ Test Checklist

- [ ] ติดตั้งสำเร็จ (ไม่มี error)
- [ ] Services ทั้งหมดขึ้น (docker compose ps)
- [ ] เข้า welcome page ได้
- [ ] เข้า MinIO console ได้
- [ ] (ถ้าเปิด) Parse Dashboard ใช้งานได้
- [ ] (ถ้าเปิด) Grafana ใช้งานได้
- [ ] (ถ้าเปิด) Adminer ใช้งานได้
- [ ] Database เชื่อมต่อได้ (ผ่าน Adminer)
- [ ] Uninstall ทำงาน (dry-run)
- [ ] Uninstall + Reinstall สำเร็จ

---

## 📊 Expected Results

**After successful installation:**
```
✓ 8-12 Docker containers running
✓ 6-8 Docker volumes created
✓ 2 Docker networks (frontend, backend)
✓ Welcome page accessible
✓ All admin UIs accessible
✓ Credentials file created
✓ No errors in logs
```

**Disk usage:**
- ~2-3 GB for Docker images
- ~500 MB for initial data
- Total: ~3-4 GB

**Memory usage:**
- Minimum: ~2 GB RAM
- Recommended: ~4 GB RAM
- With monitoring: ~5 GB RAM