# AWS EC2 Deployment

Quick deployment of the Blue/Green strategy to AWS EC2 with manual setup.

## 🚀 Quick Start

### Prerequisites
- AWS Account configured (`aws configure`)
- Docker installed locally

### One-Command Deployment

```bash
# From project root
./deploy-to-aws.sh
```

This will:
1. Push images to ECR
2. Launch EC2 instance
3. Provide SSH command for manual setup

### Manual Steps

**Step 1: Push to ECR**
```bash
./aws/push-to-ecr.sh
```

**Step 2: Launch EC2**
```bash
cd aws
./quick-deploy.sh
```

**Step 3: Run Setup on EC2**
```bash
# Use the SSH command from step 2 output
ssh -i blue-green-key.pem ec2-user@<PUBLIC_IP>
bash manual-setup.sh
```

## 📝 Scripts

- `push-to-ecr.sh` - Build and push Docker images to ECR
- `quick-deploy.sh` - Launch EC2 instance (no user-data)
- `manual-setup.sh` - Run on EC2 to install Docker, pull images, start services
- `create-iam-role.sh` - Create IAM role for ECR access
- `cleanup.sh` - Remove all AWS resources

## 🧹 Cleanup

```bash
./aws/cleanup.sh
```

Removes: EC2, Security Group, IAM Role, ECR Repository

## 💰 Estimated Cost

- t3.micro: ~$7/month
- ECR storage: ~$0.10/month

See [../DEPLOY.md](../DEPLOY.md) for detailed deployment guide.
