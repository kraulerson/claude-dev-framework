#!/usr/bin/env bash
# run-tests.sh — Discovers and runs all test-*.sh files
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
TOTAL_FILES=0
PASSED_FILES=0
FAILED_FILES=0
FAILED_NAMES=""

echo "=== Development Guardrails Test Suite ==="
echo ""

for test_file in "$TESTS_DIR"/test-*.sh; do
  [ -f "$test_file" ] || continue
  name=$(basename "$test_file")
  TOTAL_FILES=$((TOTAL_FILES + 1))

  echo "Running: $name"
  if bash "$test_file"; then
    PASSED_FILES=$((PASSED_FILES + 1))
  else
    FAILED_FILES=$((FAILED_FILES + 1))
    FAILED_NAMES="${FAILED_NAMES}  - ${name}\n"
  fi
done

echo ""
echo "=== Results ==="
echo "$TOTAL_FILES test files, $PASSED_FILES passed, $FAILED_FILES failed"

if [ "$FAILED_FILES" -gt 0 ]; then
  echo ""
  echo "Failed:"
  printf "%b" "$FAILED_NAMES"
  exit 1
fi
exit 0
