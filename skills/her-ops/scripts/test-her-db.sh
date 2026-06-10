#!/usr/bin/env bash
# test-her-db.sh — 10-case functional test for her-db.sh
set -uo pipefail

HERDB="$(cd "$(dirname "$0")" && pwd)/her-db.sh"
PASS=0 FAIL=0 SKIP=0

run() {
  local desc="$1"; shift
  local expect="$1"; shift
  local result
  result=$(bash "$HERDB" "$@" 2>/dev/null) || true
  if echo "$result" | grep -q "$expect"; then
    echo "  PASS  #$((PASS+FAIL+SKIP+1)) $desc"
    ((PASS++))
  else
    echo "  FAIL  #$((PASS+FAIL+SKIP+1)) $desc"
    echo "        expected: $expect"
    echo "        got: $(echo "$result" | head -1)"
    ((FAIL++))
  fi
}

run_err() {
  local desc="$1"; shift
  local expect="$1"; shift
  local result
  result=$(bash "$HERDB" "$@" 2>&1) || true
  if echo "$result" | grep -qi "$expect"; then
    echo "  PASS  #$((PASS+FAIL+SKIP+1)) $desc"
    ((PASS++))
  else
    echo "  FAIL  #$((PASS+FAIL+SKIP+1)) $desc"
    echo "        expected stderr: $expect"
    echo "        got: $(echo "$result" | head -1)"
    ((FAIL++))
  fi
}

echo "=== test-her-db.sh ==="
echo ""

# 1. prod SELECT 1
run "prod: SELECT 1" "1" prod "SELECT 1"

# 2. prod --schema user (contains email, her_club_tier, no role)
result=$(bash "$HERDB" prod --schema user 2>/dev/null)
if echo "$result" | grep -q "email" && echo "$result" | grep -q "her_club_tier" && ! echo "$result" | grep -q "^role|"; then
  echo "  PASS  #$((PASS+FAIL+SKIP+1)) prod --schema user (email+her_club_tier, no role)"
  ((PASS++))
else
  echo "  FAIL  #$((PASS+FAIL+SKIP+1)) prod --schema user"
  ((FAIL++))
fi

# 3. prod: quoted table name (returns UUID)
result=$(bash "$HERDB" prod "SELECT id FROM \"user\" LIMIT 1" 2>/dev/null)
if [[ "$result" =~ ^[0-9a-f]{8}-[0-9a-f]{4} ]]; then
  echo "  PASS  #$((PASS+FAIL+SKIP+1)) prod: SELECT from \"user\" (quoted) → UUID"
  ((PASS++))
else
  echo "  FAIL  #$((PASS+FAIL+SKIP+1)) prod: SELECT from \"user\" (got: $result)"
  ((FAIL++))
fi

# 4. gw: users query
run "gw: users query" "|" gw "SELECT id, username FROM users LIMIT 1"

# 5. test-gw: SELECT 1
run "test-gw: SELECT 1" "1" test-gw "SELECT 1"

# 6. test-gw --check
run "test-gw --check" "container=her-gateway-test-db" test-gw --check

# 7. test-gw: count channels
result=$(bash "$HERDB" test-gw "SELECT count(*) FROM channels" 2>/dev/null)
if [[ "$result" =~ ^[0-9]+$ ]]; then
  echo "  PASS  #$((PASS+FAIL+SKIP+1)) test-gw: count channels = $result"
  ((PASS++))
else
  echo "  FAIL  #$((PASS+FAIL+SKIP+1)) test-gw: count channels (expected number, got: $result)"
  ((FAIL++))
fi

# 8. prod: error on nonexistent column
result=$(bash "$HERDB" prod "SELECT nonexistent FROM \"user\"" 2>&1)
if echo "$result" | grep -qi "does not exist"; then
  echo "  PASS  #$((PASS+FAIL+SKIP+1)) prod: nonexistent column returns error"
  ((PASS++))
else
  echo "  FAIL  #$((PASS+FAIL+SKIP+1)) prod: nonexistent column error"
  ((FAIL++))
fi

# 9. badenv: usage error
run_err "badenv: usage error" "Unknown env" badenv "SELECT 1"

# 10. prod --schema (all tables, >=20)
result=$(bash "$HERDB" prod --schema 2>/dev/null)
count=$(echo "$result" | grep -c '^[a-z]')
if [[ $count -ge 20 ]]; then
  echo "  PASS  #$((PASS+FAIL+SKIP+1)) prod --schema lists $count tables (>=20)"
  ((PASS++))
else
  echo "  FAIL  #$((PASS+FAIL+SKIP+1)) prod --schema lists $count tables (expected >=20)"
  ((FAIL++))
fi

echo ""
echo "=== Results: $PASS pass, $FAIL fail, $SKIP skip ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
