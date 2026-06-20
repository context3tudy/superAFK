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
