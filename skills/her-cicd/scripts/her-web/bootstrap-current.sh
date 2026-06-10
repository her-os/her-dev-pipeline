#!/usr/bin/env bash
# Bootstrap her-web production metadata without deploying or restarting.
set -euo pipefail

REPO="${1:-}"
COMMIT="${2:-}"
SERVER="${SERVER:-ubuntu@192.144.187.174}"
SERVICE="${SERVICE:-her-herweb-a8y5ka}"
SSH_BIN="${SSH_BIN:-/usr/bin/ssh}"
STATE_DIR="${STATE_DIR:-/home/ubuntu/her-web-release}"
DRY_RUN=0
REQUIRED_COMMITS=()

usage() {
  cat <<'EOF'
Usage:
  bootstrap-current.sh <repo> <production-commit> [--dry-run] [--required-commit <sha>...]

Writes /home/ubuntu/her-web-release/current.json only when CONFIRM_BOOTSTRAP=1.
It does not deploy, restart, update service, or modify the database.
EOF
}

if [[ -z "$REPO" || -z "$COMMIT" ]]; then
  usage >&2
  exit 2
fi
shift 2

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --required-commit)
      REQUIRED_COMMITS+=("${2:-}")
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

COMMIT_SHA="$(git -C "$REPO" rev-parse --verify "${COMMIT}^{commit}")"
BRANCHES="$(git -C "$REPO" branch --contains "$COMMIT_SHA" --format '%(refname:short)' | paste -sd, -)"
REMOTE_MAIN_SHA="$(git -C "$REPO" ls-remote origin refs/heads/main | awk '{print $1}')"

if [[ "$COMMIT_SHA" != "$REMOTE_MAIN_SHA" ]]; then
  echo "ERROR: bootstrap commit is not current remote origin/main." >&2
  echo "  commit=$COMMIT_SHA" >&2
  echo "  remote_origin_main=$REMOTE_MAIN_SHA" >&2
  echo "Use a stronger manual process if production is intentionally not main." >&2
  exit 1
fi

for sha in "${REQUIRED_COMMITS[@]}"; do
  if ! git -C "$REPO" merge-base --is-ancestor "$sha" "$COMMIT_SHA" >/dev/null 2>&1; then
    echo "ERROR: required hotfix commit is not included in bootstrap commit: $sha" >&2
    exit 1
  fi
done

read_remote() {
  "$SSH_BIN" -n "$SERVER" "$1"
}

SERVICE_IMAGE="$(read_remote "sudo docker service inspect '$SERVICE' --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}'")"
REPLICAS="$(read_remote "sudo docker service ls --filter name='$SERVICE' --format '{{.Replicas}}'")"
TASK_ID="$(read_remote "sudo docker service ps '$SERVICE' --filter desired-state=running --format '{{.ID}}' | head -1")"
CONTAINER_ID="$(read_remote "sudo docker ps --filter label=com.docker.swarm.service.name='$SERVICE' --format '{{.ID}}' | head -1")"
RUNNING_IMAGE="$(read_remote "sudo docker inspect --format '{{.Image}}' '$CONTAINER_ID'")"
IMAGE_LABEL_REVISION="$(read_remote "sudo docker image inspect --format '{{ index .Config.Labels \"org.opencontainers.image.revision\" }}' '$SERVICE_IMAGE' 2>/dev/null || true")"

if [[ "$REPLICAS" != "1/1" ]]; then
  echo "ERROR: service replicas is not 1/1: $REPLICAS" >&2
  exit 1
fi

if ! read_remote "sudo docker image inspect '$SERVICE_IMAGE' >/dev/null 2>&1"; then
  echo "ERROR: current service image is not inspectable on server: $SERVICE_IMAGE" >&2
  exit 1
fi

BOOTSTRAPPED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
TMP_JSON="$(mktemp)"
trap 'rm -f "$TMP_JSON"' EXIT

printf '%s\n' "${REQUIRED_COMMITS[@]}" | jq -R -s 'split("\n")|map(select(length>0))' > "$TMP_JSON.required"

jq -n \
  --arg commit "$COMMIT_SHA" \
  --arg branch "${BRANCHES:-main}" \
  --arg image "$SERVICE_IMAGE" \
  --arg runningImage "$RUNNING_IMAGE" \
  --arg service "$SERVICE" \
  --arg replicas "$REPLICAS" \
  --arg taskId "$TASK_ID" \
  --arg containerId "$CONTAINER_ID" \
  --arg bootstrappedAt "$BOOTSTRAPPED_AT" \
  --arg remoteOriginMain "$REMOTE_MAIN_SHA" \
  --arg imageLabelRevision "$IMAGE_LABEL_REVISION" \
  --argjson requiredHotfixCommits "$(cat "$TMP_JSON.required")" \
  '{
    version: 1,
    commit: $commit,
    branch: $branch,
    image: $image,
    runningImage: $runningImage,
    service: $service,
    replicas: $replicas,
    taskId: $taskId,
    containerId: $containerId,
    bootstrappedAt: $bootstrappedAt,
    deployMethod: "bootstrap-current",
    nonMainOverride: false,
    releaseReportId: null,
    reportHash: null,
    bootstrap: true,
    metadataTrusted: false,
    requiredHotfixCommits: $requiredHotfixCommits,
    evidence: [
      ("serviceImage=" + $image),
      ("runningImage=" + $runningImage),
      ("replicas=" + $replicas),
      ("taskId=" + $taskId),
      ("containerId=" + $containerId),
      ("remoteOriginMain=" + $remoteOriginMain),
      ("imageLabelRevision=" + $imageLabelRevision)
    ]
  }' > "$TMP_JSON"
rm -f "$TMP_JSON.required"

echo "=== her-web bootstrap current metadata ==="
echo "server: $SERVER"
echo "service: $SERVICE"
echo "commit: $COMMIT_SHA"
echo "service_image: $SERVICE_IMAGE"
echo "running_image: $RUNNING_IMAGE"
echo "replicas: $REPLICAS"
echo "task_id: $TASK_ID"
echo "dry_run: $DRY_RUN"
echo ""
cat "$TMP_JSON"
echo ""

if [[ "$DRY_RUN" == "1" ]]; then
  echo "DRY RUN: 不写服务器 current.json。"
  exit 0
fi

if [[ "${CONFIRM_BOOTSTRAP:-0}" != "1" ]]; then
  echo "ERROR: 写入 current.json 需要 CONFIRM_BOOTSTRAP=1" >&2
  exit 1
fi

read_remote "mkdir -p '$STATE_DIR'"
"$SSH_BIN" "$SERVER" "cat > '$STATE_DIR/current.json' && cat '$STATE_DIR/current.json' >> '$STATE_DIR/history.jsonl'" < "$TMP_JSON"
echo "✓ wrote $STATE_DIR/current.json and appended history.jsonl"
