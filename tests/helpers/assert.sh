#!/usr/bin/env bash
# assert.sh — Assertion functions for framework hook tests

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILURES=""

assert_equals() {
  local expected="$1" actual="$2" msg="${3:-}"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "$expected" = "$actual" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILURES="${FAILURES}  FAIL: ${msg:-assert_equals}\n    expected: '${expected}'\n    actual:   '${actual}'\n"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  TESTS_RUN=$((TESTS_RUN + 1))
  if echo "$haystack" | grep -q "$needle"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILURES="${FAILURES}  FAIL: ${msg:-assert_contains}\n    expected to contain: '${needle}'\n    in: '${haystack:0:200}'\n"
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  TESTS_RUN=$((TESTS_RUN + 1))
  if ! echo "$haystack" | grep -q "$needle"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILURES="${FAILURES}  FAIL: ${msg:-assert_not_contains}\n    expected NOT to contain: '${needle}'\n    in: '${haystack:0:200}'\n"
  fi
}

assert_exit_code() {
  local expected="$1" actual="$2" msg="${3:-}"
  assert_equals "$expected" "$actual" "${msg:-exit code should be $expected}"
}

assert_file_exists() {
  local path="$1" msg="${2:-}"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -f "$path" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILURES="${FAILURES}  FAIL: ${msg:-assert_file_exists}\n    file not found: '${path}'\n"
  fi
}

assert_file_not_exists() {
  local path="$1" msg="${2:-}"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ ! -f "$path" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILURES="${FAILURES}  FAIL: ${msg:-assert_file_not_exists}\n    file should not exist: '${path}'\n"
  fi
}

# Call at end of test file to print results and exit with appropriate code
run_tests() {
  echo ""
  if [ "$TESTS_FAILED" -gt 0 ]; then
    printf "%b" "$FAILURES"
    echo "  $TESTS_RUN tests, $TESTS_PASSED passed, $TESTS_FAILED FAILED"
    return 1
  else
    echo "  $TESTS_RUN tests, $TESTS_PASSED passed, 0 failed"
    return 0
  fi
}
