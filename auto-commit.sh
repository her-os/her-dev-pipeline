#!/usr/bin/env bash
# 定时自动提交：launchd 每小时跑一次（cn.hersoul.skills-autocommit）。
# 1) her-dev-pipeline（共享源）：commit + pull --rebase + push
# 2) ~/.claude/skills（本地审计快照）：仅 commit，不推远端
set -uo pipefail

LOG="$HOME/Library/Logs/skills-autocommit.log"
GIT=/usr/bin/git

ts() { date '+%Y-%m-%d %H:%M:%S'; }

commit_repo() {
  local dir="$1" do_push="$2"
  cd "$dir" || return 1
  if [ -z "$($GIT status --porcelain)" ]; then
    return 0
  fi
  local files
  files=$($GIT status --porcelain | awk '{print $2}' | head -10 | tr '\n' ' ')
  $GIT add -A
  $GIT commit -q -m "auto: $(ts) — $files" || return 1
  echo "$(ts) committed in $dir: $files" >> "$LOG"
  if [ "$do_push" = "push" ]; then
    # 先 rebase 远端改动再推；rebase 冲突则放弃推送，本地 commit 保留，下轮重试
    if $GIT pull --rebase --autostash -q 2>>"$LOG"; then
      $GIT push -q 2>>"$LOG" && echo "$(ts) pushed $dir" >> "$LOG" \
        || echo "$(ts) PUSH FAILED $dir" >> "$LOG"
    else
      $GIT rebase --abort 2>/dev/null
      echo "$(ts) REBASE CONFLICT in $dir — push skipped, resolve manually" >> "$LOG"
    fi
  fi
}

commit_repo "$HOME/Documents/her-source/her-dev-pipeline" push
commit_repo "$HOME/.claude/skills" local
