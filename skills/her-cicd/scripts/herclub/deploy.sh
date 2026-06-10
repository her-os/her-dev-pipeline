#!/usr/bin/env bash
set -euo pipefail

# HerClub 一键部署：本地 build → rsync → 服务器 docker build → Swarm service update
# 用法：bash deploy.sh

HERCLUB_DIR="/Users/suyuan/Documents/her-source/herclub"
SERVER="ubuntu@192.144.187.174"
SSH="/usr/bin/ssh"
REMOTE_DIR="/tmp/herclub-deploy"
SERVICE_NAME="herclub"
IMAGE="herclub:latest"
DOMAIN="club.hersoul.cn"

echo "=== 1/5 本地 build ==="
cd "$HERCLUB_DIR"
npm run build

echo "=== 2/5 rsync 到服务器 ==="
$SSH -n "$SERVER" "mkdir -p $REMOTE_DIR/dist"
rsync -avz --delete dist/ "$SERVER:$REMOTE_DIR/dist/"
scp Dockerfile nginx.conf "$SERVER:$REMOTE_DIR/"

echo "=== 3/5 服务器 docker build ==="
$SSH -n "$SERVER" "cd $REMOTE_DIR && sudo docker build -t $IMAGE ."

echo "=== 4/5 更新 Swarm service ==="
$SSH -n "$SERVER" "sudo docker service update --image $IMAGE --no-resolve-image --force $SERVICE_NAME"

echo "=== 5/5 验证 ==="
sleep 3
HTTP_CODE=$(curl -so /dev/null -w "%{http_code}" "https://$DOMAIN")
if [ "$HTTP_CODE" = "200" ]; then
    echo "[OK] https://$DOMAIN → HTTP $HTTP_CODE"
else
    echo "[WARN] https://$DOMAIN → HTTP $HTTP_CODE（预期 200）"
    exit 1
fi
