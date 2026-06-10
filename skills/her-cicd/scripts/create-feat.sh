#!/usr/bin/env bash
# 从 main 创建功能分支并推到远程
# 用法：create-feat.sh <分支名> [仓库路径]
# 示例：create-feat.sh feat/new-payment /Users/stubbornstone/Documents/Work/Code/Her-Web

set -euo pipefail

BRANCH_NAME="${1:-}"
REPO_PATH="${2:-$(pwd)}"

if [[ -z "$BRANCH_NAME" ]]; then
  echo "❌ 用法：create-feat.sh <分支名> [仓库路径]"
  echo "  分支名格式：feat/xxx | fix/xxx | hotfix/xxx | engine/xxx"
  exit 1
fi

# 校验分支命名
if [[ ! "$BRANCH_NAME" =~ ^(feat|fix|hotfix|engine)/ ]]; then
  echo "❌ 分支名必须以 feat/ fix/ hotfix/ engine/ 开头"
  echo "  收到的是：$BRANCH_NAME"
  exit 1
fi

cd "$REPO_PATH"
REPO_NAME=$(basename "$REPO_PATH")

echo "📦 仓库：$REPO_NAME ($REPO_PATH)"
echo "🌿 分支：$BRANCH_NAME"
echo ""

# 切到 main 并拉最新
echo "→ 切到 main 并拉最新..."
git checkout main
git pull origin main

# 检查分支是否已存在
if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME" 2>/dev/null; then
  echo "❌ 本地已有分支 $BRANCH_NAME"
  exit 1
fi
if git ls-remote --exit-code --heads origin "$BRANCH_NAME" &>/dev/null; then
  echo "❌ 远程已有分支 $BRANCH_NAME"
  exit 1
fi

# 创建并推送
echo "→ 创建分支 $BRANCH_NAME..."
git checkout -b "$BRANCH_NAME"

echo "→ 推送到远程..."
git push -u origin "$BRANCH_NAME"

echo ""
echo "✅ 分支 $BRANCH_NAME 已创建并推送"
echo "   基于 main commit：$(git rev-parse --short HEAD)"
