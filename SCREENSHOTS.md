# Screenshot Instructions for Submission

This document provides step-by-step instructions for capturing the required screenshots for Stage 2 submission.

## Required Screenshots

### 📸 Screenshot #1: Slack Alert – Failover Event

**What to capture:** Slack message showing failover detection when Blue fails and Green takes over.

**Where to find it:**
1. Open your Slack workspace
2. Navigate to the channel configured with your Slack webhook. 
3. Look for messages sent around these timestamps:

**Expected message format:**
```
🔄 Failover Detected

Pool Change: blue → green
Timestamp: 2025-10-30 16:24:29 UTC
Reason: Blue pool became unavailable

The system automatically switched to the green pool to maintain service availability.
```

**Screenshot requirements:**
- ✅ Show full Slack message with emoji and formatting
- ✅ Include timestamp
- ✅ Show channel name (if visible)
- ✅ Readable text (no tight cropping)

---

### 📸 Screenshot #2: Slack Alert – Recovery Event (Alternative)

**What to capture:** Slack message showing recovery when system returns to primary pool.

**Where to find it:**
1. Same Slack channel as above
2. Look for message with timestamp around:
   - **16:25:46 UTC** (Recovery: green → blue)

**Expected message format:**
```
✅ System Recovered

Pool Change: green → blue
Timestamp: 2025-10-30 16:25:46 UTC
Recovery Time: 78 seconds

The system has successfully recovered and returned to the blue pool.
```

**Note:** If you don't have a "High Error Rate" alert (Screenshot #2 requirement), you can use this recovery alert or a second failover alert as proof of Slack integration working.

---

### 📸 Screenshot #3: Container Logs – Structured Nginx Logs

**What to capture:** Nginx access log showing structured log format with all required fields.

**How to capture:**

Run this command to get clean log output:
```bash
ssh -i aws/blue-green-key.pem ec2-user@16.16.216.200 \
  "sudo docker exec nginx-proxy tail -10 /var/log/nginx/access.log"
```

**Expected output format:**
```
green|Green-v1.0.0|200|172.19.0.3:80|0.001|0.001|200|GET /version HTTP/1.1
green|Green-v1.0.0|200|172.19.0.3:80|0.001|0.001|200|GET /version HTTP/1.1
green|Green-v1.0.0|500, 200|172.19.0.2:80, 172.19.0.3:80|0.001|0.001, 0.000|200|GET /version HTTP/1.1
```

**Log format explanation:**
```
pool | release | upstream_status | upstream_addr | request_time | upstream_response_time | status | request
```

**Screenshot requirements:**
- ✅ Show at least 5-10 log lines
- ✅ Include the terminal command at the top (for context)
- ✅ Highlight or point out the structured format fields
- ✅ If possible, include a line showing failover (with "500, 200" and two addresses)

---

## 🎯 Log Format Field Descriptions

For your screenshot annotations or submission documentation:

| Field | Description | Example |
|-------|-------------|---------|
| `pool` | Active upstream pool (blue or green) | `green` |
| `release` | Release ID from X-Release-Id header | `Green-v1.0.0` |
| `upstream_status` | HTTP status from upstream (shows retry: `500, 200`) | `200` or `500, 200` |
| `upstream_addr` | Upstream server address(es) | `172.19.0.3:80` or `172.19.0.2:80, 172.19.0.3:80` |
| `request_time` | Total request processing time (seconds) | `0.001` |
| `upstream_response_time` | Time to receive upstream response | `0.001` or `0.001, 0.000` |
| `status` | Final HTTP status returned to client | `200` |
| `request` | HTTP request line | `GET /version HTTP/1.1` |

---

## 📋 Additional Evidence (Optional but Recommended)

### Alert Watcher Logs

To show the watcher detected events and sent alerts:

```bash
ssh -i aws/blue-green-key.pem ec2-user@16.16.216.200 \
  "sudo docker logs alert-watcher 2>&1 | grep -E 'Failover detected|Slack alert sent' | tail -10"
```

**Expected output:**
```
[2025-10-30 16:24:28] INFO: Failover detected: blue → green
[2025-10-30 16:24:29] INFO: ✓ Slack alert sent: failover
[2025-10-30 16:25:46] INFO: Failover detected: green → blue
[2025-10-30 16:25:46] INFO: ✓ Slack alert sent: recovery
[2025-10-30 16:35:07] INFO: Failover detected: blue → green
[2025-10-30 16:35:07] INFO: ✓ Slack alert sent: failover
```

---

## 🚨 Generating Error Rate Alert (If Needed)

If you need to generate a "High Error Rate" alert for Screenshot #2:

```bash
# 1. Stop the green pool (force errors to reach clients)
ssh -i aws/blue-green-key.pem ec2-user@16.16.216.200 \
  "cd /opt/blue-green-deployment-strategy && sudo docker-compose stop app_green"

# 2. Enable chaos on blue
curl -X POST http://16.16.216.200:8081/chaos/start?mode=error

# 3. Generate traffic (will get 500s since green is down)
for i in {1..50}; do 
  curl -s http://16.16.216.200:8080/version
  sleep 0.1
done

# 4. Check for error rate alert in logs
ssh -i aws/blue-green-key.pem ec2-user@16.16.216.200 \
  "sudo docker logs alert-watcher --tail 20"

# 5. Check Slack for "⚠️ High Error Rate" message

# 6. Restore services
curl -X POST http://16.16.216.200:8081/chaos/stop
ssh -i aws/blue-green-key.pem ec2-user@16.16.216.200 \
  "cd /opt/blue-green-deployment-strategy && sudo docker-compose start app_green"
```

**Expected Slack message:**
```
⚠️ High Error Rate

Error Rate: 52.00%
Threshold: 2%
Current Pool: blue
Window Size: 200 requests

High error rate detected. Investigate immediately.
```

---

## ✅ Submission Checklist

Before submitting, ensure you have:

- [ ] Screenshot #1: Slack failover alert (clear, readable, with timestamp)
- [ ] Screenshot #2: Slack error-rate alert OR recovery alert
- [ ] Screenshot #3: Nginx structured logs (showing field format)
- [ ] All screenshots are properly labeled/annotated
- [ ] Screenshots show timestamps for verification
- [ ] No sensitive information visible (webhook URLs, IPs if needed)

---

## 📝 Screenshot Filename Suggestions

Organize your screenshots with clear names:

```
screenshots/
  ├── 01-slack-failover-alert.png
  ├── 02-slack-error-rate-alert.png (or 02-slack-recovery-alert.png)
  └── 03-nginx-structured-logs.png
```

---

## 🔗 Verification Links

- **Production Endpoint**: http://16.16.216.200:8080/version
- **Blue Direct**: http://16.16.216.200:8081/version
- **Green Direct**: http://16.16.216.200:8082/version
- **EC2 Instance**: i-00b0400e5cfddf9cb (eu-north-1)

---

**Last Updated**: 2025-10-30  
**Alerts Sent**: 3 failover alerts, 1 recovery alert  
**System Status**: ✅ All services operational

*P.S: Check this [link](https://drive.google.com/drive/folders/1tDA-oBFBLDdImdJ-pokeOhhzCHRqCcVP?usp=sharing) to see images.*