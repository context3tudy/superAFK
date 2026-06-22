# superAFK v4 (Autonomy + Outcome-Agnostic Takeover) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a two-state autonomy label (`superafk-auto`) that lets a user pre-authorize hands-off execution from design-approval to PR, and make the superAFK takeover fire on every `finishing-a-development-branch` outcome (PR/merge/keep/discard), always leaving a handoff when unfinished.

**Architecture:** Three thin layers, unchanged in shape from v3 — (1) `scripts/gh.sh` gains `superafk-auto` label creation plus `add-auto`/`has-auto` wrappers; (2) the injected `superafk-guide` rules gain an autonomy clause and an outcome-agnostic Touchpoint-3 trigger; (3) the `superafk` worker reads/sets the label in Touchpoint 1 and rewrites Touchpoint 3 to handle any outcome. No new state files; the GitHub issue stays the single source of truth. Authority for autonomy traces to the user's opt-in, so the injected directive legally overrides superpowers' human gates without modifying superpowers.

**Tech Stack:** POSIX/bash scripts, GitHub `gh` CLI, plain-bash assertion test suite (`tests/*_test.sh` via `tests/run.sh`), mock-`gh` fixture at `tests/fixtures/bin/gh`. Skills are markdown with YAML front-matter, linted by `tests/skill_lint_test.sh`.

## Global Constraints

- **Claude Code only** — Phase-1 scope is unchanged; no other host work.
- **Never auto-close issues; humans close.** Never emit a closing keyword: `Closes #`, `Fixes #`, `Resolves #`. Never call `gh issue close`.
- **superAFK must never break superpowers.** The `preflight` degradation gate exits non-zero on missing/unauthenticated `gh` or no GitHub origin; callers do `bash "$S/gh.sh" preflight || exit 0`.
- **Label name is exactly `superafk-auto`** — two states only: present = `auto-after-design`, absent = `manual`. No intermediate levels.
- **Autonomy ceiling = open a PR; never auto-merge.** Gate 1 (design-doc approval) always stays human. Auto covers only gates 2–5 within a single design→PR cycle. No auto-resume across sessions (Phase 2).
- **Skill word budgets** (enforced by `tests/skill_lint_test.sh`): `superafk-guide` ≤ 200 words, `superafk` worker ≤ 500 words. Skill `description` must start with `Use when`.
- **Test gate:** `bash tests/run.sh` must print `ALL TESTS PASSED`. All unit tests use the mock `gh` on `PATH`; no network.

---

### Task 1: `gh.sh` autonomy label + wrappers (`superafk-auto`, `add-auto`, `has-auto`)

**Files:**
- Modify: `scripts/gh.sh` (the `ensure-labels` case + two new cases + usage string)
- Modify: `tests/fixtures/bin/gh` (mock: answer `issue view --json labels`)
- Test: `tests/gh_test.sh` (append assertions)

**Interfaces:**
- Produces (consumed by Task 3 / the worker skill):
  - `bash scripts/gh.sh ensure-labels` — now also creates the `superafk-auto` label (idempotent `--force`).
  - `bash scripts/gh.sh add-auto <issue>` — adds the `superafk-auto` label to the issue (no output).
  - `bash scripts/gh.sh has-auto <issue>` — prints exactly `auto` if the issue carries `superafk-auto`, else `manual`.
- Mock contract: the fixture `gh` prints label names (one per line) for any `--json labels` call, driven by env `GH_MOCK_LABELS` (default `superafk`).

- [ ] **Step 1: Write the failing tests**

Append to `tests/gh_test.sh`, immediately **before** the final `assert_report || exit 1` line:

```bash
# ensure-labels also creates the superafk-auto autonomy label
: > "$GH_MOCK_LOG"
bash "$GH" ensure-labels
assert_contains "$(cat "$GH_MOCK_LOG")" "label create superafk-auto" "ensure-labels creates superafk-auto"

# add-auto adds the autonomy label and never closes the issue
: > "$GH_MOCK_LOG"
bash "$GH" add-auto 42
log="$(cat "$GH_MOCK_LOG")"
assert_contains "$log" "--add-label superafk-auto" "add-auto adds superafk-auto label"
case "$log" in *close*|*--state*) bad=1;; *) bad=0;; esac
assert_eq "0" "$bad" "add-auto never closes the issue"

# has-auto reads the label: manual when absent, auto when present
assert_eq "manual" "$(bash "$GH" has-auto 42)" "has-auto returns manual when label absent"
assert_eq "auto" "$(GH_MOCK_LABELS='superafk superafk-auto' bash "$GH" has-auto 42)" "has-auto returns auto when label present"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/gh_test.sh`
Expected: FAIL — the new assertions fail (e.g. `has-auto returns auto when label present` reports `actual: [manual]` or a usage error), because the mock doesn't answer `--json labels` and `gh.sh` has no `add-auto`/`has-auto`.

- [ ] **Step 3: Teach the mock `gh` to answer `--json labels`**

Replace the entire contents of `tests/fixtures/bin/gh` with:

```bash
#!/usr/bin/env bash
# Mock gh for unit tests. Logs args to $GH_MOCK_LOG and prints canned output.
echo "$*" >> "${GH_MOCK_LOG:-/dev/null}"
case "$*" in
  *"--json labels"*) printf '%s\n' ${GH_MOCK_LABELS:-superafk}; exit 0 ;;
esac
case "$1 $2" in
  "issue create") echo "https://github.com/o/r/issues/42" ;;
  "issue view")   echo "idea body from mock" ;;   # gh issue view N --json body -q .body
  "repo view")    echo "private" ;;               # gh repo view --json visibility -q .visibility
  "label create") : ;;
  "issue comment") : ;;
  "issue edit")   : ;;
  "auth status")  : ;;
  *) : ;;
esac
exit 0
```

(The `${GH_MOCK_LABELS:-superafk}` expansion is intentionally unquoted so a space-separated list becomes one label per line.)

- [ ] **Step 4: Add the `superafk-auto` label to `ensure-labels`**

In `scripts/gh.sh`, in the `ensure-labels)` case, add a third `gh label create` line after the `finished` one:

```bash
  ensure-labels)
    gh label create superafk --description "superAFK idea tracker" --color 1f6feb --force >/dev/null
    gh label create finished --description "superAFK: idea complete (close manually)" --color 0e8a16 --force >/dev/null
    gh label create superafk-auto --description "superAFK: autonomous after design approval" --color 8250df --force >/dev/null
    ;;
```

- [ ] **Step 5: Add the `add-auto` and `has-auto` cases**

In `scripts/gh.sh`, insert these two cases after the `add-finished)` case:

```bash
  add-auto)
    gh issue edit "${1:?n}" --add-label superafk-auto >/dev/null
    ;;
  has-auto)
    if gh issue view "${1:?n}" --json labels -q '.labels[].name' | grep -qx superafk-auto; then
      echo auto
    else
      echo manual
    fi
    ;;
```

(The `grep -qx` failing inside an `if` condition is safe under `set -euo pipefail` — `set -e` does not trigger on a tested command.)

- [ ] **Step 6: Update the usage string**

In `scripts/gh.sh`, in the `*)` default case, replace the usage line with:

```bash
    echo "usage: gh.sh {preflight|ensure-labels|visibility|create-idea|body|comment|add-finished|add-auto|has-auto|set-body}" >&2
```

- [ ] **Step 7: Run the full suite to verify it passes**

Run: `bash tests/run.sh`
Expected: PASS — ends with `ALL TESTS PASSED` (the `gh_test.sh` block shows the 5 new `ok:` lines; no other test regresses).

- [ ] **Step 8: Commit**

```bash
git add scripts/gh.sh tests/fixtures/bin/gh tests/gh_test.sh
git commit -m "feat: superafk-auto label + add-auto/has-auto gh wrappers"
```

---

### Task 2: `superafk-guide` — autonomy clause + outcome-agnostic Touchpoint 3

**Files:**
- Modify: `skills/superafk-guide/SKILL.md` (full replace of body)
- Test: `tests/skill_lint_test.sh` (append two guide assertions)

**Interfaces:**
- Consumes: nothing new (rules doc).
- Produces: the injected rule text that tells the model when to invoke the worker, including the new autonomy behavior and the any-outcome Touchpoint-3 trigger. Lint budget: ≤ 200 words (this body measures 198).

- [ ] **Step 1: Write the failing tests**

In `tests/skill_lint_test.sh`, after the existing two guide assertions:

```bash
assert_contains "$g" "finishing-a-development-branch" "guide: names the PR touchpoint"
assert_contains "$g" "superafk-issue" "guide: states the stamp rule"
```

add:

```bash
assert_contains "$g" "superafk-auto" "guide: names the autonomy label"
assert_contains "$g" "any outcome" "guide: takeover is outcome-agnostic"
```

- [ ] **Step 2: Run the lint test to verify it fails**

Run: `bash tests/skill_lint_test.sh`
Expected: FAIL — `guide: names the autonomy label` and `guide: takeover is outcome-agnostic` fail, because the current guide has neither `superafk-auto` nor `any outcome`.

- [ ] **Step 3: Replace the guide body**

Replace the entire contents of `skills/superafk-guide/SKILL.md` with:

```markdown
---
name: superafk-guide
description: Use when starting a Claude Code session where superpowers may be used — establishes how superAFK keeps the idea-issue in sync.
---

# superAFK guide

superAFK mirrors superpowers progress into ONE GitHub issue per idea (issue number = identity). Write-side only, plus one read: the `superafk-auto` label. Invoke **superafk** at these moments, nothing else:

1. **Before brainstorming:** bind this session to an idea-issue — create it, or take the one the user names — and claim the lock. On user opt-in, set `superafk-auto`; always read the label to note autonomy.
2. **When a spec/plan file is written:** stamp it with `superafk-issue: <number>`.
3. **After `finishing-a-development-branch` concludes (any outcome — PR/merge/keep/discard):** run the takeover — link the outcome (comment, never a closing keyword), judge if the idea is done, then `finished` (label only, never close) or a handoff comment, and release the lock.

**Autonomy:** if the idea carries `superafk-auto`, the user pre-authorized: after design approval, run plans → execution → code-review → finishing WITHOUT pausing; finishing opens a PR (human merges).

If `gh` is unavailable or there's no GitHub origin, stay silent — never block superpowers.

**REQUIRED SUB-SKILL:** Use the superafk skill for exact steps.
```

- [ ] **Step 4: Verify word budget locally**

Run: `wc -w < skills/superafk-guide/SKILL.md`
Expected: `198` (must be ≤ 200). If somehow over 200, trim the intro sentence — do not cut the `superafk-auto`, `any outcome`, or `finishing-a-development-branch` tokens the tests depend on.

- [ ] **Step 5: Run the full suite to verify it passes**

Run: `bash tests/run.sh`
Expected: PASS — `ALL TESTS PASSED`; `skill_lint_test.sh` shows the guide ≤200, all four guide `assert_contains` green.

- [ ] **Step 6: Commit**

```bash
git add skills/superafk-guide/SKILL.md tests/skill_lint_test.sh
git commit -m "feat: guide gains autonomy clause + outcome-agnostic takeover"
```

---

### Task 3: `superafk` worker — Touchpoint 1 autonomy + Touchpoint 3 rewrite

**Files:**
- Modify: `skills/superafk/SKILL.md` (full replace of body)
- Test: `tests/skill_lint_test.sh` (append two worker assertions)

**Interfaces:**
- Consumes (from Task 1): `bash "$S/gh.sh" add-auto "$ISSUE"`, `bash "$S/gh.sh" has-auto "$ISSUE"` (prints `auto`/`manual`), and `ensure-labels` creating `superafk-auto`.
- Produces: the executable steps the model follows — Touchpoint 1 sets/reads autonomy; Touchpoint 3 covers every outcome and always handoffs-or-finishes. Lint budget: ≤ 500 words (this body measures 470). Must contain no closing keyword.

- [ ] **Step 1: Write the failing tests**

In `tests/skill_lint_test.sh`, inside the existing `if [ -f skills/superafk/SKILL.md ]; then` block, after the `worker: no closing keyword` assertion, add:

```bash
  assert_contains "$w" "has-auto" "worker: reads autonomy via has-auto"
  assert_contains "$w" "discard" "worker: takeover covers non-PR outcomes"
```

- [ ] **Step 2: Run the lint test to verify it fails**

Run: `bash tests/skill_lint_test.sh`
Expected: FAIL — `worker: reads autonomy via has-auto` and `worker: takeover covers non-PR outcomes` fail, because the current worker mentions neither `has-auto` nor `discard`.

- [ ] **Step 3: Replace the worker body**

Replace the entire contents of `skills/superafk/SKILL.md` with:

````markdown
---
name: superafk
description: Use when binding a session to its idea-issue before brainstorming, when a spec or plan file has just been written, or just after finishing-a-development-branch concludes (any outcome).
---

# superafk worker

Let `S` be the plugin's `scripts/` dir. ALWAYS run the degradation gate first; if it exits non-zero, STOP silently:
```bash
bash "$S/gh.sh" preflight || exit 0
bash "$S/gh.sh" ensure-labels
```
`SESSION_ID` is the session id injected by the hook ("Your current session id is: ...").

## Touchpoint 1 — bind an idea-issue (before brainstorming)
**New idea** — create it, then claim the lock:
```bash
ISSUE="$(bash "$S/gh.sh" create-idea "<idea title>" "<idea original text>")"
BODY="$(bash "$S/gh.sh" body "$ISSUE")"
printf '%s' "$BODY" | bash "$S/issue_body.sh" set "$SESSION_ID" \
  | { c=$(cat); bash "$S/gh.sh" set-body "$ISSUE" "$c"; }
```
Remember `ISSUE` for this session. **Existing idea** (user names issue N): read the lock — if empty, claim it; if it equals `SESSION_ID`, proceed; otherwise WARN that another session holds it and do not double-work.

**Autonomy (opt-in):** if the user asks to run this idea autonomously, `bash "$S/gh.sh" add-auto "$ISSUE"`. Either way read it: `AUTO="$(bash "$S/gh.sh" has-auto "$ISSUE")"`. If `AUTO` equals `auto`, the user has pre-authorized — after the design doc is approved, run writing-plans → execution → code-review → finishing WITHOUT pausing for approval; at finishing choose "open a PR" (a human still merges).

## Touchpoint 2 — stamp each spec/plan file
After any file is written under `docs/superpowers/specs/` or `docs/superpowers/plans/`:
```bash
bash "$S/frontmatter.sh" set-issue "<that file>" "$ISSUE"
```

## Touchpoint 3 — takeover after finishing-a-development-branch concludes (ANY outcome)
Trigger the moment finishing concludes, whatever the outcome (PR / merge / keep / discard).
1. Link the outcome — a comment, NEVER a closing keyword, and NEVER `gh issue close`:
```bash
bash "$S/gh.sh" comment "$ISSUE" "superAFK: <PR #N — URL | merged <sha> | branch <name> kept | branch discarded>"
```
2. Completeness check:
   - **discard / keep** → treat as UNFINISHED; skip the judgment.
   - **merge / PR** → read the idea text and the realized files, then judge honestly:
```bash
IDEA="$(bash "$S/gh.sh" body "$ISSUE")"
FILES="$(bash "$S/scan.sh" "$ISSUE")"
```
     Do the landed specs/plans cover the WHOLE idea? Partial work is "unfinished".
3a. Finished → label only (a human closes the issue):
```bash
bash "$S/gh.sh" add-finished "$ISSUE"
```
3b. Unfinished → append an outcome-aware handoff comment:
```bash
bash "$S/gh.sh" comment "$ISSUE" "superAFK handoff — <outcome>. Landed: <files>. Missing vs idea: <gap>. Next: <next spec/plan>."
```
4. Release the lock:
```bash
BODY="$(bash "$S/gh.sh" body "$ISSUE")"
printf '%s' "$BODY" | bash "$S/issue_body.sh" clear \
  | { c=$(cat); bash "$S/gh.sh" set-body "$ISSUE" "$c"; }
```
Then stop. Reading the handoff to auto-resume is a future phase.

## Privacy
Before the FIRST issue in a repo, run `bash "$S/gh.sh" visibility`; if `public`, warn that idea text and handoffs become world-readable and confirm once.
````

- [ ] **Step 4: Verify word budget and no closing keyword locally**

Run: `wc -w < skills/superafk/SKILL.md`
Expected: `470` (must be ≤ 500).
Run: `grep -E 'Closes #|Fixes #|Resolves #' skills/superafk/SKILL.md; echo "rc=$?"`
Expected: no matches, `rc=1`.

- [ ] **Step 5: Run the full suite to verify it passes**

Run: `bash tests/run.sh`
Expected: PASS — `ALL TESTS PASSED`; `skill_lint_test.sh` shows worker ≤500, `worker: reads autonomy via has-auto` and `worker: takeover covers non-PR outcomes` green, `worker: no closing keyword` still green.

- [ ] **Step 6: Commit**

```bash
git add skills/superafk/SKILL.md tests/skill_lint_test.sh
git commit -m "feat: worker sets/reads autonomy + outcome-agnostic takeover"
```

---

## Self-Review

**1. Spec coverage** (against `docs/superpowers/specs/2026-06-22-superafk-autonomy-and-takeover-design.md`):

| Spec section | Task |
|---|---|
| §3 new `superafk-auto` label; `ensure-labels` creates it | Task 1 (Steps 4, 1–2) |
| §2/§5 A+B driver — read label, inject pre-authorization | Task 1 (`has-auto`) + Task 2 (Autonomy clause) + Task 3 (TP1 Autonomy) |
| §4 gate map — gate 1 human, 2–5 auto, finishing→PR | Task 2 + Task 3 autonomy text |
| §6 takeover outcome-agnostic + always handoff (discard/keep forced unfinished) | Task 3 (TP3 rewrite) + Task 2 (guide TP3) |
| §7 wording: descriptions + trigger phrasing | Task 2 (guide), Task 3 (worker description) |
| §8 boundary note (read one bool label only) | Captured in spec; worker reads only `has-auto` (Task 3), no handoff reading — by construction |

No gaps: every changed behavior in the spec maps to a task. (The §8 boundary is a documentation invariant, enforced by *not* adding any handoff-reading step — there is no such step in any task.)

**2. Placeholder scan:** No `TBD`/`TODO`/"add error handling"/"similar to Task N". Skill bodies use `<...>` angle-bracket fill-ins (idea title, issue number, outcome) — these are literal author-time templates the model fills at runtime, identical to the v3 skills, not plan placeholders. Every code/test step shows complete content.

**3. Type/name consistency:** `add-auto` and `has-auto` are spelled identically in `gh.sh` (Task 1 Steps 5), the worker skill (Task 3), and the tests. `has-auto` prints exactly `auto`/`manual`; the worker checks `AUTO equals auto`. Label string `superafk-auto` is identical across `ensure-labels`, `add-auto`, mock, tests, guide, and worker. `GH_MOCK_LABELS` is spelled identically in the mock and `gh_test.sh`.

All checks pass; no inline fixes required.
