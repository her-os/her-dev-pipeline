#!/usr/bin/env bash
# create-dev-env.sh — 创建隔离的本地开发环境
# 用法: create-dev-env.sh --repo her-web --session feat-auth
#       create-dev-env.sh --repo her-gateway --session feat-payment
set -euo pipefail

REGISTRY_DIR="$HOME/.config/her"
REGISTRY="$REGISTRY_DIR/dev-envs.json"
LOCK="$REGISTRY_DIR/dev-envs.lock"
SOURCE_BASE="$HOME/Documents/her-source"
WORKTREE_BASE="$SOURCE_BASE/worktrees"

# 端口分配范围
WEB_PORT_START=3001
WEB_PORT_END=3099
DB_PORT_START=5433
DB_PORT_END=5499
GW_PORT_START=3301
GW_PORT_END=3399

REPO=""
SESSION=""

usage() {
  cat <<'EOF'
Usage: create-dev-env.sh --repo <her-web|her-gateway> --session <name>

创建隔离的本地开发环境：
  1. 创建 git worktree
  2. 启动 Docker DB 容器（her-web）或 compose 实例（her-gateway）
  3. 生成 .env.local
  4. 注册到端口注册表

端口范围：
  her-web:     web_port 3001~3099, db_port 5433~5499
  her-gateway: api_port 3301~3399
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --session) SESSION="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$REPO" || -z "$SESSION" ]]; then
  echo "ERROR: --repo 和 --session 必须指定" >&2
  usage >&2
  exit 2
fi

if [[ "$REPO" != "her-web" && "$REPO" != "her-gateway" ]]; then
  echo "ERROR: --repo 只支持 her-web 或 her-gateway" >&2
  exit 2
fi

# 确保注册表目录和文件存在
mkdir -p "$REGISTRY_DIR"
if [[ ! -f "$REGISTRY" ]]; then
  echo '{"sessions":{}}' > "$REGISTRY"
fi

WORKTREE_PATH="$WORKTREE_BASE/${REPO}-${SESSION}"
REPO_DIR="$SOURCE_BASE/$REPO"

if [[ ! -d "$REPO_DIR/.git" ]]; then
  echo "ERROR: 仓库不存在: $REPO_DIR" >&2
  exit 1
fi

if [[ -d "$WORKTREE_PATH" ]]; then
  echo "ERROR: worktree 已存在: $WORKTREE_PATH" >&2
  echo "如需重建，先运行 destroy-dev-env.sh --repo $REPO --session $SESSION" >&2
  exit 1
fi

# ===== 加锁分配端口 =====
allocate_port() {
  local start=$1 end=$2 used_ports=$3
  for ((port=start; port<=end; port++)); do
    if ! echo "$used_ports" | grep -qw "$port"; then
      echo "$port"
      return 0
    fi
  done
  echo "ERROR: 端口范围 ${start}~${end} 已用完" >&2
  return 1
}

# 用 flock 锁注册表进行端口分配
exec 200>"$LOCK"
flock 200

USED_PORTS="$(python3 -c "
import json, sys
with open('$REGISTRY') as f:
    data = json.load(f)
ports = []
for sess in data.get('sessions', {}).values():
    for repo_info in sess.values():
        for k, v in repo_info.items():
            if k.endswith('_port') and isinstance(v, int):
                ports.append(str(v))
print(' '.join(ports))
")"

if [[ "$REPO" == "her-web" ]]; then
  WEB_PORT=$(allocate_port $WEB_PORT_START $WEB_PORT_END "$USED_PORTS")
  DB_PORT=$(allocate_port $DB_PORT_START $DB_PORT_END "$USED_PORTS")
  # 写注册表
  python3 -c "
import json
with open('$REGISTRY') as f:
    data = json.load(f)
data.setdefault('sessions', {}).setdefault('$SESSION', {})['$REPO'] = {
    'worktree': '$WORKTREE_PATH',
    'web_port': $WEB_PORT,
    'db_port': $DB_PORT
}
with open('$REGISTRY', 'w') as f:
    json.dump(data, f, indent=2)
"
elif [[ "$REPO" == "her-gateway" ]]; then
  GW_PORT=$(allocate_port $GW_PORT_START $GW_PORT_END "$USED_PORTS")
  python3 -c "
import json
with open('$REGISTRY') as f:
    data = json.load(f)
data.setdefault('sessions', {}).setdefault('$SESSION', {})['$REPO'] = {
    'worktree': '$WORKTREE_PATH',
    'api_port': $GW_PORT,
    'compose_project': 'gw-$SESSION'
}
with open('$REGISTRY', 'w') as f:
    json.dump(data, f, indent=2)
"
fi

# 释放锁
exec 200>&-

echo "=== 创建开发环境: $REPO / $SESSION ==="

# ===== 创建 worktree =====
mkdir -p "$WORKTREE_BASE"
git -C "$REPO_DIR" fetch --quiet origin main
git -C "$REPO_DIR" worktree add "$WORKTREE_PATH" -b "feat/$SESSION" origin/main
echo "[OK] worktree: $WORKTREE_PATH"

# ===== 启动服务 =====
if [[ "$REPO" == "her-web" ]]; then
  CONTAINER_NAME="her-web-dev-${SESSION}-db"
  docker run -d \
    --name "$CONTAINER_NAME" \
    -p "${DB_PORT}:5432" \
    -e POSTGRES_USER=her \
    -e POSTGRES_PASSWORD=her_dev \
    -e POSTGRES_DB=her_web \
    postgres:18-alpine \
    >/dev/null
  echo "[OK] DB 容器: $CONTAINER_NAME (port $DB_PORT)"

  # 生成 .env.local
  ENV_LOCAL="$WORKTREE_PATH/.env.local"
  cat > "$ENV_LOCAL" <<ENVEOF
DATABASE_URL=postgresql://her:her_dev@localhost:${DB_PORT}/her_web
PORT=${WEB_PORT}
ENVEOF

  # 如果同 session 有 gateway，自动填入 API_GATEWAY_BASE_URL
  GW_PORT_IN_SESSION="$(python3 -c "
import json
with open('$REGISTRY') as f:
    data = json.load(f)
gw = data.get('sessions', {}).get('$SESSION', {}).get('her-gateway', {})
print(gw.get('api_port', ''))
" 2>/dev/null || true)"
  if [[ -n "$GW_PORT_IN_SESSION" ]]; then
    echo "API_GATEWAY_BASE_URL=http://localhost:${GW_PORT_IN_SESSION}" >> "$ENV_LOCAL"
    echo "[OK] 自动关联 gateway port $GW_PORT_IN_SESSION"
  fi

  echo "[OK] .env.local: $ENV_LOCAL"
  echo ""
  echo "=== 环境就绪 ==="
  echo "  cd $WORKTREE_PATH"
  echo "  pnpm dev  # 监听 port $WEB_PORT"

elif [[ "$REPO" == "her-gateway" ]]; then
  cd "$WORKTREE_PATH"
  HER_GATEWAY_HOST_PORT=$GW_PORT docker compose -p "gw-${SESSION}" up -d 2>/dev/null || {
    echo "[WARN] docker compose 启动失败，可能需要手动配置" >&2
  }
  echo "[OK] gateway compose: gw-${SESSION} (port $GW_PORT)"

  # 如果同 session 有 her-web，更新其 .env.local
  WEB_WORKTREE="$(python3 -c "
import json
with open('$REGISTRY') as f:
    data = json.load(f)
web = data.get('sessions', {}).get('$SESSION', {}).get('her-web', {})
print(web.get('worktree', ''))
" 2>/dev/null || true)"
  if [[ -n "$WEB_WORKTREE" && -f "$WEB_WORKTREE/.env.local" ]]; then
    if ! grep -q "API_GATEWAY_BASE_URL" "$WEB_WORKTREE/.env.local"; then
      echo "API_GATEWAY_BASE_URL=http://localhost:${GW_PORT}" >> "$WEB_WORKTREE/.env.local"
    else
      sed -i '' "s|API_GATEWAY_BASE_URL=.*|API_GATEWAY_BASE_URL=http://localhost:${GW_PORT}|" "$WEB_WORKTREE/.env.local"
    fi
    echo "[OK] 已更新 her-web .env.local 的 API_GATEWAY_BASE_URL"
  fi

  echo ""
  echo "=== 环境就绪 ==="
  echo "  cd $WORKTREE_PATH"
  echo "  gateway 监听 port $GW_PORT"
fi
