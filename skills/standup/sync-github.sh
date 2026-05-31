#!/bin/bash
# sync-github.sh — 双向同步 GitHub Issues ↔ board-data.json
# 不需要 AI，直接跑：./sync-github.sh
#
# ━━━ 同步策略 ━━━
#
# GitHub → Board（拉取）：
#   - 新 issue → 待分诊列（有 in-progress label → 进行中列；已有优先级+状态 → 就绪列）
#   - 已有 issue → 更新标题、描述、标签、优先级
#   - GitHub 上有 in-progress label → 看板移到「进行中」
#   - 已关闭 issue → 移到「完成」列
#   - 本地手动创建的任务（无 github 字段）→ 不动
#
# Board → GitHub（回写）：
#   - 看板上有优先级但 GitHub 没有 → 加 P0/P1/P2 label
#   - 看板在「进行中」但 GitHub 没有 in-progress label → 加 label
#   - 看板在「完成」但 GitHub 还 open → 不自动关（需要人确认）
#
# 多仓库支持：每个仓库的 issue 用 repo 字段区分，ID 格式 gh-{repo短名}-{number}

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOARD_FILE="${1:-$SCRIPT_DIR/board-data.json}"

# ━━━ 仓库列表（短名:完整路径，用空格分隔）━━━
REPO_LIST="her-web:her-os/Her-Web her-salon:her-os/her-salon her-gateway:her-os/her-gateway herclub:her-os/herclub"

command -v gh >/dev/null 2>&1 || { echo "需要 gh CLI: brew install gh"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "需要 python3"; exit 1; }

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Fetch issues from each repo
for entry in $REPO_LIST; do
  short="${entry%%:*}"
  full="${entry#*:}"
  echo "拉取 $full ..."
  gh issue list -R "$full" --state open --limit 100 \
    --json number,title,labels,state,createdAt,updatedAt,body \
    > "$TMPDIR/${short}_open.json" 2>/dev/null || echo "[]" > "$TMPDIR/${short}_open.json"

  gh issue list -R "$full" --state closed --limit 30 \
    --json number,title,labels,state,createdAt,updatedAt,closedAt \
    > "$TMPDIR/${short}_closed.json" 2>/dev/null || echo "[]" > "$TMPDIR/${short}_closed.json"
done

# Phase 1: GitHub → Board (pull)
# Phase 2: Board → GitHub (push-back)
python3 - "$BOARD_FILE" "$TMPDIR" <<'PYEOF'
import json, sys, os, subprocess
from datetime import datetime, timedelta

board_path = sys.argv[1]
tmpdir = sys.argv[2]

REPOS = {
    "her-web": "her-os/Her-Web",
    "her-salon": "her-os/her-salon",
    "her-gateway": "her-os/her-gateway",
    "herclub": "her-os/herclub",
}

PRIORITY_LABELS = {"P0", "P1", "P2"}
STATE_LABELS = {"needs-triage", "needs-info", "ready-for-agent", "ready-for-human", "wontfix", "in-progress"}
CATEGORY_LABELS = {"bug", "enhancement"}
SYNC_LABELS = PRIORITY_LABELS | STATE_LABELS | CATEGORY_LABELS

# Load or create board
if os.path.exists(board_path):
    with open(board_path) as f:
        board = json.load(f)
else:
    board = {
        "columns": [
            {"id": "triage", "title": "待分诊"},
            {"id": "ready", "title": "就绪"},
            {"id": "in-progress", "title": "进行中"},
            {"id": "done", "title": "完成"}
        ],
        "tasks": []
    }

# Migrate old IDs and repo names
for t in board["tasks"]:
    # gh-{number} → gh-her-web-{number}
    if t["id"].startswith("gh-") and t.get("github") and not t.get("repo"):
        old_num = t["id"].replace("gh-", "")
        if old_num.isdigit():
            t["id"] = f"gh-her-web-{old_num}"
            t["repo"] = "her-web"
    # salon → her-salon
    if t.get("repo") == "salon":
        t["repo"] = "her-salon"
        t["id"] = t["id"].replace("gh-salon-", "gh-her-salon-")

existing = {}
for t in board["tasks"]:
    repo = t.get("repo")
    num = t.get("github")
    if repo and num:
        existing[(repo, num)] = t

today = datetime.now().strftime("%Y-%m-%d")
max_order = max((t.get("order", 0) for t in board["tasks"]), default=-100)

total_added = total_updated = total_closed = 0
writeback_ops = []  # (repo_full, number, add_labels, remove_labels)

# ━━━ Phase 1: GitHub → Board ━━━

for short, full in REPOS.items():
    open_path = os.path.join(tmpdir, f"{short}_open.json")
    closed_path = os.path.join(tmpdir, f"{short}_closed.json")

    with open(open_path) as f:
        open_issues = json.load(f)
    with open(closed_path) as f:
        closed_issues = json.load(f)

    added = updated = closed = 0

    for issue in open_issues:
        num = issue["number"]
        labels = [l["name"] for l in issue.get("labels", [])]
        tags = [l for l in labels if l in (SYNC_LABELS - PRIORITY_LABELS) or l.startswith("source:")]
        title = issue["title"]
        body = (issue.get("body") or "").strip()

        gh_priority = None
        for l in labels:
            if l in PRIORITY_LABELS:
                gh_priority = l
                break

        has_in_progress = "in-progress" in labels

        key = (short, num)
        if key in existing:
            t = existing[key]
            t["title"] = title
            t["description"] = body
            t["tags"] = tags
            t["updated"] = issue["updatedAt"][:10]
            # GitHub priority always wins (it's the source of truth after writeback)
            if gh_priority:
                t["priority"] = gh_priority
            # GitHub in-progress label → move to 进行中
            if has_in_progress and t["column"] in ("triage", "ready"):
                t["column"] = "in-progress"
            # Triaged issue (has priority + state label) → move from triage to ready
            elif t["column"] == "triage" and gh_priority and any(tg in tags for tg in ("ready-for-agent", "ready-for-human")):
                t["column"] = "ready"
            updated += 1
        else:
            max_order += 100
            board["tasks"].append({
                "id": f"gh-{short}-{num}",
                "title": title,
                "description": body,
                "priority": gh_priority,
                "column": "in-progress" if has_in_progress else ("ready" if gh_priority else "triage"),
                "tags": tags,
                "github": num,
                "repo": short,
                "created": issue["createdAt"][:10],
                "updated": issue["updatedAt"][:10],
                "order": max_order
            })
            added += 1

    for issue in closed_issues:
        num = issue["number"]
        key = (short, num)
        if key in existing:
            t = existing[key]
            if t["column"] != "done":
                t["column"] = "done"
                t["updated"] = today
                closed += 1

    print(f"  {short}: +{added} 新增, ~{updated} 更新, ✓{closed} 关闭")
    total_added += added
    total_updated += updated
    total_closed += closed

# ━━━ Phase 2: Board → GitHub (writeback) ━━━

# Build a quick lookup of GitHub labels per issue
gh_labels_cache = {}
for short, full in REPOS.items():
    open_path = os.path.join(tmpdir, f"{short}_open.json")
    with open(open_path) as f:
        for issue in json.load(f):
            labels = [l["name"] for l in issue.get("labels", [])]
            gh_labels_cache[(short, issue["number"])] = set(labels)

for t in board["tasks"]:
    repo = t.get("repo")
    num = t.get("github")
    if not repo or not num:
        continue
    if repo not in REPOS:
        continue

    key = (repo, num)
    gh_labels = gh_labels_cache.get(key, set())
    full = REPOS[repo]
    add_labels = []
    remove_labels = []

    # Priority writeback: board has priority, GitHub doesn't
    board_prio = t.get("priority")
    gh_prio = next((l for l in gh_labels if l in PRIORITY_LABELS), None)
    if board_prio and board_prio != gh_prio:
        if gh_prio:
            remove_labels.append(gh_prio)
        add_labels.append(board_prio)

    # In-progress writeback: board column is in-progress, GitHub lacks label
    if t.get("column") == "in-progress" and "in-progress" not in gh_labels:
        add_labels.append("in-progress")
    # Reverse: board moved out of in-progress, remove GitHub label
    if t.get("column") != "in-progress" and "in-progress" in gh_labels:
        remove_labels.append("in-progress")

    if add_labels or remove_labels:
        writeback_ops.append((full, num, add_labels, remove_labels))

# Execute writebacks
wb_count = 0
for full, num, add_labels, remove_labels in writeback_ops:
    cmd_parts = ["gh", "issue", "edit", str(num), "--repo", full]
    if add_labels:
        cmd_parts += ["--add-label", ",".join(add_labels)]
    if remove_labels:
        cmd_parts += ["--remove-label", ",".join(remove_labels)]
    try:
        subprocess.run(cmd_parts, capture_output=True, timeout=15)
        wb_count += 1
    except Exception as e:
        print(f"  ⚠ writeback failed: {full}#{num}: {e}")

# Purge done items older than 7 days
cutoff = datetime.now() - timedelta(days=7)
before_count = len(board["tasks"])
board["tasks"] = [
    t for t in board["tasks"]
    if not (
        t.get("column") == "done"
        and t.get("github")
        and t.get("updated", t.get("created", ""))[:10] < cutoff.strftime("%Y-%m-%d")
    )
]
purged = before_count - len(board["tasks"])

# Sort tasks: by column order, then by priority (P0 first), then by creation date
COL_ORDER = {"triage": 0, "ready": 1, "in-progress": 2, "done": 3}
PRIO_ORDER = {"P0": 0, "P1": 1, "P2": 2}
board["tasks"].sort(key=lambda t: (
    COL_ORDER.get(t.get("column", "ready"), 9),
    PRIO_ORDER.get(t.get("priority"), 3),
    t.get("created", "9999"),
))
for i, t in enumerate(board["tasks"]):
    t["order"] = i * 100

with open(board_path, "w") as f:
    json.dump(board, f, ensure_ascii=False, indent=2)

print(f"合计: +{total_added} 新增, ~{total_updated} 更新, ✓{total_closed} 关闭, ↩{wb_count} 回写, 🗑{purged} 过期清理")
print(f"总计 {len(board['tasks'])} 个任务")
PYEOF
