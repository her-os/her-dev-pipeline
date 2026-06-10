#!/bin/bash
# Her Gateway 健康检查
# 用法: bash scripts/health-check.sh
# 检查所有服务状态、SSL 证书、API 响应

set -euo pipefail

SSH="/usr/bin/ssh ubuntu@192.144.187.174"

pass() { echo "  [OK] $1"; }
fail() { echo "  [FAIL] $1"; FAILURES=$((FAILURES + 1)); }
warn() { echo "  [WARN] $1"; }

FAILURES=0

echo "=== Her Gateway 健康检查 ==="
echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# 1. SSH 连通性
echo "[1/6] SSH 连通性"
if $SSH "echo ok" >/dev/null 2>&1; then
  pass "SSH 连接正常"
else
  fail "SSH 连接失败"
  echo "后续检查无法执行，退出"
  exit 1
fi

# 2. 容器状态
echo "[2/6] 容器状态"
CONTAINERS=$($SSH "sudo docker ps --format '{{.Names}}|{{.Status}}'" 2>/dev/null)
for EXPECTED in new-api redis dokploy-traefik; do
  LINE=$(echo "$CONTAINERS" | grep "^${EXPECTED}|" || true)
  if [ -n "$LINE" ]; then
    STATUS=$(echo "$LINE" | cut -d'|' -f2)
    if echo "$STATUS" | grep -q "Up"; then
      pass "$EXPECTED: $STATUS"
    else
      fail "$EXPECTED: $STATUS"
    fi
  else
    fail "$EXPECTED: 未运行"
  fi
done

# 3. API 响应
echo "[3/6] API 响应"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 --insecure https://api.tokenic.cn/api/status 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
  pass "api.tokenic.cn /api/status → 200"
else
  fail "api.tokenic.cn /api/status → $HTTP_CODE"
fi

HTTP_CODE2=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 --insecure https://api.roome.cn/api/status 2>/dev/null || echo "000")
if [ "$HTTP_CODE2" = "200" ]; then
  pass "api.roome.cn /api/status → 200"
else
  fail "api.roome.cn /api/status → $HTTP_CODE2"
fi

# 4. SSL 证书
echo "[4/6] SSL 证书"
for DOMAIN in api.tokenic.cn api.roome.cn; do
  ISSUER=$(echo | openssl s_client -connect ${DOMAIN}:443 -servername ${DOMAIN} 2>/dev/null | openssl x509 -noout -issuer 2>/dev/null || echo "FAILED")
  if echo "$ISSUER" | grep -q "Let's Encrypt"; then
    EXPIRY=$(echo | openssl s_client -connect ${DOMAIN}:443 -servername ${DOMAIN} 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
    pass "$DOMAIN: Let's Encrypt (到期: $EXPIRY)"
  elif echo "$ISSUER" | grep -q "TRAEFIK DEFAULT"; then
    warn "$DOMAIN: Traefik 自签名证书（无 Let's Encrypt）"
  else
    fail "$DOMAIN: 证书检查失败 ($ISSUER)"
  fi
done

# 5. HTTP → HTTPS 重定向
echo "[5/6] HTTP 重定向"
REDIRECT=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://api.tokenic.cn 2>/dev/null || echo "000")
if [ "$REDIRECT" = "308" ] || [ "$REDIRECT" = "301" ] || [ "$REDIRECT" = "302" ]; then
  pass "HTTP → HTTPS 重定向正常 ($REDIRECT)"
else
  warn "HTTP 重定向状态: $REDIRECT"
fi

# 6. 磁盘空间
echo "[6/6] 磁盘空间"
DISK_USAGE=$($SSH "df -h / | tail -1 | awk '{print \$5}'" 2>/dev/null | tr -d '%')
if [ -n "$DISK_USAGE" ] && [ "$DISK_USAGE" -lt 80 ]; then
  pass "磁盘使用: ${DISK_USAGE}%"
elif [ -n "$DISK_USAGE" ] && [ "$DISK_USAGE" -lt 90 ]; then
  warn "磁盘使用: ${DISK_USAGE}%（接近阈值）"
else
  fail "磁盘使用: ${DISK_USAGE:-未知}%"
fi

# 汇总
echo ""
if [ "$FAILURES" -eq 0 ]; then
  echo "=== 全部通过 ==="
else
  echo "=== ${FAILURES} 项异常 ==="
fi
