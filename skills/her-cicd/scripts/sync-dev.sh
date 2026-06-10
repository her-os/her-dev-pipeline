#!/usr/bin/env bash
# 创建 main -> dev 同步 PR，不直接改 dev。
# 用法：sync-dev.sh [仓库路径]
# 示例：sync-dev.sh /path/to/repo

set -euo pipefail

REPO_PATH="${1:-$(pwd)}"

cd "$REPO_PATH"
REPO_NAME=$(basename "$REPO_PATH")

echo "📦 仓库：$REPO_NAME ($REPO_PATH)"
echo ""

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: sync-dev.sh requires GitHub CLI (gh) to create the PR" >&2
  exit 1
fi

echo "→ 拉取最新远程状态..."
git fetch origin

if ! git ls-remote --exit-code --heads origin dev >/dev/null 2>&1; then
  echo "ERROR: 远程没有 dev 分支，先通过 PR 或仓库设置创建 dev" >&2
  exit 1
fi

behind=$(git rev-list --count origin/main..origin/dev 2>/dev/null || echo "?")
ahead=$(git rev-list --count origin/dev..origin/main 2>/dev/null || echo "?")
echo "  dev 比 main 多 $behind 个 commit"
echo "  dev 比 main 少 $ahead 个 commit"
echo ""

if [[ "$ahead" == "0" ]]; then
  echo "✅ dev 已包含 origin/main，无需同步 PR"
  exit 0
fi

branch="chore/sync-dev-main-$(date +%Y%m%d%H%M%S)"
worktree="/tmp/her-sync-dev-main-$$"

cleanup() {
  git worktree remove "$worktree" --force >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "→ 创建同步分支：$branch"
git worktree add -b "$branch" "$worktree" origin/dev

echo "→ 合并 origin/main 到 $branch"
git -C "$worktree" merge --no-ff origin/main -m "merge: sync dev with main"

echo "→ 推送同步分支"
git -C "$worktree" push -u origin "$branch"

echo "→ 创建 PR：$branch → dev"
pr_url=$(gh pr create \
  --repo "$(gh repo view --json nameWithOwner -q .nameWithOwner)" \
  --base dev \
  --head "$branch" \
  --title "chore: sync dev with main" \
  --body "Sync \`dev\` with \`main\` through a protected PR. This intentionally avoids force-pushing \`dev\`." \
  --json url \
  -q .url)

echo ""
echo "✅ 已创建 dev 同步 PR"
echo "   $pr_url"
echo "   等 CI 通过后合入，再从 origin/dev 部署 test。"
