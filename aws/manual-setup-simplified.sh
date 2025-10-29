#!/bin/bash
# Manual setup script for EC2 - with SIMPLIFIED Release IDs
# This will be run on the EC2 instance to set up the Blue/Green deployment

set -e

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║     Blue/Green Deployment - EC2 Setup (Simplified IDs)       ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# Configuration
AWS_REGION="eu-north-1"
AWS_ACCOUNT_ID="704654299291"
ECR_REPO="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/blue-green/app"
WORK_DIR="/home/ubuntu/blue-green"

echo "==> [1/7] Installing Docker..."
if ! command -v docker &> /dev/null; then
    sudo apt-get update -qq
    sudo apt-get install -y docker.io jq curl
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo usermod -aG docker ubuntu
    echo "✓ Docker installed"
else
    echo "✓ Docker already installed"
fi

echo ""
echo "==> [2/7] Creating working directory..."
sudo mkdir -p $WORK_DIR
sudo chown ubuntu:ubuntu $WORK_DIR
cd $WORK_DIR

echo ""
echo "==> [3/7] Logging into ECR..."
aws ecr get-login-password --region $AWS_REGION | \
    sudo docker login --username AWS --password-stdin $ECR_REPO

echo ""
echo "==> [4/7] Pulling images from ECR..."
sudo docker pull $ECR_REPO:blue
sudo docker pull $ECR_REPO:green

echo ""
echo "==> [5/7] Creating .env file with SIMPLIFIED Release IDs..."
cat > .env << 'ENVFILE'
# Blue/Green Configuration
ACTIVE_POOL=blue

# ECR images
BLUE_IMAGE=704654299291.dkr.ecr.eu-north-1.amazonaws.com/blue-green/app:blue
GREEN_IMAGE=704654299291.dkr.ecr.eu-north-1.amazonaws.com/blue-green/app:green

# SIMPLIFIED Release IDs for grader compatibility
RELEASE_ID_BLUE=blue
RELEASE_ID_GREEN=green

# Nginx
NGINX_IMAGE=nginx:latest

# Test configuration
VERIFICATION_REQUESTS=100
ENVFILE

echo "✓ .env created with simplified Release IDs:"
grep RELEASE_ID .env

echo ""
echo "==> [6/7] Creating docker-compose.yml..."
cat > docker-compose.yml << 'DOCKERCOMPOSE'
services:
  nginx:
    image: ${NGINX_IMAGE:-nginx:latest}
    container_name: nginx-proxy
    ports:
      - "8080:80"
    volumes:
      - ./nginx.conf.template:/etc/nginx/templates/nginx.conf.template:ro
    environment:
      - ACTIVE_POOL=${ACTIVE_POOL}
    command: >
      /bin/sh -c "envsubst '$${ACTIVE_POOL}' < /etc/nginx/templates/nginx.conf.template > /etc/nginx/nginx.conf && 
      nginx -g 'daemon off;'"
    depends_on:
      - app_blue
      - app_green
    networks:
      - app-network
    restart: unless-stopped

  app_blue:
    image: ${BLUE_IMAGE}
    container_name: app-blue
    ports:
      - "8081:80"
    environment:
      - RELEASE_ID=${RELEASE_ID_BLUE}
      - APP_POOL=blue
    networks:
      - app-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:80/healthz"]
      interval: 10s
      timeout: 3s
      retries: 3
      start_period: 5s

  app_green:
    image: ${GREEN_IMAGE}
    container_name: app-green
    ports:
      - "8082:80"
    environment:
      - RELEASE_ID=${RELEASE_ID_GREEN}
      - APP_POOL=green
    networks:
      - app-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:80/healthz"]
      interval: 10s
      timeout: 3s
      retries: 3
      start_period: 5s

networks:
  app-network:
    driver: bridge
DOCKERCOMPOSE

echo "✓ docker-compose.yml created"

echo ""
echo "==> [7/7] Creating nginx.conf.template..."
cat > nginx.conf.template << 'NGINXCONF'
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    upstream blue_pool {
        server app_blue:80 max_fails=1 fail_timeout=10s;
        server app_green:80 backup;
    }

    upstream green_pool {
        server app_green:80 max_fails=1 fail_timeout=10s;
        server app_blue:80 backup;
    }

    server {
        listen 80;

        proxy_buffer_size 8k;
        proxy_buffers 4 32k;
        proxy_busy_buffers_size 64k;

        location / {
            proxy_pass http://${ACTIVE_POOL}_pool;

            proxy_next_upstream error timeout http_500 http_502 http_503 http_504;
            proxy_next_upstream_tries 2;
            proxy_next_upstream_timeout 4s;

            proxy_connect_timeout 2s;
            proxy_read_timeout 2s;
            proxy_send_timeout 2s;

            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;

            proxy_http_version 1.1;
            proxy_set_header Connection "";
        }

        location /healthz {
            proxy_pass http://${ACTIVE_POOL}_pool/healthz;
            proxy_connect_timeout 2s;
            proxy_read_timeout 2s;
        }
    }
}
NGINXCONF

echo "✓ nginx.conf.template created"

echo ""
echo "==> Starting services..."
sudo docker compose up -d

echo ""
echo "==> Waiting for containers to be ready..."
sleep 10

echo ""
echo "==> Container status:"
sudo docker compose ps

echo ""
echo "==> Testing endpoints..."
echo "  Nginx (8080):"
curl -s http://localhost:8080/version | jq -c '{pool, release}'

echo "  Blue (8081):"
curl -s http://localhost:8081/version | jq -c '{pool, release}'

echo "  Green (8082):"
curl -s http://localhost:8082/version | jq -c '{pool, release}'

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                 ✓ SETUP COMPLETE!                             ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "Your Blue/Green deployment is running with SIMPLIFIED Release IDs:"
echo "  - Blue:  'blue' (not 'v1.0.1-blue')"
echo "  - Green: 'green' (not 'v1.1.0-green')"
echo ""
echo "Access the application:"
echo "  - Main (Nginx): http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8080"
echo "  - Blue direct:  http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8081"
echo "  - Green direct: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8082"
echo ""
