#!/bin/bash
# Test IP-based access

SERVER_IP="159.223.73.110"  # ← แก้เป็น IP ของคุณ

echo "Testing OneStack services..."
echo ""

# Test main site
echo -n "Main site (port 80): "
if curl -s -o /dev/null -w "%{http_code}" "http://$SERVER_IP" | grep -q "200"; then
    echo "✓ OK"
else
    echo "✗ Failed"
fi

# Test MinIO Console
echo -n "MinIO Console (port 9001): "
if curl -s -o /dev/null -w "%{http_code}" "http://$SERVER_IP:9001" | grep -q "200"; then
    echo "✓ OK"
else
    echo "✗ Failed"
fi

# Test Parse Server
echo -n "Parse Server (port 1337): "
if curl -s "http://$SERVER_IP:1337/parse/health" | grep -q "ok"; then
    echo "✓ OK"
else
    echo "✗ Failed"
fi

# Test Parse Dashboard
echo -n "Parse Dashboard (port 4040): "
if curl -s -o /dev/null -w "%{http_code}" "http://$SERVER_IP:4040" | grep -q "200"; then
    echo "✓ OK"
else
    echo "✗ Failed"
fi

# Test Grafana
echo -n "Grafana (port 3001): "
if curl -s -o /dev/null -w "%{http_code}" "http://$SERVER_IP:3001" | grep -q "302\|200"; then
    echo "✓ OK"
else
    echo "✗ Failed"
fi

# Test Adminer
echo -n "Adminer (port 8080): "
if curl -s -o /dev/null -w "%{http_code}" "http://$SERVER_IP:8080" | grep -q "200"; then
    echo "✓ OK"
else
    echo "✗ Failed"
fi

echo ""
echo "Access URLs:"
echo "  Main: http://$SERVER_IP"
echo "  MinIO: http://$SERVER_IP:9001"
echo "  Parse: http://$SERVER_IP:4040"
echo "  Grafana: http://$SERVER_IP:3001"
echo "  Adminer: http://$SERVER_IP:8080"