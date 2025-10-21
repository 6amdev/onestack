#!/bin/bash

# OneStack SSL Certificate Fix - Complete Solution
# This script fixes all SSL certificate issues for nginx

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NGINX_CONF="/opt/onestack/nginx/conf.d/https.conf"
CERTBOT_DIR="/opt/onestack/certbot"
DOCKER_COMPOSE="/opt/onestack/docker-compose.yml"

echo -e "${BLUE}🔐 OneStack SSL Certificate Fix${NC}"
echo "=================================="
echo ""

# Function to check if certificate exists
check_cert_exists() {
    local domain=$1
    if [ -d "$CERTBOT_DIR/conf/live/$domain" ]; then
        if [ -f "$CERTBOT_DIR/conf/live/$domain/fullchain.pem" ] && \
           [ -f "$CERTBOT_DIR/conf/live/$domain/privkey.pem" ]; then
            return 0
        fi
    fi
    return 1
}

# Function to verify certificate validity
check_cert_valid() {
    local domain=$1
    local cert_file="$CERTBOT_DIR/conf/live/$domain/fullchain.pem"
    
    if [ -f "$cert_file" ]; then
        # Check if certificate is not expired
        if openssl x509 -in "$cert_file" -noout -checkend 0 >/dev/null 2>&1; then
            # Check if certificate is for the correct domain
            if openssl x509 -in "$cert_file" -noout -text | grep -q "$domain"; then
                return 0
            fi
        fi
    fi
    return 1
}

# Get list of domains from nginx config
echo -e "${YELLOW}📋 Scanning domains from nginx config...${NC}"
DOMAINS=$(grep -oP 'server_name\s+\K[^;]+' "$NGINX_CONF" | tr ' ' '\n' | sort -u | grep -v '^$')

echo "Found domains:"
echo "$DOMAINS" | while read domain; do
    echo "  - $domain"
done
echo ""

# Check each domain
echo -e "${YELLOW}🔍 Checking certificates...${NC}"
MISSING_CERTS=()
INVALID_CERTS=()

while IFS= read -r domain; do
    if [ -z "$domain" ]; then
        continue
    fi
    
    printf "Checking $domain... "
    
    if ! check_cert_exists "$domain"; then
        echo -e "${RED}❌ Certificate missing${NC}"
        MISSING_CERTS+=("$domain")
    elif ! check_cert_valid "$domain"; then
        echo -e "${RED}❌ Certificate invalid/expired${NC}"
        INVALID_CERTS+=("$domain")
    else
        echo -e "${GREEN}✅ OK${NC}"
    fi
done <<< "$DOMAINS"

echo ""

# Request missing/invalid certificates
if [ ${#MISSING_CERTS[@]} -gt 0 ] || [ ${#INVALID_CERTS[@]} -gt 0 ]; then
    echo -e "${YELLOW}📝 Certificates need to be issued/renewed:${NC}"
    
    ALL_PROBLEM_CERTS=("${MISSING_CERTS[@]}" "${INVALID_CERTS[@]}")
    
    for domain in "${ALL_PROBLEM_CERTS[@]}"; do
        echo "  - $domain"
    done
    echo ""
    
    read -p "Do you want to request/renew certificates now? (y/n) " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        for domain in "${ALL_PROBLEM_CERTS[@]}"; do
            echo -e "${BLUE}🔐 Requesting certificate for $domain...${NC}"
            
            # Request certificate
            docker compose -f "$DOCKER_COMPOSE" run --rm certbot certonly \
                --webroot \
                --webroot-path=/var/www/certbot \
                --email admin@sixamdev.com \
                --agree-tos \
                --no-eff-email \
                --force-renewal \
                -d "$domain"
            
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✅ Certificate issued for $domain${NC}"
            else
                echo -e "${RED}❌ Failed to issue certificate for $domain${NC}"
                echo -e "${YELLOW}Please check:${NC}"
                echo "  1. Domain DNS is pointing to this server"
                echo "  2. Port 80 is accessible from internet"
                echo "  3. No firewall blocking HTTP"
                echo ""
            fi
        done
        echo ""
    fi
fi

# Fix nginx configuration
echo -e "${YELLOW}🔧 Fixing nginx SSL configuration...${NC}"

# Backup current config
BACKUP_FILE="$NGINX_CONF.backup-$(date +%Y%m%d-%H%M%S)"
cp "$NGINX_CONF" "$BACKUP_FILE"
echo "Backup created: $BACKUP_FILE"

# Fix certificate paths for each domain
while IFS= read -r domain; do
    if [ -z "$domain" ]; then
        continue
    fi
    
    if check_cert_exists "$domain"; then
        echo "Fixing paths for $domain..."
        
        # Escape dots in domain for sed
        domain_escaped=$(echo "$domain" | sed 's/\./\\./g')
        
        # Fix certificate paths in the server block for this domain
        sed -i "/server_name[[:space:]].*$domain_escaped/,/^[[:space:]]*}/ {
            s|ssl_certificate[[:space:]].*fullchain\.pem;|ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;|
            s|ssl_certificate_key[[:space:]].*privkey\.pem;|ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;|
        }" "$NGINX_CONF"
    fi
done <<< "$DOMAINS"

# Add SSL security settings if not present
if ! grep -q "ssl_protocols" "$NGINX_CONF"; then
    echo "Adding SSL security settings..."
    
    # Find the first server block and add SSL settings before it
    sed -i '0,/server {/i \
# SSL Security Settings\
ssl_protocols TLSv1.2 TLSv1.3;\
ssl_prefer_server_ciphers off;\
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;\
ssl_session_timeout 1d;\
ssl_session_cache shared:SSL:50m;\
ssl_stapling on;\
ssl_stapling_verify on;\
\
# Security Headers\
add_header Strict-Transport-Security "max-age=63072000" always;\
add_header X-Frame-Options "SAMEORIGIN" always;\
add_header X-Content-Type-Options "nosniff" always;\
add_header X-XSS-Protection "1; mode=block" always;\
\n' "$NGINX_CONF"
fi

echo -e "${GREEN}✅ Nginx configuration updated${NC}"
echo ""

# Test nginx configuration
echo -e "${YELLOW}🧪 Testing nginx configuration...${NC}"
if docker compose -f "$DOCKER_COMPOSE" exec -T nginx nginx -t 2>&1 | grep -q "successful"; then
    echo -e "${GREEN}✅ Configuration is valid${NC}"
    echo ""
    
    # Reload nginx
    echo -e "${YELLOW}🔄 Reloading nginx...${NC}"
    docker compose -f "$DOCKER_COMPOSE" exec -T nginx nginx -s reload
    echo -e "${GREEN}✅ Nginx reloaded${NC}"
    echo ""
    
    # Test HTTPS for each domain
    echo -e "${YELLOW}🌐 Testing HTTPS connections...${NC}"
    echo ""
    
    while IFS= read -r domain; do
        if [ -z "$domain" ]; then
            continue
        fi
        
        printf "Testing https://$domain... "
        
        # Test with curl
        RESPONSE=$(curl -k -s -o /dev/null -w "%{http_code}" --max-time 5 "https://$domain" 2>&1)
        
        if [ "$RESPONSE" = "200" ] || [ "$RESPONSE" = "301" ] || [ "$RESPONSE" = "302" ]; then
            echo -e "${GREEN}✅ OK (HTTP $RESPONSE)${NC}"
            
            # Check certificate with openssl
            CERT_CHECK=$(echo | openssl s_client -servername "$domain" -connect "$domain:443" 2>/dev/null | openssl x509 -noout -subject 2>/dev/null)
            if [ $? -eq 0 ]; then
                echo "  Certificate: $CERT_CHECK"
            fi
        else
            echo -e "${RED}❌ Failed (HTTP $RESPONSE)${NC}"
        fi
    done <<< "$DOMAINS"
    
    echo ""
    echo -e "${GREEN}✅ SSL Configuration Complete!${NC}"
    echo ""
    echo -e "${BLUE}📝 Summary:${NC}"
    echo "  - Certificate paths fixed"
    echo "  - SSL security headers added"
    echo "  - Nginx configuration reloaded"
    echo ""
    echo -e "${YELLOW}⚠️  If domains still show as untrusted:${NC}"
    echo "  1. Wait 1-2 minutes for DNS propagation"
    echo "  2. Clear browser cache (Ctrl+Shift+Del)"
    echo "  3. Try incognito/private window"
    echo "  4. Check certificate with: openssl s_client -connect domain.com:443"
    echo ""
    
else
    echo -e "${RED}❌ Configuration test failed!${NC}"
    echo "Restoring backup..."
    mv "$BACKUP_FILE" "$NGINX_CONF"
    echo -e "${YELLOW}Configuration restored to previous version${NC}"
    exit 1
fi