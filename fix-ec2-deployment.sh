#!/bin/bash
set -e

# Fix EC2 deployment for grader accessibility
# This script ensures all ports are accessible and containers are running properly

REGION="eu-north-1"
INSTANCE_IP="16.16.194.254"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║         EC2 DEPLOYMENT FIX FOR GRADER ACCESSIBILITY            ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Step 1: Verify security group rules
echo "[1/5] Verifying Security Group Rules..."
SG_ID=$(aws ec2 describe-security-groups --region $REGION \
  --filters "Name=group-name,Values=blue-green-sg" \
  --query 'SecurityGroups[0].GroupId' --output text)

echo "Security Group ID: $SG_ID"
echo ""

# Ensure all required ports are open
for PORT in 22 8080 8081 8082; do
  echo "Checking port $PORT..."
  aws ec2 authorize-security-group-ingress \
    --region $REGION \
    --group-id $SG_ID \
    --protocol tcp \
    --port $PORT \
    --cidr 0.0.0.0/0 2>&1 | grep -q "already exists" && echo "  ✓ Port $PORT already open" || echo "  ✓ Port $PORT opened"
done
echo ""

# Step 2: Verify instance is running
echo "[2/5] Verifying EC2 Instance Status..."
INSTANCE_ID=$(aws ec2 describe-instances --region $REGION \
  --filters "Name=tag:Name,Values=blue-green-deployment" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)

if [ "$INSTANCE_ID" = "None" ] || [ -z "$INSTANCE_ID" ]; then
  echo "✗ ERROR: No running instance found!"
  echo "  Please redeploy using: ./deploy-to-aws.sh"
  exit 1
fi

echo "Instance ID: $INSTANCE_ID"
echo "Instance IP: $INSTANCE_IP"
echo ""

# Step 3: Test connectivity to all ports
echo "[3/5] Testing Port Connectivity..."
ALL_PORTS_OK=true

for PORT in 8080 8081 8082; do
  if timeout 5 bash -c "</dev/tcp/$INSTANCE_IP/$PORT" 2>/dev/null; then
    echo "  ✓ Port $PORT: ACCESSIBLE"
  else
    echo "  ✗ Port $PORT: NOT ACCESSIBLE"
    ALL_PORTS_OK=false
  fi
done
echo ""

if [ "$ALL_PORTS_OK" = "false" ]; then
  echo "⚠️  WARNING: Some ports are not accessible!"
  echo "  This might be because Docker containers are not running on EC2."
  echo ""
  echo "ACTION REQUIRED: SSH into EC2 and restart services:"
  echo "  ssh -i ~/.ssh/blue-green-key.pem ubuntu@$INSTANCE_IP"
  echo "  cd /home/ubuntu/blue-green"
  echo "  docker compose ps  # Check container status"
  echo "  docker compose up -d  # Restart if needed"
  echo ""
fi

# Step 4: Verify endpoints are returning correct data
echo "[4/5] Verifying Endpoint Responses..."

# Test nginx endpoint
NGINX_RESPONSE=$(curl -s -m 5 http://$INSTANCE_IP:8080/version 2>/dev/null || echo '{}')
NGINX_POOL=$(echo $NGINX_RESPONSE | jq -r '.pool // "ERROR"')
NGINX_RELEASE=$(echo $NGINX_RESPONSE | jq -r '.release // "ERROR"')

echo "  Nginx (8080):"
echo "    Pool: $NGINX_POOL"
echo "    Release: $NGINX_RELEASE"

if [ "$NGINX_POOL" != "blue" ]; then
  echo "  ⚠️  WARNING: Expected pool 'blue' but got '$NGINX_POOL'"
  echo "     The grader expects ACTIVE_POOL=blue in .env"
fi

# Test Blue direct
BLUE_RESPONSE=$(curl -s -m 5 http://$INSTANCE_IP:8081/version 2>/dev/null || echo '{}')
BLUE_POOL=$(echo $BLUE_RESPONSE | jq -r '.pool // "ERROR"')
BLUE_RELEASE=$(echo $BLUE_RESPONSE | jq -r '.release // "ERROR"')

echo "  Blue (8081):"
echo "    Pool: $BLUE_POOL"
echo "    Release: $BLUE_RELEASE"

# Test Green direct
GREEN_RESPONSE=$(curl -s -m 5 http://$INSTANCE_IP:8082/version 2>/dev/null || echo '{}')
GREEN_POOL=$(echo $GREEN_RESPONSE | jq -r '.pool // "ERROR"')
GREEN_RELEASE=$(echo $GREEN_RESPONSE | jq -r '.release // "ERROR"')

echo "  Green (8082):"
echo "    Pool: $GREEN_POOL"
echo "    Release: $GREEN_RELEASE"
echo ""

# Step 5: Test chaos mode and failover
echo "[5/5] Testing Chaos Mode and Failover..."

# Activate chaos on Blue
echo "  Activating chaos on Blue..."
CHAOS_START=$(curl -sX POST "http://$INSTANCE_IP:8081/chaos/start?mode=error" 2>/dev/null | jq -r '.message // "ERROR"')
echo "    Response: $CHAOS_START"

# Test failover (should get Green responses)
sleep 1
FAILOVER_POOL=$(curl -s -m 5 http://$INSTANCE_IP:8080/version 2>/dev/null | jq -r '.pool // "ERROR"')
echo "  During chaos, nginx routed to: $FAILOVER_POOL"

if [ "$FAILOVER_POOL" = "green" ]; then
  echo "    ✓ Failover working correctly"
else
  echo "    ✗ Failover NOT working (expected 'green', got '$FAILOVER_POOL')"
fi

# Deactivate chaos
echo "  Deactivating chaos..."
CHAOS_STOP=$(curl -sX POST "http://$INSTANCE_IP:8081/chaos/stop" 2>/dev/null | jq -r '.message // "ERROR"')
echo "    Response: $CHAOS_STOP"

sleep 1
RESTORED_POOL=$(curl -s -m 5 http://$INSTANCE_IP:8080/version 2>/dev/null | jq -r '.pool // "ERROR"')
echo "  After chaos stopped, nginx routing to: $RESTORED_POOL"

if [ "$RESTORED_POOL" = "blue" ]; then
  echo "    ✓ Service restored to blue"
else
  echo "    ✗ Service NOT restored (expected 'blue', got '$RESTORED_POOL')"
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                      SUMMARY                                   ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

if [ "$ALL_PORTS_OK" = "true" ] && [ "$NGINX_POOL" = "blue" ] && [ "$FAILOVER_POOL" = "green" ]; then
  echo "✅ All checks passed! Deployment is ready for grading."
  echo ""
  echo "Submit this URL: http://$INSTANCE_IP:8080"
  echo ""
  echo "Note: If the grader still reports connection timeouts, it might be:"
  echo "  - Temporary network issues"
  echo "  - Grader's IP range blocked by AWS"
  echo "  - Containers were restarting when grader accessed"
  echo ""
  echo "Try submitting again after a few minutes."
else
  echo "⚠️  Some issues detected. Please review the output above."
  echo ""
  echo "Common fixes:"
  echo "  1. Ensure Docker containers are running on EC2"
  echo "  2. Verify .env has ACTIVE_POOL=blue"
  echo "  3. Restart nginx: docker compose up -d --force-recreate nginx"
fi
echo ""
