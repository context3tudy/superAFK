# Shared assertions for superAFK bash tests. Source this in each *_test.sh.
ASSERT_FAILED=0
ASSERT_TOTAL=0

assert_eq() {
  ASSERT_TOTAL=$((ASSERT_TOTAL + 1))
  if [ "$1" = "$2" ]; then
    echo "  ok: ${3:-}"
  else
    ASSERT_FAILED=$((ASSERT_FAILED + 1))
    echo "  FAIL: ${3:-}"
    echo "    expected: [$1]"
    echo "    actual:   [$2]"
  fi
}

assert_contains() {
  ASSERT_TOTAL=$((ASSERT_TOTAL + 1))
  case "$1" in
    *"$2"*) echo "  ok: ${3:-}" ;;
    *)
      ASSERT_FAILED=$((ASSERT_FAILED + 1))
      echo "  FAIL: ${3:-} (missing substring: [$2])"
      ;;
  esac
}

assert_report() {
  echo "  $((ASSERT_TOTAL - ASSERT_FAILED))/${ASSERT_TOTAL} passed"
  [ "$ASSERT_FAILED" -eq 0 ]
}
