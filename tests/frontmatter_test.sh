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
