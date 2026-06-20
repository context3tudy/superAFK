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
