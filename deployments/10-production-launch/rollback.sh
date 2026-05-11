#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Production Rollback Script – FintechBank
# Usage: ./rollback.sh [version]
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REGISTRY="${REGISTRY_HOST:-registry.fintech.dev:5000}"
ROLLBACK_TO="${1:-}"
SERVICES=("fintech_api" "fintech_frontend")

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "═══════════════════════════════════════════════"
echo -e "  ${RED}⏪ FintechBank Production Rollback${NC}"
echo "═══════════════════════════════════════════════"

# ── Find rollback target ──────────────────────────────────────────────────────
if [ -z "$ROLLBACK_TO" ]; then
  echo "Available recent images:"
  docker service inspect fintech_api --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}' 2>/dev/null || true
  echo ""
  echo -e "${YELLOW}Usage: ./rollback.sh <version-tag>${NC}"
  echo "Example: ./rollback.sh sha-abc1234"
  exit 1
fi

echo -e "${YELLOW}Rolling back to version: $ROLLBACK_TO${NC}"
echo ""

# ── Confirmation ──────────────────────────────────────────────────────────────
read -p "Confirm rollback to $ROLLBACK_TO? [y/N]: " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo "Rollback cancelled."
  exit 0
fi

# ── Stop canary if running ────────────────────────────────────────────────────
if docker service inspect fintech_api_canary &>/dev/null; then
  echo "Removing canary service..."
  docker service rm fintech_api_canary
  echo -e "${GREEN}✓${NC} Canary removed"
fi

# ── Rollback each service ─────────────────────────────────────────────────────
for SERVICE in "${SERVICES[@]}"; do
  IMAGE_NAME=$(echo "$SERVICE" | sed 's/fintech_//')
  echo ""
  echo "Rolling back $SERVICE..."
  docker service update \
    --image "$REGISTRY/fintech-$IMAGE_NAME:$ROLLBACK_TO" \
    --update-parallelism 2 \
    --update-delay 5s \
    --update-failure-action pause \
    "$SERVICE"
  echo -e "${GREEN}✓${NC} $SERVICE rolled back"
done

# ── Restore full traffic to stable ───────────────────────────────────────────
if [ -f "/etc/nginx/conf.d/canary.conf" ]; then
  echo ""
  echo "Resetting Nginx canary config..."
  cat > /etc/nginx/conf.d/canary.conf << 'NGXEOF'
# Rollback config – 100% stable traffic
upstream fintech_upstream {
    server fintech_api:4000;
}
NGXEOF
  nginx -t && nginx -s reload
  echo -e "${GREEN}✓${NC} Nginx restored to 100% stable traffic"
fi

# ── Health check post-rollback ────────────────────────────────────────────────
echo ""
echo "Running post-rollback health check (30s wait)..."
sleep 30
bash "$(dirname "$0")/health-check.sh"

echo ""
echo "═══════════════════════════════════════════════"
echo -e "  ${GREEN}✅ Rollback to $ROLLBACK_TO complete!${NC}"
echo "═══════════════════════════════════════════════"
