#!/bin/bash
# Automated rollback script for Blue/Green deployment
# Usage: ./rollback.sh [--force] [--to=<pool>]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Detect Docker Compose command (v1 vs v2)
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
elif docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
else
    echo -e "${RED}Error: Docker Compose not found${NC}"
    exit 1
fi

# Configuration
FORCE=false
TARGET_POOL=""
HEALTH_CHECK_RETRIES=3
HEALTH_CHECK_INTERVAL=5

# Parse arguments
for arg in "$@"; do
    case $arg in
        --force)
            FORCE=true
            shift
            ;;
        --to=*)
            TARGET_POOL="${arg#*=}"
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Automated rollback script for Blue/Green deployment"
            echo ""
            echo "Options:"
            echo "  --force          Skip safety checks and force rollback"
            echo "  --to=<pool>      Rollback to specific pool (blue or green)"
            echo "  --help           Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0               # Rollback to the inactive pool"
            echo "  $0 --to=blue     # Rollback to blue pool"
            echo "  $0 --force       # Force rollback without health checks"
            exit 0
            ;;
    esac
done

# Get current active pool
CURRENT_POOL=$(grep ACTIVE_POOL .env | cut -d'=' -f2)

# Determine target pool
if [ -z "$TARGET_POOL" ]; then
    # Toggle to the other pool
    TARGET_POOL=$([ "$CURRENT_POOL" = "blue" ] && echo "green" || echo "blue")
fi

# Validate target pool
if [ "$TARGET_POOL" != "blue" ] && [ "$TARGET_POOL" != "green" ]; then
    echo -e "${RED}Error: Invalid target pool '$TARGET_POOL'. Must be 'blue' or 'green'.${NC}"
    exit 1
fi

# Check if already on target pool
if [ "$CURRENT_POOL" = "$TARGET_POOL" ]; then
    echo -e "${YELLOW}Already on $TARGET_POOL pool. Nothing to rollback.${NC}"
    exit 0
fi

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║           Blue/Green Deployment Rollback                  ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Current Active Pool:${NC} $CURRENT_POOL"
echo -e "${CYAN}Target Pool:${NC}         $TARGET_POOL"
echo ""

# Pre-rollback health check (unless forced)
if [ "$FORCE" = false ]; then
    echo -e "${CYAN}==> Running pre-rollback health checks...${NC}"
    
    # Determine target port
    TARGET_PORT=$([ "$TARGET_POOL" = "blue" ] && echo "8081" || echo "8082")
    
    # Check if target pool is healthy
    healthy=false
    for i in $(seq 1 $HEALTH_CHECK_RETRIES); do
        if curl -f -s "http://localhost:$TARGET_PORT/health" > /dev/null 2>&1; then
            healthy=true
            echo -e "${GREEN}✓${NC} Target pool ($TARGET_POOL) is healthy"
            break
        else
            echo -e "${YELLOW}⚠${NC} Target pool not responding, retry $i/$HEALTH_CHECK_RETRIES..."
            sleep $HEALTH_CHECK_INTERVAL
        fi
    done
    
    if [ "$healthy" = false ]; then
        echo -e "${RED}✗ Target pool ($TARGET_POOL) is not healthy!${NC}"
        echo ""
        echo "Options:"
        echo "  1. Fix the target pool and try again"
        echo "  2. Use --force to rollback anyway (risky)"
        echo "  3. Deploy a known-good version to target pool first"
        exit 1
    fi
    
    # Test a sample request
    response=$(curl -s -i "http://localhost:$TARGET_PORT/" 2>&1)
    status=$(echo "$response" | grep -i "HTTP/" | awk '{print $2}')
    
    if [ "$status" != "200" ]; then
        echo -e "${RED}✗ Target pool returning $status instead of 200${NC}"
        echo ""
        echo "Use --force to proceed anyway (not recommended)"
        exit 1
    fi
    
    echo -e "${GREEN}✓${NC} Target pool is responding correctly"
    echo ""
else
    echo -e "${YELLOW}⚠ Skipping health checks (--force flag set)${NC}"
    echo ""
fi

# Confirm rollback
if [ "$FORCE" = false ]; then
    echo -e "${YELLOW}WARNING: This will switch traffic from $CURRENT_POOL to $TARGET_POOL${NC}"
    read -p "Are you sure you want to proceed? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        echo -e "${CYAN}Rollback cancelled.${NC}"
        exit 0
    fi
fi

# Perform rollback
echo ""
echo -e "${CYAN}==> Executing rollback...${NC}"

# Update .env file
sed -i "s/ACTIVE_POOL=$CURRENT_POOL/ACTIVE_POOL=$TARGET_POOL/" .env
echo -e "${GREEN}✓${NC} Updated ACTIVE_POOL in .env"

# Recreate nginx to pick up new pool
$DOCKER_COMPOSE up -d --force-recreate nginx > /dev/null 2>&1
echo -e "${GREEN}✓${NC} Nginx restarted with new configuration"

# Wait for nginx to be ready
sleep 3

# Post-rollback validation
echo ""
echo -e "${CYAN}==> Running post-rollback validation...${NC}"

# Check nginx health
if curl -f -s "http://localhost:8080/health" > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Nginx is healthy"
else
    echo -e "${RED}✗ Nginx health check failed${NC}"
    exit 1
fi

# Verify traffic is going to target pool
response=$(curl -s -i "http://localhost:8080/" 2>&1)
pool=$(echo "$response" | grep -i "X-App-Pool:" | awk '{print $2}' | tr -d '\r')

if [ "$pool" = "$TARGET_POOL" ]; then
    echo -e "${GREEN}✓${NC} Traffic is now routing to $TARGET_POOL"
else
    echo -e "${RED}✗ Traffic routing failed. Expected $TARGET_POOL but got $pool${NC}"
    exit 1
fi

# Send a few test requests
echo ""
echo -e "${CYAN}==> Sending validation requests...${NC}"
success=0
for i in {1..10}; do
    status=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/")
    if [ "$status" = "200" ]; then
        success=$((success + 1))
    fi
done

if [ $success -eq 10 ]; then
    echo -e "${GREEN}✓${NC} All validation requests successful (10/10)"
else
    echo -e "${YELLOW}⚠${NC} Some validation requests failed ($success/10 successful)"
fi

# Generate rollback report
cat > rollback-report.txt << EOF
Blue/Green Rollback Report
==========================
Date: $(date)
Previous Pool: $CURRENT_POOL
New Active Pool: $TARGET_POOL
Status: SUCCESS

Validation Results:
- Nginx Health: OK
- Traffic Routing: $TARGET_POOL
- Test Requests: $success/10 successful

Next Steps:
1. Monitor application metrics for 5-10 minutes
2. Check error rates and latency
3. Review application logs
4. Update $CURRENT_POOL with fix/rollback version
EOF

echo -e "${GREEN}✓${NC} Rollback report saved to rollback-report.txt"

# Success summary
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║            ROLLBACK COMPLETED SUCCESSFULLY! ✓             ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Rolled back from: ${RED}$CURRENT_POOL${NC} → ${GREEN}$TARGET_POOL${NC}"
echo ""
echo -e "${YELLOW}Important:${NC}"
echo "  • Monitor the application for the next 5-10 minutes"
echo "  • Check metrics dashboard for any anomalies"
echo "  • Review logs: $DOCKER_COMPOSE logs -f --tail=100"
echo "  • Update the previous pool ($CURRENT_POOL) with fixes"
echo ""

exit 0
