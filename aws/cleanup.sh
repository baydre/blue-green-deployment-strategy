#!/bin/bash
# Cleanup AWS resources for Blue/Green deployment
# Usage: ./aws/cleanup.sh [--force]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

FORCE=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --force)
            FORCE=true
            shift
            ;;
        --help)
            echo "Usage: $0 [--force]"
            echo ""
            echo "Options:"
            echo "  --force    Skip confirmation prompts"
            echo "  --help     Show this help message"
            exit 0
            ;;
    esac
done

echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║        Cleanup AWS Resources for Blue/Green Deployment       ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Load instance details if available
if [ -f "aws/instance-details.env" ]; then
    source aws/instance-details.env
    echo -e "${CYAN}Found instance details:${NC}"
    echo "  Instance ID: $INSTANCE_ID"
    echo "  Region: $REGION"
    echo "  Public IP: $PUBLIC_IP"
    echo ""
else
    echo -e "${YELLOW}⚠ No instance-details.env found. Will search for resources.${NC}"
    REGION="us-east-1"
    echo ""
fi

# Confirm deletion
if [ "$FORCE" = false ]; then
    echo -e "${YELLOW}⚠ WARNING: This will delete the following resources:${NC}"
    echo "  • EC2 instance(s) tagged with 'blue-green-deployment'"
    echo "  • Security group 'blue-green-sg'"
    echo "  • ECR repository 'blue-green/app'"
    echo "  • IAM role 'BlueGreenEC2ECRRole'"
    echo "  • IAM instance profile 'BlueGreenEC2ECRRole'"
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo -e "${YELLOW}Cleanup cancelled.${NC}"
        exit 0
    fi
    echo ""
fi

# Step 1: Terminate EC2 instances
echo -e "${CYAN}==> Step 1: Terminating EC2 instances...${NC}"

if [ -n "$INSTANCE_ID" ]; then
    # Terminate specific instance
    aws ec2 terminate-instances \
        --instance-ids $INSTANCE_ID \
        --region $REGION >/dev/null 2>&1 || true
    echo -e "${GREEN}✓ Terminated instance: $INSTANCE_ID${NC}"
else
    # Find and terminate instances by tag
    INSTANCE_IDS=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=blue-green-deployment" \
                  "Name=instance-state-name,Values=running,stopped,stopping" \
        --query 'Reservations[*].Instances[*].InstanceId' \
        --output text \
        --region $REGION)
    
    if [ -n "$INSTANCE_IDS" ]; then
        aws ec2 terminate-instances \
            --instance-ids $INSTANCE_IDS \
            --region $REGION >/dev/null 2>&1 || true
        echo -e "${GREEN}✓ Terminated instances: $INSTANCE_IDS${NC}"
    else
        echo -e "${YELLOW}⚠ No running instances found${NC}"
    fi
fi

# Wait for termination
if [ -n "$INSTANCE_ID" ]; then
    echo -e "${CYAN}Waiting for instance termination...${NC}"
    aws ec2 wait instance-terminated \
        --instance-ids $INSTANCE_ID \
        --region $REGION 2>/dev/null || true
    echo -e "${GREEN}✓ Instance terminated${NC}"
fi

sleep 5

# Step 2: Delete security group
echo -e "${CYAN}==> Step 2: Deleting security group...${NC}"

if [ -n "$SECURITY_GROUP_ID" ]; then
    SG_ID=$SECURITY_GROUP_ID
else
    SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=blue-green-sg" \
        --query 'SecurityGroups[0].GroupId' \
        --output text \
        --region $REGION 2>/dev/null)
fi

if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
    aws ec2 delete-security-group \
        --group-id $SG_ID \
        --region $REGION 2>/dev/null || \
        echo -e "${YELLOW}⚠ Could not delete security group (may still be in use)${NC}"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Security group deleted: $SG_ID${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Security group not found${NC}"
fi

# Step 3: Delete ECR repository
echo -e "${CYAN}==> Step 3: Deleting ECR repository...${NC}"

if aws ecr describe-repositories --repository-names blue-green/app --region $REGION >/dev/null 2>&1; then
    aws ecr delete-repository \
        --repository-name blue-green/app \
        --force \
        --region $REGION >/dev/null 2>&1 || true
    echo -e "${GREEN}✓ ECR repository deleted: blue-green/app${NC}"
else
    echo -e "${YELLOW}⚠ ECR repository not found${NC}"
fi

# Step 4: Delete IAM resources
echo -e "${CYAN}==> Step 4: Deleting IAM resources...${NC}"

ROLE_NAME="BlueGreenEC2ECRRole"
INSTANCE_PROFILE_NAME="BlueGreenEC2ECRRole"

# Remove role from instance profile
if aws iam get-instance-profile --instance-profile-name $INSTANCE_PROFILE_NAME >/dev/null 2>&1; then
    aws iam remove-role-from-instance-profile \
        --instance-profile-name $INSTANCE_PROFILE_NAME \
        --role-name $ROLE_NAME 2>/dev/null || true
    echo -e "${GREEN}✓ Removed role from instance profile${NC}"
fi

# Delete instance profile
if aws iam get-instance-profile --instance-profile-name $INSTANCE_PROFILE_NAME >/dev/null 2>&1; then
    aws iam delete-instance-profile \
        --instance-profile-name $INSTANCE_PROFILE_NAME 2>/dev/null || true
    echo -e "${GREEN}✓ Instance profile deleted${NC}"
fi

# Delete role policy
if aws iam get-role --role-name $ROLE_NAME >/dev/null 2>&1; then
    aws iam delete-role-policy \
        --role-name $ROLE_NAME \
        --policy-name ECRAccessPolicy 2>/dev/null || true
    echo -e "${GREEN}✓ Role policy deleted${NC}"
fi

# Delete role
if aws iam get-role --role-name $ROLE_NAME >/dev/null 2>&1; then
    aws iam delete-role \
        --role-name $ROLE_NAME 2>/dev/null || true
    echo -e "${GREEN}✓ IAM role deleted${NC}"
fi

# Step 5: Clean up local files
echo -e "${CYAN}==> Step 5: Cleaning up local configuration files...${NC}"

rm -f aws/instance-details.env
rm -f aws/config.env

echo -e "${GREEN}✓ Local files cleaned${NC}"

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           ✓ Cleanup Completed Successfully!                  ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Resources removed:${NC}"
echo "  ✓ EC2 instance(s)"
echo "  ✓ Security group"
echo "  ✓ ECR repository"
echo "  ✓ IAM role and instance profile"
echo "  ✓ Local configuration files"
echo ""
echo -e "${YELLOW}Note:${NC} EBS volumes are automatically deleted with instance termination"
echo ""
