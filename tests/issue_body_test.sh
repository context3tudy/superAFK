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
