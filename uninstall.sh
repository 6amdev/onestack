#!/bin/bash

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${RED}================================${NC}"
echo -e "${RED}   OneStack Complete Removal   ${NC}"
echo -e "${RED}================================${NC}"

# Confirmation
echo -e "${YELLOW}⚠️  WARNING: This will remove:${NC}"
echo "  - All OneStack containers"
echo "  - All OneStack data (PERMANENT!)"
echo "  - All OneStack volumes"
echo "  - All OneStack networks"
echo ""
read -p "Are you sure? (type 'yes' to confirm): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Cancelled."
    exit 0
fi

echo -e "${YELLOW}Stopping OneStack...${NC}"

# Stop and remove containers
docker-compose down -v  # -v จะลบ volumes ที่ประกาศใน docker-compose

# Remove volumes (ชื่อต้องตรงกับใน docker-compose.yml)
echo -e "${YELLOW}Removing volumes...${NC}"
docker volume rm onestack_mongo_data 2>/dev/null || true
docker volume rm onestack_redis_data 2>/dev/null || true

# Remove networks
echo -e "${YELLOW}Removing networks...${NC}"
docker network rm onestack_public 2>/dev/null || true
docker network rm onestack_internal 2>/dev/null || true

# Remove images (optional)
read -p "Remove Docker images too? (y/n): " remove_images
if [ "$remove_images" = "y" ]; then
    echo -e "${YELLOW}Removing images...${NC}"
    docker rmi parseplatform/parse-dashboard:latest 2>/dev/null || true
    docker rmi mongo:7.0 2>/dev/null || true
    docker rmi redis:7-alpine 2>/dev/null || true
    docker rmi nginx:alpine 2>/dev/null || true
    # Remove local build
    docker rmi onestack-parse-server 2>/dev/null || true
fi

# Clean up files
echo -e "${YELLOW}Cleaning up files...${NC}"
rm -f .env
rm -f install.info
rm -rf data/
rm -rf logs/
rm -rf backups/

echo -e "${GREEN}✅ OneStack has been completely removed!${NC}"
echo -e "${YELLOW}Note: Project source files still remain. Run 'rm -rf onestack' to delete everything.${NC}"