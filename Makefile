.PHONY: help build start stop restart logs test verify clean status health rebuild deploy rollback

# Default target
.DEFAULT_GOAL := help

# Colors for output
CYAN := \033[0;36m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m

# Detect Docker Compose command (v1 vs v2)
DOCKER_COMPOSE := $(shell command -v docker-compose 2>/dev/null)
ifeq ($(DOCKER_COMPOSE),)
	DOCKER_COMPOSE := docker compose
endif

help: ## Show this help message
	@echo ""
	@echo "$(CYAN)Blue/Green Deployment - Available Commands$(NC)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(CYAN)%-15s$(NC) %s\n", $$1, $$2}'
	@echo ""

build: ## Build both blue and green Docker images
	@echo "$(CYAN)==> Building images...$(NC)"
	@./build-images.sh

start: ## Start the Docker Compose stack
	@echo "$(CYAN)==> Starting stack...$(NC)"
	@$(DOCKER_COMPOSE) up -d
	@echo "$(GREEN)✓ Stack started$(NC)"
	@echo ""
	@echo "Waiting for services to be ready..."
	@sleep 10
	@$(MAKE) status

stop: ## Stop the Docker Compose stack
	@echo "$(CYAN)==> Stopping stack...$(NC)"
	@$(DOCKER_COMPOSE) down
	@echo "$(GREEN)✓ Stack stopped$(NC)"

restart: stop start ## Restart the Docker Compose stack

logs: ## Show logs from all services
	@$(DOCKER_COMPOSE) logs -f

logs-nginx: ## Show Nginx logs only
	@$(DOCKER_COMPOSE) logs -f nginx

logs-blue: ## Show Blue app logs only
	@$(DOCKER_COMPOSE) logs -f app_blue

logs-green: ## Show Green app logs only
	@$(DOCKER_COMPOSE) logs -f app_green

status: ## Show status of all services
	@echo "$(CYAN)==> Service Status:$(NC)"
	@$(DOCKER_COMPOSE) ps
	@echo ""
	@echo "$(CYAN)==> Health Checks:$(NC)"
	@$(MAKE) health || true

health: ## Check health of all services
	@echo -n "Nginx (8080):  "
	@curl -sf http://localhost:8080/health > /dev/null && echo "$(GREEN)✓ Healthy$(NC)" || echo "$(YELLOW)✗ Unhealthy$(NC)"
	@echo -n "Blue (8081):   "
	@curl -sf http://localhost:8081/health > /dev/null && echo "$(GREEN)✓ Healthy$(NC)" || echo "$(YELLOW)✗ Unhealthy$(NC)"
	@echo -n "Green (8082):  "
	@curl -sf http://localhost:8082/health > /dev/null && echo "$(GREEN)✓ Healthy$(NC)" || echo "$(YELLOW)✗ Unhealthy$(NC)"

verify: ## Run the failover verification script
	@echo "$(CYAN)==> Running failover verification...$(NC)"
	@./verify-failover.sh

test: ## Run complete local test suite
	@./local-test.sh

test-fast: ## Run tests without rebuilding images
	@./local-test.sh --skip-build

test-keep: ## Run tests and keep stack running
	@./local-test.sh --keep-running

clean: ## Stop stack and remove all containers, volumes, and images
	@echo "$(CYAN)==> Cleaning up...$(NC)"
	@$(DOCKER_COMPOSE) down -v
	@docker rmi blue-app:local green-app:local 2>/dev/null || true
	@rm -f test-results-*.log test-report.txt 2>/dev/null || true
	@echo "$(GREEN)✓ Cleanup complete$(NC)"

rebuild: clean build start ## Clean, rebuild, and start everything

# Pool management
pool-status: ## Show current active pool
	@echo "$(CYAN)Current Active Pool:$(NC)"
	@grep ACTIVE_POOL .env | cut -d'=' -f2

pool-toggle: ## Toggle active pool (blue <-> green)
	@current=$$(grep ACTIVE_POOL .env | cut -d'=' -f2); \
	new=$$([ "$$current" = "blue" ] && echo "green" || echo "blue"); \
	echo "$(CYAN)==> Switching from $$current to $$new...$(NC)"; \
	sed -i "s/ACTIVE_POOL=$$current/ACTIVE_POOL=$$new/" .env; \
	docker-compose up -d --force-recreate nginx; \
	echo "$(GREEN)✓ Active pool is now: $$new$(NC)"

pool-blue: ## Set active pool to blue
	@echo "$(CYAN)==> Setting active pool to blue...$(NC)"
	@sed -i 's/ACTIVE_POOL=green/ACTIVE_POOL=blue/' .env
	@$(DOCKER_COMPOSE) up -d --force-recreate nginx
	@echo "$(GREEN)✓ Active pool set to blue$(NC)"

pool-green: ## Set active pool to green
	@echo "$(CYAN)==> Setting active pool to green...$(NC)"
	@sed -i 's/ACTIVE_POOL=blue/ACTIVE_POOL=green/' .env
	@$(DOCKER_COMPOSE) up -d --force-recreate nginx
	@echo "$(GREEN)✓ Active pool set to green$(NC)"

# Chaos engineering
chaos-blue-start: ## Start chaos mode on Blue
	@echo "$(YELLOW)==> Starting chaos mode on Blue...$(NC)"
	@curl -X POST http://localhost:8081/chaos/start
	@echo ""
	@echo "$(YELLOW)⚠ Blue is now returning 500 errors$(NC)"

chaos-blue-stop: ## Stop chaos mode on Blue
	@echo "$(CYAN)==> Stopping chaos mode on Blue...$(NC)"
	@curl -X POST http://localhost:8081/chaos/stop
	@echo ""
	@echo "$(GREEN)✓ Blue is now operating normally$(NC)"

chaos-green-start: ## Start chaos mode on Green
	@echo "$(YELLOW)==> Starting chaos mode on Green...$(NC)"
	@curl -X POST http://localhost:8082/chaos/start
	@echo ""
	@echo "$(YELLOW)⚠ Green is now returning 500 errors$(NC)"

chaos-green-stop: ## Stop chaos mode on Green
	@echo "$(CYAN)==> Stopping chaos mode on Green...$(NC)"
	@curl -X POST http://localhost:8082/chaos/stop
	@echo ""
	@echo "$(GREEN)✓ Green is now operating normally$(NC)"

chaos-stop-all: chaos-blue-stop chaos-green-stop ## Stop chaos mode on all instances

# Quick deployment workflow
deploy: build start health verify ## Full deployment: build, start, health check, verify

# Development workflow
dev: build start logs ## Start development environment with logs

# CI simulation
ci: ## Simulate CI environment (clean build and test)
	@echo "$(CYAN)==> Simulating CI pipeline...$(NC)"
	@$(MAKE) clean
	@$(MAKE) build
	@$(MAKE) test
	@echo "$(GREEN)✓ CI simulation complete$(NC)"

# Inspect
inspect-nginx: ## Inspect nginx configuration
	@echo "$(CYAN)==> Nginx Configuration:$(NC)"
	@docker exec nginx-proxy cat /etc/nginx/nginx.conf

inspect-env: ## Show current environment variables
	@echo "$(CYAN)==> Environment Variables:$(NC)"
	@cat .env

# Quick requests
req: ## Send a request to nginx (via localhost:8080)
	@curl -i http://localhost:8080/

req-blue: ## Send a request directly to blue (localhost:8081)
	@curl -i http://localhost:8081/

req-green: ## Send a request directly to green (localhost:8082)
	@curl -i http://localhost:8082/

# Benchmarking (requires apache bench)
bench: ## Run quick load test (100 requests)
	@echo "$(CYAN)==> Running load test (100 requests)...$(NC)"
	@ab -n 100 -c 10 http://localhost:8080/ 2>/dev/null | grep -E "Requests per second|Time per request|Failed requests"
