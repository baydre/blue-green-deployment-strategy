#!/usr/bin/env python3
"""
Alert Watcher for Blue-Green Deployment
Monitors Nginx access logs and sends Slack alerts on failovers and error-rate spikes.
"""

import os
import re
import time
import logging
from collections import deque
from datetime import datetime
from typing import Optional, Dict, Any
import requests

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] %(levelname)s: %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)

# Environment variables
SLACK_WEBHOOK_URL = os.getenv('SLACK_WEBHOOK_URL', '')
ERROR_RATE_THRESHOLD = float(os.getenv('ERROR_RATE_THRESHOLD', '2.0'))
WINDOW_SIZE = int(os.getenv('WINDOW_SIZE', '200'))
ALERT_COOLDOWN_SEC = int(os.getenv('ALERT_COOLDOWN_SEC', '300'))
MAINTENANCE_MODE = os.getenv('MAINTENANCE_MODE', 'false').lower() == 'true'
LOG_FILE_PATH = os.getenv('LOG_FILE_PATH', '/var/log/nginx/access.log')

# State tracking
class WatcherState:
    def __init__(self):
        self.request_window = deque(maxlen=WINDOW_SIZE)
        self.current_pool = None
        self.last_alert_times = {}
        self.failover_start_time = None
        self.total_requests = 0
        
    def add_request(self, status: int, pool: str):
        """Add a request to the sliding window"""
        self.request_window.append({
            'status': status,
            'pool': pool,
            'timestamp': time.time()
        })
        self.total_requests += 1
        
    def get_error_rate(self) -> float:
        """Calculate 5xx error rate over the window"""
        if len(self.request_window) == 0:
            return 0.0
        
        error_count = sum(1 for req in self.request_window if 500 <= req['status'] < 600)
        return (error_count / len(self.request_window)) * 100
    
    def can_send_alert(self, alert_type: str) -> bool:
        """Check if alert cooldown has expired"""
        if MAINTENANCE_MODE:
            logger.info(f"[MAINTENANCE MODE] Alert suppressed: {alert_type}")
            return False
            
        last_time = self.last_alert_times.get(alert_type, 0)
        current_time = time.time()
        
        if current_time - last_time >= ALERT_COOLDOWN_SEC:
            self.last_alert_times[alert_type] = current_time
            return True
        
        remaining = ALERT_COOLDOWN_SEC - (current_time - last_time)
        logger.debug(f"Alert cooldown active for {alert_type}: {remaining:.0f}s remaining")
        return False

state = WatcherState()

def send_slack_alert(alert_type: str, data: Dict[str, Any]) -> bool:
    """Send alert to Slack using webhook"""
    if not SLACK_WEBHOOK_URL:
        logger.warning("SLACK_WEBHOOK_URL not configured, skipping alert")
        return False
    
    try:
        if alert_type == 'failover':
            message = create_failover_message(data)
        elif alert_type == 'error_rate':
            message = create_error_rate_message(data)
        elif alert_type == 'recovery':
            message = create_recovery_message(data)
        else:
            logger.error(f"Unknown alert type: {alert_type}")
            return False
        
        response = requests.post(
            SLACK_WEBHOOK_URL,
            json=message,
            timeout=10
        )
        
        if response.status_code == 200:
            logger.info(f"✓ Slack alert sent: {alert_type}")
            return True
        else:
            logger.error(f"Slack webhook failed: {response.status_code} - {response.text}")
            return False
            
    except Exception as e:
        logger.error(f"Failed to send Slack alert: {e}")
        return False

def create_failover_message(data: Dict[str, Any]) -> Dict[str, Any]:
    """Create Slack message for failover event"""
    from_pool = data.get('from_pool', 'Unknown')
    to_pool = data.get('to_pool', 'Unknown')
    timestamp = datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')
    
    return {
        "text": f"🔄 Failover Detected: {from_pool} → {to_pool}",
        "blocks": [
            {
                "type": "header",
                "text": {
                    "type": "plain_text",
                    "text": "🔄 Blue-Green Failover Detected"
                }
            },
            {
                "type": "section",
                "fields": [
                    {"type": "mrkdwn", "text": f"*From:* {from_pool}"},
                    {"type": "mrkdwn", "text": f"*To:* {to_pool}"},
                    {"type": "mrkdwn", "text": f"*Time:* {timestamp}"},
                    {"type": "mrkdwn", "text": "*Reason:* Upstream failure detected"}
                ]
            },
            {
                "type": "context",
                "elements": [
                    {
                        "type": "mrkdwn",
                        "text": f"💡 *Action:* Check health of {from_pool} pool - see RUNBOOK.md for details"
                    }
                ]
            }
        ]
    }

def create_error_rate_message(data: Dict[str, Any]) -> Dict[str, Any]:
    """Create Slack message for high error rate"""
    error_rate = data.get('error_rate', 0)
    active_pool = data.get('active_pool', 'Unknown')
    timestamp = datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')
    
    return {
        "text": f"⚠️ High Error Rate: {error_rate:.1f}%",
        "blocks": [
            {
                "type": "header",
                "text": {
                    "type": "plain_text",
                    "text": "⚠️ High Error Rate Detected"
                }
            },
            {
                "type": "section",
                "fields": [
                    {"type": "mrkdwn", "text": f"*Error Rate:* {error_rate:.2f}%"},
                    {"type": "mrkdwn", "text": f"*Threshold:* {ERROR_RATE_THRESHOLD}%"},
                    {"type": "mrkdwn", "text": f"*Active Pool:* {active_pool}"},
                    {"type": "mrkdwn", "text": f"*Window:* Last {WINDOW_SIZE} requests"}
                ]
            },
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": f"*Time:* {timestamp}"
                }
            },
            {
                "type": "context",
                "elements": [
                    {
                        "type": "mrkdwn",
                        "text": f"💡 *Action:* Inspect logs with `docker-compose logs {active_pool.split('-')[0].lower()}` - see RUNBOOK.md"
                    }
                ]
            }
        ]
    }

def create_recovery_message(data: Dict[str, Any]) -> Dict[str, Any]:
    """Create Slack message for recovery to primary"""
    pool = data.get('pool', 'Unknown')
    duration = data.get('duration', 0)
    timestamp = datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')
    
    minutes, seconds = divmod(int(duration), 60)
    duration_str = f"{minutes}m {seconds}s" if minutes > 0 else f"{seconds}s"
    
    return {
        "text": f"✅ Service Recovered: {pool}",
        "blocks": [
            {
                "type": "header",
                "text": {
                    "type": "plain_text",
                    "text": "✅ Primary Pool Restored"
                }
            },
            {
                "type": "section",
                "fields": [
                    {"type": "mrkdwn", "text": f"*Pool:* {pool}"},
                    {"type": "mrkdwn", "text": f"*Time:* {timestamp}"},
                    {"type": "mrkdwn", "text": f"*Duration on backup:* {duration_str}"}
                ]
            },
            {
                "type": "context",
                "elements": [
                    {
                        "type": "mrkdwn",
                        "text": "✅ Normal operation resumed"
                    }
                ]
            }
        ]
    }

def parse_log_line(line: str) -> Optional[Dict[str, Any]]:
    """Parse nginx access log line to extract relevant fields"""
    # Expected format: pool|release|upstream_status|upstream_addr|request_time|upstream_response_time|...
    # Example: blue|Blue-v1.0.0|200|172.19.0.2:80|0.003|0.002|...
    
    parts = line.strip().split('|')
    
    if len(parts) < 6:
        return None
    
    try:
        return {
            'pool': parts[0].strip(),
            'release': parts[1].strip(),
            'upstream_status': int(parts[2].strip()) if parts[2].strip() else 0,
            'upstream_addr': parts[3].strip(),
            'request_time': float(parts[4].strip()) if parts[4].strip() else 0.0,
            'upstream_response_time': float(parts[5].strip()) if parts[5].strip() else 0.0
        }
    except (ValueError, IndexError) as e:
        logger.debug(f"Failed to parse log line: {e}")
        return None

def detect_failover(new_pool: str) -> bool:
    """Detect if a failover occurred"""
    if state.current_pool is None:
        state.current_pool = new_pool
        logger.info(f"Initial pool detected: {new_pool}")
        return False
    
    if state.current_pool != new_pool:
        logger.info(f"Failover detected: {state.current_pool} → {new_pool}")
        
        # Send failover alert
        if state.can_send_alert('failover'):
            send_slack_alert('failover', {
                'from_pool': state.current_pool,
                'to_pool': new_pool
            })
            state.failover_start_time = time.time()
        
        old_pool = state.current_pool
        state.current_pool = new_pool
        
        # Check for recovery (back to primary)
        # Assume Blue is primary based on ACTIVE_POOL=blue
        if new_pool.lower().startswith('blue') and state.failover_start_time:
            duration = time.time() - state.failover_start_time
            if state.can_send_alert('recovery'):
                send_slack_alert('recovery', {
                    'pool': new_pool,
                    'duration': duration
                })
            state.failover_start_time = None
        
        return True
    
    return False

def check_error_rate():
    """Check if error rate exceeds threshold"""
    if len(state.request_window) < WINDOW_SIZE * 0.1:  # Need at least 10% of window
        return
    
    error_rate = state.get_error_rate()
    
    if error_rate > ERROR_RATE_THRESHOLD:
        logger.warning(f"High error rate detected: {error_rate:.2f}% (threshold: {ERROR_RATE_THRESHOLD}%)")
        
        if state.can_send_alert('error_rate'):
            send_slack_alert('error_rate', {
                'error_rate': error_rate,
                'active_pool': state.current_pool or 'Unknown'
            })

def tail_log_file(filepath: str):
    """Tail a log file and yield new lines"""
    logger.info(f"Starting to tail log file: {filepath}")
    
    # Wait for file to exist
    while not os.path.exists(filepath):
        logger.info(f"Waiting for log file to be created: {filepath}")
        time.sleep(5)
    
    # Start from current position (don't try to seek on Docker volumes)
    logger.info(f"Log file found, starting to monitor: {filepath}")
    
    with open(filepath, 'r') as f:
        # Skip to end by reading all existing lines
        f.readlines()
        
        while True:
            line = f.readline()
            
            if line:
                yield line
            else:
                # No new data, wait a bit
                time.sleep(0.1)

def main():
    """Main watcher loop"""
    logger.info("=" * 60)
    logger.info("Blue-Green Alert Watcher Starting")
    logger.info("=" * 60)
    logger.info(f"Log file: {LOG_FILE_PATH}")
    logger.info(f"Error rate threshold: {ERROR_RATE_THRESHOLD}%")
    logger.info(f"Window size: {WINDOW_SIZE} requests")
    logger.info(f"Alert cooldown: {ALERT_COOLDOWN_SEC}s")
    logger.info(f"Maintenance mode: {MAINTENANCE_MODE}")
    logger.info(f"Slack webhook configured: {bool(SLACK_WEBHOOK_URL)}")
    logger.info("=" * 60)
    
    if not SLACK_WEBHOOK_URL:
        logger.warning("⚠️  SLACK_WEBHOOK_URL not set - alerts will be logged only")
    
    try:
        for line in tail_log_file(LOG_FILE_PATH):
            parsed = parse_log_line(line)
            
            if parsed:
                pool = parsed['pool']
                status = parsed['upstream_status']
                
                # Add to window
                state.add_request(status, pool)
                
                # Detect failover
                detect_failover(pool)
                
                # Check error rate periodically (every 10 requests)
                if state.total_requests % 10 == 0:
                    check_error_rate()
                
                # Log progress periodically
                if state.total_requests % 50 == 0:
                    error_rate = state.get_error_rate()
                    logger.info(
                        f"Processed {state.total_requests} requests | "
                        f"Pool: {state.current_pool} | "
                        f"Error rate: {error_rate:.2f}%"
                    )
    
    except KeyboardInterrupt:
        logger.info("Shutting down gracefully...")
    except Exception as e:
        logger.error(f"Fatal error: {e}", exc_info=True)
        raise

if __name__ == "__main__":
    main()
