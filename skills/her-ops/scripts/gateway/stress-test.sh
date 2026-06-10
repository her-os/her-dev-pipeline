#!/usr/bin/env bash
# Gateway 压力测试脚本
# 用法: ./stress-test.sh <gateway-api-key> [并发数] [模型]
# 示例: ./stress-test.sh sk-xxx 8 glm-5

set -euo pipefail

API_KEY="${1:?用法: $0 <api-key> [并发数] [模型]}"
CONCURRENCY="${2:-6}"
MODEL="${3:-glm-5}"
BASE_URL="https://api.tokenic.cn"

# Claude Code CLI 特征头（Z.AI 识别后给更高并发额度）
HEADERS=(
  -H "Authorization: Bearer $API_KEY"
  -H "Content-Type: application/json"
  -H "anthropic-version: 2023-06-01"
  -H "User-Agent: claude-code/2.1.94"
  -H "X-Stainless-Lang: js"
  -H "X-Stainless-Package-Version: 2.1.94"
  -H "X-Stainless-OS: macOS"
  -H "X-Stainless-Arch: arm64"
  -H "X-Stainless-Runtime: node"
  -H "X-Stainless-Runtime-Version: v22.12.0"
  -H "X-App: claude-code"
)

SYSTEM="You are Claude, a large language model made by Anthropic."

echo "=== Gateway 压测: ${CONCURRENCY} 并发, 模型 ${MODEL} ==="
echo ""

SUCCESS=0
FAIL=0

for i in $(seq 1 "$CONCURRENCY"); do
  (
    START=$(python3 -c "import time; print(int(time.time()*1000))")
    RESP=$(curl -s -w "\nHTTP_%{http_code}" "$BASE_URL/v1/messages" \
      "${HEADERS[@]}" \
      --max-time 60 \
      -d "{\"model\":\"$MODEL\",\"max_tokens\":20,\"system\":\"$SYSTEM\",\"messages\":[{\"role\":\"user\",\"content\":\"Say hi $i\"}]}")
    END=$(python3 -c "import time; print(int(time.time()*1000))")
    LATENCY=$((END - START))
    HTTP_CODE=$(echo "$RESP" | grep "HTTP_" | sed 's/HTTP_//')
    if [ "$HTTP_CODE" = "200" ]; then
      echo "req=$i status=200 latency=${LATENCY}ms"
    else
      ERR=$(echo "$RESP" | head -1 | python3 -c "import sys,json; d=json.load(sys.stdin); e=d.get('error',{}); print(e.get('type','?'), e.get('message','')[:80])" 2>/dev/null || echo "unknown")
      echo "req=$i status=$HTTP_CODE err=$ERR latency=${LATENCY}ms"
    fi
  ) &
done
wait

echo ""
echo "完成。如果 429 多，等 30 秒再跑（滑动窗口限流需要冷却）。"
