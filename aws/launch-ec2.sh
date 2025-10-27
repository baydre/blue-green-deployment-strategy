#!/bin/bash
# Launch EC2 instance with Blue/Green deployment
# Usage: ./aws/launch-ec2.sh [region] [instance-type] [key-name]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
REGION="${1:-us-east-1}"
INSTANCE_TYPE="${2:-t3.medium}"
KEY_NAME="${3}"
SG_NAME="blue-green-sg"
INSTANCE_PROFILE="BlueGreenEC2ECRRole"

echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║        Launch EC2 Instance for Blue/Green Deployment         ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Validate key pair
if [ -z "$KEY_NAME" ]; then
    echo -e "${RED}✗ SSH key pair name is required${NC}"
    echo ""
    echo -e "${YELLOW}Usage:${NC} $0 [region] [instance-type] [key-name]"
    echo ""
    echo -e "${YELLOW}Available key pairs in $REGION:${NC}"
    aws ec2 describe-key-pairs --region $REGION --query 'KeyPairs[*].KeyName' --output table
    echo ""
    exit 1
fi

# Verify key pair exists
if ! aws ec2 describe-key-pairs --key-names $KEY_NAME --region $REGION >/dev/null 2>&1; then
    echo -e "${RED}✗ Key pair '$KEY_NAME' not found in region $REGION${NC}"
    echo ""
    echo -e "${YELLOW}Available key pairs:${NC}"
    aws ec2 describe-key-pairs --region $REGION --query 'KeyPairs[*].KeyName' --output table
    exit 1
fi

echo -e "${GREEN}✓ Configuration:${NC}"
echo "  Region: $REGION"
echo "  Instance Type: $INSTANCE_TYPE"
echo "  Key Pair: $KEY_NAME"
echo ""

# Step 1: Get default VPC
echo -e "${CYAN}==> Step 1: Getting default VPC...${NC}"
VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=isDefault,Values=true" \
    --query 'Vpcs[0].VpcId' \
    --output text \
    --region $REGION)

if [ "$VPC_ID" == "None" ] || [ -z "$VPC_ID" ]; then
    echo -e "${RED}✗ No default VPC found in region $REGION${NC}"
    exit 1
fi

echo -e "${GREEN}✓ VPC ID: $VPC_ID${NC}"

# Step 2: Create security group
echo -e "${CYAN}==> Step 2: Creating security group...${NC}"

# Check if security group exists
SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=$SG_NAME" \
    --query 'SecurityGroups[0].GroupId' \
    --output text \
    --region $REGION 2>/dev/null)

if [ "$SG_ID" == "None" ] || [ -z "$SG_ID" ]; then
    # Create security group
    SG_ID=$(aws ec2 create-security-group \
        --group-name $SG_NAME \
        --description "Security group for Blue/Green deployment" \
        --vpc-id $VPC_ID \
        --region $REGION \
        --output text)
    
    echo -e "${GREEN}✓ Security group created: $SG_ID${NC}"
    
    # Wait a moment for security group to be ready
    sleep 2
    
    # Add rules
    echo -e "${CYAN}==> Adding security group rules...${NC}"
    
    # Allow HTTP (port 8080)
    aws ec2 authorize-security-group-ingress \
        --group-id $SG_ID \
        --protocol tcp \
        --port 8080 \
        --cidr 0.0.0.0/0 \
        --region $REGION 2>/dev/null || true
    echo -e "${GREEN}✓ Allowed HTTP (port 8080) from anywhere${NC}"
    
    # Allow HTTPS (port 443) for future use
    aws ec2 authorize-security-group-ingress \
        --group-id $SG_ID \
        --protocol tcp \
        --port 443 \
        --cidr 0.0.0.0/0 \
        --region $REGION 2>/dev/null || true
    echo -e "${GREEN}✓ Allowed HTTPS (port 443) from anywhere${NC}"
    
    # Allow SSH from current IP
    CURRENT_IP=$(curl -s ifconfig.me)
    aws ec2 authorize-security-group-ingress \
        --group-id $SG_ID \
        --protocol tcp \
        --port 22 \
        --cidr ${CURRENT_IP}/32 \
        --region $REGION 2>/dev/null || true
    echo -e "${GREEN}✓ Allowed SSH (port 22) from $CURRENT_IP${NC}"
else
    echo -e "${YELLOW}⚠ Security group already exists: $SG_ID${NC}"
fi

# Step 3: Get latest Amazon Linux 2023 AMI
echo -e "${CYAN}==> Step 3: Finding latest Amazon Linux 2023 AMI...${NC}"
AMI_ID=$(aws ec2 describe-images \
    --owners amazon \
    --filters "Name=name,Values=al2023-ami-2023.*-x86_64" \
              "Name=state,Values=available" \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
    --output text \
    --region $REGION)

if [ -z "$AMI_ID" ] || [ "$AMI_ID" == "None" ]; then
    echo -e "${RED}✗ Failed to find Amazon Linux 2023 AMI${NC}"
    exit 1
fi

echo -e "${GREEN}✓ AMI ID: $AMI_ID${NC}"

# Step 4: Verify IAM instance profile exists
echo -e "${CYAN}==> Step 4: Verifying IAM instance profile...${NC}"
if aws iam get-instance-profile --instance-profile-name $INSTANCE_PROFILE >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Instance profile exists: $INSTANCE_PROFILE${NC}"
else
    echo -e "${RED}✗ Instance profile not found: $INSTANCE_PROFILE${NC}"
    echo -e "${YELLOW}Run: ./aws/create-iam-role.sh${NC}"
    exit 1
fi

# Step 5: Launch EC2 instance
echo -e "${CYAN}==> Step 5: Launching EC2 instance...${NC}"

INSTANCE_ID=$(aws ec2 run-instances \
    --image-id $AMI_ID \
    --instance-type $INSTANCE_TYPE \
    --key-name $KEY_NAME \
    --security-group-ids $SG_ID \
    --iam-instance-profile Name=$INSTANCE_PROFILE \
    --user-data file://aws/ec2-user-data.sh \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=blue-green-deployment},{Key=Environment,Value=production},{Key=ManagedBy,Value=blue-green-script}]" \
    --region $REGION \
    --output text \
    --query 'Instances[0].InstanceId')

if [ -z "$INSTANCE_ID" ]; then
    echo -e "${RED}✗ Failed to launch instance${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Instance launched: $INSTANCE_ID${NC}"

# Step 6: Wait for instance to be running
echo -e "${CYAN}==> Step 6: Waiting for instance to start...${NC}"
aws ec2 wait instance-running \
    --instance-ids $INSTANCE_ID \
    --region $REGION

echo -e "${GREEN}✓ Instance is running${NC}"

# Step 7: Get public IP
PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text \
    --region $REGION)

echo -e "${GREEN}✓ Public IP: $PUBLIC_IP${NC}"

# Save instance details
cat > aws/instance-details.env << EOF
INSTANCE_ID=$INSTANCE_ID
PUBLIC_IP=$PUBLIC_IP
REGION=$REGION
KEY_NAME=$KEY_NAME
SECURITY_GROUP_ID=$SG_ID
AMI_ID=$AMI_ID
INSTANCE_TYPE=$INSTANCE_TYPE
LAUNCHED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           ✓ EC2 Instance Launched Successfully!              ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Instance Details:${NC}"
echo "  Instance ID:  $INSTANCE_ID"
echo "  Public IP:    $PUBLIC_IP"
echo "  Region:       $REGION"
echo "  Type:         $INSTANCE_TYPE"
echo "  AMI:          $AMI_ID"
echo "  Key Pair:     $KEY_NAME"
echo ""
echo -e "${CYAN}Access Information:${NC}"
echo "  Application:  http://$PUBLIC_IP:8080"
echo "  Health:       http://$PUBLIC_IP:8080/health"
echo "  SSH:          ssh -i ~/.ssh/$KEY_NAME.pem ec2-user@$PUBLIC_IP"
echo ""
echo -e "${YELLOW}⏳ Setup in Progress:${NC}"
echo "  The user-data script is installing Docker, pulling images,"
echo "  and starting the application. This takes ~3-5 minutes."
echo ""
echo -e "${CYAN}Monitor Setup Progress:${NC}"
echo "  ssh -i ~/.ssh/$KEY_NAME.pem ec2-user@$PUBLIC_IP"
echo "  sudo tail -f /var/log/blue-green-setup.log"
echo ""
echo -e "${CYAN}Verify Deployment:${NC}"
echo "  # Wait 5 minutes, then test:"
echo "  curl http://$PUBLIC_IP:8080/"
echo "  curl http://$PUBLIC_IP:8080/health"
echo ""
echo -e "${CYAN}Access Application:${NC}"
echo "  # SSH into instance:"
echo "  ssh -i ~/.ssh/$KEY_NAME.pem ec2-user@$PUBLIC_IP"
echo ""
echo "  # Check services:"
echo "  cd /opt/blue-green-deployment-strategy"
echo "  docker compose ps"
echo ""
echo "  # View logs:"
echo "  docker compose logs -f"
echo ""
echo "  # Test failover:"
echo "  ./verify-failover.sh"
echo ""
echo -e "${GREEN}✓ Instance details saved to: aws/instance-details.env${NC}"
echo ""
