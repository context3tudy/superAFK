---
name: superafk-guide
description: Use when starting a Claude Code session where superpowers may be used — establishes how superAFK keeps the idea-issue in sync.
---

# superAFK guide

superAFK mirrors superpowers progress into ONE GitHub issue per idea (issue number = identity). Write-side only: never read the issue to decide what to build. Invoke the **superafk** skill at these three moments and do nothing else:

1. **Before brainstorming:** bind this session to an idea-issue — create it for a new idea, or take the one the user names — and claim the lock.
2. **When a spec/plan file is written:** stamp it with `superafk-issue: <number>`.
3. **After `finishing-a-development-branch` opens a PR:** run the takeover — link the PR (a comment, never a closing keyword), judge whether the idea is done, mark `finished` (label only; never close the issue) or leave a handoff comment, then release the lock.

If `gh` is missing/unauthenticated or there is no GitHub origin, stay silent and do nothing — never block superpowers.

**REQUIRED SUB-SKILL:** Use the superafk skill for the exact steps.
