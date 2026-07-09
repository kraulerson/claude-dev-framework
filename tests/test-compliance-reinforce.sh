#!/usr/bin/env bash
# test-compliance-reinforce.sh — Tests for the compliance-reinforce UserPromptSubmit hook
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/compliance-reinforce.sh"

echo "compliance-reinforce"

# --- exit code is 0 (advisory) ---
test_exit_zero() {
  setup_test_project
  CODE=$(run_hook_exit_code "$HOOK" '{}')
  assert_equals "0" "$CODE" "compliance-reinforce: exits 0 on empty input"
  teardown_test_project
}

# --- stdout is valid JSON with the correct hookEventName ---
test_json_output() {
  setup_test_project
  OUTPUT=$(run_hook "$HOOK" '{}')

  # Valid JSON
  echo "$OUTPUT" | jq -e '.' >/dev/null 2>&1
  assert_equals "0" "$?" "compliance-reinforce: stdout parses as JSON"

  EVENT=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null || echo "")
  assert_equals "UserPromptSubmit" "$EVENT" "compliance-reinforce: hookEventName is UserPromptSubmit"

  CTX=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null || echo "")
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -n "$CTX" ] && [ "$CTX" != "null" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILURES="${FAILURES}  FAIL: compliance-reinforce: additionalContext is non-empty\n    got: '${CTX}'\n"
  fi

  teardown_test_project
}

test_exit_zero
test_json_output
run_tests
