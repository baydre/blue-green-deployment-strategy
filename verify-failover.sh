#!/bin/bash
set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
NGINX_URL="http://localhost:8080"
BLUE_DIRECT_URL="http://localhost:8081"
GREEN_DIRECT_URL="http://localhost:8082"
VERIFICATION_REQUESTS="${VERIFICATION_REQUESTS:-100}"

# Load expected values from .env if it exists
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

EXPECTED_BLUE_RELEASE="${RELEASE_ID_BLUE:-v1.0.1-blue}"
EXPECTED_GREEN_RELEASE="${RELEASE_ID_GREEN:-v1.1.0-green}"

echo "=================================="
echo "Blue/Green Failover Verification"
echo "=================================="
echo ""

# Step 1: Baseline verification (traffic should go to Blue)
echo -e "${YELLOW}[STEP 1]${NC} Verifying baseline traffic to Blue pool..."
RESPONSE=$(curl -s -i "$NGINX_URL/")
STATUS_CODE=$(echo "$RESPONSE" | grep -i "HTTP/" | awk '{print $2}')
APP_POOL=$(echo "$RESPONSE" | grep -i "X-App-Pool:" | awk '{print $2}' | tr -d '\r')
RELEASE_ID=$(echo "$RESPONSE" | grep -i "X-Release-Id:" | awk '{print $2}' | tr -d '\r')

if [ "$STATUS_CODE" != "200" ]; then
    echo -e "${RED}✗ FAIL${NC}: Expected 200, got $STATUS_CODE"
    exit 1
fi

if [ "$APP_POOL" != "blue" ]; then
    echo -e "${RED}✗ FAIL${NC}: Expected X-App-Pool: blue, got $APP_POOL"
    exit 1
fi

if [ "$RELEASE_ID" != "$EXPECTED_BLUE_RELEASE" ]; then
    echo -e "${RED}✗ FAIL${NC}: Expected X-Release-Id: $EXPECTED_BLUE_RELEASE, got $RELEASE_ID"
    exit 1
fi

echo -e "${GREEN}✓ PASS${NC}: Baseline traffic correctly routed to Blue"
echo "  Status: $STATUS_CODE"
echo "  X-App-Pool: $APP_POOL"
echo "  X-Release-Id: $RELEASE_ID"
echo ""

# Step 2: Trigger chaos mode on Blue
echo -e "${YELLOW}[STEP 2]${NC} Triggering chaos mode on Blue instance..."
CHAOS_RESPONSE=$(curl -s -X POST "$BLUE_DIRECT_URL/chaos/start")
echo "  Response: $CHAOS_RESPONSE"
echo ""

# Small delay to ensure chaos mode is active
sleep 1

# Step 3: Send verification requests and measure failover
echo -e "${YELLOW}[STEP 3]${NC} Sending $VERIFICATION_REQUESTS requests to test failover..."

total_requests=0
success_count=0
error_count=0
blue_count=0
green_count=0
unknown_count=0

for i in $(seq 1 $VERIFICATION_REQUESTS); do
    total_requests=$((total_requests + 1))
    
    # Send request and capture status code and headers
    RESPONSE=$(curl -s -i "$NGINX_URL/" 2>/dev/null || echo "")
    STATUS=$(echo "$RESPONSE" | grep -i "HTTP/" | awk '{print $2}')
    POOL=$(echo "$RESPONSE" | grep -i "X-App-Pool:" | awk '{print $2}' | tr -d '\r')
    
    if [ "$STATUS" = "200" ]; then
        success_count=$((success_count + 1))
        
        if [ "$POOL" = "blue" ]; then
            blue_count=$((blue_count + 1))
        elif [ "$POOL" = "green" ]; then
            green_count=$((green_count + 1))
        else
            unknown_count=$((unknown_count + 1))
        fi
    else
        error_count=$((error_count + 1))
    fi
    
    # Show progress every 20 requests
    if [ $((i % 20)) -eq 0 ]; then
        echo "  Progress: $i/$VERIFICATION_REQUESTS requests sent..."
    fi
done

echo ""
echo "=================================="
echo "Verification Results"
echo "=================================="
echo "Total Requests:    $total_requests"
echo "Successful (200):  $success_count"
echo "Failed (non-200):  $error_count"
echo ""
echo "Pool Distribution:"
echo "  Blue:    $blue_count ($(awk "BEGIN {printf \"%.1f\", ($blue_count/$total_requests)*100}")%)"
echo "  Green:   $green_count ($(awk "BEGIN {printf \"%.1f\", ($green_count/$total_requests)*100}")%)"
echo "  Unknown: $unknown_count"
echo ""

# Step 4: Validate acceptance criteria
echo "=================================="
echo "Acceptance Criteria"
echo "=================================="

PASS=true

# Criterion 1: Zero non-200 responses allowed
echo -n "1. Zero non-200 responses: "
if [ $error_count -eq 0 ]; then
    echo -e "${GREEN}✓ PASS${NC} (0 errors)"
else
    echo -e "${RED}✗ FAIL${NC} ($error_count errors found)"
    PASS=false
fi

# Criterion 2: At least 95% of responses from Green
green_percentage=$(awk "BEGIN {printf \"%.1f\", ($green_count/$total_requests)*100}")
echo -n "2. ≥95% responses from Green: "
if (( $(awk "BEGIN {print ($green_count >= $total_requests * 0.95)}") )); then
    echo -e "${GREEN}✓ PASS${NC} ($green_percentage%)"
else
    echo -e "${RED}✗ FAIL${NC} ($green_percentage%, need ≥95%)"
    PASS=false
fi

echo ""

# Step 5: Cleanup - stop chaos mode
echo -e "${YELLOW}[CLEANUP]${NC} Stopping chaos mode on Blue..."
curl -s -X POST "$BLUE_DIRECT_URL/chaos/stop" > /dev/null
echo "  Chaos mode deactivated"
echo ""

# Final verdict
if [ "$PASS" = true ]; then
    echo -e "${GREEN}=================================="
    echo "✓ ALL TESTS PASSED"
    echo "==================================${NC}"
    exit 0
else
    echo -e "${RED}=================================="
    echo "✗ TESTS FAILED"
    echo "==================================${NC}"
    exit 1
fi
