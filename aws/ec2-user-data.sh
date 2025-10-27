#!/bin/bash
# EC2 User Data Script for Blue/Green Deployment
# This script runs automatically when the EC2 instance launches

set -e

# Log everything to file and console
exec > >(tee /var/log/blue-green-setup.log)
exec 2>&1

echo "=========================================="
echo "Blue/Green Deployment Setup"
echo "Started: $(date)"
echo "=========================================="

# Update system
echo "==> [1/12] Updating system packages..."
yum update -y

# Install Docker
echo "==> [2/12] Installing Docker..."
yum install -y docker
systemctl start docker
systemctl enable docker
usermod -aG docker ec2-user

# Install Docker Compose v2
echo "==> [3/12] Installing Docker Compose..."
DOCKER_COMPOSE_VERSION="v2.23.0"
curl -SL "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64" \
    -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# Verify Docker Compose
docker-compose version

# Install Git
echo "==> [4/12] Installing Git..."
yum install -y git

# Install additional utilities
echo "==> [5/12] Installing utilities (curl, jq, wget)..."
yum install -y curl jq wget

# Get instance metadata
echo "==> [6/12] Retrieving instance metadata..."
INSTANCE_ID=$(ec2-metadata --instance-id | cut -d ' ' -f 2)
REGION=$(ec2-metadata --availability-zone | cut -d ' ' -f 2 | sed 's/[a-z]$//')
PUBLIC_IP=$(ec2-metadata --public-ipv4 | cut -d ' ' -f 2)

echo "Instance ID: $INSTANCE_ID"
echo "Region: $REGION"
echo "Public IP: $PUBLIC_IP"

# Get AWS Account ID and ECR details
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --region $REGION)
ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
ECR_REPO="${ECR_URI}/blue-green/app"

echo "AWS Account: $AWS_ACCOUNT_ID"
echo "ECR URI: $ECR_URI"

# Login to ECR
echo "==> [7/12] Logging into Amazon ECR..."
aws ecr get-login-password --region $REGION | \
    docker login --username AWS --password-stdin $ECR_URI

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to login to ECR"
    exit 1
fi

# Clone repository
echo "==> [8/12] Cloning repository..."
cd /opt
if [ -d "blue-green-deployment-strategy" ]; then
    echo "Repository already exists, pulling latest..."
    cd blue-green-deployment-strategy
    git pull
else
    git clone https://github.com/baydre/blue-green-deployment-strategy.git
    cd blue-green-deployment-strategy
fi

# Create/update .env file
echo "==> [9/12] Configuring environment..."
cat > .env << EOF
# Active pool configuration
ACTIVE_POOL=blue

# ECR Image references
BLUE_IMAGE=${ECR_REPO}:blue
GREEN_IMAGE=${ECR_REPO}:green

# Release identifiers
RELEASE_ID_BLUE=v1.0.0-blue
RELEASE_ID_GREEN=v1.0.0-green

# Nginx image (from Docker Hub)
NGINX_IMAGE=nginx:latest

# Verification settings
VERIFICATION_REQUESTS=100
EOF

echo "✓ Environment configured"
cat .env

# Set proper ownership
chown -R ec2-user:ec2-user /opt/blue-green-deployment-strategy

# Pull images from ECR
echo "==> [10/12] Pulling Docker images from ECR..."
docker pull ${ECR_REPO}:blue
docker pull ${ECR_REPO}:green
docker pull nginx:latest

# Tag images locally for docker-compose
docker tag ${ECR_REPO}:blue blue-app:local
docker tag ${ECR_REPO}:green green-app:local

# Start the Docker Compose stack
echo "==> [11/12] Starting Docker Compose stack..."
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d

# Wait for services to be healthy
echo "==> [12/12] Waiting for services to be healthy..."
sleep 10

MAX_WAIT=60
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
    # Check if nginx is responding
    if curl -f -s http://localhost:8080/health > /dev/null 2>&1; then
        echo "✓ Services are healthy!"
        break
    fi
    
    echo "Waiting for services... ($ELAPSED/$MAX_WAIT seconds)"
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "WARNING: Services did not become healthy within ${MAX_WAIT}s"
    echo "Check logs with: docker compose logs"
fi

# Show service status
echo ""
echo "==> Service Status:"
docker compose ps

# Setup log rotation for Docker containers
echo "==> Configuring log rotation..."
cat > /etc/logrotate.d/docker-containers << 'LOGROTATE'
/var/lib/docker/containers/*/*.log {
  rotate 7
  daily
  compress
  missingok
  delaycompress
  copytruncate
}
LOGROTATE

# Create systemd service for auto-restart on reboot
echo "==> Creating systemd service..."
cat > /etc/systemd/system/blue-green.service << 'SERVICE'
[Unit]
Description=Blue/Green Deployment Stack
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/blue-green-deployment-strategy
User=root

# ECR login and pull latest images
ExecStartPre=/bin/bash -c 'REGION=$(ec2-metadata --availability-zone | cut -d " " -f 2 | sed "s/[a-z]$//"); AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --region $REGION); ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"; aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_URI'
ExecStartPre=/usr/local/bin/docker compose pull

# Start the stack
ExecStart=/usr/local/bin/docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d

# Stop the stack
ExecStop=/usr/local/bin/docker compose -f docker-compose.yml -f docker-compose.prod.yml down

[Install]
WantedBy=multi-user.target
SERVICE

# Enable the service
systemctl daemon-reload
systemctl enable blue-green.service

echo ""
echo "=========================================="
echo "✓ Setup Complete!"
echo "=========================================="
echo ""
echo "Instance Details:"
echo "  Instance ID: $INSTANCE_ID"
echo "  Region: $REGION"
echo "  Public IP: $PUBLIC_IP"
echo ""
echo "Access URLs:"
echo "  Application: http://$PUBLIC_IP:8080"
echo "  Health Check: http://$PUBLIC_IP:8080/health"
echo ""
echo "SSH Access:"
echo "  ssh -i your-key.pem ec2-user@$PUBLIC_IP"
echo ""
echo "Useful Commands (on EC2):"
echo "  cd /opt/blue-green-deployment-strategy"
echo "  docker compose ps              # View services"
echo "  docker compose logs -f         # View logs"
echo "  ./verify-failover.sh           # Test failover"
echo "  make pool-toggle               # Switch pools"
echo ""
echo "Setup log: /var/log/blue-green-setup.log"
echo ""
echo "=========================================="
