#!/bin/bash
# Master AWS Deployment Script
# This orchestrates the entire deployment process

set -e

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     AWS EC2 Deployment - Blue/Green Strategy                 ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Step 1: Push images to ECR
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}STEP 1: Pushing Docker Images to ECR${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
./aws/push-to-ecr.sh

echo ""
echo -e "${GREEN}✓ Step 1 Complete - Images in ECR${NC}"
echo ""
read -p "Press Enter to continue to Step 2 (Launch EC2)..."

# Step 2: Launch EC2
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}STEP 2: Launching EC2 Instance${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
./aws/quick-deploy.sh

echo ""
echo -e "${GREEN}✓ Step 2 Complete - EC2 Instance Running${NC}"
echo ""
echo -e "${YELLOW}════════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}                  MANUAL STEP REQUIRED${NC}"
echo -e "${YELLOW}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Next steps:"
echo ""
echo "1. Wait 30-60 seconds for instance to fully initialize"
echo ""
echo "2. Check aws/ec2-connection.txt for your connection details:"
cat aws/ec2-connection.txt | grep "Public IP"
echo ""
echo "3. Run the setup command from aws/ec2-connection.txt"
echo "   (It will be a long 'ssh ... bash <(curl ...)' command)"
echo ""
echo "4. Once setup completes, test your deployment:"
PUBLIC_IP=$(cat aws/ec2-connection.txt | grep "Public IP:" | cut -d' ' -f3)
echo "   curl http://${PUBLIC_IP}:8080/version"
echo ""
echo -e "${GREEN}Deployment process initiated successfully!${NC}"
echo ""
