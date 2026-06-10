#!/usr/bin/env bash
# her-web release orchestrator: release-check → preflight → deploy.
set -euo pipefail

QUIET="${QUIET:-0}"
log() { [[ "$QUIET" == "1" ]] || echo "$@"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${1:-}"
TARGET_REF="${2:-}"
MODE="${MODE:-normal}"
DRY_RUN=0
REPORT_DIR="${REPORT_DIR:-/tmp/her-web-release}"
SERVER="${SERVER:-ubuntu@192.144.187.174}"
SERVICE="${SERVICE:-her-herweb-a8y5ka}"
SSH_BIN="${SSH_BIN:-/usr/bin/ssh}"
MIGRATION_REPORT=""

usage() {
  cat <<'EOF'
Usage:
  release.sh <repo> <target-ref> [--dry-run] [--mode normal|emergency] [--migration-report <path>]

This is the only normal production release entry for her-web.
EOF
}

if [[ -z "$REPO" || -z "$TARGET_REF" ]]; then
  usage >&2
  exit 2
fi
shift 2

EXTRA_CHECK_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --mode)
      MODE="${2:-normal}"
      EXTRA_CHECK_ARGS+=(--mode "$MODE")
      shift 2
      ;;
    --required-commit|--fix-intent)
      EXTRA_CHECK_ARGS+=("$1" "${2:-}")
      shift 2
      ;;
    --migration-report)
      MIGRATION_REPORT="${2:-}"
      EXTRA_CHECK_ARGS+=("$1" "${2:-}")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

REPO="$(cd "$REPO" && pwd)"
if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: not a git repo: $REPO" >&2
  exit 1
fi

if [[ -n "$MIGRATION_REPORT" ]]; then
  MIGRATION_REPORT="$(cd "$(dirname "$MIGRATION_REPORT")" && pwd)/$(basename "$MIGRATION_REPORT")"
  if [[ ! -f "$MIGRATION_REPORT" ]]; then
    echo "ERROR: migration report 不存在：$MIGRATION_REPORT" >&2
    exit 1
  fi
fi

LOCAL_LOCK="/tmp/her-web-release.lock"
LOCK_HELD=0
SERVER_LOCK_DIR="/home/ubuntu/her-web-release/release.lock.d"
SERVER_LOCK_HELD=0
WORKTREE=""

cleanup() {
  if [[ -n "$WORKTREE" && -d "$WORKTREE" ]]; then
    git -C "$REPO" worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true
  fi
  if [[ "$SERVER_LOCK_HELD" == "1" ]]; then
    "$SSH_BIN" -n "$SERVER" "rm -rf '$SERVER_LOCK_DIR'" >/dev/null 2>&1 || true
  fi
  if [[ "$LOCK_HELD" == "1" ]]; then
    rm -rf "$LOCAL_LOCK" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if ! mkdir "$LOCAL_LOCK" 2>/dev/null; then
  echo "ERROR: 本地 release lock 已存在：$LOCAL_LOCK" >&2
  echo "如果确认没有 release 在运行，请人工检查后删除。" >&2
  exit 1
fi
LOCK_HELD=1

TARGET_SHA="$(git -C "$REPO" rev-parse --verify "${TARGET_REF}^{commit}")"

# Tag 校验：生产 release 必须基于 git tag
if [[ "${ALLOW_NON_TAG_DEPLOY:-0}" != "1" ]]; then
  if ! git -C "$REPO" tag -l "$TARGET_REF" | grep -q '^'; then
    echo "ERROR: TARGET_REF '$TARGET_REF' 不是 git tag。" >&2
    echo "生产 release 必须基于 tag（如 v0.1.3）。" >&2
    echo "如需紧急跳过：ALLOW_NON_TAG_DEPLOY=1" >&2
    exit 1
  fi
  if [[ ! "$TARGET_REF" =~ ^v[0-9]+\. ]]; then
    echo "ERROR: tag '$TARGET_REF' 不符合版本命名规范（应为 v0.x.y）。" >&2
    exit 1
  fi
fi

REMOTE_MAIN_SHA="$(git -C "$REPO" ls-remote origin refs/heads/main | awk '{print $1}')"
git -C "$REPO" fetch --quiet origin "$REMOTE_MAIN_SHA" || git -C "$REPO" fetch --quiet origin main

REPO_HASH="$(printf '%s' "$REPO" | shasum -a 256 | awk '{print substr($1,1,12)}')"
REPORT_PATH="$REPORT_DIR/$REPO_HASH/$TARGET_SHA/report.json"
WORKTREE="$REPORT_DIR/worktrees/$TARGET_SHA"
mkdir -p "$(dirname "$REPORT_PATH")" "$(dirname "$WORKTREE")"

git -C "$REPO" worktree add --force --detach "$WORKTREE" "$TARGET_SHA" >/dev/null

if [[ ! -d "$WORKTREE/node_modules" && -d "$REPO/node_modules" ]]; then
  ln -s "$REPO/node_modules" "$WORKTREE/node_modules"
fi

log "=== her-web release ==="
log "repo: $REPO"
log "worktree: $WORKTREE"
log "target: $TARGET_SHA"
log "remote_origin_main: $REMOTE_MAIN_SHA"
log "mode: $MODE"
log "dry_run: $DRY_RUN"
log "migration_report: ${MIGRATION_REPORT:-<none>}"
log ""

# If ACCEPT_RELEASE_REPORT is provided and a cached report exists with a
# matching reportId, reuse the cached report instead of regenerating.
# This prevents token drift caused by production state changes (e.g. Docker
# task ID rotation) between step 1 (generate) and step 2 (confirm).
ACCEPT_REPORT_ID="${ACCEPT_RELEASE_REPORT:-}"
ACCEPT_REPORT_ID="${ACCEPT_REPORT_ID%%:*}"
if [[ -n "${ACCEPT_RELEASE_REPORT:-}" && -f "$REPORT_PATH" ]]; then
  CACHED_REPORT_ID="$(jq -r '.reportId // empty' "$REPORT_PATH" 2>/dev/null || true)"
  if [[ -n "$CACHED_REPORT_ID" && "$CACHED_REPORT_ID" == "$ACCEPT_REPORT_ID" ]]; then
    echo "[release] reusing cached report (reportId=${CACHED_REPORT_ID})"
  else
    "$SCRIPT_DIR/release-check.sh" "$WORKTREE" "$TARGET_SHA" --json-out "$REPORT_PATH" "${EXTRA_CHECK_ARGS[@]}"
  fi
else
  "$SCRIPT_DIR/release-check.sh" "$WORKTREE" "$TARGET_SHA" --json-out "$REPORT_PATH" "${EXTRA_CHECK_ARGS[@]}"
fi

DECISION="$(jq -r '.decision' "$REPORT_PATH")"
REPORT_ID="$(jq -r '.reportId' "$REPORT_PATH")"
REPORT_HASH="$(jq -r '.reportHash' "$REPORT_PATH")"
EXPECTED_ACCEPT="${REPORT_ID}:${REPORT_HASH}"

if [[ "$DECISION" == "BLOCKED" ]]; then
  echo "ERROR: release report BLOCKED，不会部署。" >&2
  exit 1
fi

if [[ "$DECISION" == "WARN" && "${ACCEPT_RELEASE_REPORT:-}" != "$EXPECTED_ACCEPT" ]]; then
  echo "ERROR: release report 需要明确确认。" >&2
  echo "继续需要：ACCEPT_RELEASE_REPORT=$EXPECTED_ACCEPT" >&2
  echo "" >&2
  echo "⚠️  重要：必须用同一个 NOW_EPOCH 重跑，否则 token 会变：" >&2
  echo "  NOW_EPOCH=${NOW_EPOCH:-} ACCEPT_RELEASE_REPORT=\"$EXPECTED_ACCEPT\" CONFIRM_SMOKE=\"${REQUIRED_SMOKE_IDS:-}\" \\" >&2
  echo "    bash scripts/her-web/release.sh $REPO ${TARGET_REF}" >&2
  exit 1
fi

REQUIRED_SMOKE_IDS="$(jq -r '.requiredSmoke[].id' "$REPORT_PATH" | paste -sd, -)"
if [[ -n "$REQUIRED_SMOKE_IDS" ]]; then
  IFS=',' read -r -a required <<< "$REQUIRED_SMOKE_IDS"
  for smoke_id in "${required[@]}"; do
    if [[ ",${CONFIRM_SMOKE:-}," != *",$smoke_id,"* ]]; then
      echo "ERROR: high-risk smoke 未确认：$smoke_id" >&2
      echo "继续需要：CONFIRM_SMOKE=$REQUIRED_SMOKE_IDS" >&2
      exit 1
    fi
  done
fi

log "=== release preflight ==="
PRODUCTION_COMMIT="$(jq -r '.checkedProductionState.productionCommit // empty' "$REPORT_PATH")"
PREFLIGHT_ARGS=("$WORKTREE")
if [[ -n "$MIGRATION_REPORT" ]]; then
  PREFLIGHT_ARGS+=(--migration-report "$MIGRATION_REPORT")
fi
SCHEMA_BASE_REF="$PRODUCTION_COMMIT" \
EXPECTED_TARGET_SHA="$TARGET_SHA" \
REMOTE_ORIGIN_MAIN_SHA="$REMOTE_MAIN_SHA" \
ALLOW_NON_MAIN_DEPLOY="${ALLOW_NON_MAIN_DEPLOY:-0}" \
  bash "$SCRIPT_DIR/deploy-preflight.sh" "${PREFLIGHT_ARGS[@]}"

if [[ "$DRY_RUN" == "1" ]]; then
  echo ""
  echo "=== DRY RUN COMPLETE ==="
  echo "没有部署，没有写服务器 metadata，没有改数据库。"
  echo "report: $REPORT_PATH"
  exit 0
fi

if ! "$SSH_BIN" -n "$SERVER" "mkdir -p /home/ubuntu/her-web-release && mkdir '$SERVER_LOCK_DIR'"; then
  echo "ERROR: 服务器 release lock 已存在或无法创建：$SERVER_LOCK_DIR" >&2
  exit 1
fi
SERVER_LOCK_HELD=1
"$SSH_BIN" -n "$SERVER" "cat > '$SERVER_LOCK_DIR/info.json'" <<EOF
{"targetSha":"$TARGET_SHA","reportId":"$REPORT_ID","startedAt":"$(date -u '+%Y-%m-%dT%H:%M:%SZ')","repoRoot":"$REPO"}
EOF

log "=== release deploy ==="
HER_WEB_RELEASE_INTERNAL=1 \
EXPECTED_TARGET_SHA="$TARGET_SHA" \
EXPECTED_REPORT_HASH="$REPORT_HASH" \
RELEASE_REPORT_PATH="$REPORT_PATH" \
REMOTE_ORIGIN_MAIN_SHA="$REMOTE_MAIN_SHA" \
MIGRATION_REPORT="$MIGRATION_REPORT" \
ALLOW_NON_MAIN_DEPLOY="${ALLOW_NON_MAIN_DEPLOY:-0}" \
  bash "$SCRIPT_DIR/deploy.sh" "$WORKTREE"

log ""
log "=== RELEASE COMPLETE ==="
log "target: $TARGET_SHA"
log "report: $REPORT_PATH"

# --- Post-release: resync dev to main (best-effort, D2) ---
if [[ "$DRY_RUN" != "1" ]]; then
  echo ""
  echo "=== POST-RELEASE: resync dev ==="
  RESYNC_SCRIPT="$(dirname "$SCRIPT_DIR")/resync-dev.sh"
  if [[ -x "$RESYNC_SCRIPT" ]]; then
    bash "$RESYNC_SCRIPT" "$REPO" || echo "⚠️  dev resync failed (non-fatal). Run manually: bash $RESYNC_SCRIPT $REPO"
  else
    echo "⚠️  resync-dev.sh not found at $RESYNC_SCRIPT, skipping dev reset."
  fi
fi
