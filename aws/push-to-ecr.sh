#!/bin/bash
# Push Docker images to Amazon ECR
# Usage: ./aws/push-to-ecr.sh [region]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
REGION="${1:-us-east-1}"
REPOSITORY_NAME="blue-green/app"
APP_VERSION="v1.0.0"

echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║        Push Docker Images to Amazon ECR                       ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Step 1: Get AWS Account ID
echo -e "${CYAN}==> Step 1: Getting AWS Account ID...${NC}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)

if [ -z "$AWS_ACCOUNT_ID" ]; then
    echo -e "${RED}✗ Failed to get AWS Account ID. Is AWS CLI configured?${NC}"
    echo -e "${YELLOW}Run: aws configure${NC}"
    exit 1
fi

echo -e "${GREEN}✓ AWS Account ID: $AWS_ACCOUNT_ID${NC}"
echo -e "${GREEN}✓ Region: $REGION${NC}"
echo ""

# Construct ECR URI
ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
FULL_REPO_URI="${ECR_URI}/${REPOSITORY_NAME}"

# Step 2: Create ECR repository if it doesn't exist
echo -e "${CYAN}==> Step 2: Checking ECR repository...${NC}"
if aws ecr describe-repositories --repository-names $REPOSITORY_NAME --region $REGION >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Repository already exists: $REPOSITORY_NAME${NC}"
else
    echo -e "${YELLOW}Creating ECR repository: $REPOSITORY_NAME${NC}"
    aws ecr create-repository \
        --repository-name $REPOSITORY_NAME \
        --image-scanning-configuration scanOnPush=true \
        --region $REGION \
        --output json > /dev/null
    
    echo -e "${GREEN}✓ Repository created${NC}"
fi
echo ""

# Step 3: Login to ECR
echo -e "${CYAN}==> Step 3: Logging into ECR...${NC}"
aws ecr get-login-password --region $REGION | \
    docker login --username AWS --password-stdin $ECR_URI

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully logged into ECR${NC}"
else
    echo -e "${RED}✗ Failed to login to ECR${NC}"
    exit 1
fi
echo ""

# Step 4: Build the application image
echo -e "${CYAN}==> Step 4: Building application image...${NC}"
cd "$(dirname "$0")/.."

if [ ! -f "app/Dockerfile" ]; then
    echo -e "${RED}✗ app/Dockerfile not found${NC}"
    exit 1
fi

docker build -t blue-green-app:latest ./app

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Image built successfully${NC}"
else
    echo -e "${RED}✗ Failed to build image${NC}"
    exit 1
fi
echo ""

# Step 5: Tag images
echo -e "${CYAN}==> Step 5: Tagging images for ECR...${NC}"

# Tag with version
docker tag blue-green-app:latest ${FULL_REPO_URI}:${APP_VERSION}
echo -e "${GREEN}✓ Tagged: ${FULL_REPO_URI}:${APP_VERSION}${NC}"

# Tag as 'latest'
docker tag blue-green-app:latest ${FULL_REPO_URI}:latest
echo -e "${GREEN}✓ Tagged: ${FULL_REPO_URI}:latest${NC}"

# Tag as 'blue' (for initial deployment)
docker tag blue-green-app:latest ${FULL_REPO_URI}:blue
echo -e "${GREEN}✓ Tagged: ${FULL_REPO_URI}:blue${NC}"

# Tag as 'green' (for initial deployment)
docker tag blue-green-app:latest ${FULL_REPO_URI}:green
echo -e "${GREEN}✓ Tagged: ${FULL_REPO_URI}:green${NC}"

echo ""

# Step 6: Push images to ECR
echo -e "${CYAN}==> Step 6: Pushing images to ECR...${NC}"

echo -e "${YELLOW}Pushing ${APP_VERSION}...${NC}"
docker push ${FULL_REPO_URI}:${APP_VERSION}

echo -e "${YELLOW}Pushing latest...${NC}"
docker push ${FULL_REPO_URI}:latest

echo -e "${YELLOW}Pushing blue...${NC}"
docker push ${FULL_REPO_URI}:blue

echo -e "${YELLOW}Pushing green...${NC}"
docker push ${FULL_REPO_URI}:green

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           ✓ Images Successfully Pushed to ECR!                ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Repository:${NC} ${FULL_REPO_URI}"
echo -e "${CYAN}Tags pushed:${NC}"
echo "  - ${APP_VERSION}"
echo "  - latest"
echo "  - blue"
echo "  - green"
echo ""
echo -e "${CYAN}Next steps:${NC}"
echo "  1. Create IAM role: ./aws/create-iam-role.sh"
echo "  2. Launch EC2: ./aws/launch-ec2.sh"
echo ""

# Save config for other scripts
cat > aws/config.env << EOF
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
REGION=${REGION}
ECR_URI=${ECR_URI}
REPOSITORY_NAME=${REPOSITORY_NAME}
FULL_REPO_URI=${FULL_REPO_URI}
APP_VERSION=${APP_VERSION}
EOF

echo -e "${GREEN}✓ Configuration saved to aws/config.env${NC}"
