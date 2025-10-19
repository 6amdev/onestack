#!/bin/bash

# Nuclear option - remove EVERYTHING OneStack related
echo "🧹 Deep cleaning OneStack..."

# Stop all OneStack containers
docker stop $(docker ps -a -q --filter name=onestack) 2>/dev/null

# Remove all OneStack containers
docker rm $(docker ps -a -q --filter name=onestack) 2>/dev/null

# Remove volumes
docker volume rm $(docker volume ls -q --filter name=onestack) 2>/dev/null

# Remove network
docker network rm onestack_network 2>/dev/null

# Prune everything
docker system prune -a --volumes -f

echo "✅ All OneStack traces removed!"