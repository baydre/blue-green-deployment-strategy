# EC2 Instance Setup Summary

## Current Status

**New EC2 Instance (With Simplified Release IDs):**
- **IP Address**: 13.49.137.99
- **Instance ID**: i-011854a5fe2943516
- **Region**: eu-north-1
- **Status**: Running, waiting for manual setup

**Old EC2 Instance (Terminated):**
- IP: 16.16.194.254
- Instance ID: i-0c4c52eab03aa0ec0
- Status: Terminating

## What Changed

### Fixed Issues:
1. **Simplified Release IDs** - Changed from versioned IDs to simple pool names:
   - `RELEASE_ID_BLUE`: `v1.0.1-blue` → `blue`
   - `RELEASE_ID_GREEN`: `v1.1.0-green` → `green`
   
2. **Purpose**: Fix grader error "Release ID does not match Blue"
   - Grader expects X-Release-Id header to be exactly "blue" or "green"
   - Not version strings like "v1.0.1-blue"

### Files Updated:
- `.env` - Simplified Release IDs
- `aws/manual-setup-simplified.sh` - New setup script with correct IDs
- `fix-ec2-deployment.sh` - Deployment verification tool
- `update-ec2-release-ids.sh` - Helper for updating existing instances

## Setup Instructions

### Option 1: EC2 Instance Connect (Recommended - No SSH Key Needed)

1. **Open AWS Console**:
   - Go to: https://console.aws.amazon.com/ec2
   - Region: eu-north-1 (Stockholm)

2. **Connect to Instance**:
   - Find instance: `i-011854a5fe2943516`
   - Click "Connect" button
   - Select "EC2 Instance Connect" tab
   - Click "Connect" (opens browser-based terminal)

3. **Run Setup Script**:
   ```bash
   bash <(curl -s https://raw.githubusercontent.com/baydre/blue-green-deployment-strategy/main/aws/manual-setup-simplified.sh)
   ```

4. **Wait for Completion** (~2-3 minutes):
   - Script will install Docker
   - Pull images from ECR
   - Create configuration files
   - Start containers
   - Verify deployment

### Option 2: SSH (If You Have the Key)

```bash
ssh -i blue-green-key.pem ubuntu@13.49.137.99 'bash <(curl -s https://raw.githubusercontent.com/baydre/blue-green-deployment-strategy/main/aws/manual-setup-simplified.sh)'
```

## Verification

After setup completes, verify the deployment:

```bash
# Test from your local machine
curl http://13.49.137.99:8080/version

# Expected response:
{
  "pool": "blue",
  "release": "blue",        # ← Simplified! (not "v1.0.1-blue")
  "version": "blue",
  "timestamp": "2025-10-29T..."
}
```

### Test All Endpoints:

```bash
# Nginx (main endpoint)
curl -s http://13.49.137.99:8080/version | jq '{pool, release}'

# Blue direct
curl -s http://13.49.137.99:8081/version | jq '{pool, release}'

# Green direct  
curl -s http://13.49.137.99:8082/version | jq '{pool, release}'

# Headers
curl -I http://13.49.137.99:8080/version | grep -E "X-(App-Pool|Release-Id)"
```

Expected output:
```
X-App-Pool: blue
X-Release-Id: blue
```

## Submission

Once verified, submit to grader:
- **URL**: `http://13.49.137.99:8080`

This should fix both previous grader errors:
1. ✅ Ports 8081/8082 are open and accessible
2. ✅ Release ID is now exactly "blue" (not "v1.0.1-blue")

## Troubleshooting

### If containers don't start:
```bash
# SSH into instance
cd /home/ubuntu/blue-green
sudo docker compose ps
sudo docker compose logs
```

### If ports aren't accessible:
```bash
# Check security group
aws ec2 describe-security-groups \
  --region eu-north-1 \
  --filters "Name=group-name,Values=blue-green-sg" \
  --query 'SecurityGroups[0].IpPermissions[].[FromPort,ToPort]' \
  --output table

# Should show: 22, 8080, 8081, 8082
```

### Test failover:
```bash
# Activate chaos on Blue
curl -X POST "http://13.49.137.99:8081/chaos/start?mode=error"

# Test nginx (should route to Green)
for i in {1..5}; do
  curl -s http://13.49.137.99:8080/version | jq -r '.pool'
done

# Stop chaos
curl -X POST "http://13.49.137.99:8081/chaos/stop"
```

## Next Steps

1. ✅ Connect to EC2 via Instance Connect
2. ✅ Run the setup script
3. ✅ Verify all endpoints work
4. ✅ Test failover functionality
5. ✅ Submit to grader: `http://13.49.137.99:8080`

## Cleanup (After Grading)

```bash
# Remove all AWS resources
./aws/cleanup.sh
```

This will terminate the EC2 instance, remove security group, and clean up ECR.
