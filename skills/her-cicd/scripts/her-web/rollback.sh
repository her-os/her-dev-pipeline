#!/usr/bin/env bash
# her-web minimal rollback helper.
set -euo pipefail

REPO="${1:-}"
TARGET="${2:-previous}"
SERVER="${SERVER:-ubuntu@192.144.187.174}"
SERVICE="${SERVICE:-her-herweb-a8y5ka}"
SSH_BIN="${SSH_BIN:-/usr/bin/ssh}"
DRY_RUN=0
REPORT_PATH=""

usage() {
  cat <<'EOF'
Usage:
  rollback.sh <repo> previous [--dry-run]
  rollback.sh <repo> --report <path> [--dry-run]

Requires CONFIRM_ROLLBACK=1 for real service update.
EOF
}

if [[ -z "$REPO" ]]; then
  usage >&2
  exit 2
fi
shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    previous)
      TARGET="previous"
      shift
      ;;
    --report)
      REPORT_PATH="${2:-}"
      TARGET="report"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
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

IMAGE=""
COMMIT=""
SOURCE=""

if [[ "$TARGET" == "report" ]]; then
  if [[ -z "$REPORT_PATH" || ! -f "$REPORT_PATH" ]]; then
    echo "ERROR: --report path not found: $REPORT_PATH" >&2
    exit 1
  fi
  IMAGE="$(jq -r '.rollbackTarget.image // empty' "$REPORT_PATH")"
  COMMIT="$(jq -r '.rollbackTarget.commit // empty' "$REPORT_PATH")"
  SOURCE="report:$REPORT_PATH"
else
  PREVIOUS_JSON="$("$SSH_BIN" -n "$SERVER" "cat /home/ubuntu/her-web-release/previous.json" 2>/dev/null || true)"
  if [[ -z "$PREVIOUS_JSON" ]] || ! echo "$PREVIOUS_JSON" | jq empty >/dev/null 2>&1; then
    echo "ERROR: server previous.json missing or invalid" >&2
    exit 1
  fi
  IMAGE="$(echo "$PREVIOUS_JSON" | jq -r '.image // .serviceImage // empty')"
  COMMIT="$(echo "$PREVIOUS_JSON" | jq -r '.commit // empty')"
  SOURCE="previous.json"
fi

if [[ -z "$IMAGE" ]]; then
  echo "ERROR: rollback image is empty" >&2
  exit 1
fi

echo "=== her-web rollback ==="
echo "server: $SERVER"
echo "service: $SERVICE"
echo "source: $SOURCE"
echo "image: $IMAGE"
echo "commit: ${COMMIT:-unknown}"
echo "dry_run: $DRY_RUN"
echo ""

if ! "$SSH_BIN" -n "$SERVER" "sudo docker image inspect '$IMAGE' >/dev/null 2>&1"; then
  echo "ERROR: rollback image 不在服务器本地，不能保证可回滚：$IMAGE" >&2
  exit 1
fi
echo "✓ rollback image exists on server"

if [[ "$DRY_RUN" == "1" ]]; then
  echo "DRY RUN: 不执行 service update。"
  exit 0
fi

if [[ "${CONFIRM_ROLLBACK:-0}" != "1" ]]; then
  echo "ERROR: 真实回滚需要 CONFIRM_ROLLBACK=1" >&2
  exit 1
fi

"$SSH_BIN" -n "$SERVER" "sudo docker service update --image '$IMAGE' --no-resolve-image --update-order start-first --force --detach '$SERVICE'"
echo "✓ rollback service update triggered"
