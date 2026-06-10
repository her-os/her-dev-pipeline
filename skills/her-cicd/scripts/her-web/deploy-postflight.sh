#!/bin/bash
# her-web deploy postflight (runs locally, checks remote server, < 15s)
set -euo pipefail

SERVER="${SERVER:-ubuntu@192.144.187.174}"
SERVICE="${SERVICE:-her-herweb-a8y5ka}"
HEALTH_URL="${HEALTH_URL:-https://hersoul.cn}"
SSH=/usr/bin/ssh
FAIL=0
WARN=0

pass() { echo "  [PASS] $1"; }
fail() { echo "  [FAIL] $1" >&2; FAIL=1; }
warn_msg() { echo "  [WARN] $1"; WARN=1; }

echo "=== her-web deploy postflight ==="
echo ""

# 1. Swarm replicas 1/1
echo "[1/5] Swarm service replicas"
REPLICAS=$($SSH "$SERVER" "sudo docker service ls --filter name=$SERVICE --format '{{.Replicas}}'" 2>/dev/null || echo "?/?")
if [ "$REPLICAS" = "1/1" ]; then
  pass "replicas = $REPLICAS"
else
  fail "replicas = $REPLICAS (expected 1/1)"
fi

# 2. HTTP 200 (follow locale redirects such as / -> /zh)
echo "[2/5] HTTP 200"
HTTP_CODE=$(curl -L --max-time 10 -s -o /dev/null -w "%{http_code}" "$HEALTH_URL/" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
  pass "$HEALTH_URL -> HTTP $HTTP_CODE"
else
  fail "$HEALTH_URL -> HTTP $HTTP_CODE (expected 200)"
fi

# 3. Auth endpoint not 403 (Invalid origin check)
echo "[3/5] Auth endpoint not 403"
AUTH_CODE=$(curl --max-time 10 -s -o /dev/null -w "%{http_code}" \
  -X POST "$HEALTH_URL/api/auth/sign-in/email" \
  -H "Content-Type: application/json" \
  -H "Origin: $HEALTH_URL" \
  -d '{"email":"healthcheck@test.invalid","password":"x"}' 2>/dev/null || echo "000")
if [ "$AUTH_CODE" = "403" ]; then
  fail "auth returns 403 (Invalid origin - NEXT_PUBLIC_APP_URL may be wrong)"
elif [ "$AUTH_CODE" = "000" ]; then
  fail "auth endpoint no response"
else
  pass "auth returns HTTP $AUTH_CODE (not 403)"
fi

# 4. No-rate-limit envs
echo "[4/5] No-rate-limit envs"
ENV_DUMP=$($SSH "$SERVER" "sudo docker service inspect $SERVICE --format '{{range .Spec.TaskTemplate.ContainerSpec.Env}}{{println .}}{{end}}'" 2>/dev/null || true)
if echo "$ENV_DUMP" | grep -q '^AUTH_RATE_LIMIT_ENABLED=false$'; then
  pass "AUTH_RATE_LIMIT_ENABLED=false"
else
  fail "AUTH_RATE_LIMIT_ENABLED=false missing"
fi
if echo "$ENV_DUMP" | grep -q '^HER_INTERNAL_RATE_LIMIT_BYPASS_TOKEN=.'; then
  pass "HER_INTERNAL_RATE_LIMIT_BYPASS_TOKEN present"
else
  fail "HER_INTERNAL_RATE_LIMIT_BYPASS_TOKEN missing"
fi

# 5. Container logs check
echo "[5/5] Container logs"
ERROR_COUNT=$($SSH "$SERVER" "sudo docker service logs $SERVICE --since 2m 2>&1 | grep -ci 'error\|fatal\|panic' || true" 2>/dev/null | tail -1)
ERROR_COUNT=${ERROR_COUNT:-0}
DUP_KEY=$($SSH "$SERVER" "sudo docker service logs $SERVICE --since 2m 2>&1 | grep -c 'duplicate key' || true" 2>/dev/null | tail -1)
DUP_KEY=${DUP_KEY:-0}
if [ "$DUP_KEY" -gt 3 ]; then
  fail "logs: $DUP_KEY duplicate key errors (gateway provision issue)"
elif [ "$ERROR_COUNT" -gt 10 ]; then
  warn_msg "logs: $ERROR_COUNT errors in last 50 lines"
else
  pass "logs: $ERROR_COUNT errors, $DUP_KEY duplicate key"
fi

echo ""
if [ "$FAIL" -eq 0 ] && [ "$WARN" -eq 0 ]; then
  echo "=== POSTFLIGHT PASSED ==="
elif [ "$FAIL" -eq 0 ]; then
  echo "=== POSTFLIGHT PASSED (with warnings) ==="
else
  echo "=== POSTFLIGHT FAILED ===" >&2
  exit 1
fi
