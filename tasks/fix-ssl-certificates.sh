#!/bin/bash
# แก้ SSL certificate paths ใน nginx config

NGINX_CONF="/opt/onestack/nginx/conf.d/https.conf"

echo "🔧 Fixing SSL certificate paths..."

# Backup
cp "$NGINX_CONF" "$NGINX_CONF.backup-$(date +%Y%m%d-%H%M%S)"

# แก้ flow.sixamdev.com
sed -i '/server_name flow\.sixamdev\.com/,/^}/ s|ssl_certificate .*fullchain\.pem;|ssl_certificate /etc/letsencrypt/live/flow.sixamdev.com/fullchain.pem;|' "$NGINX_CONF"
sed -i '/server_name flow\.sixamdev\.com/,/^}/ s|ssl_certificate_key .*privkey\.pem;|ssl_certificate_key /etc/letsencrypt/live/flow.sixamdev.com/privkey.pem;|' "$NGINX_CONF"

# แก้ db.sixamdev.com
sed -i '/server_name db\.sixamdev\.com/,/^}/ s|ssl_certificate .*fullchain\.pem;|ssl_certificate /etc/letsencrypt/live/db.sixamdev.com/fullchain.pem;|' "$NGINX_CONF"
sed -i '/server_name db\.sixamdev\.com/,/^}/ s|ssl_certificate_key .*privkey\.pem;|ssl_certificate_key /etc/letsencrypt/live/db.sixamdev.com/privkey.pem;|' "$NGINX_CONF"

echo "✅ Certificate paths updated!"
echo ""
echo "Testing nginx configuration..."

# Test
docker compose -f /opt/onestack/docker-compose.yml exec -T nginx nginx -t

if [ $? -eq 0 ]; then
    echo "✅ Configuration valid!"
    echo ""
    echo "Reloading nginx..."
    docker compose -f /opt/onestack/docker-compose.yml exec -T nginx nginx -s reload
    echo "✅ Nginx reloaded!"
    echo ""
    echo "Testing domains..."
    echo ""
    
    echo "flow.sixamdev.com:"
    curl -I https://flow.sixamdev.com 2>&1 | head -1
    echo ""
    
    echo "db.sixamdev.com:"
    curl -I https://db.sixamdev.com 2>&1 | head -1
    echo ""
    
    echo "✅ Done! All certificates should work now."
else
    echo "❌ Configuration test failed!"
    echo "Restoring backup..."
    mv "$NGINX_CONF.backup-"* "$NGINX_CONF"
fi