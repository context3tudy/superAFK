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

# exit 0 even when last file (alphabetically) is a non-match
nonmatch_root="$(mktemp -d)"; trap 'rm -rf "$nonmatch_root"' EXIT
mkdir -p "$nonmatch_root/docs/superpowers/specs"
printf '# match\n' > "$nonmatch_root/docs/superpowers/specs/a-match.md"
bash "$FM" set-issue "$nonmatch_root/docs/superpowers/specs/a-match.md" 5
printf '# nomatch\n' > "$nonmatch_root/docs/superpowers/specs/z-nomatch.md"
bash "$FM" set-issue "$nonmatch_root/docs/superpowers/specs/z-nomatch.md" 99
out="$(cd "$nonmatch_root" && bash "$SCAN" 5)"; rc=$?
assert_eq "0" "$rc" "scan exits 0 even when last file is a non-match"

assert_report || exit 1
