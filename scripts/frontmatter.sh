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
