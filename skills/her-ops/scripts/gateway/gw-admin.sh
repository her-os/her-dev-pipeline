#!/bin/bash
# gw-admin.sh — her-gateway Admin API 快捷调用
#
# 用法:
#   gw-admin.sh GET /api/channel/
#   gw-admin.sh GET /api/user/303/quota
#   gw-admin.sh PUT /api/user/303/quota -d '{"quota":100000}'
#   gw-admin.sh POST /api/user/303/token -d '{"name":"test","remain_quota":50000}'
#
# 凭证文件: ~/.config/her/gateway-admin.env

set -euo pipefail

ENV_FILE="${HER_GW_ENV:-$HOME/.config/her/gateway-admin.env}"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: 凭证文件不存在: $ENV_FILE" >&2
  echo "创建方法: 见 her-ops/references/gateway/admin-api.md" >&2
  exit 1
fi
source "$ENV_FILE"

METHOD="${1:?用法: gw-admin.sh METHOD /api/path [curl-args...]}"
PATH_ARG="${2:?用法: gw-admin.sh METHOD /api/path [curl-args...]}"
shift 2

curl -s -X "$METHOD" \
  -H "Authorization: ${HER_GW_TOKEN}" \
  -H "New-Api-User: ${HER_GW_USER}" \
  -H "Content-Type: application/json" \
  "${HER_GW_BASE}${PATH_ARG}" \
  "$@"
