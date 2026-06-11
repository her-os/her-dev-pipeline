#!/usr/bin/env bash
# test environment stack helper.
#
# This script manages only the test services:
#   her-web-test
#   her-web-test-db
#   her-gateway-test
#   her-gateway-test-db
#   her-gateway-test-redis
#
# It must not update/restart production services:
#   her-herweb-a8y5ka
#   new-api
#   redis
#
set -euo pipefail

QUIET="${QUIET:-0}"
log() { [[ "$QUIET" == "1" ]] || echo "$@"; }

SERVER="${SERVER:-ubuntu@192.144.187.174}"
SSH_BIN="${SSH_BIN:-/usr/bin/ssh}"
STACK_DIR="${STACK_DIR:-/home/ubuntu/her-test}"
NETWORK="${NETWORK:-dokploy-network}"

WEB_SERVICE="${WEB_SERVICE:-her-web-test}"
WEB_DB_SERVICE="${WEB_DB_SERVICE:-her-web-test-db}"
WEB_DB_VOLUME="${WEB_DB_VOLUME:-her-web-test-db-data}"
WEB_DB_IMAGE="${WEB_DB_IMAGE:-postgres:16-alpine}"

GW_SERVICE="${GW_SERVICE:-her-gateway-test}"
GW_DB_SERVICE="${GW_DB_SERVICE:-her-gateway-test-db}"
GW_DB_VOLUME="${GW_DB_VOLUME:-her-gateway-test-db18-data}"
GW_REDIS_SERVICE="${GW_REDIS_SERVICE:-her-gateway-test-redis}"
GATEWAY_DOCKER_PLATFORM="${GATEWAY_DOCKER_PLATFORM:-linux/amd64}"

PUBLIC_IP="${PUBLIC_IP:-192.144.187.174}"
WEB_PUBLIC_PORT="${WEB_PUBLIC_PORT:-31080}"
GW_PUBLIC_PORT="${GW_PUBLIC_PORT:-31081}"
WEB_URL="${WEB_URL:-https://test.hersoul.cn}"
# IP 直连入口仍可用：加入 better-auth trustedOrigins，浏览器从 IP 进也能过 origin 校验
AUTH_TRUSTED_ORIGINS="${AUTH_TRUSTED_ORIGINS:-http://$PUBLIC_IP,http://$PUBLIC_IP:80}"
API_URL="${API_URL:-http://$PUBLIC_IP:80/test-gateway}"

usage() {
  cat <<'EOF'
Usage:
  deploy-test.sh status
  deploy-test.sh enable-ip-ports
  deploy-test.sh write-routes
  deploy-test.sh verify-web-gateway
  deploy-test.sh deploy-web <origin-dev-worktree>
  deploy-test.sh deploy-gateway <her-gateway-worktree>
  ALLOW_TEST_DB_REFRESH=1 deploy-test.sh refresh-web-db
  ALLOW_TEST_DB_REFRESH=1 deploy-test.sh refresh-gateway-db

Commands:
  status
    Show test services, route file, HTTP probes, and certificate state.

  write-routes
    Write /etc/dokploy/traefik/dynamic/her-test.yml.
    HTTP stays enabled because test domain has no ICP certificate path.
    Also exposes no-domain IP routes:
      http://PUBLIC_IP:80 -> test her-web
      http://PUBLIC_IP:80/test-gateway -> test gateway

  enable-ip-ports
    Publish optional direct IP testing ports:
      WEB_PUBLIC_PORT (default 31080) -> her-web-test:3000
      GW_PUBLIC_PORT  (default 31081) -> her-gateway-test:3000
    These require the cloud firewall/security group to allow the ports.

  verify-web-gateway
    Check that test web points at her-gateway-test, gateway is reachable,
    and active web user_gateway rows still reference live gateway tokens.

  deploy-web <origin-dev-worktree>
    Rsync a her-web worktree to /tmp, build a new local image, ensure the
    isolated test web DB exists, and recreate only her-web-test.
    The worktree must be clean and HEAD must equal origin/dev. Test deploys
    only come from dev merge commits.
    Local .env*, data, node_modules, .next, .git, Trellis/agent files are
    excluded from the build context.

    Image uses fixed tag her-web:test-latest (previous saved as test-prev
    for rollback). Old timestamped images are cleaned up automatically.

    Temporary stacked PR deploys are disabled. To test a coworker's PR with
    local supplements, create a supplement branch from that PR, open a PR to
    dev whose description says "contains PR #xxx + supplement", merge it, then
    deploy from origin/dev.

    Data sync is NOT automatic. deploy-web updates only her-web-test code/env.
    Run refresh-all only when the user explicitly asks to sync a production
    snapshot or reset test data.

  deploy-gateway <worktree>
    Rsync a her-gateway worktree to the server, build natively on amd64 with
    BuildKit cache, configure her-web agent-ops ingestion env, and update only
    her-gateway-test. This never pulls ghcr/main.

  refresh-web-db
    Recreate the isolated test her-web DB from a read-only pg_dump of the
    production her-web DB, clear copied sessions, rewrite test URLs/callbacks,
    and restart only her-web-test.
    Requires ALLOW_TEST_DB_REFRESH=1.

  refresh-gateway-db
    Recreate the isolated test gateway DB from a read-only pg_dump of the
    production gateway DB, then recreate only her-gateway-test with the
    current explicit test gateway image. This never pulls ghcr/main. If test
    web keeps its test DB, missing web -> gateway token bindings are repaired.
    Requires ALLOW_TEST_DB_REFRESH=1.

  refresh-all
    Refresh both gateway DB and web DB from production in one command.
    Runs refresh-gateway-db first (so gateway is up when web DB is restored),
    then refresh-web-db (which repairs token bindings against the fresh gateway).
    Requires ALLOW_TEST_DB_REFRESH=1.

  audit-env
    Compare env vars between production and test containers.
    Flags MISSING keys (in prod but not test) and DIFF values
    (excluding known infrastructure keys that must differ).
    Also runs automatically at the end of refresh-all.

  add-test-email <email>
    Add email to payment_test_account_emails whitelist.
    Automatically restarts her-web-test to clear config cache.

  reset-password <email> <password>
    Reset a user's password in ROOME CLONE DB (never touches production).
    Uses better-auth compatible scrypt hash.
    Automatically restarts her-web-test to clear session cache.

  set-config <key> <value>
    Set a config table value in test web DB.
    Automatically restarts her-web-test to clear 1h config cache.
    Example: set-config wechat_test_amount 1

  web-db <SQL>
    Run SQL against test web clone DB (her-web-test-db-clone).
    Example: web-db "SELECT id, email FROM \"user\" LIMIT 5"

  gateway-db <SQL>
    Run SQL against test gateway DB (her-gateway-test-db).
    Example: gateway-db "SELECT id, username, quota FROM users LIMIT 5"

  prod-web-db <SQL>
    Run read-only SQL against PRODUCTION her-web DB.
    Example: prod-web-db "SELECT count(*) FROM \"user\""

  prod-gateway-db <SQL>
    Run read-only SQL against PRODUCTION gateway DB.
    Example: prod-gateway-db "SELECT count(*) FROM tokens"

Notes:
  - Production services are read-only sources for image/env/DB clone metadata.
  - Secrets are copied through env variables and are never printed.
  - This helper intentionally has no "refresh her-web production DB" button.
    See references/her-web/test-stack.md before doing that manually.
EOF
}

remote() {
  if [[ "$QUIET" == "1" ]]; then
    local output status
    set +e
    output="$("$SSH_BIN" "$SERVER" "$@" 2>&1)"
    status=$?
    set -e
    if [[ "$status" -ne 0 ]]; then
      echo "ERROR: remote command failed: $*" >&2
      printf '%s\n' "$output" >&2
      return "$status"
    fi
    return 0
  fi

  "$SSH_BIN" "$SERVER" "$@"
}

require_refresh_confirmation() {
  if [[ "${ALLOW_TEST_DB_REFRESH:-0}" != "1" ]]; then
    echo "ERROR: refusing to rebuild test DB without ALLOW_TEST_DB_REFRESH=1" >&2
    exit 1
  fi
}

require_test_web_target() {
  if [[ "$WEB_SERVICE" != "her-web-test" ]]; then
    echo "ERROR: WEB_SERVICE must be her-web-test, got: $WEB_SERVICE" >&2
    exit 1
  fi
  if [[ "$WEB_SERVICE" == "her-herweb-a8y5ka" ]]; then
    echo "ERROR: refusing to operate on production service her-herweb-a8y5ka" >&2
    exit 1
  fi
  case "$WEB_URL" in
    "https://hersoul.cn"|"http://hersoul.cn"|"https://www.hersoul.cn"|"http://www.hersoul.cn")
      echo "ERROR: refusing production NEXT_PUBLIC_APP_URL/WEB_URL: $WEB_URL" >&2
      exit 1
      ;;
  esac
  case "$WEB_URL" in
    "https://test.hersoul.cn"|"http://$PUBLIC_IP:80"|"http://$PUBLIC_IP"|"http://roome.cn"|"https://roome.cn"|"http://www.roome.cn"|"https://www.roome.cn")
      ;;
    *)
      echo "ERROR: WEB_URL must be the test IP route or test domain, got: $WEB_URL" >&2
      exit 1
      ;;
  esac
}

verify_remote_web_service_safe() {
  require_test_web_target
  remote "bash -s" <<REMOTE
set -euo pipefail
if [ '$WEB_SERVICE' != 'her-web-test' ]; then
  echo "ERROR: refusing non-test service target: $WEB_SERVICE" >&2
  exit 1
fi
if [ '$WEB_SERVICE' = 'her-herweb-a8y5ka' ]; then
  echo "ERROR: refusing production service her-herweb-a8y5ka" >&2
  exit 1
fi
if sudo docker service inspect '$WEB_SERVICE' >/dev/null 2>&1; then
  env_dump=\$(sudo docker service inspect '$WEB_SERVICE' --format '{{range .Spec.TaskTemplate.ContainerSpec.Env}}{{println .}}{{end}}')
  app_url=\$(printf '%s\n' "\$env_dump" | sed -n 's/^NEXT_PUBLIC_APP_URL=//p' | head -n 1)
  if [ "\$app_url" = 'https://hersoul.cn' ] || [ "\$app_url" = 'http://hersoul.cn' ]; then
    echo "ERROR: $WEB_SERVICE has production NEXT_PUBLIC_APP_URL=\$app_url" >&2
    exit 1
  fi
fi
if sudo docker service inspect her-herweb-a8y5ka >/dev/null 2>&1 && [ '$WEB_SERVICE' = 'her-herweb-a8y5ka' ]; then
  echo "ERROR: production service selected" >&2
  exit 1
fi
echo "web_target_safety=ok service=$WEB_SERVICE url=$WEB_URL"
REMOTE
}

# --- env parity audit ---------------------------------------------------
# Compares env vars between production and test containers.
# Env vars are classified as:
#   INFRA  - must differ (DB URLs, auth secrets, service addresses)
#   SECRET - sensitive, only flag if missing in test but present in prod
#   BIZ    - business config, should be identical
# Prints a summary table; exits 0 even if diffs found (advisory only).
audit_env_parity() {
  remote "bash -s" <<'ENV_AUDIT'
set -uo pipefail

# Container IDs
PROD_WEB=$(sudo docker ps -qf name=her-herweb-a8y5ka | head -1)
ROOME_WEB=$(sudo docker ps -qf name=her-web-test.1 | head -1)
PROD_GW=$(sudo docker ps -qf name=new-api | head -1)
ROOME_GW=$(sudo docker ps -qf name=her-gateway-test.1 | head -1)

if [ -z "$PROD_WEB" ] || [ -z "$ROOME_WEB" ]; then
  echo "env_audit=skipped reason=container_not_found prod_web=$PROD_WEB test_web=$ROOME_WEB"
  exit 0
fi

# Known infrastructure keys that MUST differ between envs
INFRA_KEYS="DATABASE_URL|AUTH_SECRET|AUTH_URL|AUTH_RATE_LIMIT_ENABLED|NEXT_PUBLIC_APP_URL|API_GATEWAY_BASE_URL|API_GATEWAY_OPENAI_BASE_URL|SQL_DSN|REDIS_CONN_STRING|SESSION_SECRET|HOSTNAME|HOME|PATH|NODE_VERSION|YARN_VERSION|PORT|NODE_ENV"

# System/container keys to ignore entirely
IGNORE_KEYS="HOSTNAME|HOME|PATH|NODE_VERSION|YARN_VERSION|SHLVL|PWD|_|TERM"

diffs=0
missing=0

echo "--- web app env audit ---"
sudo docker exec "$PROD_WEB" env 2>/dev/null | sort > /tmp/prod-web-env.txt
sudo docker exec "$ROOME_WEB" env 2>/dev/null | sort > /tmp/her-test-web-env.txt

# Find keys only in prod (missing from test)
while IFS='=' read -r key val; do
  [[ -z "$key" ]] && continue
  echo "$key" | grep -qE "^($IGNORE_KEYS)$" && continue
  if ! grep -q "^${key}=" /tmp/her-test-web-env.txt 2>/dev/null; then
    echo "$key" | grep -qE "^($INFRA_KEYS)$" && continue
    echo "  MISSING  $key  (in prod, not in test)"
    missing=$((missing + 1))
  fi
done < /tmp/prod-web-env.txt

# Find keys with different values (excluding infra)
while IFS='=' read -r key val; do
  [[ -z "$key" ]] && continue
  echo "$key" | grep -qE "^($IGNORE_KEYS)$" && continue
  echo "$key" | grep -qE "^($INFRA_KEYS)$" && continue
  prod_val=$(grep "^${key}=" /tmp/prod-web-env.txt 2>/dev/null | cut -d= -f2-)
  test_val=$(grep "^${key}=" /tmp/her-test-web-env.txt 2>/dev/null | cut -d= -f2-)
  if [ -n "$prod_val" ] && [ -n "$test_val" ] && [ "$prod_val" != "$test_val" ]; then
    echo "  DIFF     $key  prod=${prod_val:0:30}  test=${test_val:0:30}"
    diffs=$((diffs + 1))
  fi
done < /tmp/prod-web-env.txt

if [ -n "$PROD_GW" ] && [ -n "$ROOME_GW" ]; then
  echo "--- gateway env audit ---"
  sudo docker exec "$PROD_GW" env 2>/dev/null | sort > /tmp/prod-gw-env.txt
  sudo docker exec "$ROOME_GW" env 2>/dev/null | sort > /tmp/her-test-gw-env.txt

  while IFS='=' read -r key val; do
    [[ -z "$key" ]] && continue
    echo "$key" | grep -qE "^($IGNORE_KEYS)$" && continue
    if ! grep -q "^${key}=" /tmp/her-test-gw-env.txt 2>/dev/null; then
      echo "$key" | grep -qE "^($INFRA_KEYS)$" && continue
      echo "  MISSING  $key  (in prod, not in test)"
      missing=$((missing + 1))
    fi
  done < /tmp/prod-gw-env.txt

  while IFS='=' read -r key val; do
    [[ -z "$key" ]] && continue
    echo "$key" | grep -qE "^($IGNORE_KEYS)$" && continue
    echo "$key" | grep -qE "^($INFRA_KEYS)$" && continue
    prod_val=$(grep "^${key}=" /tmp/prod-gw-env.txt 2>/dev/null | cut -d= -f2-)
    test_val=$(grep "^${key}=" /tmp/her-test-gw-env.txt 2>/dev/null | cut -d= -f2-)
    if [ -n "$prod_val" ] && [ -n "$test_val" ] && [ "$prod_val" != "$test_val" ]; then
      echo "  DIFF     $key  prod=${prod_val:0:30}  test=${test_val:0:30}"
      diffs=$((diffs + 1))
    fi
  done < /tmp/prod-gw-env.txt
fi

echo "env_audit_summary  missing=$missing diffs=$diffs"
if [ $missing -eq 0 ] && [ $diffs -eq 0 ]; then
  echo "env_audit=PASS"
else
  echo "env_audit=WARN (review above)"
fi

rm -f /tmp/prod-web-env.txt /tmp/her-test-web-env.txt /tmp/prod-gw-env.txt /tmp/her-test-gw-env.txt
ENV_AUDIT
}

git_value_or_unknown() {
  local src="$1"
  shift
  git -C "$src" "$@" 2>/dev/null || printf 'unknown'
}

wait_service_removed_remote='
wait_service_removed() {
  name="$1"
  for i in $(seq 1 120); do
    if ! sudo docker service inspect "$name" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "timeout waiting for service removal: $name" >&2
  return 1
}
'

status() {
  log "=== test services ==="
  remote "sudo docker service ls --format '{{.Name}} {{.Replicas}} {{.Image}}' | grep test || true"
  echo

  log "=== test build metadata ==="
  remote "sudo test -f '$STACK_DIR/web-current.env' && sudo sed -n '1,80p' '$STACK_DIR/web-current.env' || true"
  remote "sudo docker service inspect '$WEB_SERVICE' --format 'service={{.Spec.Name}} labels={{json .Spec.Labels}} image={{.Spec.TaskTemplate.ContainerSpec.Image}}' 2>/dev/null || true"
  echo

  log "=== direct IP ports ==="
  remote "sudo docker service inspect '$WEB_SERVICE' '$GW_SERVICE' --format '{{.Spec.Name}} ports={{json .Endpoint.Spec.Ports}}' 2>/dev/null || true"
  echo

  log "=== DNS ==="
  for host in roome.cn www.roome.cn api.roome.cn; do
    result="$(dig +short "$host" A @1.1.1.1 | paste -sd, -)"
    printf '%s=%s\n' "$host" "${result:-<none>}"
  done
  echo

  log "=== route file ==="
  remote "sudo test -f /etc/dokploy/traefik/dynamic/her-test.yml && sudo sed -n '1,140p' /etc/dokploy/traefik/dynamic/her-test.yml || true"
  echo

  log "=== HTTP probes ==="
  curl -sS -I --max-time 15 "$WEB_URL/zh/pricing" | sed -n '1,12p' || true
  echo
  curl -sS --max-time 15 "$WEB_URL/zh/pricing" | grep -Eo '选择适合你的方案|Pro 月付|Max 月付' | head -8 || true
  echo
  curl -sS --max-time 15 "$API_URL/api/status" | head -c 300 || true
  echo

  log "=== TLS certificates ==="
  for host in www.roome.cn api.roome.cn; do
    log "--- $host"
    echo | openssl s_client -connect "$host:443" -servername "$host" 2>/dev/null \
      | openssl x509 -noout -issuer -subject -dates 2>/dev/null || true
  done
}

enable_ip_ports() {
  verify_remote_web_service_safe
  remote "bash -s" <<REMOTE
set -euo pipefail

publish_if_missing() {
  service="\$1"
  port="\$2"
  if ! sudo docker service inspect "\$service" >/dev/null 2>&1; then
    echo "missing_service=\$service"
    return 0
  fi
  if sudo docker service inspect "\$service" --format '{{json .Endpoint.Spec.Ports}}' | grep -q "\"PublishedPort\":\$port"; then
    echo "port_ready=\$service:\$port"
    return 0
  fi
  sudo docker service update \\
    --publish-add published="\$port",target=3000,protocol=tcp,mode=ingress \\
    "\$service" >/dev/null
  echo "port_added=\$service:\$port"
}

publish_if_missing '$WEB_SERVICE' '$WEB_PUBLIC_PORT'
publish_if_missing '$GW_SERVICE' '$GW_PUBLIC_PORT'

sudo docker service inspect '$WEB_SERVICE' '$GW_SERVICE' --format '{{.Spec.Name}} ports={{json .Endpoint.Spec.Ports}}'
REMOTE
}

write_routes() {
  remote "bash -s" <<'REMOTE'
set -euo pipefail
cat > /tmp/her-test.yml <<'EOF'
http:
  routers:
    her-test-web-router:
      rule: Host(`roome.cn`) || Host(`www.roome.cn`)
      service: her-test-web-service
      priority: 1000
      middlewares: []
      entryPoints:
        - web
    her-test-web-ip-router:
      rule: Host(`192.144.187.174`)
      service: her-test-web-service
      priority: 900
      middlewares: []
      entryPoints:
        - web
    her-test-web-router-websecure:
      rule: Host(`roome.cn`) || Host(`www.roome.cn`)
      service: her-test-web-service
      priority: 1000
      middlewares: []
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt
    her-test-api-router:
      rule: Host(`api.roome.cn`)
      service: her-test-api-service
      priority: 1000
      middlewares: []
      entryPoints:
        - web
    her-test-api-ip-router:
      rule: Host(`192.144.187.174`) && PathPrefix(`/test-gateway`)
      service: her-test-api-service
      priority: 1100
      middlewares:
        - her-test-api-ip-strip
      entryPoints:
        - web
    her-test-api-router-websecure:
      rule: Host(`api.roome.cn`)
      service: her-test-api-service
      priority: 1000
      middlewares: []
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt
  services:
    her-test-web-service:
      loadBalancer:
        servers:
          - url: http://her-web-test:3000
        passHostHeader: true
    her-test-api-service:
      loadBalancer:
        servers:
          - url: http://her-gateway-test:3000
        passHostHeader: true
  middlewares:
    her-test-api-ip-strip:
      stripPrefix:
        prefixes:
          - /test-gateway
EOF
sudo install -m 0644 -o root -g root /tmp/her-test.yml /etc/dokploy/traefik/dynamic/her-test.yml
sudo sed -n '1,120p' /etc/dokploy/traefik/dynamic/her-test.yml
REMOTE
}

verify_test_web_gateway() {
  log "=== verify test web -> gateway binding ==="
  remote "bash -s" <<REMOTE
set -euo pipefail

replicas=\$(sudo docker service ls --filter name='$GW_SERVICE' --format '{{.Replicas}}' | head -n 1)
if [ "\$replicas" != "1/1" ]; then
  echo "ERROR: $GW_SERVICE replicas=\${replicas:-missing}" >&2
  exit 1
fi

webcid=\$(sudo docker ps --filter label=com.docker.swarm.service.name='$WEB_SERVICE' --format '{{.ID}}' | head -n 1)
test -n "\$webcid"
gateway_base=\$(sudo docker exec "\$webcid" printenv API_GATEWAY_BASE_URL 2>/dev/null || true)
if [ "\$gateway_base" != "http://$GW_SERVICE:3000" ]; then
  echo "ERROR: web API_GATEWAY_BASE_URL=\${gateway_base:-missing}" >&2
  exit 1
fi

sudo docker exec "\$webcid" wget -qO- "http://$GW_SERVICE:3000/api/status" >/tmp/her-test-gateway-status.json
echo "gateway_status_ok bytes=\$(wc -c </tmp/her-test-gateway-status.json)"

if [ ! -f '$STACK_DIR/web-db-active.env' ] || [ ! -f '$STACK_DIR/gateway-db.env' ]; then
  echo "gateway_binding_check=skipped reason=missing_db_env"
  exit 0
fi

. '$STACK_DIR/web-db-active.env'
. '$STACK_DIR/gateway-db.env'

rows=\$(sudo docker run -i --rm --network '$NETWORK' -e WEB_DB_URL="\$WEB_DB_URL" postgres:18-alpine sh -ceu 'cat >/tmp/q.sql; psql "\$WEB_DB_URL" -P pager=off -t -A -F "|" -f /tmp/q.sql' <<'SQL'
select coalesce(ug.gateway_user_id, 0), coalesce(ug.token_id, 0), replace(coalesce(u.email, ''), '|', ''), left(coalesce(ug.api_key, ''), 12)
from user_gateway ug
join "user" u on u.id = ug.user_id
where ug.revoked_at is null
order by ug.updated_at desc nulls last
limit 50;
SQL
)

missing=0
total=0
pairs=""
if [ -n "\$rows" ]; then
  while IFS='|' read -r gateway_user_id token_id email api_prefix; do
    [ -n "\$gateway_user_id" ] || continue
    [ "\$gateway_user_id" != "0" ] || continue
    [ "\$token_id" != "0" ] || continue
    total=\$((total + 1))
    pairs="\${pairs:+\$pairs,}(\$token_id,\$gateway_user_id)"
  done <<< "\$rows"
fi

found=""
if [ -n "\$pairs" ]; then
  found=\$(sudo docker run --rm --network '$NETWORK' -e GW_DB_URL="\$GW_DB_URL" postgres:18-alpine sh -ceu "psql \"\\\$GW_DB_URL\" -tA -F '|' -c \"select id, user_id from tokens where (id, user_id) in (\$pairs) and deleted_at is null\"")
fi

if [ -n "\$rows" ]; then
  while IFS='|' read -r gateway_user_id token_id email api_prefix; do
    [ -n "\$gateway_user_id" ] || continue
    [ "\$gateway_user_id" != "0" ] || continue
    [ "\$token_id" != "0" ] || continue
    if ! printf '%s\n' "\$found" | grep -qxF "\$token_id|\$gateway_user_id"; then
      echo "missing_gateway_token email=\$email gateway_user_id=\$gateway_user_id token_id=\$token_id api_key_prefix=\$api_prefix"
      missing=\$((missing + 1))
    fi
  done <<< "\$rows"
fi

if [ "\$missing" -ne 0 ]; then
  echo "ERROR: gateway_binding_check=failed active_checked=\$total missing=\$missing" >&2
  exit 1
fi
echo "gateway_binding_check=ok active_checked=\$total"
REMOTE
}

deploy_web() {
  for arg in "$@"; do
    if [[ "$arg" == "--with-pr" ]]; then
      echo "ERROR: 临时叠 PR 直接部署已禁用；先创建补充分支并合入 dev，再从 origin/dev 部署。" >&2
      exit 2
    fi
  done

  if [[ $# -gt 1 ]]; then
    echo "ERROR: deploy-web accepts exactly one origin/dev worktree path" >&2
    exit 2
  fi

  local src="${1:-${SRC_REPO:-}}"
  if [[ -z "$src" ]]; then
    echo "ERROR: deploy-web requires a her-web worktree path" >&2
    exit 2
  fi
  src="$(cd "$src" && pwd)"
  if [[ ! -f "$src/Dockerfile" || ! -f "$src/package.json" ]]; then
    echo "ERROR: not a her-web worktree: $src" >&2
    exit 1
  fi

  log "=== verify origin/dev source ==="
  git -C "$src" fetch origin dev
  local source_revision dev_revision current_dirty
  source_revision="$(git -C "$src" rev-parse HEAD)"
  dev_revision="$(git -C "$src" rev-parse origin/dev)"
  current_dirty="$(git -C "$src" status --porcelain)"
  if [[ "$source_revision" != "$dev_revision" ]]; then
    echo "ERROR: deploy-web source must be origin/dev" >&2
    echo "       HEAD=$source_revision" >&2
    echo "       origin/dev=$dev_revision" >&2
    exit 1
  fi
  if [[ -n "$current_dirty" ]]; then
    echo "ERROR: deploy-web source worktree must be clean; commit and merge into dev first" >&2
    git -C "$src" status --short >&2
    exit 1
  fi

  verify_remote_web_service_safe

  local stamp remote_dir image_tag schema_sql schema_sql_base remote_schema_sql
  local source_revision_short source_branch source_dirty
  stamp="$(date +%Y%m%d%H%M%S)"
  remote_dir="/tmp/her-web-test-$stamp"
  image_tag="her-web:test-latest"
  remote_schema_sql="/tmp/her-web-test-schema-$stamp.sql"

  # --- Fixed-tag lifecycle: rotate latest → prev, clean older ---
  log "=== image rotation ==="
  remote "
    if sudo docker image inspect her-web:test-prev >/dev/null 2>&1; then
      sudo docker rmi her-web:test-prev 2>/dev/null || true
    fi
    if sudo docker image inspect her-web:test-latest >/dev/null 2>&1; then
      sudo docker tag her-web:test-latest her-web:test-prev
    fi
  "
  # Clean up old timestamped images from before this change
  remote "sudo docker images --format '{{.Repository}}:{{.Tag}}' | grep '^her-web:test-' | xargs -r sudo docker rmi 2>/dev/null || true"
  source_revision="$(git_value_or_unknown "$src" rev-parse HEAD)"
  source_revision_short="$(git_value_or_unknown "$src" rev-parse --short=12 HEAD)"
  source_branch="$(git_value_or_unknown "$src" rev-parse --abbrev-ref HEAD)"
  if [[ -n "$(git -C "$src" status --porcelain 2>/dev/null || true)" ]]; then
    source_dirty="true"
  else
    source_dirty="false"
  fi

  log "source_revision=$source_revision_short branch=$source_branch dirty=$source_dirty"

  log "=== rsync her-web worktree ==="
  remote "mkdir -p '$remote_dir'"
  rsync -az --delete \
    --exclude '.git' \
    --exclude '.env*' \
    --exclude 'node_modules' \
    --exclude '.next' \
    --exclude 'data' \
    --exclude 'docs' \
    --exclude '.agents' \
    --exclude '.codex' \
    --exclude '.claude' \
    --exclude '.trellis' \
    "$src/" "$SERVER:$remote_dir/"

  schema_sql="$(find "$src/drizzle" -maxdepth 1 -name '*.sql' 2>/dev/null | sort | head -n 1 || true)"
  if [[ -n "$schema_sql" ]]; then
    schema_sql_base="$(basename "$schema_sql")"
    remote "cp '$remote_dir/drizzle/$schema_sql_base' '$remote_schema_sql'"
  fi

  remote "cat > '$remote_dir/.env.production' <<EOF
NEXT_PUBLIC_APP_URL=$WEB_URL
NEXT_PUBLIC_APP_NAME=Her
NEXT_PUBLIC_APP_DESCRIPTION=Her test environment
NEXT_PUBLIC_DEFAULT_LOCALE=zh
NEXT_PUBLIC_API_GATEWAY_QUOTA_PER_UNIT=500000
DATABASE_PROVIDER=postgres
DB_SINGLETON_ENABLED=true
DB_MAX_CONNECTIONS=3
EOF"

  echo "=== docker build $image_tag ==="
  remote "cd '$remote_dir' && sudo DOCKER_BUILDKIT=1 docker build \
    --label her.test.source.repo=her-web \
    --label her.test.source.revision='$source_revision' \
    --label her.test.source.branch='$source_branch' \
    --label her.test.source.dirty='$source_dirty' \
    --label her.test.built_at='$stamp' \
    -t '$image_tag' . && sudo docker image inspect '$image_tag' --format 'image={{.Id}} labels={{json .Config.Labels}}'"

  echo "=== ensure isolated web DB ==="
  remote "bash -s" <<REMOTE
set -euo pipefail
mkdir -p '$STACK_DIR'
chmod 700 '$STACK_DIR'
if ! sudo docker service inspect '$WEB_DB_SERVICE' >/dev/null 2>&1; then
  WEB_DB_PASS=\$(openssl rand -base64 24 | tr -d '=+/' | cut -c1-24)
  cat > '$STACK_DIR/web-db.env' <<EOF
WEB_DB_PASS=\${WEB_DB_PASS}
WEB_DB_URL=postgres://herweb_test:\${WEB_DB_PASS}@$WEB_DB_SERVICE:5432/her_web_test
EOF
  chmod 600 '$STACK_DIR/web-db.env'
  sudo docker service create \\
    --name '$WEB_DB_SERVICE' \\
    --network '$NETWORK' \\
    --mount type=volume,src='$WEB_DB_VOLUME',dst=/var/lib/postgresql/data \\
    --env POSTGRES_DB=her_web_test \\
    --env POSTGRES_USER=herweb_test \\
    --env POSTGRES_PASSWORD=\${WEB_DB_PASS} \\
    '$WEB_DB_IMAGE' >/dev/null
fi
for i in \$(seq 1 90); do
  cid=\$(sudo docker ps --filter label=com.docker.swarm.service.name='$WEB_DB_SERVICE' --format '{{.ID}}' | head -n 1)
  if [ -n "\$cid" ] && sudo docker exec "\$cid" pg_isready -U herweb_test -d her_web_test >/dev/null 2>&1; then
    tables=\$(sudo docker exec "\$cid" psql -U herweb_test -d her_web_test -Atc "select count(*)::text from information_schema.tables where table_schema='public';")
    if [ "\$tables" = "0" ] && [ -f '$remote_schema_sql' ]; then
      sudo docker exec -i "\$cid" psql -v ON_ERROR_STOP=1 -U herweb_test -d her_web_test < '$remote_schema_sql' >/tmp/her-web-test-schema.log 2>&1 || { cat /tmp/her-web-test-schema.log; exit 1; }
    fi
    cat > /tmp/her-web-product-rescope-schema.sql <<'SQL'
alter table if exists "invite_code"
  add column if not exists "balance_cents" integer not null default 0;
alter table if exists "invite_code"
  add column if not exists "is_hclub" boolean not null default false;
do \$\$
begin
  if to_regclass('public.invite_code') is not null then
    update "invite_code"
    set "balance_cents" = case
      when coalesce("trial_days", 15) <= 3 then 100000
      else 300000
    end
    where "balance_cents" = 0;
    update "invite_code"
    set "is_hclub" = true
    where "is_hclub" = false
      and ("code" like 'HCLUB-%' or coalesce("note", '') like 'herclub:%');
  end if;
end \$\$;
create table if not exists "admin_user_note" (
  "user_id" text primary key references "user"("id") on delete cascade,
  "note" text not null default '',
  "updated_by" text references "user"("id"),
  "updated_at" timestamp not null default now()
);
create index if not exists "idx_admin_user_note_updated_at"
  on "admin_user_note" ("updated_at");
create table if not exists "usage_record" (
  "id" text primary key,
  "user_id" text not null references "user"("id") on delete cascade,
  "metric" text not null,
  "amount" integer not null default 1,
  "model" text,
  "model_region" text,
  "occurred_at" timestamp not null default now()
);
create index if not exists "idx_usage_record_user_occurred"
  on "usage_record" ("user_id", "occurred_at");
create index if not exists "idx_usage_record_user_metric_occurred"
  on "usage_record" ("user_id", "metric", "occurred_at");
create index if not exists "idx_user_gateway_api_key"
  on "user_gateway" ("api_key");
create table if not exists "agent_conversation_log" (
  "id" text primary key,
  "user_id" text not null references "user"("id") on delete cascade,
  "gateway_user_id" integer,
  "gateway_request_id" text,
  "session_id" text not null,
  "client_name" text,
  "client_version" text,
  "source" text not null default 'gateway',
  "endpoint" text,
  "request_path" text,
  "request_method" text not null default 'POST',
  "request_model" text,
  "upstream_model" text,
  "request_format" text,
  "status" text not null default 'unknown',
  "http_status" integer,
  "is_stream" boolean not null default false,
  "prompt_tokens" integer,
  "completion_tokens" integer,
  "quota" integer,
  "cost_cents" integer,
  "latency_ms" integer,
  "started_at" timestamp not null default now(),
  "completed_at" timestamp,
  "request_body" text,
  "response_body" text,
  "metadata" text,
  "truncated" boolean not null default false,
  "created_at" timestamp not null default now()
);
create index if not exists "idx_agent_conv_user_started"
  on "agent_conversation_log" ("user_id", "started_at");
create index if not exists "idx_agent_conv_session_started"
  on "agent_conversation_log" ("session_id", "started_at");
create unique index if not exists "uniq_agent_conv_request_id"
  on "agent_conversation_log" ("gateway_request_id");
create index if not exists "idx_agent_conv_model_started"
  on "agent_conversation_log" ("request_model", "started_at");
create index if not exists "idx_agent_conv_status_started"
  on "agent_conversation_log" ("status", "started_at");
create table if not exists "agent_behavior_event" (
  "id" text primary key,
  "user_id" text not null references "user"("id") on delete cascade,
  "conversation_id" text references "agent_conversation_log"("id") on delete set null,
  "client_event_id" text,
  "gateway_request_id" text,
  "session_id" text not null,
  "client_name" text,
  "client_version" text,
  "event_type" text not null,
  "source" text not null default 'client',
  "summary" text not null default '',
  "payload" text,
  "risk_level" text not null default 'low',
  "occurred_at" timestamp not null default now(),
  "created_at" timestamp not null default now()
);
alter table if exists "agent_behavior_event"
  add column if not exists "client_event_id" text;
create index if not exists "idx_agent_event_user_occurred"
  on "agent_behavior_event" ("user_id", "occurred_at");
create index if not exists "idx_agent_event_session_occurred"
  on "agent_behavior_event" ("session_id", "occurred_at");
create index if not exists "idx_agent_event_type_occurred"
  on "agent_behavior_event" ("event_type", "occurred_at");
create unique index if not exists "uniq_agent_event_request_type"
  on "agent_behavior_event" ("gateway_request_id", "event_type");
create unique index if not exists "uniq_agent_event_user_client_event"
  on "agent_behavior_event" ("user_id", "client_event_id");
create table if not exists "agent_raw_log_access" (
  "id" text primary key,
  "conversation_id" text not null references "agent_conversation_log"("id") on delete cascade,
  "operator_id" text references "user"("id") on delete set null,
  "operator_email" text,
  "action" text not null default 'view_raw',
  "reason" text,
  "created_at" timestamp not null default now()
);
create index if not exists "idx_agent_raw_access_conversation"
  on "agent_raw_log_access" ("conversation_id");
create index if not exists "idx_agent_raw_access_operator_created"
  on "agent_raw_log_access" ("operator_id", "created_at");
create table if not exists "agent_usage_forecast" (
  "id" text primary key,
  "user_id" text not null references "user"("id") on delete cascade,
  "basis" text not null,
  "window_start" timestamp not null,
  "window_end" timestamp not null,
  "sample_hours" integer not null,
  "observed_spend_cents" integer not null default 0,
  "observed_calls" integer not null default 0,
  "projected_30d_spend_cents" integer not null default 0,
  "projected_30d_calls" integer not null default 0,
  "current_balance_cents" integer not null default 0,
  "runway_hours" integer,
  "risk" text not null,
  "warnings" text,
  "created_at" timestamp not null default now()
);
create index if not exists "idx_agent_forecast_user_created"
  on "agent_usage_forecast" ("user_id", "created_at");
create index if not exists "idx_agent_forecast_risk_created"
  on "agent_usage_forecast" ("risk", "created_at");
SQL
    user_table_exists=\$(sudo docker exec "\$cid" psql -U herweb_test -d her_web_test -Atc "select count(*)::text from information_schema.tables where table_schema='public' and table_name='user';")
    if [ "\$user_table_exists" = "1" ]; then
      sudo docker exec -i "\$cid" psql -v ON_ERROR_STOP=1 -U herweb_test -d her_web_test < /tmp/her-web-product-rescope-schema.sql >/tmp/her-web-product-rescope-schema.log 2>&1 || { cat /tmp/her-web-product-rescope-schema.log; exit 1; }
    else
      echo "web_db_schema_patch=skipped_no_user_table"
    fi
    echo "web_db_ready=$WEB_DB_SERVICE tables=\$tables"
    exit 0
  fi
  sleep 2
done
echo "web DB not ready" >&2
exit 1
REMOTE

  log "=== ensure active web DB schema ==="
  remote "bash -s" <<REMOTE
set -euo pipefail
if [ ! -f '$STACK_DIR/web-db-active.env' ]; then
  echo "active_web_db_schema=primary"
  exit 0
fi
. '$STACK_DIR/web-db-active.env'
active_host=\$(printf '%s\n' "\$WEB_DB_URL" | sed -E 's#^postgres://[^@]+@([^:/]+).*#\\1#')
active_user=\$(printf '%s\n' "\$WEB_DB_URL" | sed -E 's#^postgres://([^:/]+):.*#\\1#')
active_db=\$(printf '%s\n' "\$WEB_DB_URL" | sed -E 's#^postgres://[^/]+/([^?]+).*#\\1#')
if [ -z "\$active_host" ] || [ -z "\$active_user" ] || [ -z "\$active_db" ]; then
  echo "ERROR: cannot parse active WEB_DB_URL" >&2
  exit 1
fi
if [ "\$active_host" = '$WEB_DB_SERVICE' ]; then
  echo "active_web_db_schema=primary"
  exit 0
fi
if [ ! -f /tmp/her-web-product-rescope-schema.sql ]; then
  echo "ERROR: schema patch file missing" >&2
  exit 1
fi
cid=\$(sudo docker ps --filter label=com.docker.swarm.service.name="\$active_host" --format '{{.ID}}' | head -n 1)
if [ -z "\$cid" ]; then
  echo "ERROR: active web DB container not found: \$active_host" >&2
  exit 1
fi
active_user_table_exists=\$(sudo docker exec "\$cid" psql -U "\$active_user" -d "\$active_db" -Atc "select count(*)::text from information_schema.tables where table_schema='public' and table_name='user';")
if [ "\$active_user_table_exists" = "1" ]; then
  sudo docker exec -i "\$cid" psql -v ON_ERROR_STOP=1 -U "\$active_user" -d "\$active_db" < /tmp/her-web-product-rescope-schema.sql >/tmp/her-web-active-schema.log 2>&1 || { cat /tmp/her-web-active-schema.log; exit 1; }
else
  echo "active_web_db_schema_patch=skipped_no_user_table"
fi
echo "active_web_db_schema_ready=\$active_host"
REMOTE

  log "=== recreate test web service ==="
remote "bash -s" <<REMOTE
set -euo pipefail
. '$STACK_DIR/web-db.env'
if [ -f '$STACK_DIR/web-db-active.env' ]; then
  . '$STACK_DIR/web-db-active.env'
fi
if [ ! -f '$STACK_DIR/agent-ops.env' ]; then
  AGENT_OPS_INGEST_SECRET=\$(openssl rand -hex 32)
  cat > '$STACK_DIR/agent-ops.env' <<EOF
AGENT_OPS_INGEST_SECRET=\${AGENT_OPS_INGEST_SECRET}
EOF
  chmod 600 '$STACK_DIR/agent-ops.env'
fi
. '$STACK_DIR/agent-ops.env'
if [ ! -f '$STACK_DIR/web-auth.env' ]; then
  AUTH_SECRET=\$(openssl rand -hex 32)
  cat > '$STACK_DIR/web-auth.env' <<EOF
AUTH_SECRET=\${AUTH_SECRET}
EOF
  chmod 600 '$STACK_DIR/web-auth.env'
fi
. '$STACK_DIR/web-auth.env'
webcid=\$(sudo docker ps --filter name=her-herweb-a8y5ka --format '{{.ID}}' | head -n 1)
test -n "\$webcid"
prod_env=\$(sudo docker inspect "\$webcid" --format '{{range .Config.Env}}{{println .}}{{end}}')
getenv() { printf '%s\n' "\$prod_env" | sed -n "s/^\$1=//p" | head -n 1; }
API_GATEWAY_ADMIN_TOKEN=\$(getenv API_GATEWAY_ADMIN_TOKEN)
API_GATEWAY_ADMIN_ID=\$(getenv API_GATEWAY_ADMIN_ID)
test -n "\$API_GATEWAY_ADMIN_TOKEN"
test -n "\$API_GATEWAY_ADMIN_ID"
# Inherit parity-sensitive env from production web container
PROD_BYPASS_TOKEN=\$(getenv HER_INTERNAL_RATE_LIMIT_BYPASS_TOKEN)
PROD_APP_LOGO=\$(getenv NEXT_PUBLIC_APP_LOGO)
cat > '$STACK_DIR/web-app.env' <<EOF
NODE_ENV=production
PORT=3000
HOSTNAME=0.0.0.0
NEXT_PUBLIC_APP_URL=$WEB_URL
NEXT_PUBLIC_APP_NAME=Her
NEXT_PUBLIC_APP_DESCRIPTION=Her test environment
NEXT_PUBLIC_APP_LOGO=\${PROD_APP_LOGO:-/images/logo.webp}
NEXT_PUBLIC_DEFAULT_LOCALE=zh
NEXT_PUBLIC_API_GATEWAY_QUOTA_PER_UNIT=500000
AUTH_URL=$WEB_URL
AUTH_SECRET=\${AUTH_SECRET}
AUTH_RATE_LIMIT_ENABLED=false
AUTH_TRUSTED_ORIGINS=$AUTH_TRUSTED_ORIGINS
DATABASE_PROVIDER=postgres
DATABASE_URL=\${WEB_DB_URL}
DB_SINGLETON_ENABLED=true
DB_MAX_CONNECTIONS=3
API_GATEWAY_BASE_URL=http://$GW_SERVICE:3000
API_GATEWAY_OPENAI_BASE_URL=http://$GW_SERVICE:3000/v1
API_GATEWAY_ADMIN_TOKEN=\${API_GATEWAY_ADMIN_TOKEN}
API_GATEWAY_ADMIN_ID=\${API_GATEWAY_ADMIN_ID}
API_GATEWAY_QUOTA_PER_UNIT=500000
API_GATEWAY_SIGNUP_DOLLARS_INVITED=1000
API_GATEWAY_SIGNUP_DOLLARS_DEFAULT=20
API_GATEWAY_DEFAULT_MODEL=her-latest
API_GATEWAY_PROVIDER_LABEL=Her System
AGENT_OPS_INGEST_SECRET=\${AGENT_OPS_INGEST_SECRET}
ALIPAY_NOTIFY_URL=$WEB_URL/api/payment/notify/alipay
WECHAT_NOTIFY_URL=$WEB_URL/api/payment/notify/wechat
EOF
# Append bypass token only if production has it
if [ -n "\$PROD_BYPASS_TOKEN" ]; then
  echo "HER_INTERNAL_RATE_LIMIT_BYPASS_TOKEN=\${PROD_BYPASS_TOKEN}" >> '$STACK_DIR/web-app.env'
fi
# Sync business env vars that prod has but test template doesn't list
for _key in FEISHU_APP_ID FEISHU_APP_SECRET FEISHU_BASE_TOKEN FEISHU_TABLE_ID; do
  _val=\$(getenv "\$_key")
  [ -n "\$_val" ] && echo "\${_key}=\${_val}" >> '$STACK_DIR/web-app.env'
done
chmod 600 '$STACK_DIR/web-app.env'
if sudo docker service inspect '$WEB_SERVICE' >/dev/null 2>&1; then
  update_args=()
  while IFS= read -r line || [ -n "\$line" ]; do
    [ -n "\$line" ] || continue
    update_args+=(--env-add "\$line")
  done < '$STACK_DIR/web-app.env'
  sudo docker service update \\
    --image '$image_tag' \\
    --force \\
    --update-order start-first \\
    --update-parallelism 1 \\
    --update-failure-action pause \\
    --rollback-order start-first \\
    --rollback-parallelism 1 \\
    --rollback-failure-action pause \\
    --label-add her.test.source.repo=her-web \\
    --label-add her.test.source.revision='$source_revision' \\
    --label-add her.test.source.branch='$source_branch' \\
    --label-add her.test.source.dirty='$source_dirty' \\
    --label-add her.test.built_at='$stamp' \\
    "\${update_args[@]}" \\
    '$WEB_SERVICE' >/dev/null
else
  sudo docker service create \\
    --name '$WEB_SERVICE' \\
    --network '$NETWORK' \\
    --limit-memory 1024M \\
    --env NODE_OPTIONS=--max-old-space-size=768 \\
    --label her.test.source.repo=her-web \\
    --label her.test.source.revision='$source_revision' \\
    --label her.test.source.branch='$source_branch' \\
    --label her.test.source.dirty='$source_dirty' \\
    --label her.test.built_at='$stamp' \\
    --update-order start-first \\
    --update-parallelism 1 \\
    --update-failure-action pause \\
    --rollback-order start-first \\
    --rollback-parallelism 1 \\
    --rollback-failure-action pause \\
    --publish published='$WEB_PUBLIC_PORT',target=3000,protocol=tcp,mode=ingress \\
    --env-file '$STACK_DIR/web-app.env' \\
    '$image_tag' >/dev/null
fi
for i in \$(seq 1 180); do
  cid=\$(sudo docker ps --filter label=com.docker.swarm.service.name='$WEB_SERVICE' --format '{{.ID}} {{.Image}}' | awk '\$2 == "'$image_tag'" {print \$1; exit}')
  replicas=\$(sudo docker service ls --filter name='$WEB_SERVICE' --format '{{.Replicas}}' | head -n 1)
  if [ -n "\$cid" ] && [ "\$replicas" = "1/1" ] && sudo docker exec "\$cid" wget -qO- http://127.0.0.1:3000/zh/pricing >/dev/null 2>&1; then
    cat > '$STACK_DIR/web-current.env' <<EOF
ROOME_WEB_IMAGE=$image_tag
ROOME_WEB_SOURCE_REPO=her-web
ROOME_WEB_SOURCE_REVISION=$source_revision
ROOME_WEB_SOURCE_BRANCH=$source_branch
ROOME_WEB_SOURCE_DIRTY=$source_dirty
ROOME_WEB_BUILT_AT=$stamp
ROOME_WEB_SOURCE_PATH=$src
EOF
    chmod 600 '$STACK_DIR/web-current.env'
    echo "web_ready=$WEB_SERVICE container=\$cid image=$image_tag"
    exit 0
  fi
  sleep 2
done
sudo docker service ps '$WEB_SERVICE' --no-trunc
exit 1
REMOTE

  remote "sudo docker service inspect '$WEB_SERVICE' --format 'service={{.Spec.Name}} labels={{json .Spec.Labels}} image={{.Spec.TaskTemplate.ContainerSpec.Image}}'"

  verify_test_web_gateway

  log ""
  log "=========================================="
  log "  Roome web 部署完成"
  log "  镜像: $image_tag"
  log "  来源: $source_branch ($source_revision_short) dirty=$source_dirty"
  log "=========================================="
  log ""
  log "数据同步提醒："
  log "  当前 test DB 数据未变动。如需同步生产数据，手动运行："
  log "    ALLOW_TEST_DB_REFRESH=1 bash $0 refresh-all"
  log "  注意：同步会覆盖 test 测试数据（含你手动修改的数据）。"
  log ""
  echo "deploy_web=ok image=$image_tag source=$source_revision_short branch=$source_branch"
}

deploy_gateway() {
  local src="${1:-${SRC_REPO:-}}"
  if [[ -z "$src" ]]; then
    echo "ERROR: deploy-gateway requires a her-gateway worktree path" >&2
    exit 2
  fi
  src="$(cd "$src" && pwd)"
  if [[ ! -f "$src/Dockerfile" || ! -f "$src/go.mod" || ! -f "$src/main.go" ]]; then
    echo "ERROR: not a her-gateway worktree: $src" >&2
    exit 1
  fi

  local stamp remote_dir image_tag
  stamp="$(date +%Y%m%d%H%M%S)"
  remote_dir="/tmp/her-gateway-test-$stamp"
  image_tag="her-gateway:test-latest"

  # --- Fixed-tag lifecycle: rotate latest → prev, clean older ---
  log "=== gateway image rotation ==="
  remote "
    if sudo docker image inspect her-gateway:test-prev >/dev/null 2>&1; then
      sudo docker rmi her-gateway:test-prev 2>/dev/null || true
    fi
    if sudo docker image inspect her-gateway:test-latest >/dev/null 2>&1; then
      sudo docker tag her-gateway:test-latest her-gateway:test-prev
    fi
  "
  remote "sudo docker images --format '{{.Repository}}:{{.Tag}}' | grep '^her-gateway:test-' | xargs -r sudo docker rmi 2>/dev/null || true"

  log "=== rsync her-gateway worktree to server ==="
  remote "mkdir -p '$remote_dir'"
  rsync -az --delete \
    --exclude '.git' \
    --exclude '.env*' \
    --exclude 'bin' \
    --exclude 'data' \
    --exclude 'docs' \
    --exclude 'scripts' \
    --exclude '.agents' \
    --exclude '.codex' \
    --exclude '.claude' \
    --exclude '.trellis' \
    "$src/" "$SERVER:$remote_dir/"

  log "=== server docker build $image_tag (native amd64) ==="
  remote "cd '$remote_dir' && sudo DOCKER_BUILDKIT=1 docker build -t '$image_tag' . && sudo docker image inspect '$image_tag' --format 'image={{.Id}}'"

  log "=== update test gateway service ==="
  remote "bash -s" <<REMOTE
set -euo pipefail
mkdir -p '$STACK_DIR'
chmod 700 '$STACK_DIR'
if [ ! -f '$STACK_DIR/agent-ops.env' ]; then
  AGENT_OPS_INGEST_SECRET=\$(openssl rand -hex 32)
  cat > '$STACK_DIR/agent-ops.env' <<EOF
AGENT_OPS_INGEST_SECRET=\${AGENT_OPS_INGEST_SECRET}
EOF
  chmod 600 '$STACK_DIR/agent-ops.env'
fi
. '$STACK_DIR/agent-ops.env'
if [ -f '$STACK_DIR/gateway-app.env' ]; then
  tmp=\$(mktemp)
  grep -Ev '^(HER_WEB_AGENT_OPS_|REQUEST_LOG_)' '$STACK_DIR/gateway-app.env' > "\$tmp" || true
  cat >> "\$tmp" <<EOF
HER_WEB_AGENT_OPS_INGEST_URL=http://$WEB_SERVICE:3000/api/agent-ops/ingest
HER_WEB_AGENT_OPS_INGEST_SECRET=\${AGENT_OPS_INGEST_SECRET}
HER_WEB_AGENT_OPS_MAX_BODY_BYTES=262144
REQUEST_LOG_ENABLED=true
REQUEST_LOG_MAX_BYTES=2097152
REQUEST_LOG_MAX_STRING_CHARS=200000
EOF
  install -m 0600 "\$tmp" '$STACK_DIR/gateway-app.env'
  rm -f "\$tmp"
fi
if ! sudo docker service inspect '$GW_SERVICE' >/dev/null 2>&1; then
  test -f '$STACK_DIR/gateway-app.env'
  sudo docker service create \\
    --name '$GW_SERVICE' \\
    --network '$NETWORK' \\
    --publish published='$GW_PUBLIC_PORT',target=3000,protocol=tcp,mode=ingress \\
    --env-file '$STACK_DIR/gateway-app.env' \\
    '$image_tag' >/dev/null
else
  sudo docker service update \\
    --image '$image_tag' \\
    --env-add HER_WEB_AGENT_OPS_INGEST_URL=http://$WEB_SERVICE:3000/api/agent-ops/ingest \\
    --env-add HER_WEB_AGENT_OPS_INGEST_SECRET="\${AGENT_OPS_INGEST_SECRET}" \\
    --env-add HER_WEB_AGENT_OPS_MAX_BODY_BYTES=262144 \\
    --env-add REQUEST_LOG_ENABLED=true \\
    --env-add REQUEST_LOG_MAX_BYTES=2097152 \\
    --env-add REQUEST_LOG_MAX_STRING_CHARS=200000 \\
    --force '$GW_SERVICE' >/dev/null
fi
for i in \$(seq 1 90); do
  cid=\$(sudo docker ps --filter name='$GW_SERVICE' --format '{{.ID}}' | head -n 1)
  if [ -n "\$cid" ] && sudo docker exec "\$cid" wget -qO- http://127.0.0.1:3000/api/status >/dev/null 2>&1; then
    echo "gateway_ready=$GW_SERVICE container=\$cid image=$image_tag ingest=http://$WEB_SERVICE:3000/api/agent-ops/ingest"
    exit 0
  fi
  sleep 2
done
sudo docker service ps '$GW_SERVICE' --no-trunc
exit 1
REMOTE
  echo "deploy_gateway=ok image=$image_tag"
}

refresh_web_db() {
  require_refresh_confirmation
  verify_remote_web_service_safe
  remote "bash -s" <<REMOTE
set -euo pipefail
$wait_service_removed_remote
mkdir -p '$STACK_DIR'
chmod 700 '$STACK_DIR'

WEB_IMAGE=\$(sudo docker service inspect '$WEB_SERVICE' --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}' 2>/dev/null || true)
if [ -z "\$WEB_IMAGE" ]; then
  echo "ERROR: $WEB_SERVICE does not exist; run deploy-web first" >&2
  exit 1
fi

if sudo docker service inspect her-web-test-db-clone >/dev/null 2>&1; then
  sudo docker service rm her-web-test-db-clone >/dev/null
  wait_service_removed her-web-test-db-clone
fi
for i in \$(seq 1 120); do
  if ! sudo docker ps -a --filter label=com.docker.swarm.service.name=her-web-test-db-clone --format '{{.ID}}' | grep -q .; then
    break
  fi
  sleep 1
done
if sudo docker ps -a --filter label=com.docker.swarm.service.name=her-web-test-db-clone --format '{{.ID}}' | grep -q .; then
  echo "ERROR: old her-web-test-db-clone containers still exist; refusing to reuse clone volume" >&2
  exit 1
fi
if sudo docker volume inspect her-web-test-db-clone-data >/dev/null 2>&1; then
  sudo docker volume rm her-web-test-db-clone-data >/dev/null
fi

WEB_CLONE_PASS=\$(openssl rand -base64 24 | tr -d '=+/' | cut -c1-24)
cat > '$STACK_DIR/web-db-clone.env' <<EOF
WEB_CLONE_DB_PASS=\${WEB_CLONE_PASS}
WEB_CLONE_DB_URL=postgres://herweb_test_clone:\${WEB_CLONE_PASS}@her-web-test-db-clone:5432/her_web_test_clone
EOF
chmod 600 '$STACK_DIR/web-db-clone.env'

sudo docker service create \\
  --name her-web-test-db-clone \\
  --network '$NETWORK' \\
  --mount type=volume,src=her-web-test-db-clone-data,dst=/var/lib/postgresql \\
  --env PGDATA=/var/lib/postgresql/data/pgdata \\
  --env POSTGRES_DB=her_web_test_clone \\
  --env POSTGRES_USER=herweb_test_clone \\
  --env POSTGRES_PASSWORD=\${WEB_CLONE_PASS} \\
  postgres:18-alpine >/dev/null

for i in \$(seq 1 90); do
  dbcid=\$(sudo docker ps --filter label=com.docker.swarm.service.name=her-web-test-db-clone --format '{{.ID}}' | head -n 1)
  if [ -n "\$dbcid" ] && sudo docker exec "\$dbcid" pg_isready -U herweb_test_clone -d her_web_test_clone >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
test -n "\${dbcid:-}"

prod_web_cid=\$(sudo docker ps --filter name=her-herweb-a8y5ka --format '{{.ID}}' | head -n 1)
test -n "\$prod_web_cid"
PROD_WEB_DSN=\$(sudo docker inspect "\$prod_web_cid" --format '{{range .Config.Env}}{{println .}}{{end}}' | sed -n 's/^DATABASE_URL=//p')
test -n "\$PROD_WEB_DSN"
. '$STACK_DIR/web-db-clone.env'
sudo docker run --rm --network '$NETWORK' \\
  -e PROD_WEB_DSN="\$PROD_WEB_DSN" \\
  -e WEB_CLONE_DB_URL="\$WEB_CLONE_DB_URL" \\
  postgres:18-alpine sh -ceu 'pg_dump --no-owner --no-privileges "\$PROD_WEB_DSN" | psql -v ON_ERROR_STOP=1 "\$WEB_CLONE_DB_URL" >/tmp/herweb-restore.log'

sudo docker exec -i "\$dbcid" psql -U herweb_test_clone -d her_web_test_clone -v ON_ERROR_STOP=1 <<SQL
truncate table session;
update config set value = '$WEB_URL' where name in ('app_url', 'NEXT_PUBLIC_APP_URL', 'auth_url');
update config set value = '$WEB_URL/api/payment/notify/wechat' where name = 'wechat_notify_url';
update config set value = '$WEB_URL/api/payment/notify/alipay' where name = 'alipay_notify_url';
SQL

cat > /tmp/her-web-product-rescope-schema.sql <<'SQL'
alter table if exists "invite_code"
  add column if not exists "balance_cents" integer not null default 0;
alter table if exists "invite_code"
  add column if not exists "is_hclub" boolean not null default false;
do \$\$
begin
  if to_regclass('public.invite_code') is not null then
    update "invite_code"
    set "balance_cents" = case
      when coalesce("trial_days", 15) <= 3 then 100000
      else 300000
    end
    where "balance_cents" = 0;
    update "invite_code"
    set "is_hclub" = true
    where "is_hclub" = false
      and ("code" like 'HCLUB-%' or coalesce("note", '') like 'herclub:%');
  end if;
end \$\$;
create table if not exists "admin_user_note" (
  "user_id" text primary key references "user"("id") on delete cascade,
  "note" text not null default '',
  "updated_by" text references "user"("id"),
  "updated_at" timestamp not null default now()
);
create index if not exists "idx_admin_user_note_updated_at"
  on "admin_user_note" ("updated_at");
create table if not exists "usage_record" (
  "id" text primary key,
  "user_id" text not null references "user"("id") on delete cascade,
  "metric" text not null,
  "amount" integer not null default 1,
  "model" text,
  "model_region" text,
  "occurred_at" timestamp not null default now()
);
create index if not exists "idx_usage_record_user_occurred"
  on "usage_record" ("user_id", "occurred_at");
create index if not exists "idx_usage_record_user_metric_occurred"
  on "usage_record" ("user_id", "metric", "occurred_at");
create index if not exists "idx_user_gateway_api_key"
  on "user_gateway" ("api_key");
create table if not exists "agent_conversation_log" (
  "id" text primary key,
  "user_id" text not null references "user"("id") on delete cascade,
  "gateway_user_id" integer,
  "gateway_request_id" text,
  "session_id" text not null,
  "client_name" text,
  "client_version" text,
  "source" text not null default 'gateway',
  "endpoint" text,
  "request_path" text,
  "request_method" text not null default 'POST',
  "request_model" text,
  "upstream_model" text,
  "request_format" text,
  "status" text not null default 'unknown',
  "http_status" integer,
  "is_stream" boolean not null default false,
  "prompt_tokens" integer,
  "completion_tokens" integer,
  "quota" integer,
  "cost_cents" integer,
  "latency_ms" integer,
  "started_at" timestamp not null default now(),
  "completed_at" timestamp,
  "request_body" text,
  "response_body" text,
  "metadata" text,
  "truncated" boolean not null default false,
  "created_at" timestamp not null default now()
);
create index if not exists "idx_agent_conv_user_started"
  on "agent_conversation_log" ("user_id", "started_at");
create index if not exists "idx_agent_conv_session_started"
  on "agent_conversation_log" ("session_id", "started_at");
create unique index if not exists "uniq_agent_conv_request_id"
  on "agent_conversation_log" ("gateway_request_id");
create index if not exists "idx_agent_conv_model_started"
  on "agent_conversation_log" ("request_model", "started_at");
create index if not exists "idx_agent_conv_status_started"
  on "agent_conversation_log" ("status", "started_at");
create table if not exists "agent_behavior_event" (
  "id" text primary key,
  "user_id" text not null references "user"("id") on delete cascade,
  "conversation_id" text references "agent_conversation_log"("id") on delete set null,
  "client_event_id" text,
  "gateway_request_id" text,
  "session_id" text not null,
  "client_name" text,
  "client_version" text,
  "event_type" text not null,
  "source" text not null default 'client',
  "summary" text not null default '',
  "payload" text,
  "risk_level" text not null default 'low',
  "occurred_at" timestamp not null default now(),
  "created_at" timestamp not null default now()
);
alter table if exists "agent_behavior_event"
  add column if not exists "client_event_id" text;
create index if not exists "idx_agent_event_user_occurred"
  on "agent_behavior_event" ("user_id", "occurred_at");
create index if not exists "idx_agent_event_session_occurred"
  on "agent_behavior_event" ("session_id", "occurred_at");
create index if not exists "idx_agent_event_type_occurred"
  on "agent_behavior_event" ("event_type", "occurred_at");
create unique index if not exists "uniq_agent_event_request_type"
  on "agent_behavior_event" ("gateway_request_id", "event_type");
create unique index if not exists "uniq_agent_event_user_client_event"
  on "agent_behavior_event" ("user_id", "client_event_id");
create table if not exists "agent_raw_log_access" (
  "id" text primary key,
  "conversation_id" text not null references "agent_conversation_log"("id") on delete cascade,
  "operator_id" text references "user"("id") on delete set null,
  "operator_email" text,
  "action" text not null default 'view_raw',
  "reason" text,
  "created_at" timestamp not null default now()
);
create index if not exists "idx_agent_raw_access_conversation"
  on "agent_raw_log_access" ("conversation_id");
create index if not exists "idx_agent_raw_access_operator_created"
  on "agent_raw_log_access" ("operator_id", "created_at");
create table if not exists "agent_usage_forecast" (
  "id" text primary key,
  "user_id" text not null references "user"("id") on delete cascade,
  "basis" text not null,
  "window_start" timestamp not null,
  "window_end" timestamp not null,
  "sample_hours" integer not null,
  "observed_spend_cents" integer not null default 0,
  "observed_calls" integer not null default 0,
  "projected_30d_spend_cents" integer not null default 0,
  "projected_30d_calls" integer not null default 0,
  "current_balance_cents" integer not null default 0,
  "runway_hours" integer,
  "risk" text not null,
  "warnings" text,
  "created_at" timestamp not null default now()
);
create index if not exists "idx_agent_forecast_user_created"
  on "agent_usage_forecast" ("user_id", "created_at");
create index if not exists "idx_agent_forecast_risk_created"
  on "agent_usage_forecast" ("risk", "created_at");
SQL
sudo docker exec -i "\$dbcid" psql -U herweb_test_clone -d her_web_test_clone -v ON_ERROR_STOP=1 < /tmp/her-web-product-rescope-schema.sql >/tmp/her-web-product-rescope-schema.log 2>&1 || { cat /tmp/her-web-product-rescope-schema.log; exit 1; }

cat > '$STACK_DIR/web-db-active.env' <<EOF
WEB_DB_URL=\${WEB_CLONE_DB_URL}
EOF
chmod 600 '$STACK_DIR/web-db-active.env'

sudo docker service update \\
  --env-add DATABASE_URL="\$WEB_CLONE_DB_URL" \\
  --force '$WEB_SERVICE' >/dev/null
if ! sudo docker service inspect '$WEB_SERVICE' --format '{{json .Endpoint.Spec.Ports}}' | grep -q '"PublishedPort":'$WEB_PUBLIC_PORT; then
  sudo docker service update \\
    --publish-add published='$WEB_PUBLIC_PORT',target=3000,protocol=tcp,mode=ingress \\
    '$WEB_SERVICE' >/dev/null
fi

for i in \$(seq 1 90); do
  cid=\$(sudo docker ps --filter name='$WEB_SERVICE' --format '{{.ID}}' | head -n 1)
  if [ -n "\$cid" ] && sudo docker exec "\$cid" wget -qO- http://127.0.0.1:3000/zh/pricing >/dev/null 2>&1; then
    users=\$(sudo docker exec "\$dbcid" psql -U herweb_test_clone -d her_web_test_clone -Atc 'select count(*)::text from "user";')
    accounts=\$(sudo docker exec "\$dbcid" psql -U herweb_test_clone -d her_web_test_clone -Atc 'select count(*)::text from account;')
    sessions=\$(sudo docker exec "\$dbcid" psql -U herweb_test_clone -d her_web_test_clone -Atc 'select count(*)::text from session;')
    echo "web_clone_ready=$WEB_SERVICE users=\$users accounts=\$accounts sessions=\$sessions"
    exit 0
  fi
  sleep 2
done
sudo docker service ps '$WEB_SERVICE' --no-trunc
exit 1
REMOTE
}

refresh_gateway_db() {
  require_refresh_confirmation
  remote "bash -s" <<REMOTE
set -euo pipefail
$wait_service_removed_remote
mkdir -p '$STACK_DIR'
chmod 700 '$STACK_DIR'

GW_IMAGE="\${TEST_GATEWAY_IMAGE:-}"
if [ -z "\$GW_IMAGE" ] && sudo docker service inspect '$GW_SERVICE' >/dev/null 2>&1; then
  GW_IMAGE=\$(sudo docker service inspect '$GW_SERVICE' --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}')
fi
if [ -z "\$GW_IMAGE" ]; then
  echo "ERROR: no test gateway image is available; run deploy-gateway first or set TEST_GATEWAY_IMAGE" >&2
  exit 1
fi
case "\$GW_IMAGE" in
  ghcr.io/*|*/ghcr.io/*)
    echo "ERROR: refusing to use remote ghcr image for test gateway refresh: \$GW_IMAGE" >&2
    echo "Run deploy-gateway first so a local her-gateway:test-latest image exists on the server." >&2
    exit 1
    ;;
esac
if ! sudo docker image inspect "\$GW_IMAGE" >/dev/null 2>&1; then
  echo "ERROR: test gateway image is not loaded on the server: \$GW_IMAGE" >&2
  exit 1
fi

if sudo docker service inspect '$GW_SERVICE' >/dev/null 2>&1; then
  sudo docker service rm '$GW_SERVICE' >/dev/null
  wait_service_removed '$GW_SERVICE'
fi
if sudo docker service inspect '$GW_DB_SERVICE' >/dev/null 2>&1; then
  sudo docker service rm '$GW_DB_SERVICE' >/dev/null
  wait_service_removed '$GW_DB_SERVICE'
fi
for i in \$(seq 1 120); do
  if ! sudo docker ps -a --filter label=com.docker.swarm.service.name='$GW_DB_SERVICE' --format '{{.ID}}' | grep -q .; then
    break
  fi
  sleep 1
done
if sudo docker ps -a --filter label=com.docker.swarm.service.name='$GW_DB_SERVICE' --format '{{.ID}}' | grep -q .; then
  echo "ERROR: old $GW_DB_SERVICE containers still exist; refusing to reuse DB volume" >&2
  sudo docker ps -a --filter label=com.docker.swarm.service.name='$GW_DB_SERVICE'
  exit 1
fi
if sudo docker volume inspect '$GW_DB_VOLUME' >/dev/null 2>&1; then
  sudo docker volume rm '$GW_DB_VOLUME' >/dev/null
fi

GW_DB_PASS=\$(openssl rand -base64 24 | tr -d '=+/' | cut -c1-24)
cat > '$STACK_DIR/gateway-db.env' <<EOF
GW_DB_PASS=\${GW_DB_PASS}
GW_DB_URL=postgres://gateway_test:\${GW_DB_PASS}@$GW_DB_SERVICE:5432/gateway_test?sslmode=disable
EOF
chmod 600 '$STACK_DIR/gateway-db.env'

sudo docker service create \\
  --name '$GW_DB_SERVICE' \\
  --network '$NETWORK' \\
  --mount type=volume,src='$GW_DB_VOLUME',dst=/var/lib/postgresql \\
  --env PGDATA=/var/lib/postgresql/data/pgdata \\
  --env POSTGRES_DB=gateway_test \\
  --env POSTGRES_USER=gateway_test \\
  --env POSTGRES_PASSWORD=\${GW_DB_PASS} \\
  postgres:18-alpine >/dev/null

for i in \$(seq 1 90); do
  dbcid=\$(sudo docker ps --filter name='$GW_DB_SERVICE' --format '{{.ID}}' | head -n 1)
  if [ -n "\$dbcid" ] && sudo docker exec "\$dbcid" pg_isready -U gateway_test -d gateway_test >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
test -n "\${dbcid:-}"

prod_cid=\$(sudo docker ps --filter name=new-api --format '{{.ID}}' | head -n 1)
test -n "\$prod_cid"
PROD_DSN=\$(sudo docker inspect "\$prod_cid" --format '{{range .Config.Env}}{{println .}}{{end}}' | sed -n 's/^SQL_DSN=//p')
test -n "\$PROD_DSN"
. '$STACK_DIR/gateway-db.env'
sudo docker run --rm --network '$NETWORK' \\
  -e PROD_DSN="\$PROD_DSN" \\
  -e GW_DB_URL="\$GW_DB_URL" \\
  postgres:18-alpine sh -ceu 'pg_dump --no-owner --no-privileges "\$PROD_DSN" | psql -v ON_ERROR_STOP=1 "\$GW_DB_URL" >/tmp/restore.log'

# Critical path: options must succeed
sudo docker exec -i "\$dbcid" psql -U gateway_test -d gateway_test -v ON_ERROR_STOP=1 <<SQL
update options set value = 'Roome Test Gateway' where key = 'SystemName';
update options set value = '$API_URL' where key = 'ServerAddress';
update options set value = '$WEB_URL' where key = 'general_setting.docs_link';
SQL

# Best-effort: sequence fix (may fail if schema differs; non-fatal)
sudo docker exec -i "\$dbcid" psql -U gateway_test -d gateway_test <<SQL || echo "WARN: sequence fix failed (non-fatal)"
SELECT setval('logs_id_seq', greatest((SELECT coalesce(max(id), 1) FROM logs), 1), true);
SELECT setval('tokens_id_seq', greatest((SELECT coalesce(max(id), 1) FROM tokens), 1), true);
SELECT setval('users_id_seq', greatest((SELECT coalesce(max(id), 1) FROM users), 1), true);
SQL

if ! sudo docker service inspect '$GW_REDIS_SERVICE' >/dev/null 2>&1; then
  sudo docker service create \\
    --name '$GW_REDIS_SERVICE' \\
    --network '$NETWORK' \\
    --mount type=volume,src=her-gateway-test-redis-data,dst=/data \\
    redis:7-alpine >/dev/null
fi
for i in \$(seq 1 60); do
  rcid=\$(sudo docker ps --filter name='$GW_REDIS_SERVICE' --format '{{.ID}}' | head -n 1)
  if [ -n "\$rcid" ] && sudo docker exec "\$rcid" redis-cli ping >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

SESSION_SECRET=\$(openssl rand -hex 32)
if [ ! -f '$STACK_DIR/agent-ops.env' ]; then
  AGENT_OPS_INGEST_SECRET=\$(openssl rand -hex 32)
  cat > '$STACK_DIR/agent-ops.env' <<EOF
AGENT_OPS_INGEST_SECRET=\${AGENT_OPS_INGEST_SECRET}
EOF
  chmod 600 '$STACK_DIR/agent-ops.env'
fi
. '$STACK_DIR/agent-ops.env'

# Inherit parity-sensitive env from production gateway
prod_gw_cid=\$(sudo docker ps --filter name=new-api --format '{{.ID}}' | head -n 1)
PROD_BATCH_UPDATE=\$(sudo docker exec "\$prod_gw_cid" printenv BATCH_UPDATE_ENABLED 2>/dev/null || echo "true")
PROD_BYPASS_TOKEN=\$(sudo docker exec "\$prod_gw_cid" printenv HER_INTERNAL_RATE_LIMIT_BYPASS_TOKEN 2>/dev/null || echo "")

cat > '$STACK_DIR/gateway-app.env' <<EOF
SQL_DSN=\${GW_DB_URL}
REDIS_CONN_STRING=redis://$GW_REDIS_SERVICE:6379
SESSION_SECRET=\${SESSION_SECRET}
TZ=Asia/Shanghai
GIN_MODE=release
ERROR_LOG_ENABLED=true
BATCH_UPDATE_ENABLED=\${PROD_BATCH_UPDATE}
HER_WEB_AGENT_OPS_INGEST_URL=http://$WEB_SERVICE:3000/api/agent-ops/ingest
HER_WEB_AGENT_OPS_INGEST_SECRET=\${AGENT_OPS_INGEST_SECRET}
HER_WEB_AGENT_OPS_MAX_BODY_BYTES=262144
EOF
# Append bypass token only if production has it
if [ -n "\$PROD_BYPASS_TOKEN" ]; then
  echo "HER_INTERNAL_RATE_LIMIT_BYPASS_TOKEN=\${PROD_BYPASS_TOKEN}" >> '$STACK_DIR/gateway-app.env'
fi
chmod 600 '$STACK_DIR/gateway-app.env'

repair_test_web_gateway_bindings() {
  if [ ! -f '$STACK_DIR/web-db-active.env' ]; then
    echo "gateway_binding_check=skipped reason=missing_web_db_active_env"
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 is required to repair test web gateway bindings" >&2
    return 1
  fi
  cat > /tmp/repair-test-gateway-bindings.py <<'PY'
import csv
import json
import secrets
import string
import subprocess

STACK = '$STACK_DIR'

def load_env(path):
    out = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#') or '=' not in line:
                continue
            key, value = line.split('=', 1)
            out[key] = value
    return out

def sql_quote(value):
    if value is None:
        return 'null'
    return "'" + str(value).replace("'", "''") + "'"

def psql(db_url, sql):
    raw = subprocess.check_output([
        'sudo', 'docker', 'run', '--rm', '--network', '$NETWORK',
        '-e', f'DB_URL={db_url}', '-e', f'SQL={sql}',
        'postgres:18-alpine', 'sh', '-ceu', 'psql "\$DB_URL" -Atqc "\$SQL"',
    ], text=True).strip()
    # For INSERT ... RETURNING, psql may still append 'INSERT 0 1' on some
    # versions even with -q.  Take only the first line to be safe.
    return raw.split('\n')[0].strip() if raw else raw

def random_key(length=48):
    alphabet = string.ascii_letters + string.digits
    return ''.join(secrets.choice(alphabet) for _ in range(length))

web_db = load_env(f'{STACK}/web-db-active.env')['WEB_DB_URL']
gw_db = load_env(f'{STACK}/gateway-db.env')['GW_DB_URL']

rows_csv = psql(web_db, '''
copy (
  select ug.user_id, ug.gateway_user_id, coalesce(ug.token_id, 0), ug.api_key,
         ug.gateway_username, coalesce(ug.quota_granted, 0), coalesce(u.email, '')
  from user_gateway ug
  join "user" u on u.id = ug.user_id
  where ug.revoked_at is null
  order by ug.updated_at desc nulls last
) to stdout with csv
''')
rows = list(csv.reader(rows_csv.splitlines())) if rows_csv else []
repaired = []
missing_after = []

for user_id, gateway_user_id_s, _token_id_s, api_key, gateway_username, quota_s, email in rows:
    raw_key = api_key[3:] if api_key.startswith('sk-') else api_key
    found = psql(gw_db, f"select count(*)::text from tokens where key = {sql_quote(raw_key)} and deleted_at is null")
    if found != '0':
        continue

    gateway_user_id = int(gateway_user_id_s or '0')
    user_exists = '0'
    if gateway_user_id > 0:
        user_exists = psql(gw_db, f"select count(*)::text from users where id = {gateway_user_id} and deleted_at is null")

    if user_exists == '0':
        username = (gateway_username or (email + '-Her'))[:20]
        password = secrets.token_hex(24)
        quota = int(quota_s or '0')
        gateway_user_id = int(psql(gw_db, f'''
insert into users (username, password, display_name, role, status, quota, used_quota, request_count, "group")
values ({sql_quote(username)}, {sql_quote(password)}, {sql_quote(username)}, 1, 1, {quota}, 0, 0, 'default')
returning id
'''))

    new_raw_key = random_key()
    now_ts = psql(gw_db, "select extract(epoch from now())::bigint::text")
    token_id = int(psql(gw_db, f'''
insert into tokens (
  user_id, key, status, name, created_time, accessed_time, expired_time,
  remain_quota, unlimited_quota, model_limits_enabled, model_limits,
  allow_ips, used_quota, "group", cross_group_retry
)
values (
  {gateway_user_id}, {sql_quote(new_raw_key)}, 1, 'her-web-default', {now_ts}, {now_ts}, -1,
  0, true, false, '', '', 0, '', false
)
returning id
'''))
    psql(web_db, f'''
update user_gateway
set gateway_user_id = {gateway_user_id},
    token_id = {token_id},
    api_key = {sql_quote('sk-' + new_raw_key)},
    revoked_at = null,
    updated_at = now()
where user_id = {sql_quote(user_id)}
''')
    repaired.append({'userId': user_id, 'gatewayUserId': gateway_user_id, 'tokenId': token_id})

psql(gw_db, "select setval('tokens_id_seq', (select coalesce(max(id), 1) from tokens), true)")
psql(gw_db, "select setval('users_id_seq', (select coalesce(max(id), 1) from users), true)")
psql(gw_db, "select setval('logs_id_seq', (select coalesce(max(id), 1) from logs), true)")

for user_id, _gateway_user_id_s, _token_id_s, api_key, *_rest in rows:
    raw_key = api_key[3:] if api_key.startswith('sk-') else api_key
    found = psql(gw_db, f"select count(*)::text from tokens where key = {sql_quote(raw_key)} and deleted_at is null")
    if found == '0':
        missing_after.append(user_id)

print(json.dumps({
    'activeWebBindings': len(rows),
    'repaired': len(repaired),
    'missingAfter': len(missing_after),
    'repairedBindings': repaired,
}, ensure_ascii=False))
if missing_after:
    raise SystemExit(1)
PY
  python3 /tmp/repair-test-gateway-bindings.py
}

sudo docker service create \\
  --name '$GW_SERVICE' \\
  --network '$NETWORK' \\
  --publish published='$GW_PUBLIC_PORT',target=3000,protocol=tcp,mode=ingress \\
  --env-file '$STACK_DIR/gateway-app.env' \\
  "\$GW_IMAGE" >/dev/null

for i in \$(seq 1 90); do
  cid=\$(sudo docker ps --filter name='$GW_SERVICE' --format '{{.ID}}' | head -n 1)
  if [ -n "\$cid" ] && sudo docker exec "\$cid" wget -qO- http://127.0.0.1:3000/api/status >/dev/null 2>&1; then
    if [ "${SKIP_BINDING_REPAIR:-}" != "1" ]; then
      repair_test_web_gateway_bindings
    else
      echo "binding_repair=skipped (deferred to refresh-all final step)"
    fi
    tables=\$(sudo docker exec "\$dbcid" psql -U gateway_test -d gateway_test -Atc "select count(*)::text from information_schema.tables where table_schema='public';")
    channels=\$(sudo docker exec "\$dbcid" psql -U gateway_test -d gateway_test -Atc "select count(*)::text from channels;" 2>/dev/null || echo unknown)
    echo "gateway_ready=$GW_SERVICE image=\$GW_IMAGE tables=\$tables channels=\$channels"
    exit 0
  fi
  sleep 2
done
sudo docker service ps '$GW_SERVICE' --no-trunc
exit 1
REMOTE
}

cmd="${1:-}"
case "$cmd" in
  status)
    status
    ;;
  enable-ip-ports)
    enable_ip_ports
    ;;
  write-routes)
    write_routes
    ;;
  verify-web-gateway)
    verify_test_web_gateway
    ;;
  deploy-web)
    shift
    deploy_web "$@"
    ;;
  deploy-gateway)
    shift
    deploy_gateway "$@"
    ;;
  refresh-web-db)
    refresh_web_db
    ;;
  refresh-gateway-db)
    refresh_gateway_db
    ;;
  refresh-all)
    require_refresh_confirmation
    log "=== refreshing gateway DB ==="
    SKIP_BINDING_REPAIR=1 refresh_gateway_db
    log "=== refreshing web DB ==="
    refresh_web_db
    log "=== repairing bindings (both DBs now fresh) ==="
    # Run binding repair remotely — the function lives inside the gateway HEREDOC,
    # so we invoke it via a fresh SSH that sources the same env files.
    remote "bash -s" <<'REPAIR_REMOTE'
set -euo pipefail
STACK='/home/ubuntu/her-test'
if [ ! -f "$STACK/web-db-active.env" ]; then
  echo "binding_repair=skipped reason=missing_web_db_active_env"
  exit 0
fi
if [ -f /tmp/repair-test-gateway-bindings.py ]; then
  python3 /tmp/repair-test-gateway-bindings.py
else
  echo "binding_repair=skipped reason=repair_script_not_found (run refresh-gateway-db first)"
fi
REPAIR_REMOTE
    log "=== verifying web -> gateway binding ==="
    verify_test_web_gateway
    log "=== auditing env parity ==="
    audit_env_parity
    log "=== refresh-all done ==="
    ;;
  audit-env)
    audit_env_parity
    ;;
  add-test-email)
    shift
    verify_remote_web_service_safe
    email="${1:?Usage: deploy-test.sh add-test-email <email>}"
    email_lower=$(echo "$email" | tr '[:upper:]' '[:lower:]')
    log "=== adding $email_lower to payment test whitelist ==="
    remote "bash -s" <<ADDTEST
set -euo pipefail
CID=\$(sudo docker ps -qf name=her-web-test-db-clone | head -1)
test -n "\$CID"
CURRENT=\$(sudo docker exec "\$CID" psql -U herweb_test_clone -d her_web_test_clone -tAc \
  "SELECT value FROM config WHERE name = 'payment_test_account_emails'" | tr -d '[:space:]')
if echo ",\$CURRENT," | grep -qi ",$email_lower,"; then
  echo "already_in_whitelist email=$email_lower"
else
  if [ -n "\$CURRENT" ]; then
    NEW="\${CURRENT},$email_lower"
  else
    NEW="$email_lower"
  fi
  sudo docker exec "\$CID" psql -U herweb_test_clone -d her_web_test_clone -c \
    "INSERT INTO config (name, value) VALUES ('payment_test_account_emails', '\$NEW')
     ON CONFLICT (name) DO UPDATE SET value = EXCLUDED.value"
  echo "added email=$email_lower total=$(echo "\$NEW" | tr ',' '\n' | wc -l | tr -d ' ') emails"
fi
# Ensure test amounts are set
for key in wechat_test_amount alipay_test_amount; do
  VAL=\$(sudo docker exec "\$CID" psql -U herweb_test_clone -d her_web_test_clone -tAc \
    "SELECT value FROM config WHERE name = '\$key'" | tr -d '[:space:]')
  if [ -z "\$VAL" ]; then
    sudo docker exec "\$CID" psql -U herweb_test_clone -d her_web_test_clone -c \
      "INSERT INTO config (name, value) VALUES ('\$key', '1') ON CONFLICT (name) DO UPDATE SET value = '1'"
    echo "set \$key=1 (¥0.01)"
  fi
done
ADDTEST
    log "=== restarting web to clear config cache ==="
    remote "sudo docker service update --force $WEB_SERVICE" 2>&1 | tail -2
    log "=== done ==="
    ;;
  reset-password)
    shift
    email="${1:?Usage: deploy-test.sh reset-password <email> <password>}"
    password="${2:?Usage: deploy-test.sh reset-password <email> <password>}"
    log "=== resetting password for $email (test clone DB only) ==="
    log "target: her-web-test-db-clone (NOT production)"
    # Generate better-auth compatible hash locally
    HER_WEB_DIR="${HER_WEB_DIR:-/Users/suyuan/Documents/her-source/her-web}"
    HASH_UTIL=$(find "$HER_WEB_DIR/node_modules/.pnpm/@better-auth+utils"*/node_modules/@better-auth/utils/dist/password.mjs 2>/dev/null | head -1)
    if [ -z "$HASH_UTIL" ]; then
      echo "ERROR: better-auth password util not found. Run pnpm install in $HER_WEB_DIR first." >&2
      exit 1
    fi
    HASH=$(node --input-type=module -e "
      import { hashPassword } from '$HASH_UTIL';
      const hash = await hashPassword('$password');
      process.stdout.write(hash);
    ")
    if [ -z "$HASH" ] || [ ${#HASH} -lt 100 ]; then
      echo "ERROR: hash generation failed" >&2
      exit 1
    fi
    remote "bash -s" <<RESETPW
set -euo pipefail
CID=\$(sudo docker ps -qf name=her-web-test-db-clone | head -1)
test -n "\$CID"
RESULT=\$(sudo docker exec "\$CID" psql -U herweb_test_clone -d her_web_test_clone -tAc "
  UPDATE account SET password = '$HASH', updated_at = now()
  WHERE provider_id = 'credential'
    AND user_id = (SELECT id FROM \"user\" WHERE LOWER(email) = LOWER('$email') LIMIT 1)
  RETURNING user_id
")
if [ -n "\$RESULT" ]; then
  echo "password_reset=ok email=$email user_id=\$(echo \$RESULT | tr -d '[:space:]')"
else
  echo "password_reset=FAILED email=$email (user not found or no credential account)"
fi
RESETPW
    log "=== done ==="
    ;;
  web-db)
    shift
    sql="${1:?Usage: deploy-test.sh web-db \"<SQL>\"}"
    remote "sudo docker exec \$(sudo docker ps -qf name=her-web-test-db-clone | head -1) psql -U herweb_test_clone -d her_web_test_clone -c \"$sql\""
    ;;
  gateway-db)
    shift
    sql="${1:?Usage: deploy-test.sh gateway-db \"<SQL>\"}"
    remote "sudo docker exec \$(sudo docker ps -qf name=her-gateway-test-db | head -1) psql -U gateway_test -d gateway_test -c \"$sql\""
    ;;
  prod-web-db)
    shift
    sql="${1:?Usage: deploy-test.sh prod-web-db \"<SQL>\"}"
    remote "PGPASSWORD='HerAgent#2026' psql -h 172.17.255.75 -U her -d her_web -c \"$sql\""
    ;;
  prod-gateway-db)
    shift
    sql="${1:?Usage: deploy-test.sh prod-gateway-db \"<SQL>\"}"
    remote "PGPASSWORD='HerAgent#2026' psql -h 172.17.255.75 -U her -d newapi -c \"$sql\""
    ;;
  set-config)
    shift
    verify_remote_web_service_safe
    key="${1:?Usage: deploy-test.sh set-config <key> <value>}"
    value="${2:?Usage: deploy-test.sh set-config <key> <value>}"
    log "=== setting config $key=$value ==="
    remote "bash -s" <<SETCFG
set -euo pipefail
CID=\$(sudo docker ps -qf name=her-web-test-db-clone | head -1)
test -n "\$CID"
sudo docker exec "\$CID" psql -U herweb_test_clone -d her_web_test_clone -c \
  "INSERT INTO config (name, value) VALUES ('$key', '$value')
   ON CONFLICT (name) DO UPDATE SET value = EXCLUDED.value"
echo "config_set=$key value=$value"
SETCFG
    log "=== restarting web to clear config cache ==="
    remote "sudo docker service update --force $WEB_SERVICE" 2>&1 | tail -2
    log "=== done ==="
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    echo "ERROR: unknown command: $cmd" >&2
    usage >&2
    exit 2
    ;;
esac
