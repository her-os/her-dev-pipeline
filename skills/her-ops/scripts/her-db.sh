#!/usr/bin/env bash
# her-db — thin wrapper for Her production/test DB access
# Zero escaping: SQL piped via stdin to remote psql
#
# Usage: her-db <env> "SQL"              Execute SQL
#        her-db <env> --schema [TABLE]   Table/column structure
#        her-db <env> --connect          Interactive psql
#        her-db <env> --check            Print connection info
# Env:   prod | gw | test | test-gw
set -euo pipefail

SSH="/usr/bin/ssh ubuntu@192.144.187.174"

die() { echo "ERROR: $*" >&2; exit 1; }

[[ $# -lt 1 ]] && die "Usage: her-db <env> [--schema|--connect|--check] [SQL]
Env: prod | gw | test | test-gw"

ENV="$1"; shift

# ── Build remote psql command (no flags yet) ─────────────────────────
_psql_cmd() {
  case "$ENV" in
    prod)    echo "PGPASSWORD='HerAgent#2026' psql -h 172.17.255.75 -U her -d her_web" ;;
    gw)      echo "PGPASSWORD='HerAgent#2026' psql -h 172.17.255.75 -U her -d newapi" ;;
    test)    echo 'CID=$(sudo docker ps -qf name=her-web-test-db-clone) && [ -n "$CID" ] || { echo "Container her-web-test-db-clone not found" >&2; exit 1; }; U=$(sudo docker exec $CID printenv POSTGRES_USER); D=$(sudo docker exec $CID printenv POSTGRES_DB); sudo docker exec -i $CID psql -U $U -d $D' ;;
    test-gw) echo 'CID=$(sudo docker ps -qf name=her-gateway-test-db) && [ -n "$CID" ] || { echo "Container her-gateway-test-db not found" >&2; exit 1; }; U=$(sudo docker exec $CID printenv POSTGRES_USER); D=$(sudo docker exec $CID printenv POSTGRES_DB); sudo docker exec -i $CID psql -U $U -d $D' ;;
    *) die "Unknown env '$ENV'. Use: prod | gw | test | test-gw" ;;
  esac
}

# ── --check: print connection info ───────────────────────────────────
if [[ "${1:-}" == "--check" ]]; then
  echo "env=$ENV"
  case "$ENV" in
    prod)    echo "host=172.17.255.75 user=her db=her_web method=network-psql" ;;
    gw)      echo "host=172.17.255.75 user=her db=newapi method=network-psql" ;;
    test)    echo "container=her-web-test-db-clone method=docker-exec"
             $SSH 'CID=$(sudo docker ps -qf name=her-web-test-db-clone); if [ -n "$CID" ]; then echo "cid=$CID"; echo "user=$(sudo docker exec $CID printenv POSTGRES_USER)"; echo "db=$(sudo docker exec $CID printenv POSTGRES_DB)"; else echo "(container not running)"; fi' ;;
    test-gw) echo "container=her-gateway-test-db method=docker-exec"
             $SSH 'CID=$(sudo docker ps -qf name=her-gateway-test-db); if [ -n "$CID" ]; then echo "cid=$CID"; echo "user=$(sudo docker exec $CID printenv POSTGRES_USER)"; echo "db=$(sudo docker exec $CID printenv POSTGRES_DB)"; else echo "(container not running)"; fi' ;;
  esac
  exit 0
fi

# ── --connect: interactive psql ──────────────────────────────────────
if [[ "${1:-}" == "--connect" ]]; then
  case "$ENV" in
    prod)    exec $SSH -t "PGPASSWORD='HerAgent#2026' psql -h 172.17.255.75 -U her -d her_web" ;;
    gw)      exec $SSH -t "PGPASSWORD='HerAgent#2026' psql -h 172.17.255.75 -U her -d newapi" ;;
    test)    exec $SSH -t 'CID=$(sudo docker ps -qf name=her-web-test-db-clone) && U=$(sudo docker exec $CID printenv POSTGRES_USER) && D=$(sudo docker exec $CID printenv POSTGRES_DB) && sudo docker exec -it $CID psql -U $U -d $D' ;;
    test-gw) exec $SSH -t 'CID=$(sudo docker ps -qf name=her-gateway-test-db) && U=$(sudo docker exec $CID printenv POSTGRES_USER) && D=$(sudo docker exec $CID printenv POSTGRES_DB) && sudo docker exec -it $CID psql -U $U -d $D' ;;
  esac
fi

# ── --schema: table structure ────────────────────────────────────────
if [[ "${1:-}" == "--schema" ]]; then
  TABLE="${2:-}"
  CMD=$(_psql_cmd)
  if [[ -n "$TABLE" ]]; then
    SQL="SELECT column_name, data_type, is_nullable FROM information_schema.columns WHERE table_name='$TABLE' ORDER BY ordinal_position;"
  else
    SQL="SELECT table_name FROM information_schema.tables WHERE table_schema='public' AND table_name NOT LIKE '\\_backup%' AND table_name NOT LIKE 'backup\\_%' ORDER BY table_name;"
  fi
  echo >&2 "[her-db] $ENV --schema ${TABLE:-<all>}"
  echo "$SQL" | $SSH "$CMD -t -A"
  exit $?
fi

# ── Execute SQL ──────────────────────────────────────────────────────
SQL="${1:-}"
CMD=$(_psql_cmd)

if [[ -n "$SQL" ]]; then
  echo >&2 "[her-db] $ENV: executing SQL..."
  echo "$SQL" | $SSH "$CMD -t -A"
elif [[ ! -t 0 ]]; then
  echo >&2 "[her-db] $ENV: reading SQL from stdin..."
  $SSH "$CMD -t -A"
else
  die "No SQL provided. Use: her-db $ENV \"SQL\" or pipe via stdin"
fi
