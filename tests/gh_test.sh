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

# add-finished must add the finished label and must NOT close the issue
: > "$GH_MOCK_LOG"
bash "$GH" add-finished 42
log="$(cat "$GH_MOCK_LOG")"
assert_contains "$log" "--add-label finished" "add-finished adds finished label"
case "$log" in *close*|*--state*) bad=1;; *) bad=0;; esac
assert_eq "0" "$bad" "add-finished never closes the issue"

assert_report || exit 1
