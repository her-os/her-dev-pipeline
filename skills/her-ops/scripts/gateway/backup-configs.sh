#!/bin/bash
# Her Gateway 配置备份
# 用法: bash scripts/backup-configs.sh
# 从服务器拉取关键配置到本地 backups/ 目录

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SSH="/usr/bin/ssh ubuntu@192.144.187.174"
SCP="/usr/bin/scp"
DATE=$(date +%Y-%m-%d)
BACKUP_DIR="${SKILL_DIR}/backups/${DATE}"

echo "=== Her Gateway 配置备份 ==="
echo "目标: ${BACKUP_DIR}"
echo ""

mkdir -p "${BACKUP_DIR}"

# 1. docker-compose.yml（Dokploy 管理的版本）
echo "▸ 拉取 docker-compose.yml"
$SSH "sudo cat /etc/dokploy/compose/her-newapi-e91gqn/code/docker-compose.yml" > "${BACKUP_DIR}/docker-compose.yml" 2>/dev/null && echo "  ✓" || echo "  ✗ 失败"

# 2. Traefik 主配置
echo "▸ 拉取 traefik.yml"
$SSH "sudo cat /etc/dokploy/traefik/traefik.yml" > "${BACKUP_DIR}/traefik.yml" 2>/dev/null && echo "  ✓" || echo "  ✗ 失败"

# 3. Traefik 动态配置（排除 acme.json，那个太大且含证书私钥）
echo "▸ 拉取 Traefik 动态配置"
mkdir -p "${BACKUP_DIR}/traefik-dynamic"
$SSH "sudo ls /etc/dokploy/traefik/dynamic/ 2>/dev/null" | while read -r FILE; do
  if [ "$FILE" != "acme.json" ]; then
    $SSH "sudo cat /etc/dokploy/traefik/dynamic/${FILE}" > "${BACKUP_DIR}/traefik-dynamic/${FILE}" 2>/dev/null
  fi
done
echo "  ✓ (acme.json 已跳过)"

# 4. 容器 labels 快照（Dokploy 注入的路由配置）
echo "▸ 快照 new-api 容器 labels"
$SSH "sudo docker inspect new-api --format '{{json .Config.Labels}}'" > "${BACKUP_DIR}/new-api-labels.json" 2>/dev/null && echo "  ✓" || echo "  ✗ 失败"

# 5. 运行中容器列表
echo "▸ 快照容器状态"
$SSH "sudo docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'" > "${BACKUP_DIR}/docker-ps.txt" 2>/dev/null && echo "  ✓" || echo "  ✗ 失败"

# 6. ACME 证书清单（只记域名，不拉私钥）
echo "▸ 快照 SSL 证书清单"
$SSH "sudo cat /etc/dokploy/traefik/dynamic/acme.json" 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    le = d.get("letsencrypt", {})
    certs = le.get("Certificates", []) or []
    for c in certs:
        print(f"  {c[\"domain\"][\"main\"]}")
except:
    print("  解析失败")
' > "${BACKUP_DIR}/ssl-certs-list.txt" 2>/dev/null && echo "  ✓" || echo "  ✗ 失败"

echo ""
echo "=== 备份完成: ${BACKUP_DIR} ==="
ls -la "${BACKUP_DIR}/"
