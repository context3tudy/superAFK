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
