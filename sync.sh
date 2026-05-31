#!/usr/bin/env bash
# 从本地 ~/.claude/skills/ 同步 14 个 skill 到本仓库，然后 commit + push。
# 用法：bash sync.sh [commit message]
#   无参数时自动生成 message

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"

SKILLS=(
  standup
  grill-with-docs
  prototype
  to-prd
  tdd
  mp-review
  thermo-nuclear-code-quality-review
  e2e-verify
  bugfix
  functional-test
  handoff
  improve-codebase-architecture
  her-dev-teammate
  code-map
  setup-matt-pocock-skills
)

changed=()

for s in "${SKILLS[@]}"; do
  src="$SKILLS_DIR/$s"
  dst="$REPO_DIR/skills/$s"

  if [ ! -d "$src" ]; then
    echo "⚠️  跳过 $s（本地不存在）"
    continue
  fi

  # rsync 同步，删除仓库中多余的文件
  if rsync -rc --delete --dry-run "$src/" "$dst/" 2>/dev/null | grep -q .; then
    rsync -rc --delete "$src/" "$dst/"
    changed+=("$s")
  fi
done

if [ ${#changed[@]} -eq 0 ]; then
  echo "✅ 无变更，本地和仓库已同步。"
  exit 0
fi

echo "📦 已同步 ${#changed[@]} 个 skill："
printf "   • %s\n" "${changed[@]}"

cd "$REPO_DIR"
git add -A

msg="${1:-sync: ${changed[*]}}"
git commit -m "$msg"
git push

echo "✅ 已推送到 GitHub。"
