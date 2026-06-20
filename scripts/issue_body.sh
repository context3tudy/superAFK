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
