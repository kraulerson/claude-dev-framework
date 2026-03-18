#!/usr/bin/env bash
# test-enforce-evaluate.sh — Tests for enforce-evaluate hook
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/enforce-evaluate.sh"

# --- Test: non-commit command passes silently ---
test_non_commit_passthrough() {
  setup_test_project
  INPUT='{"tool_input":{"command":"git status"}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  assert_equals "" "$RESULT" "non-commit should produce no output"
  teardown_test_project
}

# --- Test: commit without marker produces advisory ---
test_commit_without_marker() {
  setup_test_project
  INPUT='{"tool_input":{"command":"git commit -m \"Add feature\""}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  assert_contains "$RESULT" "additionalContext" "should produce advisory"
  assert_contains "$RESULT" "evaluate-before-implement" "should mention the rule"
  teardown_test_project
}

# --- Test: commit with marker passes ---
test_commit_with_marker() {
  setup_test_project
  touch "/tmp/.claude_evaluated_${TEST_HASH}"
  INPUT='{"tool_input":{"command":"git commit -m \"Add feature\""}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  assert_equals "" "$RESULT" "commit with marker should produce no output"
  teardown_test_project
}

# --- Run all tests ---
echo "enforce-evaluate.sh"
test_non_commit_passthrough
test_commit_without_marker
test_commit_with_marker
run_tests
