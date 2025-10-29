#!/bin/bash
# Local CI Test - Simulates GitHub Actions workflow
# Run this before pushing to verify everything works

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ERRORS=0

log_step() {
    echo -e "${CYAN}==>${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
    ERRORS=$((ERRORS + 1))
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║          Local CI Test - GitHub Actions Simulation            ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Cleanup function
cleanup() {
    log_step "Cleaning up..."
    docker compose down -v 2>/dev/null || true
    # Restore original .env
    if [ -f .env.backup ]; then
        mv .env.backup .env
        log_success "Restored original .env"
    fi
}

trap cleanup EXIT

# Test both pools
for ACTIVE_POOL in blue green; do
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  Testing with ACTIVE_POOL=${ACTIVE_POOL}${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Backup original .env
    log_step "Backing up .env"
    cp .env .env.backup

    # Set ACTIVE_POOL
    log_step "Setting ACTIVE_POOL=${ACTIVE_POOL}"
    sed -i "s/ACTIVE_POOL=.*/ACTIVE_POOL=${ACTIVE_POOL}/" .env
    grep "ACTIVE_POOL" .env || log_error "Failed to set ACTIVE_POOL"

    # Check Docker
    log_step "Verifying Docker is available"
    if ! docker --version > /dev/null 2>&1; then
        log_error "Docker not found"
        continue
    fi
    log_success "Docker is available"

    # Check Docker Compose
    log_step "Verifying Docker Compose is available"
    if docker compose version > /dev/null 2>&1; then
        log_success "Docker Compose V2 is available"
    elif docker-compose --version > /dev/null 2>&1; then
        log_warning "Using legacy docker-compose (V1)"
        COMPOSE_CMD="docker-compose"
    else
        log_error "Docker Compose not found"
        continue
    fi
    COMPOSE_CMD="${COMPOSE_CMD:-docker compose}"

    # Build images
    log_step "Building Blue app image"
    if docker build -t blue-app:local ./app > /dev/null 2>&1; then
        log_success "Blue image built"
    else
        log_error "Failed to build Blue image"
        continue
    fi

    log_step "Building Green app image"
    if docker build -t green-app:local ./app > /dev/null 2>&1; then
        log_success "Green image built"
    else
        log_error "Failed to build Green image"
        continue
    fi

    # Start stack
    log_step "Starting Docker Compose stack"
    if $COMPOSE_CMD up -d > /dev/null 2>&1; then
        log_success "Stack started"
    else
        log_error "Failed to start stack"
        $COMPOSE_CMD logs
        continue
    fi

    log_step "Waiting for services to be ready (10s)"
    sleep 10

    # Show containers
    log_step "Running containers:"
    $COMPOSE_CMD ps

    # Wait for health
    log_step "Checking service health"
    MAX_WAIT=30
    for i in $(seq 1 $MAX_WAIT); do
        if curl -f http://localhost:8080/healthz > /dev/null 2>&1; then
            log_success "Nginx is responding"
            break
        fi
        if [ $i -eq $MAX_WAIT ]; then
            log_error "Services not healthy after ${MAX_WAIT}s"
            $COMPOSE_CMD logs
            continue 2
        fi
        sleep 1
    done

    # Verify all services are reachable
    log_step "Verifying all services are reachable"
    if curl -f http://localhost:8081/healthz > /dev/null 2>&1; then
        log_success "Blue is reachable"
    else
        log_error "Blue not reachable"
    fi

    if curl -f http://localhost:8082/healthz > /dev/null 2>&1; then
        log_success "Green is reachable"
    else
        log_error "Green not reachable"
    fi

    # Test /version endpoint
    log_step "Testing /version endpoint"
    RESPONSE=$(curl -s http://localhost:8080/version)
    if echo "$RESPONSE" | grep -q "\"pool\":\"${ACTIVE_POOL}\""; then
        log_success "Correct pool in response: ${ACTIVE_POOL}"
    else
        log_error "Wrong pool in response. Expected: ${ACTIVE_POOL}, Got: $RESPONSE"
    fi

    # Test headers
    log_step "Testing headers"
    HEADERS=$(curl -sI http://localhost:8080/version)
    if echo "$HEADERS" | grep -q "X-App-Pool: ${ACTIVE_POOL}"; then
        log_success "X-App-Pool header correct: ${ACTIVE_POOL}"
    else
        log_error "X-App-Pool header incorrect"
    fi

    if echo "$HEADERS" | grep -q "X-Release-Id:"; then
        log_success "X-Release-Id header present"
    else
        log_error "X-Release-Id header missing"
    fi

    # Run failover verification
    log_step "Running failover verification script"
    if [ -x ./verify-failover.sh ]; then
        if ./verify-failover.sh; then
            log_success "Failover verification passed"
        else
            log_error "Failover verification failed"
            $COMPOSE_CMD logs
        fi
    else
        log_warning "verify-failover.sh not found or not executable"
    fi

    # Cleanup this iteration
    log_step "Stopping stack"
    $COMPOSE_CMD down -v > /dev/null 2>&1 || true
    
    # Restore .env for next iteration
    if [ -f .env.backup ]; then
        mv .env.backup .env
    fi
    
    echo ""
done

# Final summary
echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                    Test Summary                                ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed! Safe to push to GitHub.${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}✗ ${ERRORS} error(s) found. Fix before pushing!${NC}"
    echo ""
    exit 1
fi
