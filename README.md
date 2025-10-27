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

## 📁 Project Structure

```
.
├── .env                      # Environment variables (ACTIVE_POOL, image tags, release IDs)
├── .github/
│   └── workflows/
│       └── verify-failover.yml  # CI workflow for automated testing
├── app/
│   ├── Dockerfile            # Container image for blue/green apps
│   ├── package.json          # Node.js dependencies
│   ├── server.js             # Express app with chaos endpoints
│   └── README.md             # App-specific documentation
├── aws/                      # ☁️ AWS deployment scripts
│   ├── README.md             # AWS deployment guide
│   ├── push-to-ecr.sh        # Push images to Amazon ECR
│   ├── create-iam-role.sh    # Create IAM role for EC2
│   ├── launch-ec2.sh         # Launch EC2 instance
│   ├── ec2-user-data.sh      # EC2 initialization script
│   └── cleanup.sh            # Cleanup AWS resources
├── docs/                     # 📚 Comprehensive documentation
│   ├── README.md             # Documentation index
│   ├── QUICKSTART.md         # Fast-path setup guide
│   ├── GRADING-AND-CI.md     # Grading criteria & CI customization
│   ├── PRODUCTION.md         # Production deployment guide
│   ├── DEPLOYMENT-SUMMARY.md # Complete implementation summary
│   └── GUIDE.md              # Detailed implementation guide
├── docker-compose.yml        # Service orchestration (nginx, app_blue, app_green)
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

## 🔄 Manual Pool Toggle

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
| `RELEASE_ID_BLUE` | Release identifier for Blue (exposed in header) | `v1.0.1-blue` |
| `RELEASE_ID_GREEN` | Release identifier for Green (exposed in header) | `v1.1.0-green` |
| `VERIFICATION_REQUESTS` | Number of requests in verification script | `100` |

### Port Mappings

| Service | Host Port | Container Port | Purpose |
|---------|-----------|----------------|---------|
| Nginx | 8080 | 80 | Public entry point (all client traffic) |
| Blue | 8081 | 80 | Direct access for testing/chaos injection |
| Green | 8082 | 80 | Direct access for testing/chaos injection |

## 🎓 Acceptance Criteria

The implementation satisfies these strict requirements:

✅ **Zero non-200 responses** during failover (0% error rate)  
✅ **≥95% traffic** successfully served by backup pool after primary failure  
✅ **Headers preserved**: `X-App-Pool` and `X-Release-Id` forwarded to clients  
✅ **Rapid failover**: <2s timeout ensures fast recovery  
✅ **Automated verification**: CI pipeline validates behavior on every push  

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

## 📚 Documentation

### 📖 Quick Access

| Document | Description | Best For |
|----------|-------------|----------|
| **[Quick Start](./docs/QUICKSTART.md)** | Get running in 5 minutes | Graders, First-time users |
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
