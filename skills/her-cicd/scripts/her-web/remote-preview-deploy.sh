#!/bin/bash
# her-web 方案 B legacy/compat preview 部署 · rsync + server build + swarm service update
#
# 用法：
#   bash remote-preview-deploy.sh [SRC]
#
# 参数（可选）：
#   $1  SRC  源仓库绝对路径（默认：env SRC_REPO 或 $PWD）
#
# 环境变量：
#   SRC_REPO     同 $1
#   SERVER       服务器 SSH 目标（默认：ubuntu@192.144.187.174）
#   SERVICE      Swarm service 名（默认：her-herweb-a8y5ka）
#   TAG          镜像 tag（默认：her-web:preview）
#   REMOTE_DIR   服务器远程工作目录（默认：/tmp/her-web-preview-herclub-entitlement-20260428-1）
#   SKIP_CHECKS  设为 1 跳过单节点 Swarm 前置校验（不推荐）
#
# 前置：
#   - 单节点 Docker Swarm（sudo docker node ls 只一行 node）
#   - SSH 公钥免密
#   - SSH 绝对路径 /usr/bin/ssh
#
# ⚠️ 仅在用户明确指令时运行。本脚本是 legacy/compat 路径，不再推荐。
#    常规生产发布必须用：scripts/her-web/release.sh。
#    本脚本绕过标准 CI 链路，制造临时状态技术债。

set -euo pipefail

SRC="${1:-${SRC_REPO:-$PWD}}"
SRC="$(cd "$SRC" && pwd)"

SERVER="${SERVER:-ubuntu@192.144.187.174}"
SERVICE="${SERVICE:-her-herweb-a8y5ka}"
TAG="${TAG:-her-web:preview}"
REMOTE_DIR="${REMOTE_DIR:-/tmp/her-web-preview-herclub-entitlement-20260428-1}"
SSH=/usr/bin/ssh

echo "[info] SRC=$SRC"
echo "[info] SERVER=$SERVER"
echo "[info] SERVICE=$SERVICE"
echo "[info] TAG=$TAG"
echo "[info] REMOTE_DIR=$REMOTE_DIR"
echo "[warn] 方案 B 仅为 legacy/compat；常规生产发布必须用 scripts/her-web/release.sh。"

if [ "${HER_WEB_ALLOW_PREVIEW_DIRECT:-0}" != "1" ]; then
  echo "[ERR] remote-preview-deploy.sh 是低层 legacy/compat 入口，默认禁止直接切生产。" >&2
  echo "      常规生产发布请用 scripts/her-web/release.sh。" >&2
  echo "      明确 legacy 止血才允许 HER_WEB_ALLOW_PREVIEW_DIRECT=1。" >&2
  exit 1
fi

# 校验源
if [ ! -f "$SRC/Dockerfile" ]; then
  echo "[ERR] $SRC/Dockerfile 不存在" >&2
  exit 1
fi

# 前置校验：单节点 Swarm
if [ "${SKIP_CHECKS:-0}" != "1" ]; then
  echo "=== 前置校验：Swarm 节点数 ==="
  NODE_COUNT=$($SSH "$SERVER" 'sudo docker node ls --format "{{.Hostname}}"' | wc -l | tr -d ' ')
  if [ "$NODE_COUNT" != "1" ]; then
    echo "[ERR] Swarm 节点数 = $NODE_COUNT（非单节点），本方案只适用于单节点" >&2
    echo "      多节点必须推 registry，不能用 --no-resolve-image" >&2
    echo "      若确认要继续（通常不该），设 SKIP_CHECKS=1" >&2
    exit 1
  fi
  echo "[OK] Swarm 节点数 = 1"

  echo "=== 前置校验：service 存在 ==="
  if ! $SSH "$SERVER" "sudo docker service ls --format '{{.Name}}'" | grep -q "^${SERVICE}$"; then
    echo "[ERR] service $SERVICE 不存在于服务器" >&2
    echo "      可用 service 列表:" >&2
    $SSH "$SERVER" 'sudo docker service ls'
    exit 1
  fi
  echo "[OK] service $SERVICE 存在"
fi

# 1. rsync 到服务器
echo "=== 1/4 · rsync 代码到服务器 ==="
$SSH "$SERVER" "mkdir -p $REMOTE_DIR"
rsync -av \
  --exclude=node_modules --exclude=.next --exclude=.git \
  --exclude=.trellis --exclude=.claude \
  --exclude=.env.local --exclude=.env.development --exclude=.env.test --exclude=.env.production \
  --exclude=data \
  --exclude='*.log' --exclude=.DS_Store \
  -e "$SSH" \
  "$SRC/" "$SERVER:$REMOTE_DIR/"

$SSH "$SERVER" "cd $REMOTE_DIR && rm -f .env.local .env.development .env.test && if [ -f .env.local ]; then echo '[ERR] .env.local still exists in preview dir' >&2; exit 1; fi && if [ ! -f .env.production ]; then echo '[ERR] .env.production missing in preview dir; seed the production env before building' >&2; exit 1; fi"

# 2. 服务器 docker build
echo "=== 2/4 · 服务器 docker build -t $TAG ==="
$SSH "$SERVER" "cd $REMOTE_DIR && sudo docker build -t $TAG ."
IMAGE_ID=$($SSH "$SERVER" "sudo docker image inspect --format '{{.Id}}' $TAG")
echo "[info] built image id: $IMAGE_ID"

# 3. 滚动更新 Swarm service
echo "=== 3/4 · 滚动更新 $SERVICE -> $IMAGE_ID ==="
$SSH "$SERVER" "sudo docker service update --image $IMAGE_ID --no-resolve-image --update-order start-first --force $SERVICE"

# 4. 验证
echo "=== 4/4 · 验证 ==="
$SSH "$SERVER" "sudo docker service ps $SERVICE --no-trunc" | head -5

echo ""
echo "[OK] 部署完成"
echo "[reminder] 这是临时状态。Dokploy 面板若点 Redeploy 会回滚到 registry 版本。"
echo "[reminder] 尽快 git push 让 CI 重建 ghcr.io 镜像以收敛回标准状态。"
