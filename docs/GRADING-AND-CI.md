# Grading Criteria & CI Workflow Customization Guide

## 📊 Automated Grading Criteria

### Local Testing Criteria (via `local-test.sh`)

The local test suite validates the following acceptance criteria:

#### 1. **Pre-flight Checks** (Pass/Fail)
- ✅ Docker daemon is running and accessible
- ✅ Docker Compose is installed (v1 or v2)
- ✅ All required files present (`.env`, `docker-compose.yml`, `nginx.conf.template`, etc.)

**Grading:** Must pass all checks to proceed. **FAIL** if any check fails.

---

#### 2. **Image Build** (Pass/Fail)
- ✅ `blue-app:local` builds successfully
- ✅ `green-app:local` builds successfully

**Grading:** **FAIL** if either build fails.

---

#### 3. **Stack Deployment** (Pass/Fail)
- ✅ All 3 services start (`nginx`, `app_blue`, `app_green`)
- ✅ Services become healthy within 60 seconds
- ✅ All ports accessible (8080, 8081, 8082)

**Grading:** **FAIL** if services don't start or timeout.

---

#### 4. **Baseline Connectivity** (Pass/Fail)
- ✅ Nginx returns HTTP 200
- ✅ Correct pool routing (`X-App-Pool: blue`)
- ✅ Correct release ID (`X-Release-Id: v1.0.1-blue`)
- ✅ Direct Blue access (port 8081) works
- ✅ Direct Green access (port 8082) works

**Grading:** **FAIL** if any endpoint unreachable or headers incorrect.

---

#### 5. **Failover Verification** (Critical - 40% weight)

**Test Process:**
1. Trigger chaos mode on active pool (Blue)
2. Send 100 HTTP requests to Nginx
3. Analyze responses

**Acceptance Criteria:**
| Metric | Requirement | Weight |
|--------|-------------|--------|
| **Error Rate** | 0% (zero 5xx/4xx responses) | 20% |
| **Traffic Distribution** | ≥95% to backup pool (Green) | 15% |
| **Failover Time** | <5s (all 100 requests complete) | 5% |

**Grading:**
- ✅ **PASS:** 0% errors AND ≥95% green traffic
- ❌ **FAIL:** Any non-200 response OR <95% green traffic

**Example Output:**
```
==================================
Acceptance Criteria
==================================
1. Zero non-200 responses: ✓ PASS (0 errors found)
2. ≥95% responses from Green: ✓ PASS (100.0%, need ≥95%)

✓ TESTS PASSED
```

---

#### 6. **Chaos Mode Control** (Pass/Fail)
- ✅ POST `/chaos/start` activates chaos mode (returns 500)
- ✅ Nginx routes to backup during chaos
- ✅ POST `/chaos/stop` deactivates chaos (returns 200)

**Grading:** **FAIL** if chaos endpoints don't work or failover doesn't occur.

---

#### 7. **Health Checks** (Pass/Fail)
- ✅ `/health` endpoint returns 200 on all services
- ✅ Docker healthchecks eventually pass (30s grace period)

**Grading:** **FAIL** if health endpoints timeout or return errors.

---

### Overall Local Test Grading

**Scoring Model:**
```
Total Score = (Pre-flight × 5%) + 
              (Build × 10%) + 
              (Deployment × 15%) + 
              (Baseline × 10%) + 
              (Failover × 40%) + 
              (Chaos × 15%) + 
              (Health × 5%)
```

**Pass Threshold:** ≥85% (all critical tests must pass)

**Grade Levels:**
- 🟢 **A+ (95-100%):** All tests pass, 0% errors, 100% green traffic
- 🟢 **A (90-94%):** All tests pass, 0% errors, ≥95% green traffic
- 🟡 **B (85-89%):** Minor warnings, all critical tests pass
- 🔴 **F (<85%):** Any critical test failure

---

## 🤖 CI/CD Grading Criteria (GitHub Actions)

### Workflow: `.github/workflows/verify-failover.yml`

#### Matrix Testing Strategy

The CI runs **2 parallel test jobs**:
- ✅ Job 1: `ACTIVE_POOL=blue` (Blue primary, Green backup)
- ✅ Job 2: `ACTIVE_POOL=green` (Green primary, Blue backup)

**Grading:** **FAIL** if either matrix job fails.

---

#### CI Test Phases

**Phase 1: Build Verification**
```yaml
- Build Blue app image
- Build Green app image
- Verify images exist
```
**Grading:** **FAIL** if builds fail.

---

**Phase 2: Service Health**
```yaml
- Start Docker Compose stack
- Wait up to 30 attempts (60s total)
- Verify all services respond to /health
```
**Grading:** **FAIL** if services don't become healthy.

---

**Phase 3: Failover Test**
```yaml
- Run verify-failover.sh
- Must achieve:
  • 0% error rate
  • ≥95% backup pool traffic
```
**Grading:** **FAIL** if acceptance criteria not met.

---

**Phase 4: Performance Benchmark**
```yaml
- Normal Operation: 1000 requests, 10 concurrent
- Failover Test: 100 requests during chaos mode
- Measure: Requests/sec, latency, failed requests
```

**Benchmark Thresholds:**
| Metric | Minimum | Target | Status |
|--------|---------|--------|--------|
| Requests/sec (normal) | ≥50 | ≥200 | ⚠️ Info |
| Failed requests (normal) | 0 | 0 | ❌ Fail |
| Failed requests (failover) | ≤5% | 0% | ⚠️ Warning |
| Failover time | <10s | <5s | ⚠️ Info |

**Grading:** **FAIL** if failed requests >5% during failover.

---

**Phase 5: Artifact Upload**
```yaml
- Upload benchmark results (30-day retention)
- Upload logs on failure (7-day retention)
```
**Grading:** Informational only (no score impact).

---

### CI Grading Summary

**Critical Criteria (Must Pass):**
1. ✅ Both matrix jobs (blue & green) complete successfully
2. ✅ All services start and become healthy
3. ✅ Failover test: 0% errors, ≥95% backup traffic
4. ✅ Build artifacts generated successfully

**Warning Criteria (Non-blocking):**
1. ⚠️ Performance benchmarks below target
2. ⚠️ Docker Compose version warnings
3. ⚠️ Health checks slow to respond

**Auto-Fail Conditions:**
- ❌ Any build failure
- ❌ Services don't start within 60s
- ❌ Error rate >0%
- ❌ Backup pool traffic <95%
- ❌ Exit code ≠ 0 from verify-failover.sh

---

## 🛠️ Customizing the CI Workflow

### 1. Add Your Repository Details

Replace the CI badge in `README.md`:

```markdown
![CI Status](https://github.com/baydre/blue-green-deployment-strategy/actions/workflows/verify-failover.yml/badge.svg)
```

Update with your username:
```markdown
![CI Status](https://github.com/YOUR-USERNAME/YOUR-REPO/actions/workflows/verify-failover.yml/badge.svg)
```

---

### 2. Adjust Timeout Values

Edit `.github/workflows/verify-failover.yml`:

```yaml
jobs:
  verify-failover:
    timeout-minutes: 10  # Change from 10 to 15 for slower environments
```

For service health checks:
```yaml
- name: Wait for services to be healthy
  run: |
    for i in {1..30}; do  # Change 30 to 60 for 2-minute timeout
      if curl -f http://localhost:8080/health 2>/dev/null; then
        break
      fi
      sleep 2
    done
```

---

### 3. Add Slack/Discord Notifications

Add notification step after tests:

```yaml
- name: Notify on failure
  if: failure()
  uses: slackapi/slack-github-action@v1.24.0
  with:
    webhook-url: ${{ secrets.SLACK_WEBHOOK_URL }}
    payload: |
      {
        "text": "❌ Blue/Green deployment test failed on ${{ matrix.active_pool }}",
        "blocks": [
          {
            "type": "section",
            "text": {
              "type": "mrkdwn",
              "text": "*Repo:* ${{ github.repository }}\n*Branch:* ${{ github.ref }}"
            }
          }
        ]
      }
```

---

### 4. Add Security Scanning

Add before deployment:

```yaml
- name: Run Trivy security scan
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: 'blue-app:local'
    format: 'sarif'
    output: 'trivy-results.sarif'

- name: Upload Trivy results to GitHub Security
  uses: github/codeql-action/upload-sarif@v2
  with:
    sarif_file: 'trivy-results.sarif'
```

---

### 5. Add Deployment Gate (Require Manual Approval)

```yaml
jobs:
  verify-failover:
    # ... existing steps ...

  deploy-production:
    needs: verify-failover
    runs-on: ubuntu-latest
    environment: production  # Requires approval in GitHub Settings
    steps:
      - name: Deploy to production
        run: |
          echo "Deploying to production..."
          # Add your deployment commands
```

Then in GitHub: **Settings → Environments → production → Add protection rule**

---

### 6. Increase Test Coverage

Add integration tests:

```yaml
- name: Run integration tests
  run: |
    # Test pool switching
    sed -i 's/ACTIVE_POOL=blue/ACTIVE_POOL=green/' .env
    docker compose up -d --force-recreate nginx
    sleep 5
    
    # Verify routing changed
    POOL=$(curl -s -I http://localhost:8080/ | grep X-App-Pool | awk '{print $2}' | tr -d '\r')
    if [ "$POOL" != "green" ]; then
      echo "Pool switch failed"
      exit 1
    fi
```

---

### 7. Add Load Testing

```yaml
- name: Install k6
  run: |
    sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
    echo "deb https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
    sudo apt-get update
    sudo apt-get install k6

- name: Run load test
  run: |
    cat > loadtest.js << 'EOF'
    import http from 'k6/http';
    import { check } from 'k6';
    
    export let options = {
      vus: 50,
      duration: '30s',
    };
    
    export default function() {
      let res = http.get('http://localhost:8080/');
      check(res, {
        'status is 200': (r) => r.status === 200,
      });
    }
    EOF
    
    k6 run loadtest.js --out json=loadtest-results.json
```

---

### 8. Enable Caching for Faster Builds

```yaml
- name: Set up Docker Buildx with cache
  uses: docker/setup-buildx-action@v3
  with:
    driver-opts: |
      image=moby/buildkit:latest
      cache-from=type=gha
      cache-to=type=gha,mode=max

- name: Build Blue app image with cache
  uses: docker/build-push-action@v5
  with:
    context: ./app
    tags: blue-app:local
    cache-from: type=gha
    cache-to: type=gha,mode=max
```

---

### 9. Multi-Environment Testing

```yaml
strategy:
  matrix:
    active_pool: [blue, green]
    environment: [dev, staging, production]
```

Then use environment-specific compose files:
```yaml
- name: Start stack for ${{ matrix.environment }}
  run: |
    docker compose \
      -f docker-compose.yml \
      -f docker-compose.${{ matrix.environment }}.yml \
      up -d
```

---

### 10. Add Code Coverage for App

```yaml
- name: Run app tests with coverage
  run: |
    cd app
    npm install --save-dev jest @types/jest
    npm test -- --coverage
    
- name: Upload coverage to Codecov
  uses: codecov/codecov-action@v3
  with:
    files: ./app/coverage/lcov.info
```

---

## 📈 Viewing CI Results

### In GitHub UI

1. Navigate to **Actions** tab
2. Click on the latest workflow run
3. View:
   - ✅ Matrix job results (blue vs green)
   - 📊 Benchmark artifacts
   - 📝 Logs for each step

### CI Badge States

```markdown
![CI](badge.svg?status=passing)  # ✅ All tests passed
![CI](badge.svg?status=failing)  # ❌ Tests failed
![CI](badge.svg?status=running)  # 🔵 Tests in progress
```

---

## 🚨 Common CI Failures & Fixes

### Issue: Services don't become healthy

**Symptoms:**
```
Error: Services did not become healthy within 60s
```

**Fix:**
```yaml
# Increase wait time
for i in {1..60}; do  # Was 30, now 60
```

---

### Issue: Performance benchmark fails

**Symptoms:**
```
ab: failed requests: 15
```

**Fix:**
1. Increase `max_fails` in nginx.conf.template
2. Increase timeout values
3. Reduce concurrent connections: `ab -n 1000 -c 5`

---

### Issue: Matrix job only passes for one pool

**Symptoms:**
```
✅ Job 1 (blue): Success
❌ Job 2 (green): Failed
```

**Fix:**
Check that `.env` is properly updated in the CI workflow:
```yaml
- name: Set ACTIVE_POOL for matrix
  run: |
    sed -i 's/ACTIVE_POOL=.*/ACTIVE_POOL=${{ matrix.active_pool }}/' .env
    cat .env  # Add this to verify
```

---

## 🎓 Grading Summary

### Perfect Score Checklist

- [ ] All pre-flight checks pass
- [ ] Both images build successfully
- [ ] All services start within 60s
- [ ] Baseline connectivity: 100% success
- [ ] **Failover: 0% errors, 100% backup traffic**
- [ ] Chaos mode works correctly
- [ ] All health checks pass
- [ ] Both matrix jobs (blue & green) pass
- [ ] Performance benchmarks meet targets
- [ ] No Docker/Compose warnings
- [ ] CI completes in <10 minutes

### Minimum Passing Score

- [ ] Services start and respond
- [ ] **Failover: 0% errors, ≥95% backup traffic**
- [ ] At least one matrix job passes
- [ ] No critical failures

---

## 📚 Additional Resources

- **Local Testing:** `./local-test.sh --help`
- **Makefile Commands:** `make help`
- **Production Guide:** `PRODUCTION.md`
- **Quick Start:** `QUICKSTART.md`
- **Rollback Procedure:** `./rollback.sh --help`

---

## 🎯 Next Steps

1. **Run local tests:** `./local-test.sh`
2. **Push to GitHub:** CI will run automatically
3. **Check CI status:** Click the badge in README.md
4. **Download benchmarks:** Actions → Latest run → Artifacts
5. **Customize as needed:** Use this guide for modifications

**Happy Deploying! 🚀**
