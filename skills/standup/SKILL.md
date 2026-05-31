---
name: standup
description: Task manager that triages new issues and recommends what to work on next. Combines inbox processing (triage new issues) with a panoramic view of all open work. Use when user says "standup", "what should I work on", "show me what needs attention", "triage everything", or at the start of a coding session.
---

# Standup

Your job is to help the user decide **what to work on next**. You do this by collecting scattered context, investigating open issues in depth, and presenting a clear picture for joint decision-making.

You are not a project management dashboard. You are a decision aid. Every output should move the user closer to a confident "I'm doing X next because Y."

## Reference docs

- [Business Map](./BUSINESS-MAP.md) — **必读**，跨仓库业务逻辑地图，用于 issue 分诊路由
- [Issue tracker conventions](../../docs/agents/issue-tracker.md)
- [Triage labels](../../docs/agents/triage-labels.md)
- [Agent Brief format](../triage/AGENT-BRIEF.md) — used when an issue reaches `ready-for-agent`
- [Out-of-Scope knowledge base](../triage/OUT-OF-SCOPE.md) — used when rejecting an enhancement

## Labels

Standup works with these label groups. Create any missing labels on first use.

**Category** (one per issue): `bug`, `enhancement`

**Triage state** (one per issue): `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`

**Work state**: `in-progress` (applied when someone starts working on an issue)

**Priority** (one per issue): `P0`, `P1`, `P2`

Priority is a judgment call. Here are calibration examples — use them as anchors, not rigid rules:

- **P0**: Blocks users from completing core flows. Data loss or corruption. Production down. Security vulnerability.
- **P1**: Degrades experience but users can work around it. Important feature gap that active users are asking for.
- **P2**: Nice-to-have improvements. Cleanup. Non-urgent tech debt.

## Sync

Before any phase, run the sync script to pull latest GitHub state and push back any board changes:

```bash
bash "$(dirname "$0")/sync-github.sh"
```

This handles:
- GitHub → Board: new issues, label/priority updates, closed → done, in-progress label → 进行中 column
- Board → GitHub: priority labels, in-progress label writeback

## Process

Run all four phases in order. Phase 2 can be skipped if there are no untriaged issues.

### Phase 1: Intake

Before scanning issues, ask the user directly:

> "Anything new since last time? Customer fires, things you promised someone, ideas stuck in your head?"

If the user mentions something:
- Help them capture it as a GitHub issue right there (`gh issue create`)
- Apply `needs-triage` so it enters the Phase 2 pipeline

If nothing new, move on.

The goal is to close the gap between what's in the user's head and what's in the issue tracker. Every time standup runs, the issue pool gets more complete.

### Phase 2: Parallel Recon

Gather all issues that need triage: anything labeled `needs-triage`, or unlabeled (no category + no state label), or `needs-info` with new reporter activity since the last triage note.

**Skip if no untriaged issues.** Already-triaged issues (those with a priority label + a state label) do not need recon again.

For **each** untriaged issue, launch a subagent to investigate. Group by repo — one subagent per repo batch. Each subagent must:

1. Read `BUSINESS-MAP.md` (same directory as this SKILL.md) to understand the cross-repo business domains and issue routing rules
2. Read the full issue (body + all comments)
3. Check `.out-of-scope/` for prior rejections of similar concepts
4. Search the codebase for relevant code (types, functions, routes, config mentioned or implied by the issue)
5. Check for related open issues (duplicates, dependencies, same area of code)
6. Return a structured recon report:
   - **One-line summary**: what this issue is really asking for
   - **Category**: `bug` or `enhancement`
   - **Codebase findings**: which modules/areas are involved, how complex the change looks
   - **Related issues**: duplicates or logical dependencies found
   - **Priority recommendation**: P0 / P1 / P2 with reasoning
   - **State recommendation**: ready-for-agent / ready-for-human / needs-info / wontfix
   - **Open questions**: anything the subagent couldn't determine from the issue + code alone

Wait for all subagents to return before proceeding.

### Phase 3: Joint Triage

Present all recon reports to the user in a single view. For each issue, show:

```
#N — [one-line summary]
Category: bug | enhancement
Codebase: [which areas, estimated complexity]
Related: [duplicate of #X / depends on #Y / none]
Open questions: [if any]
My read: P0/P1/P2 — [reasoning in 1-2 sentences]
State: ready-for-agent / ready-for-human / needs-info
```

Then work through them with the user:

- **Priority**: present your recommendation, let the user confirm or override.
- **State**: for each issue, follow the triage process defined in [triage SKILL.md](../triage/SKILL.md).
- **Duplicates**: if recon found duplicates, suggest closing one with a reference to the other.
- **Dependencies**: note them in your panorama (Phase 4), don't add to issue bodies.

### Phase 3.5: Apply Labels

After the user confirms (or overrides) priorities and states, batch-apply all labels to GitHub in one pass:

```bash
gh issue edit <N> --repo <repo> --add-label "<priority>,<state>" [--remove-label "needs-triage"]
```

Do NOT apply labels one-by-one during discussion. Collect all decisions first, then execute.
The next `sync-github.sh` run will propagate these labels to the board automatically.

### Phase 4: Panorama

Fetch all open issues with their labels and recent activity. Present them grouped by priority:

```
━━━ P0 (count) ━━━
#N summary [state] [context: who's working on it / what's blocking it]
...

━━━ P1 (count) ━━━
...

━━━ P2 (count) ━━━
...

━━━ Unprioritized (count) ━━━
...
```

For `in-progress` issues, check recent activity (comments, linked PRs, commits referencing the issue number) to give a sense of whether they're moving or stalled.

End with a clear recommendation:

> "I recommend working on **#N** next. [Reasoning: why this over alternatives — priority, unblocked status, dependencies it would unblock, user context from Phase 1.]"
>
> If there are multiple good candidates, present 2-3 options with trade-offs and ask the user to pick.

## Three operating modes

This skill serves three use cases:

- **Session start** (full run): Run all four phases. Takes a few minutes. Use at the beginning of a work session to get oriented.
- **Quick check** (Phase 4 only): Skip intake and triage, just show the panorama and recommendation. Use when switching contexts mid-session. Invoke with "quick standup" or "what should I work on next?"
- **Triage only** (Phase 2-3 only): When new issues come in mid-session and need quick triage. Invoke with "triage the new issues".

## What this skill does NOT do

- **Plan how to implement an issue** — that's `/grill-with-docs` then `/to-prd`
- **Write code** — that's the execution layer (Codex or direct coding)
- **Track detailed progress within a task** — that's the responsibility of the session working on the task
- **Replace human priority judgment** — it recommends, the user decides
