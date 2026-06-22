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
