#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# DEPLOYMENT STRATEGY 07: Canary Releases – Traffic Splitting
# FintechBank – Fintech Scalability Challenge
# Usage: ./deploy-canary.sh <traffic_percentage>
# Example: ./deploy-canary.sh 10   → 10% to new, 90% to stable
#          ./deploy-canary.sh 100  → full rollout
#          ./deploy-canary.sh 0    → rollback
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

CANARY_PERCENT=${1:-10}
APP_DIR="/opt/fintech"
NGINX_CONF="/etc/nginx/conf.d/canary.conf"
STABLE_VERSION=${STABLE_VERSION:-"stable"}
CANARY_VERSION=${APP_VERSION:-$(git rev-parse --short HEAD)}

echo "═══════════════════════════════════════════════"
echo "  Canary Deploy: ${CANARY_PERCENT}% → v${CANARY_VERSION}"
echo "═══════════════════════════════════════════════"

# ── Rollback: 0% canary ──────────────────────────────────────────────────────
if [ "$CANARY_PERCENT" -eq 0 ]; then
  echo "⏪ ROLLBACK: Directing 100% traffic to stable"
  docker service update \
    --image registry.fintech.dev/fintech-api:${STABLE_VERSION} \
    --replicas 4 \
    fintech_api
  regenerate_nginx 0
  echo "✅ Rollback complete"
  exit 0
fi

# ── Full rollout: 100% ────────────────────────────────────────────────────────
if [ "$CANARY_PERCENT" -eq 100 ]; then
  echo "🌍 FULL ROLLOUT: Promoting canary to stable"
  docker service update \
    --image registry.fintech.dev/fintech-api:${CANARY_VERSION} \
    --replicas 4 \
    --update-parallelism 1 \
    --update-delay 10s \
    --update-failure-action rollback \
    fintech_api
  docker service rm fintech_api_canary 2>/dev/null || true
  regenerate_nginx 100
  echo "✅ Full rollout complete"
  exit 0
fi

# ── Canary deploy ─────────────────────────────────────────────────────────────
STABLE_PERCENT=$((100 - CANARY_PERCENT))
CANARY_REPLICAS=$(( (CANARY_PERCENT + 9) / 10 ))  # at least 1
STABLE_REPLICAS=$(( 10 - CANARY_REPLICAS ))

echo "📦 Starting canary: ${CANARY_PERCENT}% traffic (${CANARY_REPLICAS} replicas)"

# Start canary containers
docker service create \
  --name fintech_api_canary \
  --image registry.fintech.dev/fintech-api:${CANARY_VERSION} \
  --replicas $CANARY_REPLICAS \
  --network fintech-internal \
  --env NODE_ENV=production \
  --env APP_VERSION=${CANARY_VERSION} \
  --env IS_CANARY=true \
  --secret jwt_secret \
  --constraint "node.labels.env==production" \
  --update-config parallelism=1,delay=5s \
  --health-cmd "wget -qO- http://localhost:4000/health || exit 1" \
  --health-interval 15s 2>/dev/null || \
docker service update \
  --image registry.fintech.dev/fintech-api:${CANARY_VERSION} \
  --replicas $CANARY_REPLICAS \
  fintech_api_canary

# Update stable replicas
docker service scale fintech_api=$STABLE_REPLICAS

# Regenerate nginx config
regenerate_nginx() {
  local canary_pct=${1:-$CANARY_PERCENT}
  local stable_pct=$((100 - canary_pct))

  cat > "$NGINX_CONF" << NGXEOF
# Auto-generated canary config — $(date)
# Canary: ${canary_pct}% | Stable: ${stable_pct}%

split_clients "\${request_id}" \$upstream_variant {
    ${canary_pct}%   canary;
    *               stable;
}

upstream stable { 
    server fintech_api:4000;
    keepalive 32;
}
upstream canary {
    server fintech_api_canary:4000;
    keepalive 16;
}

server {
    listen 80;
    location /api/ {
        proxy_pass http://\$upstream_variant;
        proxy_set_header X-Canary "\$upstream_variant";
        add_header X-Version "\$upstream_variant" always;
    }
}
NGXEOF
  nginx -t && nginx -s reload
  echo "✓ Nginx updated: ${canary_pct}% canary / ${stable_pct}% stable"
}

regenerate_nginx "$CANARY_PERCENT"

# ── Health check ──────────────────────────────────────────────────────────────
echo "⏳ Waiting for canary containers to be healthy..."
sleep 15
HEALTHY=$(docker service ps fintech_api_canary --filter "desired-state=running" --format "{{.CurrentState}}" | grep -c "Running" || echo "0")

if [ "$HEALTHY" -lt "$CANARY_REPLICAS" ]; then
  echo "❌ Canary containers unhealthy! Rolling back..."
  bash "$0" 0
  exit 1
fi

echo ""
echo "═══════════════════════════════════════════════"
echo "  ✅ Canary deploy successful!"
echo "  Traffic: ${CANARY_PERCENT}% → v${CANARY_VERSION}"
echo "  Traffic: ${STABLE_PERCENT}% → v${STABLE_VERSION}"
echo "  Monitor: https://grafana.fintech.dev"
echo "  Rollback: ./deploy-canary.sh 0"
echo "  Full rollout: ./deploy-canary.sh 100"
echo "═══════════════════════════════════════════════"
