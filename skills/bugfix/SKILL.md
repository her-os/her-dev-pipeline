---
name: bugfix
description: >
  All bugs start here. Disciplined 7-phase diagnosis loop (Phase 0-6) for bugs and performance regressions.
  Load context → build feedback loop → reproduce → hypothesise → instrument → fix → knowledge capture.
  Use when user says "bugfix" / "fix this bug" / reports a bug / says something is broken/throwing/failing /
  describes a performance regression, or when E2E verification fails.
---

# /bugfix

All bugs start here. Skip phases only when explicitly justified.

Core methodology: Matt Pocock's 6-phase diagnose loop (Phase 1-6), unchanged.
Enhancements wrap around it: Phase 0 (context loading), Phase 3 (prototype escape hatch),
Phase 6 (knowledge capture + path escalation), multi-session support, and skill handoffs.

### Phase declaration rule (MANDATORY)

Every phase transition must be explicitly declared in output. Do not silently merge or skip phases.

- **Entering**: `## Entering Phase N — <phase name>`
- **Completing**: `## Phase N complete — <one-line summary of what was accomplished>`

This applies to ALL phases (0 through 6). If you find yourself writing Phase 5 content without having declared Phase 4 complete, stop — you skipped a phase.

---

## Phase 0 — Load context

Before touching code, read:

1. **CONTEXT.md** — domain terms and concept relationships for the target area (skip if not present)
2. **docs/specs/\<area\>.md** — known pitfalls, invariants, prior debugging experience (skip if not present)
3. **Relevant docs/adr/** — architectural decisions in the area (skip if not present)
4. **Bug context** — one of:
   - Bug Issue full text (symptoms, repro steps, user environment)
   - Original PRD Issue + E2E verification report (when entering from E2E failure)
   - Main thread conversation context (when bug found during development without a filed Issue)

Scope judgment: based on the bug description and involved files, decide which specs and ADRs are relevant. No mechanical path-matching — use judgment. If CONTEXT.md / docs/specs/ / docs/adr/ don't exist, proceed without them.

When entering from E2E failure: the original PRD likely has a `Knowledge Base References` section listing relevant CONTEXT.md, ADRs, and specs. Read those first — the E2E report only shows symptoms, not which specs are relevant.

If docs/specs/ contains a directly relevant pitfall record, check whether the bug matches it first.
Many "new bugs" are just another manifestation of a known pitfall.

If the Issue has a Debug Chain (see Multi-session debugging below), read the handoff and continue from the last state — do not start from scratch, do not re-test hypotheses that were already conclusively ruled out.

Do not proceed to Phase 1 until you have loaded the relevant context.

---

## Phase 1 — Build a feedback loop

**This is the skill.** Everything else is mechanical. If you have a fast, deterministic, agent-runnable pass/fail signal for the bug, you will find the cause — bisection, hypothesis-testing, and instrumentation all just consume that signal. If you don't have one, no amount of staring at code will save you.

Spend disproportionate effort here. **Be aggressive. Be creative. Refuse to give up.**

### Ways to construct one — try them in roughly this order

1. **Failing test** at whatever seam reaches the bug — unit, integration, e2e.
2. **Curl / HTTP script** against a running dev server.
3. **CLI invocation** with a fixture input, diffing stdout against a known-good snapshot.
4. **Headless browser script** (Playwright / Puppeteer) — drives the UI, asserts on DOM/console/network.
5. **Replay a captured trace.** Save a real network request / payload / event log to disk; replay it through the code path in isolation.
6. **Throwaway harness.** Spin up a minimal subset of the system (one service, mocked deps) that exercises the bug code path with a single function call.
7. **Property / fuzz loop.** If the bug is "sometimes wrong output", run 1000 random inputs and look for the failure mode.
8. **Bisection harness.** If the bug appeared between two known states (commit, dataset, version), automate "boot at state X, check, repeat" so you can `git bisect run` it.
9. **Differential loop.** Run the same input through old-version vs new-version (or two configs) and diff outputs.
10. **HITL bash script.** Last resort. If a human must click, drive _them_ with `scripts/hitl-loop.template.sh` so the loop is still structured. Captured output feeds back to you.

Build the right feedback loop, and the bug is 90% fixed.

### Iterate on the loop itself

Treat the loop as a product. Once you have _a_ loop, ask:

- Can I make it faster? (Cache setup, skip unrelated init, narrow the test scope.)
- Can I make the signal sharper? (Assert on the specific symptom, not "didn't crash".)
- Can I make it more deterministic? (Pin time, seed RNG, isolate filesystem, freeze network.)

A 30-second flaky loop is barely better than no loop. A 2-second deterministic loop is a debugging superpower.

### Non-deterministic bugs

The goal is not a clean repro but a **higher reproduction rate**. Loop the trigger 100x, parallelise, add stress, narrow timing windows, inject sleeps. A 50%-flake bug is debuggable; 1% is not — keep raising the rate until it's debuggable.

### When you genuinely cannot build a loop

Stop and say so explicitly. List what you tried. Ask the user for: (a) access to whatever environment reproduces it, (b) a captured artifact (HAR file, log dump, core dump, screen recording with timestamps), or (c) permission to add temporary production instrumentation. Do **not** proceed to hypothesise without a loop.

Do not proceed to Phase 2 until you have a loop you believe in.

---

## Phase 2 — Reproduce

Run the loop. Watch the bug appear.

Confirm:

- [ ] The loop produces the failure mode the **user** described — not a different failure that happens to be nearby. Wrong bug = wrong fix.
- [ ] The failure is reproducible across multiple runs (or, for non-deterministic bugs, reproducible at a high enough rate to debug against).
- [ ] You have captured the exact symptom (error message, wrong output, slow timing) so later phases can verify the fix actually addresses it.

Do not proceed until you reproduce the bug.

---

## Phase 3 — Hypothesise

Generate **3-5 ranked hypotheses** before testing any of them. Single-hypothesis generation anchors on the first plausible idea.

Each hypothesis must be **falsifiable**: state the prediction it makes.

> Format: "If \<X\> is the cause, then \<changing Y\> will make the bug disappear / \<changing Z\> will make it worse."

If you cannot state the prediction, the hypothesis is a vibe — discard or sharpen it.

**Show the ranked list to the user before testing.** They often have domain knowledge that re-ranks instantly ("we just deployed a change to #3"), or know hypotheses they've already ruled out. Cheap checkpoint, big time saver. Don't block on it — proceed with your ranking if the user is AFK.

### Prototype escape hatch

If a hypothesis involves complex interaction logic or state transitions, and you are not sure which fix approach is correct:
- Use `/prototype` to quickly validate the hypothesis before committing to a fix.
- Do not modify production code when you are uncertain about the fix approach.

**Trigger**: the fix involves multi-module coordination, state machine changes, or data migration. Simple single-point fixes do not need a prototype.

---

## Phase 4 — Instrument

Each probe must map to a specific prediction from Phase 3. **Change one variable at a time.**

Tool preference:

1. **Debugger / REPL inspection** if the env supports it. One breakpoint beats ten logs.
2. **Targeted logs** at the boundaries that distinguish hypotheses.
3. Never "log everything and grep".

**Tag every debug log** with a unique prefix, e.g. `[DEBUG-a4f2]`. Cleanup at the end becomes a single grep. Untagged logs survive; tagged logs die.

**Perf branch.** For performance regressions, logs are usually wrong. Instead: establish a baseline measurement (timing harness, `performance.now()`, profiler, query plan), then bisect. Measure first, fix second.

---

## Phase 5 — Fix + regression test

Write the regression test **before the fix** — but only if there is a **correct seam** for it.

> **Do not write tests that merely restate the implementation.** A test that mocks all dependencies and then asserts the mocks were called provides zero confidence — it will pass even if the implementation is completely wrong. Tests must verify observable behavior through real (or realistically integrated) code paths.

A correct seam is one where the test exercises the **real bug pattern** as it occurs at the call site. If the only available seam is too shallow (single-caller test when the bug needs multiple callers, unit test that can't replicate the chain that triggered the bug), a regression test there gives false confidence.

**If no correct seam exists, that itself is the finding.** Note it. The codebase architecture is preventing the bug from being locked down. Flag this for Phase 6.

If a correct seam exists:

1. Turn the minimised repro into a failing test at that seam.
2. Watch it fail.
3. Apply the fix.
4. Watch it pass.
5. Re-run the Phase 1 feedback loop against the original (un-minimised) scenario.

---

## Phase 6 — Cleanup + knowledge capture (NEVER SKIP)

**Phase 6 is not optional.** It is part of the fix, not a post-fix activity. A bug fix without knowledge capture will cause the same class of bug to recur. Do not exit /bugfix without completing Phase 6.

### 6a. Cleanup checklist

Required before declaring done:

- [ ] Original repro no longer reproduces (re-run the Phase 1 loop)
- [ ] Regression test passes (or absence of seam is documented)
- [ ] All `[DEBUG-...]` instrumentation removed (`grep` the prefix)
- [ ] Throwaway prototypes deleted (or moved to a clearly-marked debug location)
- [ ] The hypothesis that turned out correct is stated in the commit / PR message

### 6b. Knowledge capture — three questions

Answer all three questions. Every question must be answered, even if the answer is "none". Unanswered = defect.

**Document quality rule**: the next agent can never access this conversation. Enumerate every decision, constraint, boundary condition, and excluded alternative exhaustively — no summaries, no "highlights only", no merging similar items. Missing one item = defect. (Full rule: `docs/coding-workflow/shared/doc-quality-rules.md`)

**Q1: "What domain knowledge did I learn while fixing this bug that I didn't know before?"**
- Output: update `CONTEXT.md`
- Content: new terms, new concept relationships, corrections to old definitions
- Format: follow `CONTEXT-FORMAT.md`
- If no new discoveries: skip, record "CONTEXT.md: no update needed"

**Q2: "What pitfalls in this area should the next person writing code here know about?"**
- Output: write/update `docs/specs/<area>.md`
- Content format: `[condition] → [invariant that must hold] + [consequence of violation]`
- Example: "When modifying SubscriptionCredit.expiresAt, must sync tokenRemainQuota on the gateway side. Violation: quota mismatch between gateway and billing."
- Example: "Trial credit cleanup only triggers on first payment, not on renewal. Violation: user's historical quota zeroed on renewal."
- If no new pitfalls: skip, record "docs/specs/: no update needed"

**Q3: "What architectural improvement would fundamentally prevent this class of bug?"**
- Has a concrete suggestion: hand off to `/improve-codebase-architecture` with the specifics
- No suggestion: record "No architectural improvement needed at this time"

**Q2 vs Q3 distinction**:
- Q2 specs are **operational contracts**: "watch out for this when writing code" — for the next coding agent
- Q3 architectural improvements are **structural changes**: "this module should be redesigned" — for the architecture improvement agent/human
- They don't conflict: Q2 captures current knowledge as specs, Q3 addresses root causes on a longer timeline

### 6c. Path escalation

If during Phase 3-5 you discovered:

- **This is not a bug, it's a design flaw** → escalate to feature: `/grill-with-docs` → `/to-prd`
- **Fix scope exceeds the original Issue** → use `/her-issue` to create a new Issue tracking remaining work
- **Architectural issue worth addressing independently** → use `/her-issue` to create an architecture improvement Issue

### 6d. Methodology improvement

If during the diagnosis you noticed a flaw in the /bugfix methodology itself (a missing step, a misleading instruction, a phase that should be reordered):

- **If the user is present in the conversation**: describe the flaw and your suggested improvement directly. The user decides whether to apply it.
- **If running autonomously (agent mode)**: append the suggestion to this skill's `IMPROVEMENTS.md` file (`bugfix/IMPROVEMENTS.md`). Format:

```markdown
## <Date> — <One-line summary>

**Observed during**: <Bug Issue # or description>
**Phase affected**: <Phase number>
**Problem**: <What went wrong with the current methodology>
**Suggested change**: <Specific edit to SKILL.md>
```

---

## Multi-session debugging

### When to handoff

- Context window approaching limit (subjective: conversation is very long, tool calls slowing down)
- Same hypothesis attempted 3 times without success — need a fresh approach
- User requests switching to a new window

### Handoff format — Debug Chain

When using `/handoff`, include a Debug Chain section:

```
## Debug Chain

- Session 1 [<JSONL-filename>]: Phase 1-3 complete.
    Built failing test (test/xxx.test.ts:42).
    Ruled out hypothesis 1 (race condition), hypothesis 2 (cache stale), hypothesis 3 (wrong query).
    Hypothesis 4 (cross-module state sync) pending verification.
    Key discovery: Credit.expiresAt update does not trigger tokenSync.

- Session 2 [<JSONL-filename>] (current): Verifying hypothesis 4.
    Fix approach A (add syncToken call in updateExpiry) introduced regression —
    token double-issued on renewal.
    Next step suggestion: approach B — intercept expiresAt changes at middleware layer.
```

Each session entry must include:
1. Which Phase was reached
2. The feedback loop that was built (specific file:line)
3. Hypotheses ruled out (each + the evidence that ruled it out)
4. Hypotheses not yet verified
5. Key discoveries (new domain knowledge or code behavior)
6. Next step suggestion

### Continuation rules

A new session's /bugfix:
1. Read the handoff's Debug Chain — do not start from scratch
2. Continue from the debug chain's last state
3. Do not re-test hypotheses that were conclusively ruled out (unless new evidence overturns the ruling)
4. First verify the previous session's "next step suggestion"

### Post-mortem (triggered when debug chain has > 1 session)

After the bug is finally fixed, if the debug chain contains more than 1 session entry, automatically run a post-mortem:

**1. Review where each session got stuck**
- How many turns did Session N take? Which Phase did it stall at?
- Which hypothesis wasted the most time?

**2. Identify: what information, if available from the start, would have saved an entire session?**
- Example: "If docs/specs/billing.md had documented the Credit.expiresAt ↔ tokenSync relationship, Session 1 would not have spent time ruling out the first 3 hypotheses"

**3. Outputs**:
- Write to `docs/specs/` — so the next agent has this information from the start (Phase 0 will read it)
- Update `CONTEXT.md` — if new domain relationships were discovered
- If the flaw is in /bugfix methodology itself → follow 6d (IMPROVEMENTS.md or tell the user)

**Post-mortem vs Phase 6 knowledge capture distinction**:
- Phase 6: knowledge about **the bug itself** (domain knowledge, code pitfalls, architecture issues)
- Post-mortem: knowledge about **the debugging process** (why did it take so long? what missing information caused detours?)
- Timing: Phase 6 runs after every bug fix; post-mortem only runs after multi-session debugging

---

## Skill handoffs

### Entry points (how you get to /bugfix)

- `/standup` recommends a bug Issue → /bugfix
- E2E verification fails → /bugfix directly (no "try once first" — E2E failures go straight to /bugfix)
- `/functional-test` discovers a bug → if current window context is long → `/handoff` → new window /bugfix; otherwise /bugfix in current window
- Production user/colleague feedback → create Bug Issue → /bugfix
- During development, you hit a bug → /bugfix directly, or `/her-issue` to file an Issue first then /bugfix
- User invokes /bugfix directly

### Exit points (where you go after /bugfix)

> **Gate: Phase 6 complete?** Before taking ANY exit path below, verify Phase 6 (cleanup + knowledge capture) has been completed. If not → go back and complete Phase 6 first. No exceptions.

- **Fixed** → Phase 6 knowledge capture → return to original flow
  - If entered from E2E → re-run `/e2e-verify #N` with round M+1/3 and previous E2E report
  - If entered from functional-test → return to functional-test window, verify fix + continue remaining tests
- **Architectural issue** → `/improve-codebase-architecture`
- **Design flaw (not a bug)** → `/grill-with-docs` → `/to-prd`
- **Additional problems discovered** → `/her-issue` to file new Issues

### E2E failure → /bugfix flow

```
E2E agent reports FAIL
    │
    ▼
→ /bugfix (all E2E failures go directly to /bugfix)
    │
    ├─ Current window context still has room → /bugfix in current window
    │
    └─ Context is long → /handoff → new window /bugfix
        │
        After fix:
        1. Same window: re-run E2E directly
        2. New window: return to original window, re-run E2E
```

### functional-test → /bugfix flow

```
/functional-test discovers bug
    │
    ▼
User confirms it's a real bug (not misuse / expected behavior)
    │
    ├─ Current window context still has room → /bugfix in current window → after fix, continue /functional-test
    │
    └─ Context is long → /handoff (include test progress + bug description)
        → new window /bugfix → fix
        → return to original window /functional-test → verify fix + continue remaining tests
```
