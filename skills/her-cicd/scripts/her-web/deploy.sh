#!/bin/bash
# her-web 方案 C 一键部署：preflight → git archive HEAD → server build → image id → start-first update → postflight
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="${1:-${SRC_REPO:-$(git rev-parse --show-toplevel 2>/dev/null || echo $PWD)}}"
SRC="$(cd "$SRC" && pwd)"

SERVER="${SERVER:-ubuntu@192.144.187.174}"
SERVICE="${SERVICE:-her-herweb-a8y5ka}"
TAG="${TAG:-her-web:deploy}"
REMOTE_DIR="${REMOTE_DIR:-/tmp/her-web-deploy}"
SSH=/usr/bin/ssh

ENV_PROD_SERVER="/home/ubuntu/.her-web-env-production"
ALLOW_DIRTY_DEPLOY="${ALLOW_DIRTY_DEPLOY:-0}"
ALLOW_NON_MAIN_DEPLOY="${ALLOW_NON_MAIN_DEPLOY:-0}"
HER_WEB_RELEASE_INTERNAL="${HER_WEB_RELEASE_INTERNAL:-0}"
EXPECTED_TARGET_SHA="${EXPECTED_TARGET_SHA:-}"
EXPECTED_REPORT_HASH="${EXPECTED_REPORT_HASH:-}"
RELEASE_REPORT_PATH="${RELEASE_REPORT_PATH:-}"
REMOTE_ORIGIN_MAIN_SHA="${REMOTE_ORIGIN_MAIN_SHA:-}"
RELEASE_STATE_DIR="/home/ubuntu/her-web-release"
MIGRATION_REPORT="${MIGRATION_REPORT:-}"

echo "=== her-web deploy · 服务器端构建 ==="
echo ""

if [ "$HER_WEB_RELEASE_INTERNAL" != "1" ] && [ "${HER_WEB_DEPLOY_LEGACY_DIRECT:-0}" != "1" ]; then
  echo "[FAIL] deploy.sh 现在是 release 内部执行器。" >&2
  echo "  正常生产发布请使用：scripts/her-web/release.sh <repo> <target-ref>" >&2
  echo "  低层调试才允许 HER_WEB_DEPLOY_LEGACY_DIRECT=1。" >&2
  exit 1
fi

if ! git -C "$SRC" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "[FAIL] $SRC 不是 git 仓库，方案 C 需要从 git archive HEAD 取代码。" >&2
  exit 1
fi

BRANCH="$(git -C "$SRC" rev-parse --abbrev-ref HEAD)"
COMMIT_SHA="$(git -C "$SRC" rev-parse HEAD)"
SHORT_SHA="$(git -C "$SRC" rev-parse --short HEAD)"

echo "  SRC=$SRC"
echo "  SERVER=$SERVER"
echo "  SERVICE=$SERVICE"
echo "  TAG=$TAG"
echo "  BRANCH=$BRANCH"
echo "  COMMIT=$SHORT_SHA"
echo "  ALLOW_NON_MAIN_DEPLOY=$ALLOW_NON_MAIN_DEPLOY"
echo ""

if [ "$HER_WEB_RELEASE_INTERNAL" = "1" ]; then
  if [ -z "$EXPECTED_TARGET_SHA" ] || [ -z "$EXPECTED_REPORT_HASH" ] || [ -z "$RELEASE_REPORT_PATH" ]; then
    echo "[FAIL] release 内部调用缺少 EXPECTED_TARGET_SHA / EXPECTED_REPORT_HASH / RELEASE_REPORT_PATH。" >&2
    exit 1
  fi
  if [ ! -f "$RELEASE_REPORT_PATH" ]; then
    echo "[FAIL] RELEASE_REPORT_PATH 不存在：$RELEASE_REPORT_PATH" >&2
    exit 1
  fi
  if [ "$COMMIT_SHA" != "$EXPECTED_TARGET_SHA" ]; then
    echo "[FAIL] 当前 HEAD 不等于 EXPECTED_TARGET_SHA。HEAD=$COMMIT_SHA EXPECTED_TARGET_SHA=$EXPECTED_TARGET_SHA" >&2
    exit 1
  fi
  REPORT_TARGET_SHA="$(jq -r '.targetSha' "$RELEASE_REPORT_PATH")"
  REPORT_HASH="$(jq -S -c 'del(.reportHash)' "$RELEASE_REPORT_PATH" | shasum -a 256 | awk '{print $1}')"
  if [ "$REPORT_TARGET_SHA" != "$EXPECTED_TARGET_SHA" ]; then
    echo "[FAIL] release report targetSha 不匹配：$REPORT_TARGET_SHA" >&2
    exit 1
  fi
  if [ "$REPORT_HASH" != "$EXPECTED_REPORT_HASH" ]; then
    echo "[FAIL] release report hash 不匹配：$REPORT_HASH" >&2
    exit 1
  fi
  if [ -n "$REMOTE_ORIGIN_MAIN_SHA" ] && [ "$EXPECTED_TARGET_SHA" != "$REMOTE_ORIGIN_MAIN_SHA" ] && [ "$ALLOW_NON_MAIN_DEPLOY" != "1" ]; then
    echo "[FAIL] 目标 commit 不是实时远端 origin/main。紧急止血才允许 ALLOW_NON_MAIN_DEPLOY=1。" >&2
    exit 1
  fi
elif [ "$BRANCH" != "main" ] && [ "$ALLOW_NON_MAIN_DEPLOY" != "1" ]; then
  echo "[FAIL] 当前分支是 $BRANCH。方案 C 正常只允许从 main 部署。" >&2
  echo "  紧急止血才允许 ALLOW_NON_MAIN_DEPLOY=1，并且必须用户当前会话明确授权。" >&2
  exit 1
fi

START_TIME=$(date +%s)

DIRTY_TRACKED="$(git -C "$SRC" status --porcelain --untracked-files=no)"
if [ -n "$DIRTY_TRACKED" ] && [ "$ALLOW_DIRTY_DEPLOY" != "1" ]; then
  echo "[FAIL] 工作区有未提交的已跟踪文件，方案 C 默认拒绝部署：" >&2
  echo "$DIRTY_TRACKED" >&2
  echo "" >&2
  echo "  方案 C 只部署 HEAD；请先提交代码。紧急例外可显式设置 ALLOW_DIRTY_DEPLOY=1。" >&2
  exit 1
fi

if [ "$HER_WEB_RELEASE_INTERNAL" = "1" ] && { [ "${SKIP_POSTFLIGHT:-0}" = "1" ] || [ "$ALLOW_DIRTY_DEPLOY" = "1" ]; }; then
  echo "[FAIL] release 生产部署不允许 SKIP_POSTFLIGHT / ALLOW_DIRTY_DEPLOY 绕过。" >&2
  exit 1
fi

# release.sh 已经跑过 preflight，deploy.sh 作为内部执行器时跳过重复检查
if [ "$HER_WEB_RELEASE_INTERNAL" = "1" ]; then
  echo "[0/5] Preflight 跳过（release.sh 已验证）"
  echo ""
elif [ "${SKIP_PREFLIGHT:-0}" != "1" ]; then
  echo "[0/5] Preflight 检查"
  PREFLIGHT_ARGS=("$SRC")
  if [ -n "$MIGRATION_REPORT" ]; then
    PREFLIGHT_ARGS+=(--migration-report "$MIGRATION_REPORT")
  fi
  ALLOW_NON_MAIN_DEPLOY="$ALLOW_NON_MAIN_DEPLOY" \
  EXPECTED_TARGET_SHA="$EXPECTED_TARGET_SHA" \
  REMOTE_ORIGIN_MAIN_SHA="$REMOTE_ORIGIN_MAIN_SHA" \
  bash "$SCRIPT_DIR/deploy-preflight.sh" "${PREFLIGHT_ARGS[@]}"
  echo ""
else
  echo "[0/5] Preflight 跳过（SKIP_PREFLIGHT=1）"
  echo ""
fi

echo "[1/5] 检查服务器环境与 Swarm 前提"
if $SSH "$SERVER" "test -f $ENV_PROD_SERVER"; then
  echo "  [OK] $ENV_PROD_SERVER 存在"
else
  echo "  [FAIL] $ENV_PROD_SERVER 不存在" >&2
  echo "  首次部署需要先在服务器创建它，内容与 GitHub Secrets ENV_PRODUCTION 一致。" >&2
  exit 1
fi

HAS_APP_URL="$($SSH "$SERVER" "grep -c 'NEXT_PUBLIC_APP_URL=https://hersoul.cn' $ENV_PROD_SERVER" || echo 0)"
if [ "$HAS_APP_URL" -eq 0 ]; then
  echo "  [FAIL] .env.production 缺少 NEXT_PUBLIC_APP_URL=https://hersoul.cn" >&2
  exit 1
fi
echo "  [OK] NEXT_PUBLIC_APP_URL=https://hersoul.cn"

echo "  [INFO] 固化生产不限流 env"
$SSH "$SERVER" "set -euo pipefail
sudo touch '$ENV_PROD_SERVER'
if sudo grep -q '^AUTH_RATE_LIMIT_ENABLED=' '$ENV_PROD_SERVER'; then
  sudo sed -i 's/^AUTH_RATE_LIMIT_ENABLED=.*/AUTH_RATE_LIMIT_ENABLED=false/' '$ENV_PROD_SERVER'
else
  printf '\nAUTH_RATE_LIMIT_ENABLED=false\n' | sudo tee -a '$ENV_PROD_SERVER' >/dev/null
fi
if ! sudo grep -q '^HER_INTERNAL_RATE_LIMIT_BYPASS_TOKEN=' '$ENV_PROD_SERVER'; then
  token=\$(sudo docker service inspect '$SERVICE' --format '{{range .Spec.TaskTemplate.ContainerSpec.Env}}{{println .}}{{end}}' | sed -n 's/^HER_INTERNAL_RATE_LIMIT_BYPASS_TOKEN=//p' | head -n 1)
  if [ -z \"\$token\" ]; then
    echo '[FAIL] 生产 service 和 env 文件都缺 HER_INTERNAL_RATE_LIMIT_BYPASS_TOKEN' >&2
    exit 1
  fi
  printf '\nHER_INTERNAL_RATE_LIMIT_BYPASS_TOKEN=%s\n' \"\$token\" | sudo tee -a '$ENV_PROD_SERVER' >/dev/null
fi
"
echo "  [OK] AUTH_RATE_LIMIT_ENABLED=false"
echo "  [OK] HER_INTERNAL_RATE_LIMIT_BYPASS_TOKEN present"

NODE_COUNT="$($SSH "$SERVER" "sudo docker node ls --format '{{.Hostname}}' | wc -l | tr -d ' '")"
if [ "$NODE_COUNT" != "1" ]; then
  echo "  [FAIL] Swarm 节点数 = $NODE_COUNT。方案 C 使用本地 image id，只允许单节点。" >&2
  exit 1
fi
echo "  [OK] Swarm 节点数 = 1"
echo ""

if [ "$HER_WEB_RELEASE_INTERNAL" = "1" ]; then
  echo "[1b/5] 复核 release report 对应的生产状态"
  CURRENT_SERVICE_IMAGE="$($SSH "$SERVER" "sudo docker service inspect '$SERVICE' --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}'" 2>/dev/null || true)"
  CURRENT_CONTAINER_ID="$($SSH "$SERVER" "sudo docker ps --filter label=com.docker.swarm.service.name='$SERVICE' --format '{{.ID}}' | head -1" 2>/dev/null || true)"
  CURRENT_RUNNING_IMAGE="$($SSH "$SERVER" "if [ -n '$CURRENT_CONTAINER_ID' ]; then sudo docker inspect --format '{{.Image}}' '$CURRENT_CONTAINER_ID'; fi" 2>/dev/null || true)"
  CURRENT_TASK_ID="$($SSH "$SERVER" "sudo docker service ps '$SERVICE' --filter desired-state=running --format '{{.ID}}' | head -1" 2>/dev/null || true)"
  CURRENT_JSON_SHA="$($SSH "$SERVER" "if [ -f '$RELEASE_STATE_DIR/current.json' ]; then shasum -a 256 '$RELEASE_STATE_DIR/current.json' | cut -d ' ' -f1; fi" 2>/dev/null || true)"
  CURRENT_FINGERPRINT="$(printf '%s|%s|%s|%s' "$CURRENT_SERVICE_IMAGE" "$CURRENT_RUNNING_IMAGE" "$CURRENT_TASK_ID" "$CURRENT_JSON_SHA" | shasum -a 256 | awk '{print $1}')"
  REPORT_FINGERPRINT="$(jq -r '.checkedProductionState.fingerprint // empty' "$RELEASE_REPORT_PATH")"
  if [ -n "$REPORT_FINGERPRINT" ] && [ "$CURRENT_FINGERPRINT" != "$REPORT_FINGERPRINT" ]; then
    echo "[FAIL] 生产状态已变化，release report 过期。" >&2
    echo "  report fingerprint:  $REPORT_FINGERPRINT" >&2
    echo "  current fingerprint: $CURRENT_FINGERPRINT" >&2
    exit 1
  fi
  echo "  [OK] production fingerprint 未变化"
  echo ""
fi

echo "[2/5] 传输已提交代码到服务器"
$SSH "$SERVER" "rm -rf '$REMOTE_DIR' && mkdir -p '$REMOTE_DIR'"
git -C "$SRC" archive --format=tar HEAD | $SSH "$SERVER" "tar -xf - -C '$REMOTE_DIR'"
$SSH "$SERVER" "cd '$REMOTE_DIR' && rm -f .env.local .env.development .env.test .env.production.local && cp '$ENV_PROD_SERVER' .env.production"
echo "  [OK] git archive HEAD 已传输到 $REMOTE_DIR"
echo ""

echo "[3/5] 服务器 docker build"
RELEASE_TAG="her-web:release-${SHORT_SHA}-$(date -u '+%Y%m%d%H%M%S')"
$SSH "$SERVER" "cd '$REMOTE_DIR' && sudo DOCKER_BUILDKIT=1 docker build --label 'org.opencontainers.image.revision=$COMMIT_SHA' -t '$TAG' -t '$RELEASE_TAG' ."
IMAGE_ID="$($SSH "$SERVER" "sudo docker image inspect --format '{{.Id}}' '$RELEASE_TAG'")"
echo "  [OK] docker build 完成：$IMAGE_ID"
echo "  [OK] release tag：$RELEASE_TAG"
echo ""

echo "[4/5] 更新 Swarm service"
if [ "$HER_WEB_RELEASE_INTERNAL" = "1" ]; then
  $SSH "$SERVER" "mkdir -p '$RELEASE_STATE_DIR' && if [ -f '$RELEASE_STATE_DIR/current.json' ]; then cp '$RELEASE_STATE_DIR/current.json' '$RELEASE_STATE_DIR/previous.json'; else printf '{\"version\":1,\"image\":\"%s\",\"service\":\"%s\",\"commit\":null,\"source\":\"pre-release-service\"}\n' '$CURRENT_SERVICE_IMAGE' '$SERVICE' > '$RELEASE_STATE_DIR/previous.json'; fi"
fi
$SSH "$SERVER" "set -euo pipefail
BYPASS_TOKEN=\$(sudo sed -n 's/^HER_INTERNAL_RATE_LIMIT_BYPASS_TOKEN=//p' '$ENV_PROD_SERVER' | head -n 1)
test -n \"\$BYPASS_TOKEN\"
sudo docker service update \\
  --env-add AUTH_RATE_LIMIT_ENABLED=false \\
  --env-add \"HER_INTERNAL_RATE_LIMIT_BYPASS_TOKEN=\$BYPASS_TOKEN\" \\
  --image '$IMAGE_ID' \\
  --no-resolve-image \\
  --update-order start-first \\
  --force \\
  --detach \\
  '$SERVICE'
"
echo "  [OK] service update 已触发（detach 模式）"
echo "  等待新容器启动..."
sleep 5

RETRIES=0
REPLICAS="?/?"
while [ "$RETRIES" -lt 18 ]; do
  REPLICAS="$($SSH "$SERVER" "sudo docker service ls --filter name='$SERVICE' --format '{{.Replicas}}'" 2>/dev/null || echo '?/?')"
  RUNNING_IMAGE="$($SSH "$SERVER" "sudo docker service ps '$SERVICE' --filter desired-state=running --format '{{.Image}}' | head -1" 2>/dev/null || echo '')"
  if [ "$REPLICAS" = "1/1" ] && [ "$RUNNING_IMAGE" = "$IMAGE_ID" ]; then
    echo "  [OK] replicas=$REPLICAS image=目标镜像"
    break
  fi
  RETRIES=$((RETRIES + 1))
  echo "  ... replicas=$REPLICAS image=${RUNNING_IMAGE:-unknown} ($RETRIES/18)"
  sleep 5
done
if [ "$REPLICAS" != "1/1" ] || [ "$RUNNING_IMAGE" != "$IMAGE_ID" ]; then
  echo "  [FAIL] 服务未就绪（replicas=$REPLICAS image=${RUNNING_IMAGE:-unknown}），继续 postflight 验证..." >&2
fi
echo ""

if [ "${SKIP_POSTFLIGHT:-0}" != "1" ]; then
  echo "[5/5] Postflight 验证"
  bash "$SCRIPT_DIR/deploy-postflight.sh"
  echo ""
else
  echo "[5/5] Postflight 跳过（SKIP_POSTFLIGHT=1）"
  echo ""
fi

if [ "$HER_WEB_RELEASE_INTERNAL" = "1" ]; then
  echo "[5b/5] 写入 release metadata"
  TASK_ID="$($SSH "$SERVER" "sudo docker service ps '$SERVICE' --filter desired-state=running --format '{{.ID}}' | head -1" 2>/dev/null || true)"
  DEPLOYED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  CURRENT_META="$(mktemp)"
  jq -n \
    --arg commit "$COMMIT_SHA" \
    --arg branch "$BRANCH" \
    --arg image "$IMAGE_ID" \
    --arg releaseTag "$RELEASE_TAG" \
    --arg service "$SERVICE" \
    --arg taskId "$TASK_ID" \
    --arg deployedAt "$DEPLOYED_AT" \
    --arg nonMainOverride "$ALLOW_NON_MAIN_DEPLOY" \
    --arg reportId "$(jq -r '.reportId' "$RELEASE_REPORT_PATH")" \
    --arg reportHash "$EXPECTED_REPORT_HASH" \
    '{
      version: 1,
      commit: $commit,
      branch: $branch,
      image: $image,
      releaseTag: $releaseTag,
      service: $service,
      taskId: $taskId,
      deployedAt: $deployedAt,
      deployMethod: "C",
      nonMainOverride: ($nonMainOverride == "1"),
      releaseReportId: $reportId,
      reportHash: $reportHash,
      bootstrap: false,
      metadataTrusted: true,
      requiredHotfixCommits: []
    }' > "$CURRENT_META"
  $SSH "$SERVER" "mkdir -p '$RELEASE_STATE_DIR' && cat > '$RELEASE_STATE_DIR/current.json' && cat '$RELEASE_STATE_DIR/current.json' >> '$RELEASE_STATE_DIR/history.jsonl'" < "$CURRENT_META"
  rm -f "$CURRENT_META"
  echo "  [OK] current.json / history.jsonl 已写入"
  echo ""
fi

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo "=== 部署完成 · 耗时 ${ELAPSED} 秒 ==="
echo ""
echo "  branch: $BRANCH"
echo "  commit: $COMMIT_SHA"
echo "  non-main override: $ALLOW_NON_MAIN_DEPLOY"
echo "  image: $IMAGE_ID"
echo "  service: $SERVICE"
echo "  status: $($SSH "$SERVER" "sudo docker service ls --filter name='$SERVICE' --format '{{.Replicas}}'")"
echo ""
echo "  [WARN] 方案 C 部署的是 git archive HEAD，对应当前已提交 commit，不会带未提交或未跟踪文件。"
echo "  [WARN] 正常生产只允许从 main 部署；非 main 仅限紧急止血，并且必须后补 PR 回 main。"
echo "  [WARN] 这是服务器本地镜像。Dokploy Redeploy 会回到 registry 版本。"
