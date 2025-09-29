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
echo -e "${YELLOW}⚠️  This will remove:${NC}"
echo "  - All OneStack containers"
echo "  - All OneStack data"
echo "  - All OneStack volumes"
echo "  - All OneStack networks"
echo ""
read -p "Are you sure? (type 'yes' to confirm): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Cancelled."
    exit 0
fi

echo -e "${YELLOW}Removing OneStack...${NC}"

# Stop and remove containers
docker-compose down

# Remove volumes (THIS DELETES ALL DATA!)
docker volume rm onestack_mongo onestack_redis 2>/dev/null

# Remove network
docker network rm onestack_network 2>/dev/null

# Remove images (optional)
read -p "Remove Docker images too? (y/n): " remove_images
if [ "$remove_images" = "y" ]; then
    docker rmi parseplatform/parse-server:6.4.0
    docker rmi parseplatform/parse-dashboard:5.3.3
    docker rmi mongo:7.0
    docker rmi redis:7-alpine
fi

# Clean up files
rm -f .env

echo -e "${GREEN}✅ OneStack has been completely removed!${NC}"
echo -e "${YELLOW}Note: The project files are still here. Delete this folder to remove everything.${NC}"