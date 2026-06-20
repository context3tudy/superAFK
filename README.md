# superAFK

Track [superpowers](https://github.com/obra/superpowers) development progress as a
**single GitHub issue per idea** — without modifying superpowers, while you use it normally.

## How it works
One SessionStart hook injects `superafk-guide`. superAFK touches superpowers at 3 points:
1. **Before brainstorming** — create/bind one idea-issue (issue number = identity) and lock it to your session.
2. **On each spec/plan file** — stamp `superafk-issue: <n>` into its front-matter.
3. **After `finishing-a-development-branch` opens a PR** — link the PR (non-closing), judge
   if the idea is done → add a `finished` label (stays open; you close it) or leave a handoff comment → release the lock.

## Requirements & limits (Phase 1)
- **Claude Code only.** Other harnesses: superAFK injects nothing (no error).
- Requires the **`gh` CLI**, authenticated, in a repo with a GitHub `origin`. Otherwise superAFK
  stays silent and never blocks superpowers.
- **Never auto-closes** issues. `finished` is a label; humans close.
- Idea text and handoffs are posted to the issue — on a **public** repo they are world-readable
  (superAFK confirms once before the first create).
- Write-side only: reading the handoff to auto-resume is a future phase.

## Install
Add this plugin to your Claude Code plugins (alongside superpowers). It activates via its SessionStart hook.

## Develop
`bash tests/run.sh` runs unit tests (no network). Set `SUPERAFK_RUN_INTEGRATION=1`,
`SUPERAFK_TEST_REPO=owner/name`, with `gh` authed, to run the end-to-end scenario.
