#!/usr/bin/env bash
set -u
cd "$(dirname "$0")/.."
rc=0
shopt -s nullglob
for t in tests/*_test.sh; do
  echo "== $t =="
  if ! bash "$t"; then rc=1; fi
done
if [ "$rc" -eq 0 ]; then echo "ALL TESTS PASSED"; else echo "SOME TESTS FAILED"; fi
exit "$rc"
