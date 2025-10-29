#!/bin/bash
# Manual EC2 Setup Script for Blue/Green Deployment
# Run this on the EC2 instance after SSH

set -e

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║     Manual EC2 Setup for Blue/Green Deployment               ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# Get AWS Account ID and Region from instance metadata
AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" -s)
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "704654299291")
ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/blue-green/app"

echo "AWS Region: $AWS_REGION"
echo "AWS Account: $AWS_ACCOUNT_ID"
echo "ECR URI: $ECR_URI"
echo ""

echo "==> [1/8] Installing Docker..."
sudo dnf install -y docker || sudo yum install -y docker || {
    echo "Trying alternative Docker installation..."
    sudo amazon-linux-extras install -y docker 2>/dev/null || true
}
echo "✓ Docker installed"

echo ""
echo "==> [2/8] Starting Docker service..."
sudo systemctl start docker
sudo systemctl enable docker
echo "✓ Docker service started"

echo ""
echo "==> [3/8] Installing Docker Compose..."
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
docker-compose --version
echo "✓ Docker Compose installed"

echo ""
echo "==> [4/8] Logging into Amazon ECR..."
aws ecr get-login-password --region ${AWS_REGION} | sudo docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
echo "✓ Logged into ECR"

echo ""
echo "==> [5/8] Cloning repository..."
cd /opt
if [ -d "blue-green-deployment-strategy" ]; then
    echo "Repository exists, pulling latest..."
    cd blue-green-deployment-strategy
    sudo git pull
else
    sudo git clone https://github.com/baydre/blue-green-deployment-strategy.git
    cd blue-green-deployment-strategy
fi
echo "✓ Repository cloned"

echo ""
echo "==> [6/8] Creating .env file with ECR images..."
sudo tee .env > /dev/null <<EOF
# Active pool configuration
ACTIVE_POOL=blue

# ECR Image references
BLUE_IMAGE=${ECR_URI}:blue
GREEN_IMAGE=${ECR_URI}:green

# Release identifiers
RELEASE_ID_BLUE=v1.0.1-blue
RELEASE_ID_GREEN=v1.1.0-green

# Nginx image
NGINX_IMAGE=nginx:latest
EOF
echo "✓ .env file created"

echo ""
echo "==> [7/8] Pulling Docker images from ECR..."
sudo docker pull ${ECR_URI}:blue
sudo docker pull ${ECR_URI}:green
sudo docker pull nginx:latest
echo "✓ Images pulled"

echo ""
echo "==> [8/8] Starting Docker Compose stack..."
sudo docker-compose up -d
echo "✓ Stack started"

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║              ✓ Setup Complete!                                ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "Checking services..."
sleep 5
sudo docker-compose ps
echo ""
echo "Testing endpoint..."
sleep 3
curl -i http://localhost:8080/version || echo "App starting up, wait a moment..."
echo ""
echo "Public IP: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
echo ""
echo "Access the application:"
echo "  http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8080/version"
echo ""
echo "View logs:"
echo "  sudo docker-compose logs -f"
