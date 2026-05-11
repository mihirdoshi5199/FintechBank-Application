# ─────────────────────────────────────────────────────────────────────────────
# FintechBank Makefile – Common commands
# Usage: make <target>
# ─────────────────────────────────────────────────────────────────────────────

.PHONY: help dev build test clean deploy-staging health rollback

GREEN  := \033[0;32m
YELLOW := \033[1;33m
NC     := \033[0m

## help        → Show this help
help:
	@echo "$(GREEN)FintechBank$(NC) – Available commands:"
	@grep -E '^## ' Makefile | sed 's/## /  make /'

## dev         → Start local development stack
dev:
	docker compose -f docker-compose.dev.yml up --build

## dev-down    → Stop development stack
dev-down:
	docker compose -f docker-compose.dev.yml down -v

## build       → Build all Docker images
build:
	docker build -t fintech-api:local ./app/backend
	docker build -t fintech-frontend:local ./app/frontend
	@echo "$(GREEN)✓ Images built$(NC)"

## test        → Run backend tests
test:
	cd app/backend && npm ci && npm test

## test-cover  → Run tests with coverage
test-cover:
	cd app/backend && npm ci && npm test -- --coverage

## lint        → Lint backend code
lint:
	cd app/backend && npm run lint

## setup-vps   → Harden VPS (run on server)
setup-vps:
	sudo bash deployments/01-vps-ssh/setup.sh

## setup-monitoring → Start Grafana + Prometheus stack
setup-monitoring:
	docker compose -f deployments/08-monitoring-grafana/docker-compose.monitoring.yml up -d
	@echo "$(GREEN)✓ Grafana:    http://localhost:3001$(NC)"
	@echo "$(GREEN)✓ Prometheus: http://localhost:9090$(NC)"

## setup-registry  → Start private Docker registry
setup-registry:
	docker compose -f deployments/04-self-hosted-registry/registry-compose.yml up -d
	@echo "$(GREEN)✓ Registry: http://localhost:5000$(NC)"
	@echo "$(GREEN)✓ Registry UI: http://localhost:8080$(NC)"

## canary-10   → Deploy canary to 10% traffic
canary-10:
	bash deployments/07-canary-releases/deploy-canary.sh 10

## canary-100  → Full rollout (promote canary)
canary-100:
	bash deployments/07-canary-releases/deploy-canary.sh 100

## rollback    → Rollback to previous version
rollback:
	@read -p "Version to rollback to: " VERSION; \
	bash deployments/10-production-launch/rollback.sh $$VERSION

## health      → Run production health checks
health:
	bash deployments/10-production-launch/health-check.sh

## prod-deploy → Deploy full production stack (Docker Swarm)
prod-deploy:
	docker stack deploy \
		-c deployments/10-production-launch/production-compose.yml \
		fintech
	@echo "$(GREEN)✓ Production stack deployed$(NC)"

## prod-down   → Remove production stack
prod-down:
	docker stack rm fintech

## secrets-init → Initialize Vault secrets
secrets-init:
	bash deployments/09-secrets-management/secrets-init.sh

## clean       → Remove local Docker artifacts
clean:
	docker compose -f docker-compose.dev.yml down -v --remove-orphans
	docker image prune -f
	docker volume prune -f
	@echo "$(GREEN)✓ Cleaned$(NC)"

## logs        → Tail API logs
logs:
	docker compose -f docker-compose.dev.yml logs -f api

## shell       → Shell into API container
shell:
	docker compose -f docker-compose.dev.yml exec api sh
