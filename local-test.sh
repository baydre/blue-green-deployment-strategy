#!/bin/bash
# Complete local test suite for Blue/Green deployment
# Usage: ./local-test.sh [--skip-build] [--keep-running]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SKIP_BUILD=false
KEEP_RUNNING=false
LOG_FILE="test-results-$(date +%Y%m%d-%H%M%S).log"

# Detect Docker Compose command (v1 vs v2)
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
elif docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
else
    echo -e "${RED}Error: Docker Compose not found${NC}"
    exit 1
fi

# Parse arguments
for arg in "$@"; do
    case $arg in
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --keep-running)
            KEEP_RUNNING=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --skip-build     Skip image building step"
            echo "  --keep-running   Don't tear down stack after tests"
            echo "  --help           Show this help message"
            exit 0
            ;;
    esac
done

# Helper functions
log_step() {
    echo -e "${CYAN}==>${NC} $1"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
    echo "[SUCCESS] $1" >> "$LOG_FILE"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
    echo "[ERROR] $1" >> "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
    echo "[WARNING] $1" >> "$LOG_FILE"
}

cleanup() {
    if [ "$KEEP_RUNNING" = false ]; then
        log_step "Cleaning up..."
        $DOCKER_COMPOSE down -v >> "$LOG_FILE" 2>&1 || true
        log_success "Cleanup complete"
    else
        log_warning "Skipping cleanup (--keep-running flag set)"
        echo -e "${YELLOW}Services are still running. Use '$DOCKER_COMPOSE down -v' to clean up.${NC}"
    fi
}

# Trap errors and cleanup
trap 'log_error "Test suite failed"; cleanup; exit 1' ERR

# Start test suite
echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Blue/Green Deployment - Complete Local Test Suite       ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
log_step "Starting test suite at $(date)"
log_step "Log file: $LOG_FILE"
echo ""

# Step 1: Pre-flight checks
log_step "Running pre-flight checks..."

# Check Docker
if ! docker info > /dev/null 2>&1; then
    log_error "Docker is not running or not accessible"
    exit 1
fi
log_success "Docker daemon is running"

# Check Docker Compose
if ! $DOCKER_COMPOSE version > /dev/null 2>&1; then
    log_error "Docker Compose is not installed"
    exit 1
fi
log_success "Docker Compose is available ($DOCKER_COMPOSE)"

# Check required files
required_files=(".env" "docker-compose.yml" "nginx.conf.template" "verify-failover.sh" "app/Dockerfile")
for file in "${required_files[@]}"; do
    if [ ! -f "$file" ]; then
        log_error "Required file missing: $file"
        exit 1
    fi
done
log_success "All required files present"
echo ""

# Step 2: Build images
if [ "$SKIP_BUILD" = false ]; then
    log_step "Building Docker images..."
    
    docker build -t blue-app:local ./app >> "$LOG_FILE" 2>&1
    log_success "blue-app:local built"
    
    docker build -t green-app:local ./app >> "$LOG_FILE" 2>&1
    log_success "green-app:local built"
    
    echo ""
else
    log_warning "Skipping build step (--skip-build flag set)"
    echo ""
fi

# Step 3: Clean up any existing containers
log_step "Cleaning up existing containers..."
$DOCKER_COMPOSE down -v >> "$LOG_FILE" 2>&1 || true
log_success "Cleanup complete"
echo ""

# Step 4: Start the stack
log_step "Starting Docker Compose stack..."
$DOCKER_COMPOSE up -d >> "$LOG_FILE" 2>&1
log_success "Stack started"
echo ""

# Step 5: Wait for services to be healthy
log_step "Waiting for services to be healthy..."
MAX_WAIT=60
WAIT_INTERVAL=2
elapsed=0

while [ $elapsed -lt $MAX_WAIT ]; do
    if curl -f -s http://localhost:8080/health > /dev/null 2>&1 && \
       curl -f -s http://localhost:8081/health > /dev/null 2>&1 && \
       curl -f -s http://localhost:8082/health > /dev/null 2>&1; then
        log_success "All services are healthy (took ${elapsed}s)"
        break
    fi
    
    if [ $elapsed -ge $MAX_WAIT ]; then
        log_error "Services did not become healthy within ${MAX_WAIT}s"
        $DOCKER_COMPOSE ps
        $DOCKER_COMPOSE logs
        exit 1
    fi
    
    sleep $WAIT_INTERVAL
    elapsed=$((elapsed + WAIT_INTERVAL))
    echo -n "."
done
echo ""
echo ""

# Step 6: Show running services
log_step "Running services:"
$DOCKER_COMPOSE ps
echo ""

# Step 7: Run baseline tests
log_step "Running baseline connectivity tests..."

# Test Nginx
if response=$(curl -s -i http://localhost:8080/ 2>&1); then
    status=$(echo "$response" | grep -i "HTTP/" | awk '{print $2}')
    pool=$(echo "$response" | grep -i "X-App-Pool:" | awk '{print $2}' | tr -d '\r')
    release=$(echo "$response" | grep -i "X-Release-Id:" | awk '{print $2}' | tr -d '\r')
    
    if [ "$status" = "200" ] && [ "$pool" = "blue" ]; then
        log_success "Nginx routing correctly (Status: $status, Pool: $pool, Release: $release)"
    else
        log_error "Nginx routing failed (Status: $status, Pool: $pool)"
        exit 1
    fi
else
    log_error "Failed to connect to Nginx"
    exit 1
fi

# Test Blue direct
if curl -f -s http://localhost:8081/ > /dev/null 2>&1; then
    log_success "Blue instance accessible"
else
    log_error "Blue instance not accessible"
    exit 1
fi

# Test Green direct
if curl -f -s http://localhost:8082/ > /dev/null 2>&1; then
    log_success "Green instance accessible"
else
    log_error "Green instance not accessible"
    exit 1
fi
echo ""

# Step 8: Run automated failover verification
log_step "Running automated failover verification..."
if ./verify-failover.sh >> "$LOG_FILE" 2>&1; then
    log_success "Failover verification passed"
else
    log_error "Failover verification failed"
    echo ""
    echo "Last 20 lines of log:"
    tail -n 20 "$LOG_FILE"
    exit 1
fi
echo ""

# Step 9: Test chaos endpoints
log_step "Testing chaos mode endpoints..."

# Activate chaos on Blue
if curl -f -s -X POST http://localhost:8081/chaos/start > /dev/null 2>&1; then
    log_success "Chaos mode activated on Blue"
else
    log_error "Failed to activate chaos mode"
    exit 1
fi

# Verify Blue returns 500
blue_status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8081/)
if [ "$blue_status" = "500" ]; then
    log_success "Blue correctly returning 500 in chaos mode"
else
    log_error "Blue not returning 500 in chaos mode (got $blue_status)"
    exit 1
fi

# Verify Nginx fails over to Green
nginx_status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/)
if [ "$nginx_status" = "200" ]; then
    log_success "Nginx successfully failed over to Green"
else
    log_error "Nginx failover failed (got $nginx_status)"
    exit 1
fi

# Deactivate chaos
if curl -f -s -X POST http://localhost:8081/chaos/stop > /dev/null 2>&1; then
    log_success "Chaos mode deactivated"
else
    log_warning "Failed to deactivate chaos mode"
fi
echo ""

# Step 10: Test health checks
log_step "Testing health check endpoints..."

for port in 8080 8081 8082; do
    if health=$(curl -s http://localhost:$port/health 2>&1); then
        log_success "Health check on port $port: OK"
    else
        log_error "Health check on port $port: FAILED"
        exit 1
    fi
done
echo ""

# Step 11: Verify Docker healthchecks
log_step "Verifying Docker healthcheck status..."
health_status=$($DOCKER_COMPOSE ps | grep -E "(app-blue|app-green)" | grep -c "healthy" || echo 0)
if [ "$health_status" -ge 2 ]; then
    log_success "Docker healthchecks passing ($health_status/2)"
else
    log_warning "Some Docker healthchecks may be pending"
fi
echo ""

# Step 12: Generate test report
log_step "Generating test report..."
cat > test-report.txt << EOF
Blue/Green Deployment Test Report
Generated: $(date)
Duration: ${SECONDS}s

Test Results:
✓ Pre-flight checks passed
✓ Images built successfully
✓ Stack started successfully
✓ Services became healthy
✓ Baseline connectivity tests passed
✓ Failover verification passed
✓ Chaos mode tests passed
✓ Health checks passed

Services:
$($DOCKER_COMPOSE ps)

Docker Images:
$(docker images | grep -E "REPOSITORY|blue-app|green-app")

Log File: $LOG_FILE
EOF

log_success "Test report saved to test-report.txt"
echo ""

# Cleanup
cleanup

# Final summary
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║            ALL TESTS PASSED SUCCESSFULLY! ✓               ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Test duration: ${SECONDS}s"
echo -e "Log file: ${CYAN}$LOG_FILE${NC}"
echo -e "Report file: ${CYAN}test-report.txt${NC}"
echo ""

exit 0
