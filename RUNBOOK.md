# 🚨 Blue-Green Deployment Runbook

**Operational guide for responding to alerts from the Blue-Green deployment monitoring system.**

---

## 📋 Table of Contents

1. [Alert Types](#alert-types)
2. [Response Procedures](#response-procedures)
3. [Maintenance Mode](#maintenance-mode)
4. [Common Commands](#common-commands)
5. [Troubleshooting](#troubleshooting)

---

## 🔔 Alert Types

### 1. 🔄 Failover Detected

**What it means:**  
Traffic has automatically switched from one pool (Blue/Green) to the other due to upstream failures.

**Example Alert:**
```
🔄 Blue-Green Failover Detected
From: Blue-v1.0.0
To: Green-v1.0.0
Time: 2025-10-30 14:23:45 UTC
Reason: Upstream failure detected
```

**Why it happens:**
- Primary pool (e.g., Blue) started returning 5xx errors
- Primary pool timed out (connection or read timeout)
- Primary pool became unreachable

**Severity:** ⚠️ **Medium** (System self-healed, but requires investigation)

---

### 2. ⚠️ High Error Rate

**What it means:**  
The percentage of 5xx errors from the active pool has exceeded the configured threshold (default: 2%).

**Example Alert:**
```
⚠️ High Error Rate Detected
Error Rate: 5.2%
Threshold: 2.0%
Active Pool: Green-v1.0.0
Window: Last 200 requests
```

**Why it happens:**
- Application bug causing crashes
- Resource exhaustion (memory, CPU)
- Dependency failure (database, external API)
- Cascading failures

**Severity:** 🔴 **High** (Active degradation of service quality)

---

### 3. ✅ Primary Pool Restored

**What it means:**  
Traffic has successfully returned to the primary pool (usually Blue) after a failover event.

**Example Alert:**
```
✅ Primary Pool Restored
Pool: Blue-v1.0.0
Time: 2025-10-30 14:28:12 UTC
Duration on backup: 4m 27s
```

**Why it happens:**
- Primary pool health recovered
- fail_timeout period expired and nginx retried the primary
- Issue was transient

**Severity:** ✅ **Info** (System recovered, but review logs for root cause)

---

## 🛠️ Response Procedures

### Response to: 🔄 Failover Detected

#### Immediate Actions (within 5 minutes)

1. **Verify the failover occurred:**
   ```bash
   curl -s http://YOUR_IP:8080/version | jq
   ```
   Should show the backup pool is now active.

2. **Check health of the failed pool:**
   
   If **Blue failed** (failover to Green):
   ```bash
   # Direct health check
   curl http://YOUR_IP:8081/healthz
   
   # Check if in chaos mode
   curl http://YOUR_IP:8081/version
   ```
   
   If **Green failed** (failover to Blue):
   ```bash
   curl http://YOUR_IP:8082/healthz
   curl http://YOUR_IP:8082/version
   ```

3. **Check container status:**
   ```bash
   docker-compose ps
   docker-compose logs --tail=50 app_blue
   docker-compose logs --tail=50 app_green
   ```

#### Investigation Actions (within 15 minutes)

4. **Review nginx error logs:**
   ```bash
   docker-compose logs --tail=100 nginx | grep error
   ```

5. **Check for chaos mode:**
   If chaos testing was active, stop it:
   ```bash
   # Stop chaos on Blue
   curl -X POST http://YOUR_IP:8081/chaos/stop
   
   # Stop chaos on Green
   curl -X POST http://YOUR_IP:8082/chaos/stop
   ```

6. **Check resource usage:**
   ```bash
   docker stats --no-stream
   ```

#### Resolution Actions

7. **If issue is transient:**
   - Wait for fail_timeout (5s) to expire
   - Traffic will automatically return to primary
   - Monitor for recovery alert

8. **If issue persists:**
   - Restart the affected container:
     ```bash
     docker-compose restart app_blue
     # or
     docker-compose restart app_green
     ```
   
9. **If restart doesn't help:**
   - Check application logs for errors
   - Verify environment variables are correct
   - Consider rolling back to previous image version

---

### Response to: ⚠️ High Error Rate

#### Immediate Actions (within 2 minutes)

1. **Identify which pool is failing:**
   ```bash
   # The alert tells you, but verify:
   curl -s http://YOUR_IP:8080/version | jq '.pool'
   ```

2. **Check current error rate:**
   ```bash
   # Last 50 nginx access log entries
   docker-compose exec nginx tail -50 /var/log/nginx/access.log
   ```

3. **Inspect application logs:**
   ```bash
   # If Blue is active
   docker-compose logs --tail=100 --follow app_blue
   
   # If Green is active
   docker-compose logs --tail=100 --follow app_green
   ```

#### Investigation Actions (within 10 minutes)

4. **Check for common issues:**
   - Out of memory: `docker stats --no-stream`
   - Application crashes: Look for stack traces in logs
   - Database connection issues: Check for connection errors
   - External API failures: Check for timeout errors

5. **Test direct endpoint:**
   ```bash
   # Test Blue directly
   for i in {1..10}; do curl -s -o /dev/null -w "%{http_code}\n" http://YOUR_IP:8081/version; done
   
   # Test Green directly
   for i in {1..10}; do curl -s -o /dev/null -w "%{http_code}\n" http://YOUR_IP:8082/version; done
   ```

#### Resolution Actions

6. **If error rate is acceptable after investigation:**
   - Document findings
   - Continue monitoring
   - Alert will auto-clear after cooldown period

7. **If errors are critical:**
   
   **Option A: Manual failover to backup pool**
   ```bash
   # If Blue is failing, switch to Green
   sed -i 's/ACTIVE_POOL=blue/ACTIVE_POOL=green/' .env
   docker-compose up -d nginx
   
   # If Green is failing, switch to Blue
   sed -i 's/ACTIVE_POOL=green/ACTIVE_POOL=blue/' .env
   docker-compose up -d nginx
   ```
   
   **Option B: Restart the affected pool**
   ```bash
   docker-compose restart app_blue
   # or
   docker-compose restart app_green
   ```
   
   **Option C: Roll back to previous version**
   ```bash
   # Update .env with previous image tag
   # Then restart
   docker-compose down
   docker-compose up -d
   ```

8. **Create incident report:**
   - Document error rate, duration, resolution
   - Identify root cause
   - Implement preventive measures

---

### Response to: ✅ Primary Pool Restored

#### Actions (Low Priority)

1. **Verify normal operation:**
   ```bash
   # Check a few requests are successful
   for i in {1..5}; do curl -s http://YOUR_IP:8080/version | jq '.pool'; done
   ```

2. **Review incident:**
   - How long was the system on backup?
   - What caused the initial failover?
   - Was recovery automatic or manual?

3. **Check error rates returned to normal:**
   ```bash
   docker-compose logs alert_watcher | tail -20
   ```

4. **Document in post-mortem:**
   - Timeline of events
   - Impact duration
   - Lessons learned

---

## 🔧 Maintenance Mode

### When to Enable Maintenance Mode

Use maintenance mode to **suppress alerts** during:
- Planned pool toggles (Blue → Green testing)
- Chaos testing drills
- System upgrades
- Configuration changes

### How to Enable

1. **Edit `.env` file:**
   ```bash
   MAINTENANCE_MODE=true
   ```

2. **Restart alert watcher:**
   ```bash
   docker-compose restart alert_watcher
   ```

3. **Verify maintenance mode is active:**
   ```bash
   docker-compose logs alert_watcher | grep "MAINTENANCE MODE"
   ```

### How to Disable

1. **Edit `.env` file:**
   ```bash
   MAINTENANCE_MODE=false
   ```

2. **Restart alert watcher:**
   ```bash
   docker-compose restart alert_watcher
   ```

**⚠️ Important:** Don't forget to disable maintenance mode after planned work is complete!

---

## 💻 Common Commands

### Quick Health Checks

```bash
# Check all services
docker-compose ps

# Test main endpoint
curl http://YOUR_IP:8080/version

# Test Blue directly
curl http://YOUR_IP:8081/version

# Test Green directly
curl http://YOUR_IP:8082/version

# Check which pool is active
curl -s http://YOUR_IP:8080/version | jq '.pool'
```

### Log Inspection

```bash
# Follow all logs
docker-compose logs -f

# Nginx access logs (with alert data)
docker-compose exec nginx tail -f /var/log/nginx/access.log

# Nginx error logs
docker-compose exec nginx tail -f /var/log/nginx/error.log

# Alert watcher logs
docker-compose logs -f alert_watcher

# Application logs
docker-compose logs -f app_blue app_green
```

### Manual Failover

```bash
# Switch to Green
sed -i 's/ACTIVE_POOL=blue/ACTIVE_POOL=green/' .env
docker-compose up -d nginx

# Switch to Blue
sed -i 's/ACTIVE_POOL=green/ACTIVE_POOL=blue/' .env
docker-compose up -d nginx
```

### Chaos Testing

```bash
# Start chaos mode on Blue (error mode)
curl -X POST "http://YOUR_IP:8081/chaos/start?mode=error"

# Start chaos mode on Blue (timeout mode)
curl -X POST "http://YOUR_IP:8081/chaos/start?mode=timeout"

# Stop chaos on Blue
curl -X POST "http://YOUR_IP:8081/chaos/stop"

# Check chaos status
curl http://YOUR_IP:8081/healthz | jq '.chaosMode'
```

### Service Restarts

```bash
# Restart nginx only
docker-compose restart nginx

# Restart specific app pool
docker-compose restart app_blue
docker-compose restart app_green

# Restart alert watcher
docker-compose restart alert_watcher

# Full restart
docker-compose down
docker-compose up -d
```

---

## 🔍 Troubleshooting

### Problem: No alerts being sent to Slack

**Possible Causes:**
1. SLACK_WEBHOOK_URL not configured
2. Alert cooldown still active
3. Maintenance mode enabled
4. Network connectivity issues

**Solutions:**
```bash
# Check if webhook is configured
docker-compose exec alert_watcher env | grep SLACK_WEBHOOK_URL

# Check alert watcher logs
docker-compose logs alert_watcher | grep -i slack

# Verify maintenance mode is off
docker-compose exec alert_watcher env | grep MAINTENANCE_MODE

# Test webhook manually
curl -X POST $SLACK_WEBHOOK_URL \
  -H 'Content-Type: application/json' \
  -d '{"text":"Test alert from blue-green deployment"}'
```

---

### Problem: Alerts are being sent too frequently

**Possible Causes:**
1. Alert cooldown too short
2. System is genuinely unstable

**Solutions:**
```bash
# Increase cooldown period in .env
ALERT_COOLDOWN_SEC=600  # 10 minutes

# Restart alert watcher
docker-compose restart alert_watcher

# If system is unstable, investigate root cause
docker-compose logs app_blue app_green
```

---

### Problem: Failover not detected

**Possible Causes:**
1. Nginx log format not updated
2. Alert watcher not reading logs
3. Log file permissions issue

**Solutions:**
```bash
# Check nginx log format
docker-compose exec nginx cat /etc/nginx/nginx.conf | grep log_format

# Check if logs are being written
docker-compose exec nginx tail /var/log/nginx/access.log

# Check if watcher can read logs
docker-compose logs alert_watcher | grep "Starting to tail"

# Restart alert watcher
docker-compose restart alert_watcher
```

---

### Problem: High error rate is a false positive

**Possible Causes:**
1. Threshold too low for normal traffic patterns
2. Health checks being counted
3. Legitimate failed requests (4xx)

**Solutions:**
```bash
# Adjust threshold in .env
ERROR_RATE_THRESHOLD=5  # Increase from 2% to 5%

# Adjust window size for more stability
WINDOW_SIZE=500  # Increase from 200 to 500

# Restart alert watcher
docker-compose restart alert_watcher
```

---

## 📞 Escalation

If issues persist after following this runbook:

1. **Check application health:** Verify app containers are running and healthy
2. **Review system resources:** CPU, memory, disk space
3. **Check dependencies:** External services, databases
4. **Contact on-call engineer:** Escalate if impact is user-facing
5. **Create incident ticket:** Document timeline and actions taken

---

## 📚 Additional Resources

- **Repository:** https://github.com/baydre/blue-green-deployment-strategy
- **Nginx upstream docs:** https://nginx.org/en/docs/http/ngx_http_upstream_module.html
- **Slack webhooks:** https://api.slack.com/messaging/webhooks
- **Docker Compose docs:** https://docs.docker.com/compose/

---

**Last Updated:** 2025-10-30  
**Maintainer:** DevOps Team
