#!/bin/bash
# Quick EC2 Launch Script (Manual Setup)
# This launches an EC2 instance WITHOUT user-data for manual configuration

set -e

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║     Quick EC2 Launch for Manual Setup                        ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# Configuration
AWS_REGION="${AWS_REGION:-eu-north-1}"
INSTANCE_TYPE="t3.micro"
KEY_NAME="${KEY_NAME:-blue-green-key}"

echo "Configuration:"
echo "  Region: $AWS_REGION"
echo "  Instance Type: $INSTANCE_TYPE"
echo "  Key Pair: $KEY_NAME"
echo ""

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ Error: AWS CLI not configured"
    echo "Run: aws configure"
    exit 1
fi

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "✓ AWS Account: $AWS_ACCOUNT_ID"

# Check if key pair exists
echo ""
echo "==> [1/6] Checking SSH key pair..."
if ! aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$AWS_REGION" &> /dev/null; then
    echo "Creating new key pair: $KEY_NAME"
    aws ec2 create-key-pair \
        --key-name "$KEY_NAME" \
        --region "$AWS_REGION" \
        --query 'KeyMaterial' \
        --output text > "${KEY_NAME}.pem"
    chmod 400 "${KEY_NAME}.pem"
    echo "✓ Key pair created and saved to ${KEY_NAME}.pem"
else
    echo "✓ Key pair exists: $KEY_NAME"
    if [ ! -f "${KEY_NAME}.pem" ]; then
        echo "⚠️  Warning: ${KEY_NAME}.pem not found locally"
        echo "   Make sure you have the private key file!"
    fi
fi

# Create/check IAM role
echo ""
echo "==> [2/6] Setting up IAM role..."
ROLE_NAME="BlueGreenEC2ECRRole"

if ! aws iam get-role --role-name "$ROLE_NAME" &> /dev/null; then
    echo "Creating IAM role..."
    cd "$(dirname "$0")"
    ./create-iam-role.sh
    cd - > /dev/null
else
    echo "✓ IAM role exists: $ROLE_NAME"
fi

# Get default VPC and subnet
echo ""
echo "==> [3/6] Getting VPC and subnet..."
VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=isDefault,Values=true" \
    --region "$AWS_REGION" \
    --query 'Vpcs[0].VpcId' \
    --output text)

SUBNET_ID=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --region "$AWS_REGION" \
    --query 'Subnets[0].SubnetId' \
    --output text)

echo "✓ VPC: $VPC_ID"
echo "✓ Subnet: $SUBNET_ID"

# Create security group
echo ""
echo "==> [4/6] Setting up security group..."
SG_NAME="blue-green-sg"

# Check if security group exists
SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC_ID" \
    --region "$AWS_REGION" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null || echo "")

if [ "$SG_ID" = "None" ] || [ -z "$SG_ID" ]; then
    echo "Creating security group..."
    SG_ID=$(aws ec2 create-security-group \
        --group-name "$SG_NAME" \
        --description "Security group for Blue/Green deployment" \
        --vpc-id "$VPC_ID" \
        --region "$AWS_REGION" \
        --query 'GroupId' \
        --output text)
    
    # Add rules
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port 22 \
        --cidr 0.0.0.0/0 \
        --region "$AWS_REGION"
    
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port 8080 \
        --cidr 0.0.0.0/0 \
        --region "$AWS_REGION"
    
    echo "✓ Security group created: $SG_ID"
else
    echo "✓ Security group exists: $SG_ID"
fi

# Get latest Amazon Linux 2023 AMI
echo ""
echo "==> [5/6] Getting latest AMI..."
AMI_ID=$(aws ec2 describe-images \
    --owners amazon \
    --filters "Name=name,Values=al2023-ami-2023*-x86_64" \
              "Name=state,Values=available" \
    --region "$AWS_REGION" \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
    --output text)

echo "✓ AMI: $AMI_ID"

# Launch EC2 instance
echo ""
echo "==> [6/6] Launching EC2 instance..."
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SG_ID" \
    --subnet-id "$SUBNET_ID" \
    --iam-instance-profile "Name=$ROLE_NAME" \
    --region "$AWS_REGION" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=blue-green-deployment},{Key=Project,Value=blue-green}]" \
    --query 'Instances[0].InstanceId' \
    --output text)

echo "✓ Instance launching: $INSTANCE_ID"

# Wait for instance to be running
echo ""
echo "Waiting for instance to be running..."
aws ec2 wait instance-running \
    --instance-ids "$INSTANCE_ID" \
    --region "$AWS_REGION"

# Get public IP
PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$AWS_REGION" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║              ✓ EC2 Instance Launched!                        ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "Instance Details:"
echo "  Instance ID: $INSTANCE_ID"
echo "  Public IP: $PUBLIC_IP"
echo "  Region: $AWS_REGION"
echo "  SSH Key: ${KEY_NAME}.pem"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "                 NEXT STEPS - MANUAL SETUP"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "1. Wait ~30 seconds for instance initialization"
echo ""
echo "2. SSH into the instance:"
echo "   ssh -i ${KEY_NAME}.pem ec2-user@${PUBLIC_IP}"
echo ""
echo "3. Run the setup script on the EC2 instance:"
echo "   bash <(curl -s https://raw.githubusercontent.com/baydre/blue-green-deployment-strategy/main/aws/manual-setup.sh)"
echo ""
echo "   OR copy the script manually:"
echo "   scp -i ${KEY_NAME}.pem aws/manual-setup.sh ec2-user@${PUBLIC_IP}:~/"
echo "   ssh -i ${KEY_NAME}.pem ec2-user@${PUBLIC_IP}"
echo "   bash manual-setup.sh"
echo ""
echo "4. After setup completes, access your application:"
echo "   http://${PUBLIC_IP}:8080/version"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Instance connection info saved to: ec2-connection.txt"

# Save connection info
cat > ec2-connection.txt <<EOF
EC2 Instance Connection Details
================================

Instance ID: $INSTANCE_ID
Public IP: $PUBLIC_IP
Region: $AWS_REGION
SSH Key: ${KEY_NAME}.pem

SSH Command:
ssh -i ${KEY_NAME}.pem ec2-user@${PUBLIC_IP}

Application URL:
http://${PUBLIC_IP}:8080/version

Quick Setup:
ssh -i ${KEY_NAME}.pem ec2-user@${PUBLIC_IP} 'bash <(curl -s https://raw.githubusercontent.com/baydre/blue-green-deployment-strategy/main/aws/manual-setup.sh)'

Manual Setup (if above fails):
1. scp -i ${KEY_NAME}.pem aws/manual-setup.sh ec2-user@${PUBLIC_IP}:~/
2. ssh -i ${KEY_NAME}.pem ec2-user@${PUBLIC_IP}
3. bash manual-setup.sh
EOF

echo "Quick setup command (run after ~30 seconds):"
echo ""
echo "ssh -i ${KEY_NAME}.pem ec2-user@${PUBLIC_IP} 'bash <(curl -s https://raw.githubusercontent.com/baydre/blue-green-deployment-strategy/main/aws/manual-setup.sh)'"
echo ""
