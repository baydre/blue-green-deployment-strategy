#!/bin/bash
set -e

# Update EC2 deployment with simplified Release IDs
# This script helps fix the grader's "Release ID does not match Blue" error

REGION="eu-north-1"
INSTANCE_IP="16.16.194.254"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║        UPDATE EC2 WITH SIMPLIFIED RELEASE IDs                  ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "The grader expects simple Release IDs:"
echo "  - Blue: 'blue' (not 'v1.0.1-blue')"
echo "  - Green: 'green' (not 'v1.1.0-green')"
echo ""

# Check if we have SSH access
if [ ! -f ~/.ssh/blue-green-key.pem ]; then
    echo "⚠️  SSH key not found at ~/.ssh/blue-green-key.pem"
    echo ""
    echo "To update manually, you need to:"
    echo ""
    echo "1. Get SSH access to the instance:"
    echo "   - Download the key from AWS Console → EC2 → Key Pairs"
    echo "   - Or use AWS Session Manager if IAM role is configured"
    echo ""
    echo "2. SSH into the instance:"
    echo "   ssh -i blue-green-key.pem ubuntu@$INSTANCE_IP"
    echo ""
    echo "3. Update the .env file:"
    echo "   cd /home/ubuntu/blue-green"
    echo "   nano .env"
    echo "   # Change:"
    echo "   #   RELEASE_ID_BLUE=v1.0.1-blue  →  RELEASE_ID_BLUE=blue"
    echo "   #   RELEASE_ID_GREEN=v1.1.0-green  →  RELEASE_ID_GREEN=green"
    echo ""
    echo "4. Restart containers:"
    echo "   docker compose down"
    echo "   docker compose up -d"
    echo ""
    echo "5. Verify:"
    echo "   curl http://localhost:8080/version"
    echo "   # Should show: \"release\":\"blue\""
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "ALTERNATIVE: Terminate and redeploy with updated .env"
    echo ""
    echo "Since local .env is now updated, you can:"
    echo "  1. ./aws/cleanup.sh (removes current EC2)"
    echo "  2. ./deploy-to-aws.sh (deploys with new Release IDs)"
    echo ""
    
    read -p "Do you want to terminate and redeploy? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        echo "Starting redeployment..."
        ./deploy-to-aws.sh
    else
        echo "Skipping redeployment. Please update manually via SSH."
    fi
    
    exit 0
fi

echo "✓ SSH key found!"
echo ""
echo "Connecting to EC2 and updating configuration..."
echo ""

# Create update script
cat > /tmp/ec2-update.sh << 'EOFSCRIPT'
#!/bin/bash
set -e

cd /home/ubuntu/blue-green

echo "Backing up current .env..."
cp .env .env.backup.$(date +%Y%m%d_%H%M%S)

echo "Updating Release IDs..."
sed -i 's/RELEASE_ID_BLUE=.*/RELEASE_ID_BLUE=blue/' .env
sed -i 's/RELEASE_ID_GREEN=.*/RELEASE_ID_GREEN=green/' .env

echo ""
echo "New Release IDs:"
grep RELEASE_ID .env

echo ""
echo "Restarting containers..."
docker compose down
docker compose up -d

echo ""
echo "Waiting for containers to be ready..."
sleep 8

echo ""
echo "Container status:"
docker compose ps

echo ""
echo "Testing endpoints:"
echo "  Nginx (8080):"
curl -s http://localhost:8080/version | jq -c '{pool, release}'

echo "  Blue (8081):"
curl -s http://localhost:8081/version | jq -c '{pool, release}'

echo "  Green (8082):"
curl -s http://localhost:8082/version | jq -c '{pool, release}'

echo ""
echo "✅ Update complete!"
EOFSCRIPT

# Copy and execute
scp -i ~/.ssh/blue-green-key.pem \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    /tmp/ec2-update.sh ubuntu@$INSTANCE_IP:/tmp/

ssh -i ~/.ssh/blue-green-key.pem \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    ubuntu@$INSTANCE_IP \
    'bash /tmp/ec2-update.sh'

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                   UPDATE COMPLETE                              ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Verifying from external access..."
sleep 2

NGINX_RELEASE=$(curl -s http://$INSTANCE_IP:8080/version | jq -r '.release')
BLUE_RELEASE=$(curl -s http://$INSTANCE_IP:8081/version | jq -r '.release')
GREEN_RELEASE=$(curl -s http://$INSTANCE_IP:8082/version | jq -r '.release')

echo "  Nginx Release ID: $NGINX_RELEASE"
echo "  Blue Release ID:  $BLUE_RELEASE"
echo "  Green Release ID: $GREEN_RELEASE"
echo ""

if [ "$BLUE_RELEASE" = "blue" ] && [ "$GREEN_RELEASE" = "green" ]; then
    echo "✅ Release IDs updated successfully!"
    echo ""
    echo "Ready to submit: http://$INSTANCE_IP:8080"
else
    echo "⚠️  Release IDs don't match expected values"
    echo "   Expected: blue and green"
    echo "   Got: $BLUE_RELEASE and $GREEN_RELEASE"
fi
