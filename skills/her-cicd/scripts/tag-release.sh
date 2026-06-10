#!/usr/bin/env bash
# 在 main 上打 tag 并推送
# 用法：tag-release.sh <版本号> [仓库路径]
# 示例：tag-release.sh v0.2.0 /Users/stubbornstone/Documents/Work/Code/Her-Web

set -euo pipefail

VERSION="${1:-}"
REPO_PATH="${2:-$(pwd)}"

if [[ -z "$VERSION" ]]; then
  echo "❌ 用法：tag-release.sh <版本号> [仓库路径]"
  echo "  示例：tag-release.sh v0.2.0"
  exit 1
fi

# 校验版本号格式
if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "❌ 版本号格式不对，应为 v主.次.修（如 v0.2.0）"
  echo "  收到的是：$VERSION"
  exit 1
fi

cd "$REPO_PATH"
REPO_NAME=$(basename "$REPO_PATH")

echo "📦 仓库：$REPO_NAME ($REPO_PATH)"
echo "🏷️  版本：$VERSION"
echo ""

# 拉最新
git fetch origin

# 检查是否在 main 上
CURRENT_BRANCH=$(git branch --show-current)
if [[ -z "$CURRENT_BRANCH" ]]; then
  echo "❌ 当前处于 detached HEAD 状态，必须在 main 上打 tag"
  echo "  先执行：git checkout main"
  exit 1
fi
if [[ "$CURRENT_BRANCH" != "main" ]]; then
  echo "❌ 当前在 $CURRENT_BRANCH，必须在 main 上打 tag"
  exit 1
fi

# 检查本地 main 是否和远程一致
LOCAL_HEAD=$(git rev-parse HEAD)
REMOTE_HEAD=$(git rev-parse origin/main)
if [[ "$LOCAL_HEAD" != "$REMOTE_HEAD" ]]; then
  echo "❌ 本地 main 和远程不一致"
  echo "  本地：$(git rev-parse --short HEAD)"
  echo "  远程：$(git rev-parse --short origin/main)"
  echo "  先 git pull origin main"
  exit 1
fi

# 检查 tag 是否已存在
if git rev-parse "$VERSION" &>/dev/null; then
  echo "❌ tag $VERSION 已存在"
  echo "  指向：$(git rev-parse --short "$VERSION")"
  exit 1
fi

# 显示最近的 tag
LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "无")
echo "  最近的 tag：$LATEST_TAG"
echo "  将要 tag 的 commit：$(git rev-parse --short HEAD)"
echo ""

# 显示自上个 tag 以来的 commit
if [[ "$LATEST_TAG" != "无" ]]; then
  echo "📋 自 $LATEST_TAG 以来的变更："
  git log --oneline "$LATEST_TAG"..HEAD | head -20
  echo ""
fi

# 执行前输出将要做什么
echo "→ 打 tag $VERSION 并推送"

# 打 tag 并推送
echo "→ 打 tag $VERSION..."
git tag "$VERSION"

echo "→ 推送 tag..."
git push origin "$VERSION"

echo ""
echo "✅ tag $VERSION 已推送"

# 检查仓库是否有 CI workflow
if ls .github/workflows/*.yml .github/workflows/*.yaml &>/dev/null 2>&1; then
  echo "   CI 将自动构建 GHCR 镜像 + 创建 draft Release"
  echo ""
  echo "下一步："
  echo "  1. 等 CI 完成（GitHub Actions 页面查看）"
  echo "  2. 跑部署脚本部署到生产"
  echo "  3. 去 GitHub Releases 补 release notes"
else
  echo "   该仓库无 CI workflow，跳过镜像构建"
  echo ""
  echo "下一步："
  echo "  1. 本地构建（如 salon: build-macos-local.sh）"
  echo "  2. 部署 / 上传"
fi
