#!/bin/bash
# fix-parse-dashboard-config.sh - แก้ไข Parse Dashboard Configuration

echo "═══════════════════════════════════════════════════"
echo "  Fix Parse Dashboard Configuration"
echo "═══════════════════════════════════════════════════"

cd /opt/onestack

# ═══════════════════════════════════════════════════
# สร้าง Parse Dashboard config file ที่ถูกต้อง
# ═══════════════════════════════════════════════════
echo "▶ Creating Parse Dashboard config.json..."

mkdir -p parse-dashboard

cat > parse-dashboard/config.json << 'EOF'
{
  "apps": [
    {
      "serverURL": "http://parse-server:1337/parse",
      "appId": "onestack_app_id",
      "masterKey": "onestack_master_key_12345",
      "appName": "OneStack"
    }
  ],
  "users": [
    {
      "user": "admin",
      "pass": "onestack123"
    }
  ],
  "trustProxy": 1,
  "allowInsecureHTTP": true
}
EOF

echo "✓ Config file created"

# ═══════════════════════════════════════════════════
# อัพเดท docker-compose.yml ให้ mount config file
# ═══════════════════════════════════════════════════
echo ""
echo "▶ Checking docker-compose.yml..."

# ตรวจสอบว่ามี volume mount สำหรับ config.json หรือยัง
if grep -q "parse-dashboard/config.json" docker-compose.yml; then
    echo "✓ Config volume already exists"
else
    echo "⚠ Need to add config volume to docker-compose.yml"
    echo ""
    echo "Please add this to parse-dashboard service volumes:"
    echo "  - ./parse-dashboard/config.json:/parse-dashboard/config.json:ro"
fi

# ═══════════════════════════════════════════════════
# Restart Parse Dashboard
# ═══════════════════════════════════════════════════
echo ""
echo "▶ Restarting Parse Dashboard..."

docker compose stop parse-dashboard
docker compose rm -f parse-dashboard
docker compose up -d parse-dashboard

echo ""
echo "⏳ Waiting 10 seconds..."
sleep 10

# ═══════════════════════════════════════════════════
# Check status
# ═══════════════════════════════════════════════════
echo ""
echo "▶ Checking Parse Dashboard status..."
echo ""

docker compose ps parse-dashboard

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Recent logs:"
docker compose logs --tail=30 parse-dashboard
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ═══════════════════════════════════════════════════
# Test access
# ═══════════════════════════════════════════════════
echo ""
echo "▶ Testing access..."
echo ""

sleep 5

STATUS=$(docker compose ps parse-dashboard --format json | jq -r '.[0].State' 2>/dev/null || echo "unknown")

if [ "$STATUS" = "running" ]; then
    echo "✅ Parse Dashboard is running!"
    echo ""
    echo "Access URLs:"
    echo "  • Internal: http://parse-dashboard:4040"
    echo "  • External: http://api.sixamdev.com (via Nginx)"
    echo ""
    echo "Login credentials:"
    echo "  • Username: admin"
    echo "  • Password: onestack123"
else
    echo "❌ Parse Dashboard is NOT running"
    echo "Status: $STATUS"
fi