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
assert_contains "$g" "superafk-auto" "guide: names the autonomy label"
assert_contains "$g" "any outcome" "guide: takeover is outcome-agnostic"

if [ -f skills/superafk/SKILL.md ]; then
  lint_skill skills/superafk/SKILL.md 500
  w="$(cat skills/superafk/SKILL.md)"
  assert_contains "$w" "preflight" "worker: runs preflight"
  ck=pass; case "$w" in *"Closes #"*|*"Fixes #"*|*"Resolves #"*) ck=fail;; esac
  assert_eq "pass" "$ck" "worker: no closing keyword"
  assert_contains "$w" "has-auto" "worker: reads autonomy via has-auto"
  assert_contains "$w" "discard" "worker: takeover covers non-PR outcomes"
fi

assert_report || exit 1
