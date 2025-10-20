#!/bin/bash
# Fix Parse Dashboard - Final Solution

set -e

cd /opt/onestack

echo "=== Fix Parse Dashboard - Final ==="
echo ""

# 1. สร้าง directory และ config file
echo "1. Creating config file..."
mkdir -p parse-dashboard

cat > parse-dashboard/parse-dashboard-config.json << 'CONFIGEOF'
{
  "apps": [
    {
      "serverURL": "http://parse-server:1337/parse",
      "appId": "onestack_app_id",
      "masterKey": "onestack_master_key_12345",
      "appName": "OneStack",
      "production": false,
      "iconName": "onestack.png"
    }
  ],
  "users": [
    {
      "user": "admin",
      "pass": "onestack123"
    }
  ],
  "iconsFolder": "icons"
}
CONFIGEOF

echo "✓ Config file created"
echo ""

# 2. ตรวจสอบว่าไฟล์ถูกต้อง
echo "2. Validating JSON..."
if python3 -m json.tool parse-dashboard/parse-dashboard-config.json > /dev/null 2>&1; then
    echo "✓ JSON is valid"
else
    echo "✗ JSON is invalid!"
    cat parse-dashboard/parse-dashboard-config.json
    exit 1
fi
echo ""

# 3. แสดงเนื้อหาไฟล์
echo "3. Config file content:"
cat parse-dashboard/parse-dashboard-config.json
echo ""

# 4. ตรวจสอบ docker-compose.yml
echo "4. Checking docker-compose.yml..."
if grep -q "parse-dashboard/parse-dashboard-config.json" docker-compose.yml; then
    echo "✓ Config volume already mounted"
else
    echo "✗ Config volume NOT found, adding..."
    
    # Backup
    cp docker-compose.yml docker-compose.yml.backup-$(date +%Y%m%d_%H%M%S)
    
    # แก้ parse-dashboard section ให้ตรงกับ code
    # หา parse-dashboard section และแทนที่
    sed -i '/parse-dashboard:/,/depends_on:/ {
        /depends_on:/i\    volumes:\n      - ./parse-dashboard/parse-dashboard-config.json:/parse-dashboard/config.json:ro\n    environment:\n      PARSE_DASHBOARD_CONFIG: /parse-dashboard/config.json\n      TZ: ${TIMEZONE}
    }' docker-compose.yml
    
    echo "✓ Config added to docker-compose.yml"
fi
echo ""

# 5. แสดง parse-dashboard section
echo "5. Parse Dashboard configuration:"
echo "---"
sed -n '/parse-dashboard:/,/^  [a-z]/p' docker-compose.yml | head -n -1
echo "---"
echo ""

# 6. Restart Parse Dashboard
echo "6. Restarting Parse Dashboard..."
docker compose stop parse-dashboard
docker compose rm -f parse-dashboard
docker compose up -d parse-dashboard

echo ""
echo "Waiting 15 seconds..."
sleep 15

# 7. Check status
echo ""
echo "7. Status:"
docker compose ps parse-dashboard
echo ""

# 8. Check logs
echo "8. Recent logs:"
docker compose logs --tail=30 parse-dashboard
echo ""

# 9. Test access
echo "9. Testing access..."
sleep 5

STATUS=$(docker compose ps parse-dashboard --format '{{.Status}}')
echo "Container status: $STATUS"

if echo "$STATUS" | grep -q "Up"; then
    echo ""
    echo "✅ Parse Dashboard is running!"
    echo ""
    echo "Access via:"
    echo "  • http://localhost:4040"
    echo "  • http://api.sixamdev.com"
    echo ""
    echo "Login:"
    echo "  Username: admin"
    echo "  Password: onestack123"
    
    # Test HTTP
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:4040 | grep -q "200\|301\|302"; then
        echo ""
        echo "✅ HTTP access working!"
    fi
else
    echo ""
    echo "❌ Parse Dashboard is NOT running"
    echo "Status: $STATUS"
    echo ""
    echo "Check full logs:"
    echo "  docker compose logs parse-dashboard"
fi

echo ""
echo "=== Done ==="