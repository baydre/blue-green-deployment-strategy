#!/bin/bash
# Create IAM role for EC2 to access ECR
# Usage: ./aws/create-iam-role.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ROLE_NAME="BlueGreenEC2ECRRole"
INSTANCE_PROFILE_NAME="BlueGreenEC2ECRRole"

echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║        Create IAM Role for EC2 ECR Access                    ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Step 1: Create trust policy
echo -e "${CYAN}==> Step 1: Creating IAM trust policy...${NC}"
cat > /tmp/iam-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
echo -e "${GREEN}✓ Trust policy created${NC}"

# Step 2: Create ECR access policy
echo -e "${CYAN}==> Step 2: Creating ECR access policy...${NC}"
cat > /tmp/iam-ecr-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:DescribeRepositories",
        "ecr:ListImages"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
EOF
echo -e "${GREEN}✓ ECR policy created${NC}"
echo ""

# Step 3: Create IAM role
echo -e "${CYAN}==> Step 3: Creating IAM role...${NC}"
if aws iam get-role --role-name $ROLE_NAME >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠ Role already exists: $ROLE_NAME${NC}"
else
    aws iam create-role \
        --role-name $ROLE_NAME \
        --assume-role-policy-document file:///tmp/iam-trust-policy.json \
        --description "Allows EC2 instances to access ECR for Blue/Green deployment" \
        --output json > /dev/null
    
    echo -e "${GREEN}✓ IAM role created: $ROLE_NAME${NC}"
fi

# Step 4: Attach policy to role
echo -e "${CYAN}==> Step 4: Attaching ECR policy to role...${NC}"
aws iam put-role-policy \
    --role-name $ROLE_NAME \
    --policy-name ECRAccessPolicy \
    --policy-document file:///tmp/iam-ecr-policy.json

echo -e "${GREEN}✓ Policy attached${NC}"

# Step 5: Create instance profile
echo -e "${CYAN}==> Step 5: Creating instance profile...${NC}"
if aws iam get-instance-profile --instance-profile-name $INSTANCE_PROFILE_NAME >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠ Instance profile already exists: $INSTANCE_PROFILE_NAME${NC}"
else
    aws iam create-instance-profile \
        --instance-profile-name $INSTANCE_PROFILE_NAME \
        --output json > /dev/null
    
    echo -e "${GREEN}✓ Instance profile created${NC}"
fi

# Step 6: Add role to instance profile
echo -e "${CYAN}==> Step 6: Adding role to instance profile...${NC}"
if aws iam get-instance-profile --instance-profile-name $INSTANCE_PROFILE_NAME | grep -q $ROLE_NAME; then
    echo -e "${YELLOW}⚠ Role already added to instance profile${NC}"
else
    aws iam add-role-to-instance-profile \
        --instance-profile-name $INSTANCE_PROFILE_NAME \
        --role-name $ROLE_NAME
    
    echo -e "${GREEN}✓ Role added to instance profile${NC}"
fi

# Cleanup temp files
rm -f /tmp/iam-trust-policy.json /tmp/iam-ecr-policy.json

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           ✓ IAM Role Created Successfully!                    ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Role Name:${NC} $ROLE_NAME"
echo -e "${CYAN}Instance Profile:${NC} $INSTANCE_PROFILE_NAME"
echo ""
echo -e "${CYAN}Permissions granted:${NC}"
echo "  ✓ ECR repository access (pull images)"
echo "  ✓ CloudWatch Logs (write logs)"
echo ""
echo -e "${CYAN}Next step:${NC}"
echo "  Launch EC2 instance: ./aws/launch-ec2.sh"
echo ""
