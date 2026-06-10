#!/usr/bin/env bash
set -euo pipefail

REPO="${REPO:-her-os/Her-Web}"
WORKFLOW="${WORKFLOW:-docker-build.yaml}"
IMAGE_REPO="${IMAGE_REPO:-ghcr.io/her-os/her-web}"
SERVER="${SERVER:-ubuntu@192.144.187.174}"
SSH_BIN="${SSH_BIN:-/usr/bin/ssh}"
SERVICE="${SERVICE:-her-herweb-a8y5ka}"
HEALTH_URL="${HEALTH_URL:-https://hersoul.cn}"

DRY_RUN=0
VERIFY_ONLY=0
DIGEST=""

usage() {
  cat <<'EOF'
Usage:
  scripts/her-web/deploy-main-digest.sh [sha256:<digest>]
  scripts/her-web/deploy-main-digest.sh --dry-run [sha256:<digest>]
  scripts/her-web/deploy-main-digest.sh --verify-only [sha256:<digest>]

Default behavior:
  1. If no digest is passed, read the latest successful main GitHub Actions
     docker-build.yaml run and extract containerimage.digest.
  2. Pull ghcr.io/her-os/her-web@sha256:<digest> on the server.
  3. Update Swarm service her-herweb-a8y5ka directly to that digest.
  4. Verify service task image and https://hersoul.cn HTTP status.

Scheme A note:
  This script is GHCR backup/rollback only while Scheme C is the main fast path.
  It is never called automatically by Scheme C or by CI completion.
  Normal production releases must use scripts/her-web/release.sh.
  This round does not add TCR support or Docker build cache assumptions.

Env overrides:
  REPO=her-os/Her-Web
  WORKFLOW=docker-build.yaml
  IMAGE_REPO=ghcr.io/her-os/her-web
  SERVER=ubuntu@192.144.187.174
  SSH_BIN=/usr/bin/ssh
  SERVICE=her-herweb-a8y5ka
  HEALTH_URL=https://hersoul.cn
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --verify-only)
      VERIFY_ONLY=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    sha256:*)
      DIGEST="$1"
      shift
      ;;
    *@sha256:*)
      DIGEST="${1##*@}"
      shift
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "${HER_WEB_ALLOW_DIGEST_DIRECT:-0}" != "1" && "$VERIFY_ONLY" -eq 0 && "$DRY_RUN" -eq 0 ]]; then
  echo "ERROR: deploy-main-digest.sh is a low-level GHCR backup/rollback tool." >&2
  echo "Normal production release must use scripts/her-web/release.sh." >&2
  echo "For an explicit GHCR rollback, rerun with HER_WEB_ALLOW_DIGEST_DIRECT=1 after user authorization." >&2
  exit 1
fi

need_cmd() {
  command -v "$1" >/dev/null || {
    echo "ERROR: missing command: $1" >&2
    exit 1
  }
}

need_cmd gh
need_cmd sed
need_cmd tail
need_cmd curl
[[ -x "$SSH_BIN" ]] || {
  echo "ERROR: SSH_BIN is not executable: $SSH_BIN" >&2
  exit 1
}

latest_digest_from_actions() {
  local run_id digest
  run_id="$(gh run list \
    --repo "$REPO" \
    --branch main \
    --workflow "$WORKFLOW" \
    --status success \
    --limit 1 \
    --json databaseId \
    --jq '.[0].databaseId')"

  if [[ -z "$run_id" || "$run_id" == "null" ]]; then
    echo "ERROR: no successful main run found for $REPO / $WORKFLOW" >&2
    exit 1
  fi

  digest="$(gh run view "$run_id" --repo "$REPO" --log \
    | sed -n 's/.*"containerimage.digest": "\(sha256:[^"]*\)".*/\1/p' \
    | tail -1)"

  if [[ -z "$digest" ]]; then
    echo "ERROR: could not find containerimage.digest in run $run_id" >&2
    exit 1
  fi

  echo "$digest"
}

ssh_cmd() {
  local remote_cmd="$1"
  echo "+ $SSH_BIN -n $SERVER '$remote_cmd'"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    "$SSH_BIN" -n "$SERVER" "$remote_cmd"
  fi
}

local_cmd() {
  echo "+ $*"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    "$@"
  fi
}

if [[ -z "$DIGEST" ]]; then
  DIGEST="$(latest_digest_from_actions)"
fi

IMAGE="${IMAGE_REPO}@${DIGEST}"
CURRENT_SERVICE_IMAGE="$("$SSH_BIN" -n "$SERVER" "sudo docker service inspect $SERVICE --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}'" 2>/dev/null || echo unknown)"

echo "repo: $REPO"
echo "workflow: $WORKFLOW"
echo "image: $IMAGE"
echo "current_service_image: $CURRENT_SERVICE_IMAGE"
echo "service: $SERVICE"
echo "server: $SERVER"
echo "health_url: $HEALTH_URL"

if [[ "$VERIFY_ONLY" -eq 0 ]]; then
  ssh_cmd "sudo docker pull $IMAGE"
  ssh_cmd "sudo docker service update --image $IMAGE --force --update-order start-first $SERVICE"
else
  echo "verify-only: skipping pull and service update"
fi

ssh_cmd "sudo docker service ps $SERVICE --no-trunc --format '{{.ID}}|{{.CurrentState}}|{{.Error}}|{{.Image}}' | head -8"
ssh_cmd "sudo docker ps --filter label=com.docker.swarm.service.name=$SERVICE --format '{{.ID}} {{.Image}} {{.RunningFor}} {{.Status}}'"
local_cmd curl -s -o /dev/null -w "http=%{http_code} time=%{time_total}s\n" "$HEALTH_URL"
