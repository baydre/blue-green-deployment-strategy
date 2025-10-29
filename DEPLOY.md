# 🚀 AWS EC2 Manual Deployment Guide

**Quick 10-Minute Deployment** - Get your blue-green deployment running on AWS EC2

---

## Prerequisites

✅ AWS Account with credits (you have $118!)  
✅ AWS CLI configured (`aws configure`)  
✅ Docker images in ECR (already pushed)

---

## 📋 Deployment Steps

### Step 1: Push Images to ECR (if not done)

```bash
cd /home/baydre_africa/HNG-13/devOps/blue-green-deployment-strategy
./aws/push-to-ecr.sh
```

**Expected:** Images uploaded to `704654299291.dkr.ecr.eu-north-1.amazonaws.com/blue-green/app:blue` and `:green`

---

### Step 2: Launch EC2 Instance

```bash
cd aws
./quick-deploy.sh
```

**What this does:**
- Creates SSH key pair (`blue-green-key.pem`)
- Creates IAM role with ECR permissions
- Creates security group (ports 22, 8080)
- Launches t3.micro instance (~$7/month, covered by your credits)
- Saves connection details to `ec2-connection.txt`

**Expected output:**
```
✓ EC2 Instance Launched!
Instance ID: i-xxxxxxxxx
Public IP: x.x.x.x
```

---

### Step 3: Wait for Instance Initialization

⏱️ **Wait 30-60 seconds** for the instance to fully boot up.

```bash
# Optional: Watch instance status
watch -n 5 'aws ec2 describe-instance-status --instance-ids <INSTANCE_ID> --region eu-north-1'
```

---

### Step 4: SSH into EC2 and Run Setup

**Option A: One-Command Setup** (Recommended)

```bash
# Get the command from the output above, it looks like:
ssh -i blue-green-key.pem ec2-user@<PUBLIC_IP> 'bash <(curl -s https://raw.githubusercontent.com/baydre/blue-green-deployment-strategy/main/aws/manual-setup.sh)'
```

**Option B: Manual SCP + SSH** (If Option A fails)

```bash
# Copy setup script to EC2
scp -i blue-green-key.pem aws/manual-setup.sh ec2-user@<PUBLIC_IP>:~/

# SSH into instance
ssh -i blue-green-key.pem ec2-user@<PUBLIC_IP>

# On EC2 instance, run:
bash manual-setup.sh
```

**Setup takes ~3-5 minutes** and will:
1. ✅ Install Docker & Docker Compose
2. ✅ Login to ECR
3. ✅ Clone your repository
4. ✅ Pull Docker images
5. ✅ Start nginx + blue + green containers
6. ✅ Verify services are running

---

### Step 5: Verify Deployment

```bash
# From your local machine
curl http://<PUBLIC_IP>:8080/version
```

**Expected response:**
```json
{
  "app_pool": "blue",
  "release_id": "v1.0.1-blue",
  "version": "1.0.0"
}
```

**Check headers:**
```bash
curl -i http://<PUBLIC_IP>:8080/version
```

Should see:
```
X-App-Pool: blue
X-Release-Id: v1.0.1-blue
```

---

### Step 6: Test Failover (Optional but Recommended)

```bash
# SSH into EC2
ssh -i blue-green-key.pem ec2-user@<PUBLIC_IP>

# On EC2, run failover test
cd /opt/blue-green-deployment-strategy
sudo bash verify-failover.sh
```

**Expected:**
```
✓ 100/100 requests successful
✓ 0 failures during failover
✓ 100% traffic routed to green during blue chaos
```

---

## 🎯 Quick Reference

### EC2 Instance Access

```bash
# SSH
ssh -i blue-green-key.pem ec2-user@<PUBLIC_IP>

# View logs
sudo docker-compose logs -f

# Check services
sudo docker-compose ps

# Restart services
sudo docker-compose restart
```

### Application Endpoints

- **Version**: `http://<PUBLIC_IP>:8080/version`
- **Health**: `http://<PUBLIC_IP>:8080/healthz`
- **Chaos (Blue)**: `http://<PUBLIC_IP>:8081/chaos/start?mode=error`
- **Chaos (Green)**: `http://<PUBLIC_IP>:8082/chaos/start?mode=error`

### Useful Commands

```bash
# Switch active pool
cd /opt/blue-green-deployment-strategy
sudo ACTIVE_POOL=green docker-compose up -d nginx

# View nginx logs
sudo docker-compose logs -f nginx

# Stop all services
sudo docker-compose down

# Start all services
sudo docker-compose up -d
```

---

## 📝 Submission Information

Once deployed, add to your `SUBMISSION.md`:

```markdown
## Deployment Information

- **Public URL**: http://<PUBLIC_IP>:8080/version
- **Cloud Provider**: AWS EC2
- **Instance Type**: t3.micro
- **Region**: eu-north-1 (Stockholm)
- **Container Registry**: Amazon ECR
```

---

## 🛑 Cleanup (When Done)

To avoid charges after submission:

```bash
# From local machine
cd aws
./cleanup.sh
```

This will:
- Terminate EC2 instance
- Delete security group
- Delete IAM role
- **Keep ECR images** (minimal storage cost)

**Cost while running:** ~$0.01/hour (t3.micro) = covered by your $118 credits

---

## 🔧 Troubleshooting

### Can't SSH into instance

```bash
# Check security group allows SSH
aws ec2 describe-security-groups --group-ids <SG_ID> --region eu-north-1

# Check instance is running
aws ec2 describe-instances --instance-ids <INSTANCE_ID> --region eu-north-1
```

### Docker Compose fails

```bash
# SSH into instance
ssh -i blue-green-key.pem ec2-user@<PUBLIC_IP>

# Check Docker
sudo systemctl status docker

# Check images
sudo docker images

# Manually pull if needed
sudo aws ecr get-login-password --region eu-north-1 | sudo docker login --username AWS --password-stdin 704654299291.dkr.ecr.eu-north-1.amazonaws.com
sudo docker pull 704654299291.dkr.ecr.eu-north-1.amazonaws.com/blue-green/app:blue
```

### Services won't start

```bash
# Check logs
cd /opt/blue-green-deployment-strategy
sudo docker-compose logs

# Check .env file
cat .env

# Restart
sudo docker-compose down
sudo docker-compose up -d
```

---

## 📞 Need Help?

Check these files:
- `ec2-connection.txt` - Connection details
- `/var/log/cloud-init-output.log` - Instance initialization log (on EC2)
- `/opt/blue-green-deployment-strategy/` - Application directory (on EC2)

---

**Ready to deploy? Run:** `./aws/quick-deploy.sh` 🚀
