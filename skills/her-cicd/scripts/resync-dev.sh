#!/usr/bin/env bash
# 重置 dev 分支到纯 main（commit-tree 方式，因 dev 受保护不能 force-push）。
# 用法：resync-dev.sh [仓库路径]
# 典型场景：release.sh 部署生产后自动调用；也可手动运行。
#
# 流程：
#   1. 检查 dev 是否已同步 main（空 diff 则退出）
#   2. 备份当前 dev 到 backup/dev-<timestamp>
#   3. 清理 7 天前的 backup/dev-* 远端分支
#   4. commit-tree 造重置 commit（dev 树 = main）
#   5. 推送临时分支，开 PR → dev，admin merge
#   6. 打印提示：若有在测 feat，手动 merge feat→dev

set -euo pipefail

REPO_PATH="${1:-$(pwd)}"
cd "$REPO_PATH"
REPO_NAME=$(basename "$REPO_PATH")

echo "🔄 resync-dev: $REPO_NAME ($REPO_PATH)"
echo ""

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: resync-dev.sh requires GitHub CLI (gh)" >&2
  exit 1
fi

# --- 1. Fetch & check ---
echo "→ 拉取最新远程状态..."
git fetch origin

if ! git ls-remote --exit-code --heads origin dev >/dev/null 2>&1; then
  echo "ERROR: 远程没有 dev 分支" >&2
  exit 1
fi

# 用 diff-tree 检查实际文件差异（比 rev-list 可靠——merge commit 可能虚增 commit 数）
DIFF_STAT="$(git diff --stat origin/main origin/dev 2>/dev/null || true)"
if [[ -z "$DIFF_STAT" ]]; then
  echo "✅ dev 与 main 文件树相同，无需重置"
  exit 0
fi

echo "  dev 与 main 存在文件差异："
echo "$DIFF_STAT" | head -10
echo ""

# --- 2. 备份当前 dev ---
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_REF="backup/dev-${TIMESTAMP}"
echo "→ 备份 dev 到 ${BACKUP_REF}..."
git push origin "origin/dev:refs/heads/${BACKUP_REF}"

# --- 3. Prune 7 天前的 backup/dev-* ---
echo "→ 清理 7 天前的 backup/dev-* 远端分支..."
CUTOFF_EPOCH="$(date -v-7d +%s 2>/dev/null || date -d '7 days ago' +%s)"
for ref in $(git for-each-ref --format='%(refname:short)' 'refs/remotes/origin/backup/dev-*'); do
  # 提取时间戳部分：backup/dev-YYYYMMDD-HHMMSS
  TS_PART="${ref##*/dev-}"
  # 解析 YYYYMMDD-HHMMSS → epoch
  if [[ "$TS_PART" =~ ^([0-9]{4})([0-9]{2})([0-9]{2})-([0-9]{2})([0-9]{2})([0-9]{2})$ ]]; then
    REF_DATE="${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}T${BASH_REMATCH[4]}:${BASH_REMATCH[5]}:${BASH_REMATCH[6]}"
    REF_EPOCH="$(date -jf '%Y-%m-%dT%H:%M:%S' "$REF_DATE" +%s 2>/dev/null || date -d "$REF_DATE" +%s 2>/dev/null || echo 0)"
    if [[ "$REF_EPOCH" -gt 0 && "$REF_EPOCH" -lt "$CUTOFF_EPOCH" ]]; then
      REMOTE_BRANCH="${ref#origin/}"
      echo "  🗑️  删除过期备份: $REMOTE_BRANCH"
      git push origin --delete "$REMOTE_BRANCH" 2>/dev/null || true
    fi
  fi
done

# --- 4. commit-tree 重置 ---
echo "→ 构造重置 commit（dev 树 = main）..."
MAIN_TREE="$(git rev-parse origin/main^{tree})"
RESET_COMMIT="$(git commit-tree "$MAIN_TREE" \
  -p origin/dev \
  -p origin/main \
  -m "chore: resync dev to main (post-release)

Resets dev tree to match main exactly.
Backup: ${BACKUP_REF}")"

# 安全检查：重置 commit 与 main 应零 diff
VERIFY_DIFF="$(git diff --stat "$RESET_COMMIT" origin/main 2>/dev/null || true)"
if [[ -n "$VERIFY_DIFF" ]]; then
  echo "ERROR: 重置 commit 与 main 有差异，中止！" >&2
  echo "$VERIFY_DIFF" >&2
  exit 1
fi

# --- 5. 推送 & 开 PR ---
BRANCH_NAME="chore/resync-dev-${TIMESTAMP}"
echo "→ 推送 ${BRANCH_NAME}..."
git push origin "${RESET_COMMIT}:refs/heads/${BRANCH_NAME}"

REPO_SLUG="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
echo "→ 创建 PR: ${BRANCH_NAME} → dev..."
PR_URL="$(gh pr create \
  --repo "$REPO_SLUG" \
  --base dev \
  --head "$BRANCH_NAME" \
  --title "chore: resync dev to main (post-release)" \
  --body "Automated dev reset after production release.

Dev tree is now identical to main. Backup: \`${BACKUP_REF}\`.

If you have a feat branch under testing, re-merge it:
\`\`\`bash
git fetch origin dev && git checkout dev && git pull && git merge feat/your-branch && git push
\`\`\`" \
  )"

echo "→ Admin merge PR..."
gh pr merge "$PR_URL" --admin --merge --delete-branch

echo ""
echo "✅ dev 已重置到 main"
echo "   备份: ${BACKUP_REF}"
echo "   PR: ${PR_URL}"
echo ""
echo "⚠️  若有在测 feat 分支，请手动重新合入 dev："
echo "   git fetch origin dev"
echo "   git switch dev && git pull"
echo "   git merge feat/your-branch"
echo "   git push origin dev"
