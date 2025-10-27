# Quick Start Guide for Graders/CI

This guide provides the exact commands to build, run, and verify the Blue/Green deployment system.

## Prerequisites

- Docker 20.10+
- Docker Compose 2.0+
- curl (for testing)

## Step 1: Build the Images (30 seconds)

```bash
# Build both blue and green images
./build-images.sh

# Or manually:
docker build -t blue-app:local ./app
docker build -t green-app:local ./app
```

## Step 2: Start the Stack (10 seconds)

```bash
# Start all services
docker-compose up -d

# Wait for services to be ready
sleep 10

# Verify all services are running
docker-compose ps
```

Expected output: 3 containers running (nginx, app_blue, app_green)

## Step 3: Verify Baseline (Blue Active)

```bash
# Test via Nginx (should route to Blue)
curl -i http://localhost:8080/
```

**Expected:**
- Status: `200 OK`
- Header: `X-App-Pool: blue`
- Header: `X-Release-Id: v1.0.1-blue`

## Step 4: Run Automated Verification

```bash
# Run the complete failover test
./verify-failover.sh
```

**This script will:**
1. ✅ Verify baseline traffic goes to Blue
2. 🔥 Trigger chaos mode on Blue (simulate failures)
3. 📊 Send 100 requests and measure responses
4. ✅ Assert zero non-200s and ≥95% responses from Green
5. 🧹 Clean up (stop chaos mode)

**Expected output:**
```
==================================
✓ ALL TESTS PASSED
==================================
```

Exit code: `0` (success)

## Step 5: Manual Testing (Optional)

### Test Direct Access to Instances

```bash
# Blue instance (primary)
curl http://localhost:8081/

# Green instance (backup)
curl http://localhost:8082/
```

### Test Chaos Endpoints

```bash
# Trigger failure on Blue
curl -X POST http://localhost:8081/chaos/start

# Verify Blue returns 500
curl -i http://localhost:8081/

# Verify Nginx fails over to Green (returns 200)
curl -i http://localhost:8080/

# Stop chaos mode
curl -X POST http://localhost:8081/chaos/stop
```

### Test Health Endpoints

```bash
# Via Nginx
curl http://localhost:8080/health

# Direct to Blue
curl http://localhost:8081/health

# Direct to Green
curl http://localhost:8082/health
```

## Step 6: Cleanup

```bash
# Stop and remove all containers
docker-compose down -v

# Remove images (optional)
docker rmi blue-app:local green-app:local
```

## Acceptance Criteria Checklist

The system passes if:

- ✅ **Baseline**: Initial requests go to Blue (X-App-Pool: blue)
- ✅ **Zero errors**: After Blue failure, 0% non-200 responses
- ✅ **Failover**: ≥95% of responses come from Green after Blue failure
- ✅ **Headers preserved**: X-App-Pool and X-Release-Id correctly forwarded
- ✅ **Fast failover**: Sub-2-second timeout ensures rapid recovery

## Troubleshooting

### Services won't start

```bash
# Check Docker daemon
docker info

# View logs
docker-compose logs

# Rebuild from scratch
docker-compose down -v
./build-images.sh
docker-compose up -d
```

### Verification script fails

```bash
# Ensure services are healthy
docker-compose ps

# Check nginx can reach backends
docker exec nginx-proxy wget -O- http://app_blue:80/health
docker exec nginx-proxy wget -O- http://app_green:80/health

# Reset chaos mode
curl -X POST http://localhost:8081/chaos/stop
curl -X POST http://localhost:8082/chaos/stop
```

### Port conflicts

If ports 8080, 8081, or 8082 are in use:

```bash
# Find processes using the ports
sudo lsof -i :8080
sudo lsof -i :8081
sudo lsof -i :8082

# Stop conflicting services or edit docker-compose.yml to use different ports
```

## CI/CD Integration

The GitHub Actions workflow (`.github/workflows/verify-failover.yml`) automatically runs these steps on every push:

1. Build images
2. Start stack
3. Run verification
4. Upload logs on failure
5. Cleanup

## Key Files Reference

| File | Purpose |
|------|---------|
| `.env` | Environment variables (ACTIVE_POOL, image tags, release IDs) |
| `docker-compose.yml` | Service orchestration |
| `nginx.conf.template` | Nginx config with failover logic |
| `app/` | Node.js test application |
| `verify-failover.sh` | Automated verification script |
| `build-images.sh` | Helper to build both images |
| `README.md` | Complete documentation |
| `GUIDE.md` | Detailed implementation guide |

## Time Estimates

- Build images: ~30 seconds
- Start stack: ~10 seconds
- Run verification: ~15 seconds
- **Total**: ~1 minute end-to-end

---

**Questions?** See [README.md](./README.md) for full documentation or [GUIDE.md](./GUIDE.md) for implementation details.
