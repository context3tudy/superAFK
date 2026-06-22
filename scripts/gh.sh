#!/usr/bin/env bash
# Thin wrappers over the gh CLI used by superAFK. Never embeds closing keywords.
set -euo pipefail

cmd="${1:-}"; shift || true

case "$cmd" in
  preflight)
    gh auth status >/dev/null 2>&1 || { echo "superAFK: gh not authenticated; skipping issue sync." >&2; exit 10; }
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "superAFK: not a git repo; skipping." >&2; exit 11; }
    git remote get-url origin >/dev/null 2>&1 || { echo "superAFK: no origin remote; skipping." >&2; exit 12; }
    gh repo view >/dev/null 2>&1 || { echo "superAFK: origin is not a GitHub repo; skipping." >&2; exit 13; }
    ;;
  ensure-labels)
    gh label create superafk --description "superAFK idea tracker" --color 1f6feb --force >/dev/null
    gh label create finished --description "superAFK: idea complete (close manually)" --color 0e8a16 --force >/dev/null
    gh label create superafk-auto --description "superAFK: autonomous after design approval" --color 8250df --force >/dev/null
    ;;
  visibility)
    gh repo view --json visibility -q .visibility
    ;;
  create-idea)
    title="${1:?title}"; body="${2:?body}"
    url="$(gh issue create --title "$title" --body "$body" --label superafk)"
    printf '%s\n' "$url" | awk -F/ '{print $NF}'
    ;;
  body)
    gh issue view "${1:?n}" --json body -q .body
    ;;
  comment)
    gh issue comment "${1:?n}" --body "${2:?body}" >/dev/null
    ;;
  add-finished)
    gh issue edit "${1:?n}" --add-label finished >/dev/null
    ;;
  add-auto)
    gh issue edit "${1:?n}" --add-label superafk-auto >/dev/null
    ;;
  has-auto)
    if gh issue view "${1:?n}" --json labels -q '.labels[].name' | grep -qx superafk-auto; then
      echo auto
    else
      echo manual
    fi
    ;;
  set-body)
    gh issue edit "${1:?n}" --body "${2:?body}" >/dev/null
    ;;
  *)
    echo "usage: gh.sh {preflight|ensure-labels|visibility|create-idea|body|comment|add-finished|add-auto|has-auto|set-body}" >&2
    exit 2
    ;;
esac
