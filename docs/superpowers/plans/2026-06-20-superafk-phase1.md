# superAFK Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the superAFK Claude Code plugin that mirrors superpowers development progress into a single GitHub idea-issue, touching superpowers at only 3 points, with the real work concentrated after a PR is opened.

**Architecture:** Same mechanism as superpowers — one SessionStart hook injects a guide skill (`superafk-guide`) plus the session id. A worker skill (`superafk`) orchestrates small, tested bash helper scripts (`scripts/*.sh`) that do the deterministic work (front-matter stamping, scanning files by issue number, lock-marker editing, `gh` calls). One idea = one GitHub issue; the issue number is the identity, stamped into spec/plan files' front-matter. Completion is judged by the model (LLM) reading the idea body + the scanned spec/plan files; results are written as a `finished` label or a handoff comment.

**Tech Stack:** Bash (hooks + helper scripts), `gh` CLI (GitHub), git. No Python/Node. Tests: a plain-bash harness (`tests/run.sh` + `tests/lib/assert.sh`) with a `gh` mock for unit tests; integration scenarios are opt-in, gated on `gh auth status`.

## Global Constraints

- Do NOT modify superpowers. Mechanism = one SessionStart hook injecting `superafk-guide` as `additionalContext`. Matcher: `startup|clear|compact`.
- Claude Code only (Phase 1). On other harnesses superAFK injects nothing; never error.
- gh unavailable / not authenticated / no GitHub origin remote → print one notice, then skip silently. NEVER block or break the superpowers workflow. `scripts/gh.sh preflight` returns non-zero and callers skip.
- NEVER auto-close an issue. "finished" = add the `finished` label; the issue stays OPEN; a human closes it.
- No local state file. The GitHub issue is the single source of truth.
- Identity = the GitHub issue NUMBER, written into spec/plan files' YAML front-matter as `superafk-issue: <number>`.
- Link a PR to the issue with a NON-closing reference (a comment mentioning the PR). NEVER use `Closes/Fixes/Resolves #N` (would auto-close on merge).
- Lock = `<!-- superafk-active-session: <id> -->` in the issue BODY. Handoff = issue COMMENTS. Idea original text = issue BODY.
- The takeover (link PR + completion check + status/handoff + release lock) triggers ONLY when finishing-a-development-branch opens a PR.
- Phase 1 is write-side only. Auto-reading the handoff to resume work is Phase 2 — not in this plan.

---

### Task 1: Plugin scaffold + bash test harness

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `tests/lib/assert.sh`
- Create: `tests/run.sh`
- Create: `tests/smoke_test.sh`

**Interfaces:**
- Produces: test harness contract — every `tests/*_test.sh` is a standalone bash script that `source`s `tests/lib/assert.sh`, calls `assert_eq <expected> <actual> <msg>` and `assert_contains <haystack> <needle> <msg>`, and ends with `assert_report || exit 1`. `tests/run.sh` runs all `tests/*_test.sh` and exits non-zero if any fail.

- [ ] **Step 1: Write the assert library**

Create `tests/lib/assert.sh`:
```bash
# Shared assertions for superAFK bash tests. Source this in each *_test.sh.
ASSERT_FAILED=0
ASSERT_TOTAL=0

assert_eq() {
  ASSERT_TOTAL=$((ASSERT_TOTAL + 1))
  if [ "$1" = "$2" ]; then
    echo "  ok: ${3:-}"
  else
    ASSERT_FAILED=$((ASSERT_FAILED + 1))
    echo "  FAIL: ${3:-}"
    echo "    expected: [$1]"
    echo "    actual:   [$2]"
  fi
}

assert_contains() {
  ASSERT_TOTAL=$((ASSERT_TOTAL + 1))
  case "$1" in
    *"$2"*) echo "  ok: ${3:-}" ;;
    *)
      ASSERT_FAILED=$((ASSERT_FAILED + 1))
      echo "  FAIL: ${3:-} (missing substring: [$2])"
      ;;
  esac
}

assert_report() {
  echo "  $((ASSERT_TOTAL - ASSERT_FAILED))/${ASSERT_TOTAL} passed"
  [ "$ASSERT_FAILED" -eq 0 ]
}
```

- [ ] **Step 2: Write the runner**

Create `tests/run.sh`:
```bash
#!/usr/bin/env bash
set -u
cd "$(dirname "$0")/.."
rc=0
shopt -s nullglob
for t in tests/*_test.sh; do
  echo "== $t =="
  if ! bash "$t"; then rc=1; fi
done
if [ "$rc" -eq 0 ]; then echo "ALL TESTS PASSED"; else echo "SOME TESTS FAILED"; fi
exit "$rc"
```
Then: `chmod +x tests/run.sh`

- [ ] **Step 3: Write the failing smoke test**

Create `tests/smoke_test.sh`:
```bash
#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib/assert.sh"

# The plugin manifest must exist and declare the plugin name.
manifest="$DIR/../.claude-plugin/plugin.json"
[ -f "$manifest" ] && content="$(cat "$manifest")" || content=""
assert_contains "$content" '"name": "superafk"' "plugin.json declares name superafk"

assert_report || exit 1
```

- [ ] **Step 4: Run it to confirm it fails**

Run: `bash tests/run.sh`
Expected: FAIL — `plugin.json declares name superafk (missing substring...)`, final line `SOME TESTS FAILED`, exit non-zero.

- [ ] **Step 5: Create the plugin manifest**

Create `.claude-plugin/plugin.json`:
```json
{
  "name": "superafk",
  "description": "Track superpowers development progress as a single GitHub idea-issue, without modifying superpowers.",
  "version": "0.1.0",
  "author": { "name": "gingerly" },
  "license": "MIT",
  "keywords": ["superpowers", "github", "issues", "progress", "tracking"]
}
```

- [ ] **Step 6: Run tests to confirm pass**

Run: `bash tests/run.sh`
Expected: `== tests/smoke_test.sh ==`, `ok: plugin.json declares name superafk`, `ALL TESTS PASSED`, exit 0.

- [ ] **Step 7: Commit**

```bash
git add .claude-plugin/plugin.json tests/lib/assert.sh tests/run.sh tests/smoke_test.sh
git commit -m "feat: plugin scaffold + bash test harness"
```

---

### Task 2: front-matter helper (`scripts/frontmatter.sh`)

**Files:**
- Create: `scripts/frontmatter.sh`
- Create: `tests/frontmatter_test.sh`

**Interfaces:**
- Produces:
  - `bash scripts/frontmatter.sh get-issue <file>` → prints the `superafk-issue` value from the leading `---` YAML block, or nothing if absent/no front-matter.
  - `bash scripts/frontmatter.sh set-issue <file> <number>` → idempotently sets `superafk-issue: <number>` inside the leading front-matter block (creating the block if the file has none), preserving the rest of the file.

- [ ] **Step 1: Write the failing test**

Create `tests/frontmatter_test.sh`:
```bash
#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib/assert.sh"
FM="$DIR/../scripts/frontmatter.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# 1) get-issue on a file with no front-matter -> empty
printf '# Hello\nbody\n' > "$tmp/a.md"
assert_eq "" "$(bash "$FM" get-issue "$tmp/a.md")" "no front-matter -> empty"

# 2) set-issue on a file with no front-matter -> prepends block, get returns it
bash "$FM" set-issue "$tmp/a.md" 42
assert_eq "42" "$(bash "$FM" get-issue "$tmp/a.md")" "set then get on bare file"
assert_contains "$(cat "$tmp/a.md")" "# Hello" "original body preserved"

# 3) set-issue is idempotent / updates in place (no duplicate keys)
bash "$FM" set-issue "$tmp/a.md" 99
assert_eq "99" "$(bash "$FM" get-issue "$tmp/a.md")" "update existing key"
assert_eq "1" "$(grep -c '^superafk-issue:' "$tmp/a.md")" "exactly one superafk-issue line"

# 4) set-issue on a file that already has a front-matter block (other keys kept)
printf -- '---\ntitle: X\n---\n# Body\n' > "$tmp/b.md"
bash "$FM" set-issue "$tmp/b.md" 7
assert_eq "7" "$(bash "$FM" get-issue "$tmp/b.md")" "insert into existing block"
assert_contains "$(cat "$tmp/b.md")" "title: X" "existing front-matter key kept"

assert_report || exit 1
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bash tests/run.sh`
Expected: FAIL — `frontmatter.sh` does not exist, asserts fail, `SOME TESTS FAILED`.

- [ ] **Step 3: Implement `scripts/frontmatter.sh`**

Create `scripts/frontmatter.sh`:
```bash
#!/usr/bin/env bash
# Read/write the `superafk-issue:` key in a markdown file's leading YAML front-matter.
set -euo pipefail

cmd="${1:-}"
file="${2:-}"

case "$cmd" in
  get-issue)
    [ -f "$file" ] || exit 0
    awk '
      NR==1 && $0!="---" { exit }
      NR==1 { infm=1; next }
      infm==1 && $0=="---" { exit }
      infm==1 && /^superafk-issue:[[:space:]]*/ {
        line=$0; sub(/^superafk-issue:[[:space:]]*/, "", line); print line; exit
      }
    ' "$file"
    ;;
  set-issue)
    num="${3:?usage: set-issue <file> <number>}"
    tmp="$(mktemp)"
    first=""
    [ -f "$file" ] && IFS= read -r first < "$file" || true
    if [ "$first" = "---" ]; then
      awk -v num="$num" '
        BEGIN { infm=0; done=0 }
        NR==1 && $0=="---" { print; infm=1; next }
        infm==1 && $0=="---" {
          if (done==0) { print "superafk-issue: " num; done=1 }
          print; infm=0; next
        }
        infm==1 && /^superafk-issue:/ { print "superafk-issue: " num; done=1; next }
        { print }
      ' "$file" > "$tmp"
    else
      { printf -- "---\nsuperafk-issue: %s\n---\n" "$num"; [ -f "$file" ] && cat "$file"; } > "$tmp"
    fi
    mv "$tmp" "$file"
    ;;
  *)
    echo "usage: frontmatter.sh {get-issue <file> | set-issue <file> <number>}" >&2
    exit 2
    ;;
esac
```
Then: `chmod +x scripts/frontmatter.sh`

- [ ] **Step 4: Run tests to confirm pass**

Run: `bash tests/run.sh`
Expected: all `frontmatter_test.sh` asserts `ok`, `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add scripts/frontmatter.sh tests/frontmatter_test.sh
git commit -m "feat: front-matter superafk-issue get/set helper"
```

---

### Task 3: scan helper (`scripts/scan.sh`)

**Files:**
- Create: `scripts/scan.sh`
- Create: `tests/scan_test.sh`

**Interfaces:**
- Consumes: `scripts/frontmatter.sh get-issue`.
- Produces: `bash scripts/scan.sh <issue-number> [<root>]` → prints (one per line) every file under `<root>/docs/superpowers/specs/*.md` and `<root>/docs/superpowers/plans/*.md` whose front-matter `superafk-issue` equals `<issue-number>`. `<root>` defaults to `.`.

- [ ] **Step 1: Write the failing test**

Create `tests/scan_test.sh`:
```bash
#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib/assert.sh"
FM="$DIR/../scripts/frontmatter.sh"
SCAN="$DIR/../scripts/scan.sh"
root="$(mktemp -d)"; trap 'rm -rf "$root"' EXIT
mkdir -p "$root/docs/superpowers/specs" "$root/docs/superpowers/plans"

printf '# spec a\n' > "$root/docs/superpowers/specs/a-design.md"
bash "$FM" set-issue "$root/docs/superpowers/specs/a-design.md" 5
printf '# plan a\n' > "$root/docs/superpowers/plans/a.md"
bash "$FM" set-issue "$root/docs/superpowers/plans/a.md" 5
printf '# spec b\n' > "$root/docs/superpowers/specs/b-design.md"
bash "$FM" set-issue "$root/docs/superpowers/specs/b-design.md" 6

out="$(cd "$root" && bash "$SCAN" 5 | sort)"
assert_contains "$out" "docs/superpowers/specs/a-design.md" "scan finds spec for issue 5"
assert_contains "$out" "docs/superpowers/plans/a.md" "scan finds plan for issue 5"
case "$out" in *b-design.md*) found_b=1;; *) found_b=0;; esac
assert_eq "0" "$found_b" "scan excludes issue 6 file"

# empty when dirs missing
empty_root="$(mktemp -d)"
assert_eq "" "$(cd "$empty_root" && bash "$SCAN" 5)" "no docs dir -> empty"
rm -rf "$empty_root"

assert_report || exit 1
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bash tests/run.sh`
Expected: FAIL — `scan.sh` missing.

- [ ] **Step 3: Implement `scripts/scan.sh`**

Create `scripts/scan.sh`:
```bash
#!/usr/bin/env bash
# Print files under docs/superpowers/{specs,plans} whose front-matter superafk-issue == <number>.
set -euo pipefail

num="${1:?usage: scan.sh <issue-number> [root]}"
root="${2:-.}"
here="$(cd "$(dirname "$0")" && pwd)"

shopt -s nullglob
for f in "$root"/docs/superpowers/specs/*.md "$root"/docs/superpowers/plans/*.md; do
  v="$(bash "$here/frontmatter.sh" get-issue "$f")"
  [ "$v" = "$num" ] && printf '%s\n' "$f"
done
```
Then: `chmod +x scripts/scan.sh`

- [ ] **Step 4: Run tests to confirm pass**

Run: `bash tests/run.sh`
Expected: `scan_test.sh` asserts `ok`, `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add scripts/scan.sh tests/scan_test.sh
git commit -m "feat: scan files by superafk-issue number"
```

---

### Task 4: lock-marker helper (`scripts/issue_body.sh`)

**Files:**
- Create: `scripts/issue_body.sh`
- Create: `tests/issue_body_test.sh`

**Interfaces:**
- Produces (all read the issue body on STDIN and write the result to STDOUT; pure text transforms):
  - `issue_body.sh read` → prints the active-session id inside `<!-- superafk-active-session: <id> -->`, or empty if the marker is absent or empty.
  - `issue_body.sh set <id>` → returns the body with the marker set to `<id>` (replacing an existing marker, or appending one).
  - `issue_body.sh clear` → returns the body with the marker's id emptied (`<!-- superafk-active-session:  -->`).

- [ ] **Step 1: Write the failing test**

Create `tests/issue_body_test.sh`:
```bash
#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib/assert.sh"
IB="$DIR/../scripts/issue_body.sh"

body_plain="$(printf '# Idea\n\ngoal text\n')"

# read when no marker -> empty
assert_eq "" "$(printf '%s' "$body_plain" | bash "$IB" read)" "read: no marker -> empty"

# set on body without marker -> appends, read returns id
set_out="$(printf '%s' "$body_plain" | bash "$IB" set sess-123)"
assert_eq "sess-123" "$(printf '%s' "$set_out" | bash "$IB" read)" "set then read"
assert_contains "$set_out" "goal text" "set preserves body"

# set replacing an existing marker (no duplicate marker lines)
set_again="$(printf '%s' "$set_out" | bash "$IB" set sess-999)"
assert_eq "sess-999" "$(printf '%s' "$set_again" | bash "$IB" read)" "set replaces id"
assert_eq "1" "$(printf '%s' "$set_again" | grep -c 'superafk-active-session')" "one marker only"

# clear empties the id
clear_out="$(printf '%s' "$set_again" | bash "$IB" clear)"
assert_eq "" "$(printf '%s' "$clear_out" | bash "$IB" read)" "clear -> empty id"
assert_contains "$clear_out" "superafk-active-session" "clear keeps marker line"

assert_report || exit 1
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bash tests/run.sh`
Expected: FAIL — `issue_body.sh` missing.

- [ ] **Step 3: Implement `scripts/issue_body.sh`**

Create `scripts/issue_body.sh`:
```bash
#!/usr/bin/env bash
# Read/set/clear the active-session lock marker in an issue body (stdin -> stdout).
set -euo pipefail

cmd="${1:-}"
body="$(cat)"
marker='superafk-active-session'

case "$cmd" in
  read)
    printf '%s\n' "$body" \
      | sed -n "s/.*<!-- ${marker}:[[:space:]]*\\([^ ]*\\)[[:space:]]*-->.*/\\1/p" \
      | head -n1
    ;;
  set)
    id="${2:?usage: set <id>}"
    if printf '%s\n' "$body" | grep -q "$marker"; then
      printf '%s\n' "$body" | sed "s|<!-- ${marker}:[^>]*-->|<!-- ${marker}: ${id} -->|"
    else
      printf '%s\n%s\n' "$body" "<!-- ${marker}: ${id} -->"
    fi
    ;;
  clear)
    if printf '%s\n' "$body" | grep -q "$marker"; then
      printf '%s\n' "$body" | sed "s|<!-- ${marker}:[^>]*-->|<!-- ${marker}:  -->|"
    else
      printf '%s\n' "$body"
    fi
    ;;
  *)
    echo "usage: issue_body.sh {read | set <id> | clear}" >&2
    exit 2
    ;;
esac
```
Then: `chmod +x scripts/issue_body.sh`

- [ ] **Step 4: Run tests to confirm pass**

Run: `bash tests/run.sh`
Expected: `issue_body_test.sh` asserts `ok`, `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add scripts/issue_body.sh tests/issue_body_test.sh
git commit -m "feat: issue-body active-session lock marker helper"
```

---

### Task 5: gh wrappers (`scripts/gh.sh`) with a mock

**Files:**
- Create: `scripts/gh.sh`
- Create: `tests/fixtures/bin/gh`
- Create: `tests/gh_test.sh`

**Interfaces:**
- Produces:
  - `gh.sh preflight` → exit 0 if gh authed + cwd has a GitHub origin; non-zero (with a one-line stderr notice) otherwise.
  - `gh.sh ensure-labels` → idempotently create `superafk` and `finished` labels.
  - `gh.sh visibility` → print repo visibility (`public`/`private`/`internal`).
  - `gh.sh create-idea <title> <body>` → create an issue labeled `superafk`, print its issue NUMBER.
  - `gh.sh body <n>` → print issue `<n>` body.
  - `gh.sh comment <n> <body>` → add a comment.
  - `gh.sh add-finished <n>` → add the `finished` label.
  - `gh.sh set-body <n> <body>` → replace issue body.

- [ ] **Step 1: Write the mock gh**

Create `tests/fixtures/bin/gh`:
```bash
#!/usr/bin/env bash
# Mock gh for unit tests. Logs args to $GH_MOCK_LOG and prints canned output.
echo "$*" >> "${GH_MOCK_LOG:-/dev/null}"
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
Then: `chmod +x tests/fixtures/bin/gh`

- [ ] **Step 2: Write the failing test**

Create `tests/gh_test.sh`:
```bash
#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib/assert.sh"
GH="$DIR/../scripts/gh.sh"

export PATH="$DIR/fixtures/bin:$PATH"      # mock gh wins
export GH_MOCK_LOG="$(mktemp)"; trap 'rm -f "$GH_MOCK_LOG"' EXIT

# create-idea parses the issue number out of the URL
num="$(bash "$GH" create-idea "My Idea" "the body")"
assert_eq "42" "$num" "create-idea returns issue number"
assert_contains "$(cat "$GH_MOCK_LOG")" "issue create" "called gh issue create"
assert_contains "$(cat "$GH_MOCK_LOG")" "--label superafk" "labelled superafk on create"

# body fetch
assert_eq "idea body from mock" "$(bash "$GH" body 42)" "body returns issue body"

# visibility
assert_eq "private" "$(bash "$GH" visibility)" "visibility passthrough"

# comment must NOT contain a closing keyword
: > "$GH_MOCK_LOG"
bash "$GH" comment 42 "superAFK: PR #7 https://github.com/o/r/pull/7"
log="$(cat "$GH_MOCK_LOG")"
assert_contains "$log" "issue comment" "comment calls gh issue comment"
case "$log" in *Closes*|*Fixes*|*Resolves*) bad=1;; *) bad=0;; esac
assert_eq "0" "$bad" "comment carries no closing keyword"

assert_report || exit 1
```

- [ ] **Step 3: Run it to confirm it fails**

Run: `bash tests/run.sh`
Expected: FAIL — `gh.sh` missing.

- [ ] **Step 4: Implement `scripts/gh.sh`**

Create `scripts/gh.sh`:
```bash
#!/usr/bin/env bash
# Thin wrappers over the gh CLI used by superAFK. Never embeds closing keywords.
set -euo pipefail

cmd="${1:-}"; shift || true

case "$cmd" in
  preflight)
    gh auth status >/dev/null 2>&1 || { echo "superAFK: gh not authenticated; skipping issue sync." >&2; exit 10; }
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "superAFK: not a git repo; skipping." >&2; exit 11; }
    git remote get-url origin >/dev/null 2>&1 || { echo "superAFK: no origin remote; skipping." >&2; exit 12; }
    gh repo view >/dev/null 2>&1 || { echo "superAFK: origin is not a GitHub repo; skipping." >&2; exit 13; }
    ;;
  ensure-labels)
    gh label create superafk --description "superAFK idea tracker" --color 1f6feb --force >/dev/null
    gh label create finished --description "superAFK: idea complete (close manually)" --color 0e8a16 --force >/dev/null
    ;;
  visibility)
    gh repo view --json visibility -q .visibility
    ;;
  create-idea)
    title="${1:?title}"; body="${2:?body}"
    url="$(gh issue create --title "$title" --body "$body" --label superafk)"
    printf '%s\n' "$url" | awk -F/ '{print $NF}'
    ;;
  body)
    gh issue view "${1:?n}" --json body -q .body
    ;;
  comment)
    gh issue comment "${1:?n}" --body "${2:?body}" >/dev/null
    ;;
  add-finished)
    gh issue edit "${1:?n}" --add-label finished >/dev/null
    ;;
  set-body)
    gh issue edit "${1:?n}" --body "${2:?body}" >/dev/null
    ;;
  *)
    echo "usage: gh.sh {preflight|ensure-labels|visibility|create-idea|body|comment|add-finished|set-body}" >&2
    exit 2
    ;;
esac
```
Then: `chmod +x scripts/gh.sh`

- [ ] **Step 5: Run tests to confirm pass**

Run: `bash tests/run.sh`
Expected: `gh_test.sh` asserts `ok`, `ALL TESTS PASSED`.

- [ ] **Step 6: Commit**

```bash
git add scripts/gh.sh tests/fixtures/bin/gh tests/gh_test.sh
git commit -m "feat: gh CLI wrappers (non-closing PR link) + mock-based tests"
```

---

### Task 6: SessionStart hook (`hooks/`)

**Files:**
- Create: `hooks/hooks.json`
- Create: `hooks/run-hook.cmd`
- Create: `hooks/session-start`
- Create: `tests/hook_test.sh`

**Interfaces:**
- Consumes: `skills/superafk-guide/SKILL.md` (read at runtime; Task 7 creates the real content — a placeholder is created here so the hook is testable, then overwritten in Task 7).
- Produces: `hooks/session-start` reads the SessionStart JSON payload on stdin, extracts `session_id`, and prints a single JSON object with `hookSpecificOutput.additionalContext` containing the session id and the guide content.

- [ ] **Step 1: Create a temporary guide placeholder so the hook can be tested**

Create `skills/superafk-guide/SKILL.md` (overwritten in Task 7):
```markdown
---
name: superafk-guide
description: superAFK guide (placeholder, replaced in Task 7)
---
# superAFK guide
PLACEHOLDER
```

- [ ] **Step 2: Write the failing test**

Create `tests/hook_test.sh`:
```bash
#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib/assert.sh"
HOOK="$DIR/../hooks/session-start"

out="$(printf '{"session_id":"abc-123","source":"startup"}' | bash "$HOOK")"
assert_contains "$out" '"hookEventName": "SessionStart"' "emits SessionStart event"
assert_contains "$out" '"additionalContext"' "emits additionalContext"
assert_contains "$out" "abc-123" "injects the session id"
assert_contains "$out" "superAFK guide" "injects the guide content"

# Valid JSON (validate with python if available; otherwise skip the strict check)
if command -v python3 >/dev/null 2>&1; then
  echo "$out" | python3 -c 'import sys,json; json.load(sys.stdin)' \
    && echo "  ok: output is valid JSON" \
    || { echo "  FAIL: invalid JSON"; exit 1; }
fi

assert_report || exit 1
```

- [ ] **Step 3: Run it to confirm it fails**

Run: `bash tests/run.sh`
Expected: FAIL — `hooks/session-start` missing.

- [ ] **Step 4: Implement the hook script**

Create `hooks/session-start`:
```bash
#!/usr/bin/env bash
# SessionStart hook: inject the superafk-guide skill + this session's id as additionalContext.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

payload="$(cat || true)"
session_id="$(printf '%s' "$payload" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"

guide="$(cat "${PLUGIN_ROOT}/skills/superafk-guide/SKILL.md" 2>/dev/null || echo "Error reading superafk-guide skill")"

escape_for_json() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

guide_escaped="$(escape_for_json "$guide")"
id_escaped="$(escape_for_json "$session_id")"

context="<EXTREMELY_IMPORTANT>\nsuperAFK is active. Your current session id is: ${id_escaped}\n\nBelow is your 'superafk-guide' skill. Follow it.\n\n${guide_escaped}\n</EXTREMELY_IMPORTANT>"

printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "SessionStart",\n    "additionalContext": "%s"\n  }\n}\n' "$context"
exit 0
```
Then: `chmod +x hooks/session-start`

- [ ] **Step 5: Run tests to confirm pass**

Run: `bash tests/run.sh`
Expected: `hook_test.sh` asserts `ok` (incl. valid JSON if python3 present), `ALL TESTS PASSED`.

- [ ] **Step 6: Create the polyglot wrapper**

Create `hooks/run-hook.cmd` (Unix path is the part after `CMDBLOCK`; the batch header lets Windows find bash):
```
: << 'CMDBLOCK'
@echo off
if "%~1"=="" ( echo run-hook.cmd: missing script name >&2 & exit /b 1 )
set "HOOK_DIR=%~dp0"
if exist "C:\Program Files\Git\bin\bash.exe" (
    "C:\Program Files\Git\bin\bash.exe" "%HOOK_DIR%%~1" %2 %3 %4 %5 %6 %7 %8 %9
    exit /b %ERRORLEVEL%
)
where bash >nul 2>nul
if %ERRORLEVEL% equ 0 ( bash "%HOOK_DIR%%~1" %2 %3 %4 %5 %6 %7 %8 %9 & exit /b %ERRORLEVEL% )
exit /b 0
CMDBLOCK

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_NAME="$1"; shift
exec bash "${SCRIPT_DIR}/${SCRIPT_NAME}" "$@"
```

- [ ] **Step 7: Create the hook registration**

Create `hooks/hooks.json`:
```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|clear|compact",
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd\" session-start",
            "async": false
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 8: Verify the wrapper dispatches the hook**

Run: `printf '{"session_id":"zzz-9","source":"startup"}' | bash hooks/run-hook.cmd session-start`
Expected: same JSON object as the hook, containing `zzz-9` and `"hookEventName": "SessionStart"`.

- [ ] **Step 9: Commit**

```bash
git add hooks/hooks.json hooks/run-hook.cmd hooks/session-start skills/superafk-guide/SKILL.md tests/hook_test.sh
git commit -m "feat: SessionStart hook injects guide + session id"
```

---

### Task 7: `superafk-guide` skill (RED→GREEN per writing-skills)

**Files:**
- Modify: `skills/superafk-guide/SKILL.md` (replace the Task 6 placeholder)
- Create: `tests/skill_lint_test.sh`

**Interfaces:**
- Produces: the rules injected at SessionStart. MUST be token-lean (injected EVERY session — budget <200 words), `description` = triggering conditions only (NO workflow summary), name the 3 touchpoints + degradation + single-direction, and point at the `superafk` worker.

**Why this shape (superpowers:writing-skills):** a skill's real test is a subagent scenario (Iron Law: watch the baseline fail first), NOT a phrase-grep. `tests/skill_lint_test.sh` is only the mechanical gate (frontmatter / "Use when" description / word budget). Steps 1 and 6 are the RED→GREEN scenarios — the actual test.

- [ ] **Step 1 (RED): baseline — run the scenarios WITHOUT the guide, document the failure**

Dispatch a fresh subagent (superpowers:dispatching-parallel-agents) for EACH scenario, with NO superAFK context. Record the verbatim response.

Scenario A (touchpoint 1 — bind at start):
> You're about to help build a new feature with the superpowers workflow. The user says: "let's add dark mode." What are your first 1–3 actions? Be specific.

Scenario B (touchpoint 3 — post-PR):
> You just finished a feature with superpowers' finishing-a-development-branch, which opened PR #7. The work is tracked in GitHub issue #42. What do you do now? List your next actions.

Expected baseline (RED): A → jumps straight into brainstorming, creates/binds NO issue. B → treats it as done; does NOT link the PR to the issue, no completeness check, no handoff. Write these down — they are the failures the guide must fix.

- [ ] **Step 2: Write the mechanical lint (deterministic gate)**

Create `tests/skill_lint_test.sh`:
```bash
#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib/assert.sh"
cd "$DIR/.."

lint_skill() {   # <file> <word-budget>
  local md="$1" budget="$2" fm name desc words charset desc_ok ph words_ok
  fm="$(awk 'NR==1&&$0=="---"{f=1;next} f&&$0=="---"{exit} f{print}' "$md")"
  name="$(printf '%s\n' "$fm" | sed -n 's/^name:[[:space:]]*//p' | head -1)"
  desc="$(printf '%s\n' "$fm" | sed -n 's/^description:[[:space:]]*//p' | head -1)"
  words="$(wc -w < "$md" | tr -d ' ')"
  charset=pass; case "$name" in ""|*[!A-Za-z0-9-]*) charset=fail;; esac
  assert_eq "pass" "$charset" "$md: name charset (letters/numbers/hyphens)"
  desc_ok=fail; case "$desc" in "Use when"*) desc_ok=pass;; esac
  assert_eq "pass" "$desc_ok" "$md: description starts with 'Use when'"
  ph=pass; grep -q PLACEHOLDER "$md" && ph=fail
  assert_eq "pass" "$ph" "$md: no PLACEHOLDER"
  words_ok=pass; [ "$words" -le "$budget" ] || words_ok=fail
  assert_eq "pass" "$words_ok" "$md: <= $budget words (got $words)"
}

lint_skill skills/superafk-guide/SKILL.md 200
g="$(cat skills/superafk-guide/SKILL.md)"
assert_contains "$g" "finishing-a-development-branch" "guide: names the PR touchpoint"
assert_contains "$g" "superafk-issue" "guide: states the stamp rule"

if [ -f skills/superafk/SKILL.md ]; then
  lint_skill skills/superafk/SKILL.md 500
  w="$(cat skills/superafk/SKILL.md)"
  assert_contains "$w" "preflight" "worker: runs preflight"
  ck=pass; case "$w" in *"Closes #"*|*"Fixes #"*|*"Resolves #"*) ck=fail;; esac
  assert_eq "pass" "$ck" "worker: no closing keyword"
fi

assert_report || exit 1
```

- [ ] **Step 3: Run it to confirm it fails**

Run: `bash tests/run.sh`
Expected: FAIL — the guide still has the Task 6 `PLACEHOLDER`, and the placeholder description does not start with "Use when".

- [ ] **Step 4: Write the lean guide (trigger-only description, <200 words)**

Overwrite `skills/superafk-guide/SKILL.md`:
```markdown
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
```

- [ ] **Step 5: Run the suite — lint passes, hook still green**

Run: `bash tests/run.sh`
Expected: `skill_lint_test.sh` all `ok` (guide within 200 words, description starts with "Use when", no placeholder); `hook_test.sh` still passes (injects the real guide). `ALL TESTS PASSED`.

- [ ] **Step 6 (GREEN): re-run the scenarios WITH the guide; verify compliance**

For each scenario from Step 1, dispatch a fresh subagent whose context BEGINS with the full guide text (simulating the SessionStart injection), then the scenario prompt.

Pass criteria:
- Scenario A → the agent binds/creates the idea-issue via the superafk skill BEFORE brainstorming.
- Scenario B → the agent invokes the superafk skill to run the post-PR takeover (link PR, completeness check, finished/handoff, release lock).

- [ ] **Step 7 (REFACTOR): close loopholes**

If a scenario still fails or the agent rationalizes (e.g., "the PR is open, I'm done"), add ONE explicit counter line to the guide addressing that exact rationalization, then re-run Step 6 until both pass. Keep it under 200 words (`bash tests/run.sh` must stay green).

- [ ] **Step 8: Commit**

```bash
git add skills/superafk-guide/SKILL.md tests/skill_lint_test.sh
git commit -m "feat: superafk-guide skill (lean, trigger-only description, scenario-tested)"
```

---

### Task 8: `superafk` worker skill (RED→GREEN per writing-skills)

**Files:**
- Create: `skills/superafk/SKILL.md`

**Interfaces:**
- Consumes: `scripts/frontmatter.sh`, `scripts/scan.sh`, `scripts/issue_body.sh`, `scripts/gh.sh`, and the session id injected by the hook.
- Produces: the worker procedure for all 3 touchpoints. `description` = triggers only; body <500 words; NEVER uses a closing keyword or `gh issue close`. Linted by `tests/skill_lint_test.sh` (created in Task 7), which now also covers this file.

- [ ] **Step 1 (RED): baseline — run the takeover WITHOUT the worker, document the footguns**

Dispatch a fresh subagent whose context has the `superafk-guide` (so it knows a takeover is due) but NOT the worker skill:
> [superafk-guide is active in your context.] You opened PR #7 for idea issue #42. The plugin's scripts are in `./scripts`. Run the superAFK post-PR takeover — show the EXACT shell commands you would run, in order.

Expected baseline (RED): it improvises — typically `gh issue close 42` and/or a `Closes #42` reference, and often skips the file scan or the lock release. Record the exact commands. Those footguns (auto-close, closing keyword) are precisely what the worker must prevent.

- [ ] **Step 2: Write the worker skill (trigger-only description)**

Create `skills/superafk/SKILL.md`:
````markdown
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
````

- [ ] **Step 3: Run the mechanical lint**

Run: `bash tests/run.sh`
Expected: `skill_lint_test.sh` now also lints the worker — `ok` for: description starts with "Use when", `<= 500 words`, runs `preflight`, no closing keyword. `ALL TESTS PASSED`.

- [ ] **Step 4 (GREEN): re-run the takeover scenario WITH the worker skill**

Dispatch a fresh subagent whose context includes the worker skill, with the SAME prompt as Step 1.

Pass criteria (ALL must hold):
- Commands follow the worker order: `preflight` → `gh.sh comment` (PR link) → `scan.sh` → completeness judgment → `add-finished` OR handoff comment → `issue_body.sh clear`.
- Contains NO `gh issue close` and NO `Closes/Fixes/Resolves #`.
- Includes BOTH the file scan and the lock release.

- [ ] **Step 5 (REFACTOR): close loopholes**

If the agent still reaches for `gh issue close` or a closing keyword, or skips the scan / lock-release, add ONE explicit counter to the relevant worker step (e.g., "NEVER `gh issue close` — a human closes") and re-run Step 4 until it complies. Keep the body <500 words.

- [ ] **Step 6: Commit**

```bash
git add skills/superafk/SKILL.md
git commit -m "feat: superafk worker skill (trigger-only description, scenario-tested, no auto-close)"
```

---

### Task 9: README + opt-in integration scenario

**Files:**
- Create: `README.md`
- Create: `tests/integration_test.sh`

**Interfaces:**
- Consumes: all scripts; real `gh` (only when `SUPERAFK_RUN_INTEGRATION=1` and `gh auth status` succeed).
- Produces: user-facing docs; one end-to-end gh scenario that is SKIPPED (passes) unless explicitly enabled.

- [ ] **Step 1: Write the integration test (skips unless enabled)**

Create `tests/integration_test.sh`:
```bash
#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib/assert.sh"

if [ "${SUPERAFK_RUN_INTEGRATION:-0}" != "1" ] || ! gh auth status >/dev/null 2>&1; then
  echo "  skip: integration disabled (set SUPERAFK_RUN_INTEGRATION=1 with gh auth + SUPERAFK_TEST_REPO)"
  assert_report || exit 1
  exit 0
fi

S="$DIR/../scripts"
repo="${SUPERAFK_TEST_REPO:?set SUPERAFK_TEST_REPO=owner/name}"
title="superAFK integration $(date +%s)"

num="$(GH_REPO="$repo" bash "$S/gh.sh" create-idea "$title" "idea: prove the loop")"
case "$num" in ''|*[!0-9]*) numok=fail;; *) numok=pass;; esac
assert_eq "pass" "$numok" "create-idea returned a numeric issue number ($num)"
GH_REPO="$repo" bash "$S/gh.sh" comment "$num" "superAFK: PR #1 — https://example/pr/1"
GH_REPO="$repo" bash "$S/gh.sh" add-finished "$num"
state="$(GH_REPO="$repo" gh issue view "$num" --json state -q .state)"
assert_eq "OPEN" "$state" "finished issue stays OPEN (human closes)"
GH_REPO="$repo" gh issue close "$num" >/dev/null 2>&1 || true   # cleanup

assert_report || exit 1
```
(Note: `gh.sh` honors `GH_REPO` because gh itself does; no code change needed.)

- [ ] **Step 2: Run the suite — integration skips, everything else passes**

Run: `bash tests/run.sh`
Expected: `integration_test.sh` prints `skip: integration disabled`, all other tests pass, `ALL TESTS PASSED`.

- [ ] **Step 3: Write the README**

Create `README.md`:
```markdown
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
```

- [ ] **Step 4: Run the full suite once more**

Run: `bash tests/run.sh`
Expected: `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add README.md tests/integration_test.sh
git commit -m "docs: README + opt-in gh integration scenario"
```

---

## Notes for the implementer

- **Run `bash tests/run.sh` after every task** — it is the mechanical gate (scripts + the skill lint). Tasks 7–8 ALSO require their RED→GREEN subagent scenarios (Steps 1 & 6 / Steps 1 & 4); those are agentic and not part of `run.sh`.
- The two skills are prose executed by the model. Per superpowers:writing-skills they are tested by **subagent scenarios** (baseline fails first, then comply-with-skill, then refactor); `tests/skill_lint_test.sh` enforces only the mechanical properties (frontmatter, "Use when" description, <word budget, no placeholder). The deterministic logic lives in `scripts/*.sh`, which are unit-tested.
- Do not add a local state file, do not use closing keywords, do not auto-close issues, do not add other-platform hooks — all are explicit Phase-1 constraints above.
- `gh.sh` calls real GitHub; everything that touches it in unit tests goes through `tests/fixtures/bin/gh`.
