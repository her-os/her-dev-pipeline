#!/usr/bin/env bash
# destroy-dev-env.sh — 销毁隔离的本地开发环境
# 用法: destroy-dev-env.sh --repo her-web --session feat-auth
#       destroy-dev-env.sh --session feat-auth  (销毁 session 下所有 repo)
set -euo pipefail

REGISTRY_DIR="$HOME/.config/her"
REGISTRY="$REGISTRY_DIR/dev-envs.json"
LOCK="$REGISTRY_DIR/dev-envs.lock"
SOURCE_BASE="$HOME/Documents/her-source"

REPO=""
SESSION=""

usage() {
  cat <<'EOF'
Usage: destroy-dev-env.sh --session <name> [--repo <her-web|her-gateway>]

销毁开发环境：
  1. 停止并删除 Docker 容器
  2. 删除 git worktree
  3. 从注册表移除条目

不指定 --repo 时，销毁 session 下所有 repo 的环境。
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

if [[ -z "$SESSION" ]]; then
  echo "ERROR: --session 必须指定" >&2
  usage >&2
  exit 2
fi

if [[ ! -f "$REGISTRY" ]]; then
  echo "ERROR: 注册表不存在: $REGISTRY" >&2
  exit 1
fi

destroy_repo() {
  local repo=$1
  local session=$2

  # 读注册表获取信息
  local info
  info="$(python3 -c "
import json, sys
with open('$REGISTRY') as f:
    data = json.load(f)
repo_info = data.get('sessions', {}).get('$session', {}).get('$repo', {})
if not repo_info:
    sys.exit(1)
import json as j
print(j.dumps(repo_info))
" 2>/dev/null)" || {
    echo "[SKIP] $repo 在 session $session 中没有注册记录"
    return 0
  }

  local worktree
  worktree="$(echo "$info" | python3 -c "import json,sys; print(json.load(sys.stdin).get('worktree',''))")"

  echo "=== 销毁: $repo / $session ==="

  if [[ "$repo" == "her-web" ]]; then
    # 停止 DB 容器
    local container="her-web-dev-${session}-db"
    if docker ps -a --format '{{.Names}}' | grep -qw "$container"; then
      docker stop "$container" >/dev/null 2>&1 || true
      docker rm "$container" >/dev/null 2>&1 || true
      echo "[OK] 已删除容器: $container"
    fi
  elif [[ "$repo" == "her-gateway" ]]; then
    # 停止 compose 实例
    local project="gw-${session}"
    if [[ -n "$worktree" && -d "$worktree" ]]; then
      (cd "$worktree" && docker compose -p "$project" down 2>/dev/null || true)
      echo "[OK] 已停止 compose: $project"
    fi
  fi

  # 删除 worktree
  if [[ -n "$worktree" && -d "$worktree" ]]; then
    local repo_dir="$SOURCE_BASE/$repo"
    git -C "$repo_dir" worktree remove --force "$worktree" 2>/dev/null || {
      echo "[WARN] git worktree remove 失败，尝试直接删除目录"
      rm -rf "$worktree"
    }
    echo "[OK] 已删除 worktree: $worktree"
  fi

  # 加锁更新注册表
  exec 200>"$LOCK"
  flock 200
  python3 -c "
import json
with open('$REGISTRY') as f:
    data = json.load(f)
sessions = data.get('sessions', {})
if '$session' in sessions and '$repo' in sessions['$session']:
    del sessions['$session']['$repo']
    if not sessions['$session']:
        del sessions['$session']
with open('$REGISTRY', 'w') as f:
    json.dump(data, f, indent=2)
"
  exec 200>&-
  echo "[OK] 已从注册表移除"
}

if [[ -n "$REPO" ]]; then
  destroy_repo "$REPO" "$SESSION"
else
  # 销毁 session 下所有 repo
  REPOS="$(python3 -c "
import json
with open('$REGISTRY') as f:
    data = json.load(f)
repos = list(data.get('sessions', {}).get('$SESSION', {}).keys())
print(' '.join(repos))
" 2>/dev/null || true)"

  if [[ -z "$REPOS" ]]; then
    echo "session '$SESSION' 在注册表中没有记录"
    exit 0
  fi

  for r in $REPOS; do
    destroy_repo "$r" "$SESSION"
  done
fi

echo ""
echo "=== 清理完成 ==="
