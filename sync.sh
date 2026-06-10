#!/usr/bin/env bash
# ⚠️ 已废弃（2026-06-11）：本仓库现在是 skill 的唯一源。
# ~/.claude/skills/ 里的共享 skill 已软链接到本仓库 skills/，
# ~/.codex/skills/ 再软链到 ~/.claude/skills/，改动直接落在 git 工作区。
# 不再需要 rsync 同步；改完 skill 直接在本仓库 git add / commit / push。
echo "sync.sh 已废弃：skills 已软链到本仓库，直接 git commit + push 即可。"
exit 1
