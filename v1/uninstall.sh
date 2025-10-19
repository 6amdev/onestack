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
echo "  - All configuration files"
echo ""
read -p "Are you sure? (type 'yes' to confirm): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Cancelled."
    exit 0
fi

echo -e "${YELLOW}Stopping OneStack...${NC}"

# Stop and remove containers with volumes
docker-compose down -v 2>/dev/null || true

# Remove additional volumes (ในกรณีที่ชื่อไม่ตรง)
echo -e "${YELLOW}Removing volumes...${NC}"
docker volume ls | grep onestack | awk '{print $2}' | xargs -r docker volume rm 2>/dev/null || true

# Remove networks
echo -e "${YELLOW}Removing networks...${NC}"
docker network ls | grep onestack | awk '{print $2}' | xargs -r docker network rm 2>/dev/null || true

# Remove images (optional)
read -p "Remove Docker images too? (y/n): " remove_images
if [ "$remove_images" = "y" ]; then
    echo -e "${YELLOW}Removing images...${NC}"
    docker rmi parseplatform/parse-dashboard:5.2.0 2>/dev/null || true
    docker rmi mongo:7.0 2>/dev/null || true
    docker rmi redis:7-alpine 2>/dev/null || true
    docker rmi nginx:alpine 2>/dev/null || true
    # Remove local build
    docker images | grep onestack | awk '{print $3}' | xargs -r docker rmi -f 2>/dev/null || true
fi

# Clean up files
echo -e "${YELLOW}Cleaning up files...${NC}"
rm -f .env
rm -f install.info
rm -rf data/
rm -rf logs/
rm -rf backups/
rm -f configs/dashboard/parse-dashboard-config.json

# Clean Docker system (optional)
read -p "Clean up Docker system (remove unused data)? (y/n): " clean_docker
if [ "$clean_docker" = "y" ]; then
    echo -e "${YELLOW}Cleaning Docker system...${NC}"
    docker system prune -f
fi

echo -e "${GREEN}✅ OneStack has been completely removed!${NC}"
echo -e "${YELLOW}Note: Project source files still remain.${NC}"
echo -e "${YELLOW}To completely remove everything: cd .. && rm -rf onestack${NC}"