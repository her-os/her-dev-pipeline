#!/bin/bash
# her-gateway 一键部署：git archive → scp → 服务器 build → compose recreate → 验证
# 不依赖 ghcr pull（腾讯云 pull ghcr 不稳定）
# 前提：服务器已安装 docker-compose-plugin
set -euo pipefail

QUIET="${QUIET:-0}"
log() { [[ "$QUIET" == "1" ]] || echo "$@"; }

SSH="/usr/bin/ssh -o ConnectTimeout=10 -o ServerAliveInterval=30 -o ServerAliveCountMax=5"
SCP="/usr/bin/scp"
SERVER="ubuntu@192.144.187.174"
IMAGE_NAME="her-newapi-e91gqn-new-api"
COMPOSE_PROJECT="her-newapi-e91gqn"
CODE_DIR="/etc/dokploy/compose/her-newapi-e91gqn/code"
SRC="${1:-/Users/suyuan/Documents/her-source/her-gateway}"
VERSION="${2:-}"
BUILD_LOG="/tmp/gateway-build.log"

log "=== her-gateway deploy ==="
log "  源码: $SRC"

# 如果传了版本参数，checkout 到对应 tag
if [ -n "$VERSION" ]; then
  if ! git -C "$SRC" tag -l "$VERSION" | grep -q '^'; then
    echo "[FAIL] '$VERSION' 不是 git tag。生产部署必须基于 tag。" >&2
    echo "  如需紧急跳过 tag 校验，不传版本参数并设 ALLOW_NON_TAG_DEPLOY=1" >&2
    exit 1
  fi
  if [[ ! "$VERSION" =~ ^v[0-9]+\. ]]; then
    echo "[FAIL] tag '$VERSION' 不符合版本命名规范（应为 v0.x.y）。" >&2
    exit 1
  fi
  echo "  版本: $VERSION"
  git -C "$SRC" checkout "$VERSION" --quiet
fi

echo "  分支: $(git -C "$SRC" branch --show-current 2>/dev/null || echo 'detached HEAD')"
echo "  commit: $(git -C "$SRC" log -1 --format='%h %s')"
echo ""

# 检查是否在 main 分支或 tag
BRANCH="$(git -C "$SRC" branch --show-current 2>/dev/null || echo "")"
if [ -z "$VERSION" ] && [ "$BRANCH" != "main" ] && [ "${ALLOW_NON_TAG_DEPLOY:-0}" != "1" ]; then
  echo "[WARN] 当前分支是 ${BRANCH:-detached}，不是 main，也没有传版本 tag。"
  read -p "确定要从 ${BRANCH:-detached HEAD} 部署吗？(y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "已取消。"
    exit 1
  fi
fi

# 检查工作区干净
if ! git -C "$SRC" diff --quiet HEAD 2>/dev/null; then
  echo "[FAIL] 工作区有未提交的改动，不部署未提交代码。" >&2
  git -C "$SRC" diff --stat HEAD
  exit 1
fi

echo "[1/4] 打包 + 上传"
ARCHIVE="/tmp/her-gateway.tar.gz"
git -C "$SRC" archive --format=tar.gz HEAD -o "$ARCHIVE"
$SCP "$ARCHIVE" "$SERVER:/tmp/"
$SSH "$SERVER" "sudo mv $CODE_DIR ${CODE_DIR}.bak.\$(date +%s) 2>/dev/null || true && sudo mkdir -p $CODE_DIR && sudo tar -xzf /tmp/her-gateway.tar.gz -C $CODE_DIR"
echo "  [OK] 代码已上传（$(du -h "$ARCHIVE" | cut -f1)）"
echo ""

echo "[2/4] 服务器 build（nohup 防断连）"
$SSH "$SERVER" "nohup sudo DOCKER_BUILDKIT=1 docker build -t $IMAGE_NAME $CODE_DIR > $BUILD_LOG 2>&1 &"
echo "  Build 已在后台启动（BuildKit enabled）..."

# 轮询等 build 完成
WAIT=0
while true; do
  sleep 5
  WAIT=$((WAIT + 5))
  RUNNING=$($SSH "$SERVER" "ps aux | grep 'docker build' | grep -v grep | wc -l" 2>/dev/null || echo "1")
  if [ "$RUNNING" = "0" ]; then
    # 检查 build 是否成功
    IMAGE_TIME=$($SSH "$SERVER" "sudo docker images --format '{{.CreatedAt}}' $IMAGE_NAME:latest 2>/dev/null" 2>/dev/null || echo "")
    if [ -z "$IMAGE_TIME" ]; then
      echo "  [FAIL] Build 完成但镜像不存在。查看服务器 $BUILD_LOG" >&2
      $SSH "$SERVER" "tail -20 $BUILD_LOG" 2>/dev/null || true
      exit 1
    fi
    echo "  [OK] Build 完成（${WAIT}s），镜像时间: $IMAGE_TIME"
    break
  fi
  echo "  Build 进行中...（${WAIT}s）"
  if [ $WAIT -gt 300 ]; then
    echo "[FAIL] Build 超过 5 分钟，可能卡死。查看服务器 $BUILD_LOG" >&2
    exit 1
  fi
done
echo ""

echo "[3/4] 重建容器（compose recreate）"
echo "  [WARN] 即将重建 new-api，约 30s 不可用"

# 检查 docker compose 可用性
COMPOSE_VERSION=$($SSH "$SERVER" "sudo docker compose version --short 2>/dev/null" || echo "")
if [ -z "$COMPOSE_VERSION" ]; then
  echo "[FAIL] 服务器未安装 docker-compose-plugin。" >&2
  echo "  请先执行: ssh $SERVER 'sudo apt-get update && sudo apt-get install -y docker-compose-plugin'" >&2
  echo "  或手动从 Dokploy UI 点 Redeploy。" >&2
  exit 1
fi
echo "  docker compose $COMPOSE_VERSION"

# 安全门：验证 volume 路径
EXISTING_DATA_MOUNT=$($SSH "$SERVER" "sudo docker inspect new-api --format '{{range .Mounts}}{{if eq .Destination \"/data\"}}{{.Source}}{{end}}{{end}}'" 2>/dev/null || echo "")
EXPECTED_DATA_MOUNT="$CODE_DIR/data"
if [ -n "$EXISTING_DATA_MOUNT" ] && [ "$EXISTING_DATA_MOUNT" != "$EXPECTED_DATA_MOUNT" ]; then
  echo "  [WARN] 现有容器 /data 挂载在 $EXISTING_DATA_MOUNT"
  echo "         compose 会挂载到 $EXPECTED_DATA_MOUNT"
  echo "         创建软链接兼容..."
  $SSH "$SERVER" "sudo mkdir -p '$EXPECTED_DATA_MOUNT' && sudo ln -sfn '$EXISTING_DATA_MOUNT'/* '$EXPECTED_DATA_MOUNT/' 2>/dev/null || true"
fi

# 修改 compose 文件指向本地 build 镜像
$SSH "$SERVER" "cd '$CODE_DIR' && sudo sed -i.bak \
  -e 's|image: ghcr.io/her-os/her-gateway:main|image: $IMAGE_NAME:latest|' \
  -e 's|pull_policy: always|pull_policy: never|' \
  docker-compose.yml"

if ! $SSH "$SERVER" "cd '$CODE_DIR' && sudo grep -q '^      - HER_INTERNAL_RATE_LIMIT_BYPASS_TOKEN=' docker-compose.yml"; then
  echo "  [FAIL] docker-compose.yml 缺 HER_INTERNAL_RATE_LIMIT_BYPASS_TOKEN，拒绝部署会导致 her-web → gateway 内部调用被限流。" >&2
  exit 1
fi
echo "  [OK] HER_INTERNAL_RATE_LIMIT_BYPASS_TOKEN present"

# compose recreate（只重建 new-api，不动 redis）
$SSH "$SERVER" "cd '$CODE_DIR' && sudo docker compose -p '$COMPOSE_PROJECT' up -d --force-recreate --no-deps new-api"

# 验证镜像切换成功
CONTAINER_IMAGE=$($SSH "$SERVER" "sudo docker inspect new-api --format '{{.Image}}'" 2>/dev/null || echo "")
LATEST_IMAGE=$($SSH "$SERVER" "sudo docker images --no-trunc --format '{{.ID}}' $IMAGE_NAME:latest 2>/dev/null | head -1" 2>/dev/null || echo "")
if [ -n "$LATEST_IMAGE" ] && [ "$CONTAINER_IMAGE" != "$LATEST_IMAGE" ]; then
  echo "  [FAIL] 镜像切换失败！容器: $CONTAINER_IMAGE, 目标: $LATEST_IMAGE" >&2
  echo "  回滚：ssh $SERVER 'cd $CODE_DIR && sudo mv docker-compose.yml.bak docker-compose.yml'" >&2
  echo "  然后从 Dokploy UI 手动 Redeploy" >&2
  exit 1
fi
echo "  [OK] 容器已切到新镜像"

# 验证双网络成员
NETWORKS=$($SSH "$SERVER" "sudo docker inspect new-api --format '{{range \$k, \$v := .NetworkSettings.Networks}}{{\$k}} {{end}}'" 2>/dev/null || echo "")
if ! echo "$NETWORKS" | grep -q "dokploy-network"; then
  echo "  [FAIL] new-api 不在 dokploy-network，Traefik 路由可能断了" >&2
  exit 1
fi
if ! echo "$NETWORKS" | grep -q "new-api-network"; then
  echo "  [WARN] new-api 不在 new-api-network，尝试手动连接..." >&2
  $SSH "$SERVER" "sudo docker network connect '${COMPOSE_PROJECT}_new-api-network' new-api" 2>/dev/null || true
fi
echo "  [OK] 网络: $NETWORKS"

# 等待 healthy
for i in $(seq 1 12); do
  sleep 5
  STATUS=$($SSH "$SERVER" "sudo docker ps --filter 'name=new-api' --format '{{.Status}}'" 2>/dev/null || echo "")
  if echo "$STATUS" | grep -q "healthy"; then
    echo "  [OK] 容器 healthy（等待 $((i * 5))s）"
    break
  fi
  if [ $i -eq 12 ]; then
    echo "  [FAIL] 60s 内未 healthy，请检查: $SSH $SERVER 'sudo docker logs new-api --tail 20'" >&2
    exit 1
  fi
done
echo ""

echo "[4/4] 外部验证"
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://api.tokenic.cn/api/status 2>/dev/null || echo "000")
if [ "$HTTP_STATUS" = "200" ]; then
  echo "  [OK] api.tokenic.cn HTTP 200"
else
  echo "  [FAIL] api.tokenic.cn HTTP $HTTP_STATUS" >&2
fi

log ""
log "=== 部署完成 ==="
log "  镜像: $IMAGE_NAME:latest"
log "  commit: $(git -C "$SRC" log -1 --format='%h %s')"
log "  回滚: ssh $SERVER 'cd $CODE_DIR && sudo mv docker-compose.yml.bak docker-compose.yml && sudo docker compose -p $COMPOSE_PROJECT up -d --force-recreate --no-deps new-api'"
log "  [WARN] 这是服务器本地镜像。Dokploy Redeploy 会回到 registry 版本。"
