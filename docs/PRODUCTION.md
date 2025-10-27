# Production Deployment Guide

This guide covers deploying the Blue/Green Nginx architecture to production environments with security, scalability, and reliability best practices.

## 📋 Table of Contents

1. [Pre-Deployment Checklist](#pre-deployment-checklist)
2. [Environment Configuration](#environment-configuration)
3. [Security Hardening](#security-hardening)
4. [TLS/HTTPS Setup](#tlshttps-setup)
5. [Resource Management](#resource-management)
6. [Monitoring & Observability](#monitoring--observability)
7. [Deployment Process](#deployment-process)
8. [Rollback Procedures](#rollback-procedures)
9. [Scaling Considerations](#scaling-considerations)
10. [Disaster Recovery](#disaster-recovery)

## Pre-Deployment Checklist

Before deploying to production:

- [ ] Review and test all configuration in staging environment
- [ ] Set up monitoring and alerting
- [ ] Configure backup and disaster recovery procedures
- [ ] Document rollback procedures
- [ ] Prepare incident response runbook
- [ ] Set up log aggregation and retention
- [ ] Configure secrets management (avoid .env files in production)
- [ ] Review security hardening steps
- [ ] Set up TLS certificates
- [ ] Configure resource limits and health checks
- [ ] Test failover scenarios under load
- [ ] Set up on-call rotation and escalation

## Environment Configuration

### Production Environment Variables

Create environment-specific configuration using one of these methods:

#### Method 1: Docker Secrets (Recommended for Docker Swarm)

```bash
# Create secrets
echo "blue" | docker secret create active_pool -
echo "v2.0.0-blue" | docker secret create release_id_blue -
echo "v2.0.1-green" | docker secret create release_id_green -

# Reference in docker-compose.prod.yml
secrets:
  active_pool:
    external: true
```

#### Method 2: Environment Files per Environment

```bash
# .env.production
ACTIVE_POOL=blue
BLUE_IMAGE=registry.example.com/myapp:v2.0.0-blue
GREEN_IMAGE=registry.example.com/myapp:v2.0.1-green
RELEASE_ID_BLUE=v2.0.0-blue
RELEASE_ID_GREEN=v2.0.1-green
NGINX_IMAGE=nginx:1.25-alpine

# Load specific environment
docker-compose --env-file .env.production -f docker-compose.yml -f docker-compose.prod.yml up -d
```

#### Method 3: External Configuration Management

Use tools like:
- **HashiCorp Vault** for secrets
- **AWS Systems Manager Parameter Store**
- **Azure Key Vault**
- **Kubernetes ConfigMaps/Secrets**

### Registry Configuration

Push images to a private container registry:

```bash
# Tag images for registry
docker tag blue-app:local registry.example.com/myapp:v2.0.0-blue
docker tag green-app:local registry.example.com/myapp:v2.0.1-green

# Push to registry
docker login registry.example.com
docker push registry.example.com/myapp:v2.0.0-blue
docker push registry.example.com/myapp:v2.0.1-green

# Update .env.production
BLUE_IMAGE=registry.example.com/myapp:v2.0.0-blue
GREEN_IMAGE=registry.example.com/myapp:v2.0.1-green
```

## Security Hardening

### 1. Remove Direct App Exposure

In production, only expose Nginx (port 443/80). Remove direct app ports:

```yaml
# docker-compose.prod.yml
services:
  app_blue:
    ports: []  # No exposed ports
  app_green:
    ports: []  # No exposed ports
```

### 2. Run as Non-Root User

Already implemented in Dockerfile:

```dockerfile
USER node
```

### 3. Add Security Headers in Nginx

Update `nginx.conf.template`:

```nginx
server {
    listen 80;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;
    
    # ... rest of config
}
```

### 4. Implement Rate Limiting

```nginx
# In nginx.conf.template
http {
    # Rate limiting zone: 10MB can track ~160k IP addresses
    limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;
    
    server {
        location / {
            # Allow burst of 20 requests, delay additional
            limit_req zone=api_limit burst=20 nodelay;
            proxy_pass http://${ACTIVE_POOL}_pool;
            # ... rest of config
        }
    }
}
```

### 5. Enable Nginx Access Control

```nginx
# Restrict access to specific IPs (if applicable)
location /admin {
    allow 10.0.0.0/8;
    deny all;
}
```

## TLS/HTTPS Setup

### Option 1: Let's Encrypt with Certbot

```bash
# Install certbot
sudo apt-get install certbot

# Obtain certificate
sudo certbot certonly --standalone -d example.com -d www.example.com

# Update nginx.conf.template
server {
    listen 443 ssl http2;
    server_name example.com www.example.com;
    
    ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    
    # ... rest of config
}

# HTTP to HTTPS redirect
server {
    listen 80;
    server_name example.com www.example.com;
    return 301 https://$server_name$request_uri;
}
```

### Option 2: Custom Certificate

```yaml
# docker-compose.prod.yml
services:
  nginx:
    volumes:
      - ./certs/fullchain.pem:/etc/nginx/ssl/fullchain.pem:ro
      - ./certs/privkey.pem:/etc/nginx/ssl/privkey.pem:ro
```

## Resource Management

### CPU and Memory Limits

```yaml
# docker-compose.prod.yml
services:
  nginx:
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 512M
        reservations:
          cpus: '0.5'
          memory: 256M
  
  app_blue:
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 1G
        reservations:
          cpus: '1'
          memory: 512M
          
  app_green:
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 1G
        reservations:
          cpus: '1'
          memory: 512M
```

### Health Check Tuning

```yaml
# docker-compose.prod.yml
services:
  app_blue:
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:80/health"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 40s
```

## Monitoring & Observability

### Log Management

```yaml
# docker-compose.prod.yml
services:
  nginx:
    logging:
      driver: "json-file"
      options:
        max-size: "50m"
        max-file: "10"
        labels: "service=nginx"
        
  app_blue:
    logging:
      driver: "json-file"
      options:
        max-size: "100m"
        max-file: "5"
        labels: "service=app,pool=blue"
```

### Metrics to Monitor

- Request rate per pool (blue vs green)
- Error rate (5xx) per pool
- Response time (p50, p95, p99)
- Upstream health check failures
- Failover events
- CPU and memory usage
- Connection pool utilization

### Recommended Stack

- **Prometheus** - Metrics collection
- **Grafana** - Visualization and dashboards
- **Loki** - Log aggregation
- **AlertManager** - Alert routing

See `docker-compose.monitoring.yml` (coming in next section).

## Deployment Process

### 1. Pre-Deployment Validation

```bash
# Validate configuration
docker-compose -f docker-compose.yml -f docker-compose.prod.yml config

# Run smoke tests in staging
./local-test.sh

# Check image availability
docker pull registry.example.com/myapp:v2.0.1-green
```

### 2. Deployment Steps

```bash
# Step 1: Deploy new version to Green (inactive pool)
export GREEN_IMAGE=registry.example.com/myapp:v2.0.1-green
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d app_green

# Step 2: Wait for Green to be healthy
sleep 30
curl -f http://green-internal:80/health

# Step 3: Run smoke tests against Green
curl -f http://green-internal:80/

# Step 4: Switch traffic to Green
make pool-toggle
# or manually:
# sed -i 's/ACTIVE_POOL=blue/ACTIVE_POOL=green/' .env
# docker-compose up -d --force-recreate nginx

# Step 5: Monitor for 5-10 minutes
watch -n 5 'curl -s http://localhost:8080/ | grep X-App-Pool'

# Step 6: Update Blue with new version (now safe to update)
export BLUE_IMAGE=registry.example.com/myapp:v2.0.1-blue
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d app_blue
```

### 3. Post-Deployment Validation

```bash
# Run verification
./verify-failover.sh

# Check metrics
# Monitor error rates, latency, throughput

# Review logs
docker-compose logs --tail=100 nginx
docker-compose logs --tail=100 app_green
```

## Rollback Procedures

### Immediate Rollback (< 5 minutes)

```bash
# If Green is having issues, switch back to Blue
make pool-toggle  # or pool-blue

# Verify
curl -i http://localhost:8080/ | grep X-App-Pool
```

### Full Rollback (restore previous version)

```bash
# Redeploy previous version to both pools
export BLUE_IMAGE=registry.example.com/myapp:v2.0.0-blue
export GREEN_IMAGE=registry.example.com/myapp:v2.0.0-green

docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

### Automated Rollback Script

See `rollback.sh` (created separately).

## Scaling Considerations

### Horizontal Scaling (Multiple Backends)

Update `nginx.conf.template`:

```nginx
upstream blue_pool {
    server app_blue_1:80 max_fails=1 fail_timeout=10s;
    server app_blue_2:80 max_fails=1 fail_timeout=10s;
    server app_green_1:80 backup;
    server app_green_2:80 backup;
}
```

### Docker Swarm Scaling

```bash
# Scale to 3 replicas
docker service scale blue-app=3
docker service scale green-app=3
```

### Kubernetes Alternative

For large-scale deployments, consider migrating to Kubernetes with Ingress controllers for advanced traffic management.

## Disaster Recovery

### Backup Strategy

- **Configuration**: Version control (Git) for all config files
- **State**: Externalize state to databases, not containers
- **Images**: Keep multiple versions in registry with retention policy

### Recovery Procedures

#### Both Pools Failed

```bash
# Serve static maintenance page
docker run -d -p 8080:80 -v ./maintenance.html:/usr/share/nginx/html/index.html nginx
```

#### Database Unavailable

Ensure apps handle database failures gracefully and return 503 (not 500) so Nginx knows it's a temporary issue.

#### Complete System Failure

1. Restore from last known good configuration
2. Pull last stable images from registry
3. Deploy to new infrastructure
4. Update DNS if necessary
5. Validate with smoke tests

## Production Checklist

- [ ] All services use production images from registry
- [ ] TLS/HTTPS configured and tested
- [ ] Security headers added to Nginx
- [ ] Rate limiting configured
- [ ] Resource limits set
- [ ] Health checks tuned
- [ ] Logging configured and centralized
- [ ] Monitoring and alerting active
- [ ] Backup and DR procedures tested
- [ ] Runbook created and shared with team
- [ ] On-call rotation established

## Additional Resources

- [docker-compose.prod.yml](./docker-compose.prod.yml) - Production overrides
- [rollback.sh](./rollback.sh) - Automated rollback script
- [Nginx Best Practices](https://www.nginx.com/blog/nginx-best-practices/)
- [Docker Security](https://docs.docker.com/engine/security/)

---

**Last Updated**: 2025-10-27  
**Maintained By**: DevOps Team
