#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Production Health Check Script – FintechBank
# Checks all services and exits non-zero if any are unhealthy
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

BASE_URL="${BASE_URL:-https://fintech.dev}"
EXIT_CODE=0
PASS=0
FAIL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; ((PASS++)); }
fail() { echo -e "${RED}✗${NC} $1"; ((FAIL++)); EXIT_CODE=1; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }

echo "═══════════════════════════════════════════════"
echo "  FintechBank Production Health Check"
echo "  $(date)"
echo "  Target: $BASE_URL"
echo "═══════════════════════════════════════════════"
echo ""

# ── 1. API Health ─────────────────────────────────────────────────────────────
echo "── API Health ───────────────────────────────"
HEALTH=$(curl -sf "$BASE_URL/health" 2>/dev/null || echo "")
if echo "$HEALTH" | grep -q '"status":"healthy"'; then
  pass "API /health → healthy"
  UPTIME=$(echo "$HEALTH" | grep -o '"uptime":[0-9.]*' | cut -d: -f2)
  pass "API uptime: ${UPTIME}s"
else
  fail "API /health unreachable or unhealthy"
fi

# ── 2. Frontend ───────────────────────────────────────────────────────────────
echo ""
echo "── Frontend ─────────────────────────────────"
HTTP_CODE=$(curl -so /dev/null -w "%{http_code}" "$BASE_URL/" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
  pass "Frontend returns HTTP 200"
else
  fail "Frontend returned HTTP $HTTP_CODE"
fi

# ── 3. SSL Certificate ────────────────────────────────────────────────────────
echo ""
echo "── SSL Certificate ──────────────────────────"
DOMAIN=$(echo "$BASE_URL" | sed 's|https://||' | sed 's|/.*||')
CERT_EXPIRY=$(echo | openssl s_client -servername "$DOMAIN" -connect "$DOMAIN:443" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 || echo "")
if [ -n "$CERT_EXPIRY" ]; then
  EXPIRY_EPOCH=$(date -d "$CERT_EXPIRY" +%s 2>/dev/null || gdate -d "$CERT_EXPIRY" +%s 2>/dev/null || echo "0")
  NOW_EPOCH=$(date +%s)
  DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))
  if [ "$DAYS_LEFT" -gt 30 ]; then
    pass "SSL cert valid for $DAYS_LEFT days"
  elif [ "$DAYS_LEFT" -gt 7 ]; then
    warn "SSL cert expiring in $DAYS_LEFT days — renew soon!"
  else
    fail "SSL cert expiring in $DAYS_LEFT days — CRITICAL!"
  fi
else
  warn "Could not check SSL certificate"
fi

# ── 4. Security Headers ───────────────────────────────────────────────────────
echo ""
echo "── Security Headers ─────────────────────────"
HEADERS=$(curl -sI "$BASE_URL/" 2>/dev/null || echo "")
for HEADER in "Strict-Transport-Security" "X-Content-Type-Options" "X-Frame-Options" "Content-Security-Policy"; do
  if echo "$HEADERS" | grep -qi "$HEADER"; then
    pass "Header present: $HEADER"
  else
    fail "Missing header: $HEADER"
  fi
done

# ── 5. Auth API ───────────────────────────────────────────────────────────────
echo ""
echo "── Auth Endpoint ────────────────────────────"
AUTH_RESP=$(curl -sf -X POST "$BASE_URL/api/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"shubham@fintech.dev","password":"Password@123"}' 2>/dev/null || echo "")
if echo "$AUTH_RESP" | grep -q '"token"'; then
  pass "Auth login endpoint working"
  TOKEN=$(echo "$AUTH_RESP" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
else
  fail "Auth login endpoint failed"
  TOKEN=""
fi

# ── 6. Protected Route ────────────────────────────────────────────────────────
if [ -n "$TOKEN" ]; then
  ACCOUNTS=$(curl -sf "$BASE_URL/api/accounts" \
    -H "Authorization: Bearer $TOKEN" 2>/dev/null || echo "")
  if echo "$ACCOUNTS" | grep -q '"accounts"'; then
    pass "Protected route /api/accounts accessible"
  else
    fail "Protected route /api/accounts failed"
  fi
fi

# ── 7. Rate Limiting ──────────────────────────────────────────────────────────
echo ""
echo "── Rate Limiting ────────────────────────────"
RATE_CODE=""
for i in {1..12}; do
  CODE=$(curl -so /dev/null -w "%{http_code}" -X POST "$BASE_URL/api/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"email":"test@test.com","password":"wrong"}' 2>/dev/null || echo "000")
  if [ "$CODE" = "429" ]; then
    RATE_CODE="429"
    break
  fi
done
if [ "$RATE_CODE" = "429" ]; then
  pass "Rate limiting active (429 after repeated requests)"
else
  warn "Rate limiting may not be configured correctly"
fi

# ── 8. Docker Services ────────────────────────────────────────────────────────
echo ""
echo "── Docker Services ──────────────────────────"
if command -v docker &>/dev/null; then
  SERVICES=("fintech_api" "fintech_frontend" "fintech_nginx" "fintech_redis")
  for SVC in "${SERVICES[@]}"; do
    STATE=$(docker service ps "$SVC" --filter "desired-state=running" --format "{{.CurrentState}}" 2>/dev/null | head -1 || echo "")
    if echo "$STATE" | grep -q "Running"; then
      pass "Service $SVC: Running"
    else
      fail "Service $SVC: Not running (state: $STATE)"
    fi
  done
else
  warn "Docker not available on this machine — skipping service checks"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════"
echo -e "  Results: ${GREEN}$PASS passed${NC}  ${RED}$FAIL failed${NC}"
if [ $EXIT_CODE -eq 0 ]; then
  echo -e "  Status: ${GREEN}✅ ALL CHECKS PASSED${NC}"
else
  echo -e "  Status: ${RED}❌ SOME CHECKS FAILED${NC}"
fi
echo "═══════════════════════════════════════════════"

exit $EXIT_CODE
