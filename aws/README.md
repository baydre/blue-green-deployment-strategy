# AWS EC2 Deployment Guide

Quick deployment of the Blue/Green strategy to AWS EC2.

## 📋 Prerequisites

- AWS Account with appropriate permissions
- AWS CLI installed and configured (`aws configure`)
- SSH key pair created in your AWS region
- Docker installed locally (for building images)

## 🚀 Quick Deployment

### Step 1: Push Images to ECR

```bash
# Make scripts executable
chmod +x aws/*.sh

# Push Docker images to Amazon ECR
./aws/push-to-ecr.sh us-east-1
```

This will:
- Create ECR repository `blue-green/app`
- Build your application image
- Tag as `blue`, `green`, `latest`, and `v1.0.0`
- Push all tags to ECR

### Step 2: Create IAM Role

```bash
# Create IAM role for EC2 to access ECR
./aws/create-iam-role.sh
```

This creates:
- IAM role: `BlueGreenEC2ECRRole`
- Permissions: ECR pull access, CloudWatch Logs
- Instance profile for EC2

### Step 3: Launch EC2 Instance

```bash
# Replace 'your-key-pair' with your actual SSH key pair name
./aws/launch-ec2.sh us-east-1 t3.medium your-key-pair
```

This will:
- Create security group with ports 8080, 443, and 22
- Launch t3.medium instance with Amazon Linux 2023
- Run user-data script to install Docker & Docker Compose
- Clone your repository
- Pull images from ECR
- Start the Blue/Green stack

**Setup Time:** ~3-5 minutes

### Step 4: Verify Deployment

```bash
# Get the public IP from the output, then test:
PUBLIC_IP="<your-ec2-public-ip>"

# Wait 5 minutes for setup to complete, then:
curl http://$PUBLIC_IP:8080/
curl http://$PUBLIC_IP:8080/health
```

Expected output:
```
HTTP/1.1 200 OK
X-App-Pool: blue
X-Release-Id: v1.0.0-blue
```

---

## 🔧 Managing Your Deployment

### SSH into Instance

```bash
ssh -i ~/.ssh/your-key-pair.pem ec2-user@<public-ip>
```

### Check Services

```bash
cd /opt/blue-green-deployment-strategy

# View running services
docker compose ps

# View logs
docker compose logs -f

# View setup log
sudo tail -f /var/log/blue-green-setup.log
```

### Test Failover

```bash
cd /opt/blue-green-deployment-strategy

# Run automated failover test
./verify-failover.sh
```

### Toggle Active Pool

```bash
cd /opt/blue-green-deployment-strategy

# Switch to green pool
make pool-toggle

# Or use rollback script
./rollback.sh --to=green
```

### Deploy New Version

```bash
# On your local machine:
# 1. Build new version
docker build -t blue-green-app:v1.1.0 ./app

# 2. Push to ECR
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPO="${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/blue-green/app"

aws ecr get-login-password --region us-east-1 | \
    docker login --username AWS --password-stdin $ECR_REPO

docker tag blue-green-app:v1.1.0 ${ECR_REPO}:v1.1.0
docker tag blue-green-app:v1.1.0 ${ECR_REPO}:green
docker push ${ECR_REPO}:v1.1.0
docker push ${ECR_REPO}:green

# 3. On EC2 instance:
ssh -i ~/.ssh/your-key.pem ec2-user@<public-ip>
cd /opt/blue-green-deployment-strategy

# Pull new image
docker compose pull app_green

# Restart green with new version
docker compose up -d app_green

# Wait for health checks
sleep 30

# Switch traffic to green
make pool-toggle
```

---

## 📊 Monitoring

### View Application Logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f nginx
docker compose logs -f app_blue
docker compose logs -f app_green
```

### Check Health

```bash
# From EC2 instance
curl http://localhost:8080/health

# From local machine
curl http://<public-ip>:8080/health

# Using make
make health
```

### View Resource Usage

```bash
# Docker stats
docker stats

# System resources
htop
```

---

## 🧹 Cleanup

When you're done testing:

```bash
# Clean up all AWS resources
./aws/cleanup.sh

# Or with confirmation skip
./aws/cleanup.sh --force
```

This removes:
- EC2 instance
- Security group
- ECR repository (including all images)
- IAM role and instance profile
- Local configuration files

**Cost savings:** Prevents ongoing charges

---

## 💰 Cost Estimation

| Resource | Monthly Cost (us-east-1) |
|----------|-------------------------|
| t3.medium EC2 | ~$30 |
| 20 GB EBS | ~$2 |
| Data Transfer (first 1GB free) | ~$5 |
| ECR Storage (500 MB free) | ~$1 |
| **Total** | **~$38/month** |

**Tip:** Use t3.small (~$15/month) for testing

---

## 🔒 Security Best Practices

### 1. Restrict SSH Access

```bash
# Update security group to your IP only
YOUR_IP=$(curl -s ifconfig.me)
SG_ID="<your-security-group-id>"

aws ec2 revoke-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0 \
    --region us-east-1

aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 22 \
    --cidr ${YOUR_IP}/32 \
    --region us-east-1
```

### 2. Use HTTPS

See [../docs/PRODUCTION.md](../docs/PRODUCTION.md) for TLS/SSL setup with Let's Encrypt

### 3. Enable CloudWatch Monitoring

```bash
# Install CloudWatch agent on EC2
sudo yum install amazon-cloudwatch-agent -y

# Configure monitoring (see AWS documentation)
```

### 4. Regular Updates

```bash
# SSH into instance
ssh -i ~/.ssh/your-key.pem ec2-user@<public-ip>

# Update system
sudo yum update -y

# Update Docker images
cd /opt/blue-green-deployment-strategy
docker compose pull
docker compose up -d
```

---

## 🐛 Troubleshooting

### Instance not accessible

1. **Check security group rules:**
   ```bash
   aws ec2 describe-security-groups \
       --group-ids <sg-id> \
       --region us-east-1
   ```

2. **Verify instance is running:**
   ```bash
   aws ec2 describe-instances \
       --instance-ids <instance-id> \
       --region us-east-1
   ```

### User-data script failed

```bash
# SSH into instance
ssh -i ~/.ssh/your-key.pem ec2-user@<public-ip>

# Check setup log
sudo tail -100 /var/log/blue-green-setup.log

# Check cloud-init logs
sudo tail -100 /var/log/cloud-init-output.log
```

### Services not starting

```bash
# SSH into instance
cd /opt/blue-green-deployment-strategy

# Check Docker status
sudo systemctl status docker

# Check compose logs
docker compose logs

# Restart services
docker compose down
docker compose up -d
```

### ECR authentication issues

```bash
# Re-login to ECR
REGION="us-east-1"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

aws ecr get-login-password --region $REGION | \
    docker login --username AWS --password-stdin $ECR_URI
```

---

## 📚 Additional Resources

- [Main Documentation](../README.md)
- [Production Deployment Guide](../docs/PRODUCTION.md)
- [Grading & CI Guide](../docs/GRADING-AND-CI.md)
- [Quick Start Guide](../docs/QUICKSTART.md)

---

## 🆘 Support

- Check AWS CloudWatch logs
- Review `/var/log/blue-green-setup.log` on EC2
- Test locally first with `./local-test.sh`
- Verify IAM permissions if ECR pull fails

**Happy Deploying! 🚀**
