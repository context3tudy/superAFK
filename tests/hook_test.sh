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
