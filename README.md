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

superAFK installs as a Claude Code plugin via its own marketplace (this repo is the marketplace).
Run these slash commands in Claude Code — in the project you want tracked, or anywhere for user scope:

```text
/plugin marketplace add /path/to/superAFK          # or a git URL once pushed
/plugin install superafk@superafk-marketplace --scope project
/reload-plugins
```

Then **restart Claude Code** (start a new session) — the `SessionStart` hook only fires on a fresh session,
so it won't activate in the session where you installed it.

**Scope:**
- `--scope project` — enable it for one project (writes `enabledPlugins` into that project's `.claude/settings.json`).
- `--scope user` — enable it globally for all your projects. superAFK is a cross-project tool, so this is often what you want.

Or run `/plugin`, open the **Discover** tab, pick `superafk`, and choose the scope in the UI.

The marketplace is registered per machine when added from a local path; after you push this repo to GitHub,
`/plugin marketplace add <git-url>` lets you install (and share) it from the remote.

**Verify:** a new session's context should contain the injected `# superAFK guide` block (the same way superpowers
injects its own guide). It needs superpowers installed, `gh` authenticated, and a GitHub `origin` in the tracked
repo (see Requirements above) — otherwise it stays silent.

## Develop
`bash tests/run.sh` runs unit tests (no network). Set `SUPERAFK_RUN_INTEGRATION=1`,
`SUPERAFK_TEST_REPO=owner/name`, with `gh` authed, to run the end-to-end scenario.
