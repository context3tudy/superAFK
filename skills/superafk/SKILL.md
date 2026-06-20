---
name: superafk
description: Use when binding a session to its idea-issue before brainstorming, when a spec or plan file has just been written, or just after finishing-a-development-branch opens a PR.
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

## Touchpoint 2 — stamp each spec/plan file
After any file is written under `docs/superpowers/specs/` or `docs/superpowers/plans/`:
```bash
bash "$S/frontmatter.sh" set-issue "<that file>" "$ISSUE"
```

## Touchpoint 3 — takeover after a PR opens (PR_NUM / PR_URL)
1. Link the PR — a comment, NEVER a closing keyword, and NEVER `gh issue close`:
```bash
bash "$S/gh.sh" comment "$ISSUE" "superAFK: PR #$PR_NUM — $PR_URL"
```
2. Completeness check — read the idea text and the realized files, then judge honestly:
```bash
IDEA="$(bash "$S/gh.sh" body "$ISSUE")"
FILES="$(bash "$S/scan.sh" "$ISSUE")"
```
Do the landed specs/plans cover the WHOLE idea? Partial work is "unfinished".
3a. Finished → label only (a human closes the issue):
```bash
bash "$S/gh.sh" add-finished "$ISSUE"
```
3b. Unfinished → append a handoff comment:
```bash
bash "$S/gh.sh" comment "$ISSUE" "superAFK handoff — PR #$PR_NUM. Landed: <files>. Missing vs idea: <gap>. Next: <next spec/plan>."
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
