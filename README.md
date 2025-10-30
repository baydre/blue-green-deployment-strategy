# Blue/Green Deployment with Nginx Auto-Failover

[![CI Status](https://github.com/baydre/blue-green-deployment-strategy/workflows/Blue%2FGreen%20Failover%20Verification/badge.svg)](https://github.com/baydre/blue-green-deployment-strategy/actions)

Zero-downtime blue/green deployment implementation using Nginx reverse proxy with automated failover and Docker Compose orchestration.

## 🎯 Overview

This project demonstrates a production-grade blue/green deployment strategy where:
- **Nginx** acts as an intelligent reverse proxy with automatic failover
- **Blue** and **Green** are identical application instances (one active, one backup)
- **Docker Compose** orchestrates the entire stack with dynamic configuration

### Key Features

✅ **Zero-downtime failover** - Automatic recovery from backend failures  
✅ **Sub-2-second failover** - Aggressive timeouts ensure fast recovery  
✅ **Header preservation** - `X-App-Pool` and `X-Release-Id` forwarded to clients  
✅ **Chaos engineering** - Built-in failure simulation via `/chaos` endpoints  
✅ **Automated verification** - CI-ready test script validates acceptance criteria  
✅ **Real-time alert monitoring** - Python watcher with Slack integration  
✅ **Structured logging** - Comprehensive nginx logs with pool, release, and timing data  
✅ **Operator runbook** - Documented incident response procedures  

## 📁 Project Structure

```
.
├── .env                      # Environment variables (ACTIVE_POOL, image tags, release IDs)
├── .env.example              # Environment template (no secrets)
├── .github/
│   └── workflows/
│       └── verify-failover.yml  # CI workflow for automated testing
├── alert-watcher/            # 🚨 Real-time alert monitoring
│   ├── Dockerfile            # Python 3.11 alpine container
│   ├── requirements.txt      # Python dependencies (requests)
│   └── watcher.py            # Log monitoring with Slack integration
├── app/
│   ├── Dockerfile            # Container image for blue/green apps
│   ├── package.json          # Node.js dependencies
│   ├── server.js             # Express app with chaos endpoints
│   └── README.md             # App-specific documentation
├── aws/                      # ☁️ AWS deployment scripts
│   ├── README.md             # AWS deployment guide
│   ├── push-to-ecr.sh        # Push images to Amazon ECR
│   ├── create-iam-role.sh    # Create IAM role for EC2
│   ├── quick-deploy.sh       # Quick EC2 deployment
│   ├── manual-setup.sh       # EC2 setup script
│   └── cleanup.sh            # Cleanup AWS resources
├── DEPLOY.md                 # Detailed deployment guide
├── RUNBOOK.md                # 📋 Operator incident response guide
├── SCREENSHOTS.md            # 📸 Instructions for capturing verification screenshots
├── SUBMISSION.md             # Submission documentation
├── docs/                     # 📚 Comprehensive documentation
│   ├── README.md             # Documentation index
│   ├── QUICKSTART.md         # Fast-path setup guide
│   ├── GRADING-AND-CI.md     # Grading criteria & CI customization
│   ├── PRODUCTION.md         # Production deployment guide
│   ├── DEPLOYMENT-SUMMARY.md # Complete implementation summary
│   └── GUIDE.md              # Detailed implementation guide
├── docker-compose.yml        # Service orchestration (nginx, app_blue, app_green, alert_watcher)
├── docker-compose.prod.yml   # Production overrides
├── nginx.conf.template       # Nginx config with ${ACTIVE_POOL} substitution
├── build-images.sh           # Image builder script
├── local-test.sh             # Comprehensive test suite (12 phases)
├── verify-failover.sh        # Automated failover verification script
├── rollback.sh               # Automated rollback script
├── Makefile                  # Developer workflow automation (40+ commands)
└── README.md                 # This file
```

## 🚀 Quick Start

### Prerequisites

- Docker 20.10+
- Docker Compose 2.0+
- curl (for verification script)

### 1. Build the Application Images

```bash
# Build both blue and green images (they're identical, just tagged differently)
docker build -t blue-app:local ./app
docker build -t green-app:local ./app
```

### 2. Start the Stack

```bash
# Start all services in detached mode
docker-compose up -d

# Check service status
docker-compose ps

# View logs
docker-compose logs -f
```

### 3. Verify Baseline Operation

Test that traffic is routed to the Blue pool:

```bash
curl -i http://localhost:8080/
```

**Expected output:**
- Status: `200 OK`
- Header: `X-App-Pool: blue`
- Header: `X-Release-Id: v1.0.1-blue`

### 4. Test Automated Failover

```bash
# Run the automated verification script
./verify-failover.sh
```

The script will:
1. ✅ Verify baseline traffic to Blue
2. 🔥 Trigger chaos mode on Blue (simulates 500 errors)
3. 📊 Send 100 requests and measure failover
4. ✅ Validate zero non-200s and ≥95% responses from Green

## � Alert Monitoring & Slack Integration

The system includes a real-time alert watcher that monitors nginx logs and sends notifications to Slack.

### Setup Alert Monitoring

1. **Get a Slack Webhook URL**
   - Go to https://api.slack.com/messaging/webhooks
   - Create an incoming webhook for your workspace
   - Copy the webhook URL

2. **Configure Environment**
   ```bash
   # Copy the example file
   cp .env.example .env
   
   # Edit .env and set your Slack webhook
   SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
   ```

3. **Start Services with Alert Watcher**
   ```bash
   docker-compose up -d
   ```

### Alert Types

The watcher detects and reports three types of events:

| Alert | Trigger | Slack Message |
|-------|---------|---------------|
| 🔄 **Failover** | Pool changes (blue→green or green→blue) | Pool change notification with timestamp |
| ⚠️ **High Error Rate** | >2% 5xx errors in sliding 200-request window | Error rate percentage and threshold breach |
| ✅ **Recovery** | System returns to primary pool after failover | Recovery confirmation with downtime duration |

### View Alert Logs

```bash
# Check alert watcher activity
docker logs alert-watcher --tail 50

# Watch in real-time
docker logs alert-watcher -f
```

**Example output:**
```
[2025-10-30 16:24:28] INFO: Failover detected: blue → green
[2025-10-30 16:24:29] INFO: ✓ Slack alert sent: failover
[2025-10-30 16:43:53] WARNING: High error rate detected: 4.00% (threshold: 2.0%)
[2025-10-30 16:43:53] INFO: ✓ Slack alert sent: error_rate
[2025-10-30 16:49:22] INFO: ✓ Slack alert sent: recovery
```

### Test Slack Alerts

```bash
# Trigger a failover alert
curl -X POST http://localhost:8081/chaos/start?mode=error
for i in {1..20}; do curl http://localhost:8080/version; sleep 0.2; done

# Check Slack for the alert message
# Stop chaos to trigger recovery alert
curl -X POST http://localhost:8081/chaos/stop
```

### Structured Nginx Logs

All nginx access logs use a structured format for easy parsing:

**Format:** `pool|release|upstream_status|upstream_addr|request_time|upstream_response_time|status|request`

**Example:**
```
green|Green-v1.0.0|200|172.19.0.3:80|0.001|0.001|200|GET /version HTTP/1.1
green|Green-v1.0.0|500, 200|172.19.0.2:80, 172.19.0.3:80|0.001|0.001, 0.000|200|GET /version HTTP/1.1
```

**View logs:**
```bash
# Live tail
docker exec nginx-proxy tail -f /var/log/nginx/access.log

# Last 20 lines
docker exec nginx-proxy tail -20 /var/log/nginx/access.log
```

### Alert Configuration

Customize alert behavior in `.env`:

```bash
# Error rate threshold (percentage)
ERROR_RATE_THRESHOLD=2

# Sliding window size (number of requests)
WINDOW_SIZE=200

# Minimum seconds between alerts of same type
ALERT_COOLDOWN_SEC=300

# Suppress alerts during maintenance
MAINTENANCE_MODE=false
```

### Operator Runbook

See **[RUNBOOK.md](./RUNBOOK.md)** for detailed incident response procedures, including:
- Alert interpretation and severity levels
- Step-by-step troubleshooting guides
- Maintenance mode procedures
- Common failure scenarios and remediation

## �🔄 Manual Pool Toggle

To switch the active pool from Blue to Green (or vice versa):

### Method 1: Update `.env` and Restart

```bash
# Edit .env and change ACTIVE_POOL
sed -i 's/ACTIVE_POOL=blue/ACTIVE_POOL=green/' .env

# Recreate nginx service to pick up the new ACTIVE_POOL
docker-compose up -d --force-recreate nginx
```

**Impact:** Nginx container restarts (~2-3 seconds downtime). Existing connections may be dropped.

### Method 2: Manual Template Rendering + Reload (No Downtime)

```bash
# Render the template manually with the new ACTIVE_POOL
export ACTIVE_POOL=green
envsubst '${ACTIVE_POOL}' < nginx.conf.template > /tmp/nginx.conf

# Copy into running nginx container
docker cp /tmp/nginx.conf nginx-proxy:/etc/nginx/nginx.conf

# Reload nginx gracefully (zero downtime)
docker exec nginx-proxy nginx -s reload
```

**Impact:** Zero downtime. Nginx gracefully reloads config. Existing connections complete normally.

### Method 3: Use a Helper Script (Recommended)

Create `toggle-pool.sh`:

```bash
#!/bin/bash
CURRENT_POOL=$(grep ACTIVE_POOL .env | cut -d '=' -f2)
NEW_POOL=$([ "$CURRENT_POOL" = "blue" ] && echo "green" || echo "blue")

echo "Switching from $CURRENT_POOL to $NEW_POOL..."
sed -i "s/ACTIVE_POOL=$CURRENT_POOL/ACTIVE_POOL=$NEW_POOL/" .env

docker-compose up -d --force-recreate nginx
echo "Active pool is now: $NEW_POOL"
```

## 🧪 Testing & Verification

### Direct Access to App Instances

The app containers are exposed on dedicated ports for testing:

```bash
# Blue instance (primary when ACTIVE_POOL=blue)
curl http://localhost:8081/

# Green instance (backup when ACTIVE_POOL=blue)
curl http://localhost:8082/
```

### Chaos Engineering Endpoints

Simulate failures on a specific instance:

```bash
# Trigger chaos mode on Blue (all requests return 500)
curl -X POST http://localhost:8081/chaos/start

# Verify Blue is returning errors
curl -i http://localhost:8081/  # Should return 500

# Verify Nginx fails over to Green
curl -i http://localhost:8080/  # Should return 200 from Green

# Stop chaos mode
curl -X POST http://localhost:8081/chaos/stop
```

### Health Checks

```bash
# Via Nginx (routes to active pool)
curl http://localhost:8080/health

# Direct to Blue
curl http://localhost:8081/health

# Direct to Green
curl http://localhost:8082/health
```

## 📊 Architecture Details

### Nginx Upstream Pools

Two upstream pools are defined in `nginx.conf.template`:

```nginx
upstream blue_pool {
    server app_blue:80 max_fails=1 fail_timeout=10s;
    server app_green:80 backup;
}

upstream green_pool {
    server app_green:80 max_fails=1 fail_timeout=10s;
    server app_blue:80 backup;
}
```

- **Primary server**: `max_fails=1` (marked down after single failure)
- **Backup server**: Only receives traffic when primary is unavailable
- **fail_timeout**: 10s window where server stays marked down

### Failover Behavior

1. **Normal state**: All traffic goes to primary (Blue when `ACTIVE_POOL=blue`)
2. **Failure detected**: Nginx receives timeout or 5xx from primary
3. **Immediate retry**: Same request is retried against backup (Green)
4. **Client unaware**: Client receives 200 from Green, no error perceived

### Timeout Configuration

```nginx
proxy_connect_timeout 2s;   # Max time to establish connection
proxy_read_timeout 2s;      # Max time to read response
proxy_next_upstream error timeout http_5xx;  # Retry conditions
```

Aggressive 2-second timeouts ensure:
- Fast failure detection
- Quick failover to backup
- Better user experience vs. 60s default

## 🔧 Configuration Reference

### Environment Variables (`.env`)

| Variable | Purpose | Example |
|----------|---------|---------|
| `ACTIVE_POOL` | Primary upstream pool (`blue` or `green`) | `blue` |
| `BLUE_IMAGE` | Docker image for Blue instance | `blue-app:local` |
| `GREEN_IMAGE` | Docker image for Green instance | `green-app:local` |
| `RELEASE_ID_BLUE` | Release identifier for Blue (exposed in header) | `Blue-v1.0.0` |
| `RELEASE_ID_GREEN` | Release identifier for Green (exposed in header) | `Green-v1.0.0` |
| `VERIFICATION_REQUESTS` | Number of requests in verification script | `100` |
| `SLACK_WEBHOOK_URL` | Slack incoming webhook for alerts | `https://hooks.slack.com/...` |
| `ERROR_RATE_THRESHOLD` | Error percentage that triggers alert | `2` |
| `WINDOW_SIZE` | Request window for error rate calculation | `200` |
| `ALERT_COOLDOWN_SEC` | Minimum seconds between same alert type | `300` |
| `MAINTENANCE_MODE` | Suppress alerts during planned changes | `false` |

### Port Mappings

| Service | Host Port | Container Port | Purpose |
|---------|-----------|----------------|---------|
| Nginx | 8080 | 80 | Public entry point (all client traffic) |
| Blue | 8081 | 80 | Direct access for testing/chaos injection |
| Green | 8082 | 80 | Direct access for testing/chaos injection |

## 🎓 Acceptance Criteria

The implementation satisfies these strict requirements:

### Stage 1: Blue-Green Failover
✅ **Zero non-200 responses** during failover (0% error rate)  
✅ **≥95% traffic** successfully served by backup pool after primary failure  
✅ **Headers preserved**: `X-App-Pool` and `X-Release-Id` forwarded to clients  
✅ **Rapid failover**: <5s timeout ensures fast recovery  
✅ **Automated verification**: CI pipeline validates behavior on every push  

### Stage 2: Alert Monitoring
✅ **Structured logging**: Nginx logs include pool, release, upstream status, address, and timing  
✅ **Failover alerts**: Slack notifications sent when pool changes detected  
✅ **Error rate alerts**: Notifications when 5xx rate exceeds threshold (2%)  
✅ **Alert deduplication**: Cooldown mechanism prevents alert spam  
✅ **Operator runbook**: Documented incident response procedures  
✅ **Production tested**: Deployed to AWS EC2 with verified Slack integration  

## 📸 Screenshots

Verification proof for Stage 2 submission requirements:

### 📷 Required Screenshots

1. **Slack Alert - Failover Event**  
   Screenshot showing Slack message when Blue fails and Green takes over
   - See [SCREENSHOTS.md](./SCREENSHOTS.md) for detailed capture instructions
   - Located in: `screenshots/01-slack-failover-alert.png`

2. **Slack Alert - High Error Rate**  
   Screenshot showing Slack message triggered when error rate >2%
   - Located in: `screenshots/02-slack-error-rate-alert.png`

3. **Container Logs - Structured Format**  
   Screenshot showing nginx log format with structured fields
   - Located in: `screenshots/03-nginx-structured-logs.png`

**View Instructions:** See **[SCREENSHOTS.md](./SCREENSHOTS.md)** for step-by-step guide on capturing these screenshots.

## 🐛 Troubleshooting

### Services not starting

```bash
# Check Docker daemon is running
docker info

# View detailed logs
docker-compose logs

# Rebuild images
docker-compose build --no-cache
```

### Failover not working

```bash
# Check nginx config was rendered correctly
docker exec nginx-proxy cat /etc/nginx/nginx.conf | grep upstream -A 3

# Verify ACTIVE_POOL is set
docker exec nginx-proxy env | grep ACTIVE_POOL

# Test upstream connectivity from nginx
docker exec nginx-proxy wget -O- http://app_blue:80/health
docker exec nginx-proxy wget -O- http://app_green:80/health
```

### Verification script fails

```bash
# Ensure services are healthy first
docker-compose ps

# Run with debug output
bash -x ./verify-failover.sh

# Check if chaos mode is stuck active
curl -X POST http://localhost:8081/chaos/stop
curl -X POST http://localhost:8082/chaos/stop
```

### Alert watcher not sending Slack notifications

```bash
# Check if webhook URL is configured
docker exec alert-watcher env | grep SLACK_WEBHOOK_URL

# Check watcher logs for errors
docker logs alert-watcher --tail 50

# Verify watcher is processing logs
docker logs alert-watcher | grep "Processed.*requests"

# Test Slack webhook manually
curl -X POST YOUR_SLACK_WEBHOOK_URL \
  -H 'Content-Type: application/json' \
  -d '{"text":"Test message from blue-green deployment"}'
```

### Nginx logs not showing structured format

```bash
# Verify nginx config has custom log format
docker exec nginx-proxy cat /etc/nginx/nginx.conf | grep "log_format alert_format"

# Check if logs are being written
docker exec nginx-proxy ls -lh /var/log/nginx/access.log

# Regenerate nginx config and restart
docker-compose up -d --force-recreate nginx
```

## 📚 Documentation

### 📖 Quick Access

| Document | Description | Best For |
|----------|-------------|----------|
| **[Quick Start](./docs/QUICKSTART.md)** | Get running in 5 minutes | Graders, First-time users |
| **[Runbook](./RUNBOOK.md)** | Incident response & alert handling | Operators, On-call engineers |
| **[Screenshots Guide](./SCREENSHOTS.md)** | Capture verification screenshots | Submission, Documentation |
| **[Grading & CI](./docs/GRADING-AND-CI.md)** | Grading criteria & CI customization | Evaluators, Developers |
| **[Production Guide](./docs/PRODUCTION.md)** | Production deployment strategies | DevOps, SRE |
| **[Implementation Guide](./docs/GUIDE.md)** | Architecture & edge cases | Developers, Architects |
| **[Deployment Summary](./docs/DEPLOYMENT-SUMMARY.md)** | Complete overview | All audiences |

📂 **[Browse all documentation →](./docs/)**

### 🎓 Learning Path

**New to the project?**
1. Read this README for overview
2. Follow **[Quick Start Guide](./docs/QUICKSTART.md)** to deploy locally
3. Review **[Implementation Guide](./docs/GUIDE.md)** for architecture details

**Deploying to production?**
1. Study **[Production Guide](./docs/PRODUCTION.md)** for best practices
2. Check **[Grading & CI](./docs/GRADING-AND-CI.md)** for CI/CD setup
3. Use **[Deployment Summary](./docs/DEPLOYMENT-SUMMARY.md)** as checklist

**Deploying to AWS?**
1. Follow **[AWS Deployment Guide](./aws/README.md)** for EC2 setup
2. Run `./aws/push-to-ecr.sh` to push images
3. Run `./aws/launch-ec2.sh` to deploy infrastructure

---

## ☁️ AWS Deployment

Deploy to AWS EC2 with automated scripts:

```bash
# 1. Push images to Amazon ECR
./aws/push-to-ecr.sh us-east-1

# 2. Create IAM role for ECR access
./aws/create-iam-role.sh

# 3. Launch EC2 instance (replace 'your-key-pair')
./aws/launch-ec2.sh us-east-1 t3.medium your-key-pair

# 4. Wait ~5 minutes, then access:
# http://<public-ip>:8080
```

**See [aws/README.md](./aws/README.md) for complete deployment guide.**

---

## 📚 Additional Resources

- [App Documentation](./app/README.md) - Application-specific details
- [Nginx upstream docs](http://nginx.org/en/docs/http/ngx_http_upstream_module.html)
- [Docker Compose reference](https://docs.docker.com/compose/compose-file/)

## 🏆 CI/CD Integration

GitHub Actions workflow (`.github/workflows/verify-failover.yml`) automatically:

1. Builds blue and green images
2. Starts the Docker Compose stack
3. Waits for services to be healthy
4. Runs the verification script
5. Uploads logs on failure
6. Tears down the stack

**To run locally:**

```bash
# Simulate CI environment
docker-compose down -v
docker build -t blue-app:local ./app
docker build -t green-app:local ./app
docker-compose up -d
sleep 10
./verify-failover.sh
docker-compose down -v
```

## 📝 License

See [LICENSE](./LICENSE) file for details.

---

**Built with ❤️ for zero-downtime deployments**
