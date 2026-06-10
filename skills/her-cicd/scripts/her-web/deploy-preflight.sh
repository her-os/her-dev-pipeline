#!/bin/bash
# her-web 部署 preflight 检查（本地执行）
set -euo pipefail

SRC="${1:-${SRC_REPO:-$(git rev-parse --show-toplevel 2>/dev/null || echo $PWD)}}"
if [[ $# -gt 0 ]]; then
  shift
fi
SRC="$(cd "$SRC" && pwd)"

FAIL=0
WARN=0

SCHEMA_BASE_REF="${SCHEMA_BASE_REF:-}"
MIGRATION_REPORT="${MIGRATION_REPORT:-}"
ALLOW_NON_MAIN_DEPLOY="${ALLOW_NON_MAIN_DEPLOY:-0}"
EXPECTED_APP_URL="${EXPECTED_APP_URL:-https://hersoul.cn}"
SCHEMA_PATHS=(
  "src/config/db/schema.ts"
  "src/config/db/schema.postgres.ts"
  "src/config/db/schema.sqlite.ts"
  "drizzle"
  "drizzle.config.ts"
)
MYSQL_SCHEMA_PATH="src/config/db/schema.mysql.ts"
EXPECTED_TARGET_SHA="${EXPECTED_TARGET_SHA:-}"
REMOTE_ORIGIN_MAIN_SHA="${REMOTE_ORIGIN_MAIN_SHA:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

source "$SCRIPT_DIR/migration-report-lib.sh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --migration-report)
      MIGRATION_REPORT="${2:-}"
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

pass() { echo "  [OK] $1"; }
warn_msg() { echo "  [WARN] $1"; WARN=1; }
fail() { echo "  [FAIL] $1" >&2; FAIL=1; }

git_ref_exists() {
  git -C "$SRC" rev-parse --verify "$1" >/dev/null 2>&1
}

collect_schema_diff() {
  local base_ref="$1"
  if ! git_ref_exists "$base_ref"; then
    return 0
  fi
  git -C "$SRC" diff --name-only "$base_ref..HEAD" -- "${SCHEMA_PATHS[@]}" || true
}

default_schema_base_ref() {
  if git_ref_exists "origin/main"; then
    git -C "$SRC" merge-base HEAD origin/main
    return 0
  fi
  if git_ref_exists "main"; then
    git -C "$SRC" merge-base HEAD main
    return 0
  fi
  if git_ref_exists "HEAD~1"; then
    echo "HEAD~1"
    return 0
  fi
  return 1
}

echo "=== her-web deploy preflight ==="
echo "    SRC=$SRC"
echo ""

if git -C "$SRC" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  BRANCH="$(git -C "$SRC" rev-parse --abbrev-ref HEAD)"
  COMMIT="$(git -C "$SRC" rev-parse --short HEAD)"
else
  BRANCH="unknown"
  COMMIT="unknown"
fi

echo "    BRANCH=$BRANCH"
echo "    COMMIT=$COMMIT"
echo ""

echo "[0/7] 分支闸门"
if [ -n "$EXPECTED_TARGET_SHA" ]; then
  ACTUAL_SHA="$(git -C "$SRC" rev-parse HEAD)"
  if [ "$ACTUAL_SHA" != "$EXPECTED_TARGET_SHA" ]; then
    fail "当前 HEAD 不等于 EXPECTED_TARGET_SHA。HEAD=$ACTUAL_SHA EXPECTED_TARGET_SHA=$EXPECTED_TARGET_SHA"
  else
    pass "HEAD 等于 EXPECTED_TARGET_SHA"
  fi

  if [ -n "$REMOTE_ORIGIN_MAIN_SHA" ] && [ "$EXPECTED_TARGET_SHA" != "$REMOTE_ORIGIN_MAIN_SHA" ] && [ "$ALLOW_NON_MAIN_DEPLOY" != "1" ]; then
    fail "目标 commit 不是实时远端 origin/main。紧急止血才允许 ALLOW_NON_MAIN_DEPLOY=1。"
  elif [ -n "$REMOTE_ORIGIN_MAIN_SHA" ] && [ "$EXPECTED_TARGET_SHA" != "$REMOTE_ORIGIN_MAIN_SHA" ]; then
    warn_msg "目标 commit 不是实时远端 origin/main，已启用 ALLOW_NON_MAIN_DEPLOY=1。仅限紧急止血，部署后必须补 PR 到 main。"
  else
    pass "目标 commit 等于实时远端 origin/main"
  fi
elif [ "$BRANCH" != "main" ] && [ "$ALLOW_NON_MAIN_DEPLOY" != "1" ]; then
  fail "当前分支是 ${BRANCH}。直接 preflight 正常只允许 main；release 流程应传 EXPECTED_TARGET_SHA。"
elif [ "$BRANCH" != "main" ]; then
  warn_msg "当前分支是 ${BRANCH}，已启用 ALLOW_NON_MAIN_DEPLOY=1。仅限紧急止血，部署后必须补 PR 到 main。"
else
  pass "当前分支是 main"
fi

echo "[1/7] schema.postgres.ts 存在"
if [ -f "$SRC/src/config/db/schema.postgres.ts" ]; then
  pass "schema.postgres.ts 存在"
else
  fail "schema.postgres.ts 不存在，Dockerfile 需要它"
fi

echo "[2/7] schema 模板表名一致"
if [ -f "$SRC/src/config/db/schema.sqlite.ts" ] && [ -f "$SRC/src/config/db/schema.postgres.ts" ]; then
  PG_TABLES="$(grep '^export const' "$SRC/src/config/db/schema.postgres.ts" | awk '{print $3}' | sort)"
  SL_TABLES="$(grep '^export const' "$SRC/src/config/db/schema.sqlite.ts" | awk '{print $3}' | sort)"
  DIFF="$(diff <(echo "$PG_TABLES") <(echo "$SL_TABLES") || true)"
  if [ -z "$DIFF" ]; then
    pass "postgres/sqlite 模板表名一致（$(echo "$PG_TABLES" | wc -l | tr -d ' ') 张表）"
  else
    fail "postgres/sqlite 模板表名不一致：$DIFF"
  fi
else
  fail "缺少 schema 模板文件，无法确认 postgres/sqlite 一致性"
fi

echo "[3/7] schema / migration 变更"
if [ -z "$SCHEMA_BASE_REF" ]; then
  SCHEMA_BASE_REF="$(default_schema_base_ref || true)"
fi
SCHEMA_DIFF="$(collect_schema_diff "$SCHEMA_BASE_REF")"
MYSQL_SCHEMA_DIFF=""
if git_ref_exists "$SCHEMA_BASE_REF"; then
  MYSQL_SCHEMA_DIFF="$(git -C "$SRC" diff --name-only "$SCHEMA_BASE_REF..HEAD" -- "$MYSQL_SCHEMA_PATH" || true)"
fi
if [ -z "$SCHEMA_BASE_REF" ]; then
  warn_msg "无法自动推断 schema diff 基线，跳过 schema / migration 对比。需要时显式设置 SCHEMA_BASE_REF。"
elif [ -n "$SCHEMA_DIFF" ]; then
  if [[ -n "$MIGRATION_REPORT" ]] && migration_report_validate "$MIGRATION_REPORT" "${EXPECTED_TARGET_SHA:-}" "$SCHEMA_DIFF"; then
    warn_msg "检测到 schema / migration 相关变更，但 migration report 已通过校验：$MIGRATION_REPORT"
  elif [[ -n "$MIGRATION_REPORT" ]]; then
    fail "检测到 schema / migration 相关变更，且 migration report 无效：$MIGRATION_REPORT"
  else
    fail "检测到 schema 或 migration 相关文件变更：$(echo "$SCHEMA_DIFF" | tr '\n' ' ')。先准备生产迁移方案，再部署。"
  fi
elif [ -n "$MYSQL_SCHEMA_DIFF" ]; then
  warn_msg "检测到 schema.mysql.ts 单独变更；当前生产是 Postgres，先记 WARN：$(echo "$MYSQL_SCHEMA_DIFF" | tr '\n' ' ')"
else
  pass "未检测到相对 $SCHEMA_BASE_REF 的 schema / migration 变更"
fi

echo "[4/7] 未跟踪源码文件"
UNTRACKED_SOURCE="$(git -C "$SRC" ls-files --others --exclude-standard -- 'src/**' 'app/**' 'components/**' 'lib/**' 'config/**' 'scripts/**' 'public/**' || true)"
if [ -n "$UNTRACKED_SOURCE" ]; then
  warn_msg "发现未跟踪源码文件。git archive HEAD 不会把它们带上去：$(echo "$UNTRACKED_SOURCE" | tr '\n' ' ')"
else
  pass "没有未跟踪源码文件"
fi

echo "[5/7] 无 NEXT_PUBLIC localhost 硬编码"
LOCALHOST_HITS="$(grep -rn 'NEXT_PUBLIC.*localhost' "$SRC/.env.production" 2>/dev/null || true)"
if [ -n "$LOCALHOST_HITS" ]; then
  fail ".env.production 含 localhost：$LOCALHOST_HITS"
else
  pass "无 localhost 硬编码（.env.production 不存在或已正确配置）"
fi

echo "[6/7] TypeScript 类型检查"
if command -v npx >/dev/null 2>&1 && [ -f "$SRC/tsconfig.json" ]; then
  if [ ! -d "$SRC/node_modules" ]; then
    fail "node_modules 缺失。当前 worktree/目录需要先安装依赖，再做 TypeScript 检查。"
  elif (cd "$SRC" && : > /tmp/her-web-preflight-tsc.log && npx tsc --noEmit >/tmp/her-web-preflight-tsc.log 2>&1); then
    pass "TypeScript 编译通过"
  else
    tail -20 /tmp/her-web-preflight-tsc.log >&2 || true
    fail "TypeScript 编译失败（npx tsc --noEmit）"
  fi
  rm -f /tmp/her-web-preflight-tsc.log
else
  fail "缺少 npx 或 tsconfig.json，无法做 TypeScript 检查"
fi

echo "[7/7] Dockerfile 存在"
if [ -f "$SRC/Dockerfile" ]; then
  pass "Dockerfile 存在"
else
  fail "Dockerfile 不存在"
fi

echo ""
if [ "$FAIL" -eq 0 ] && [ "$WARN" -eq 0 ]; then
  echo "=== PREFLIGHT PASSED ==="
elif [ "$FAIL" -eq 0 ]; then
  echo "=== PREFLIGHT PASSED (with warnings) ==="
else
  echo "=== PREFLIGHT FAILED — 修复上述问题后重试 ===" >&2
  exit 1
fi
