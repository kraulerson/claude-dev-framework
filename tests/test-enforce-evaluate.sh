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

# --- Test: commit without marker blocks with exit 2 ---
test_commit_without_marker() {
  setup_test_project
  INPUT='{"tool_input":{"command":"git commit -m \"Add feature\""}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block with exit 2"
  assert_contains "$RESULT" "BLOCKED" "should say BLOCKED"
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

# --- Test: chained git commit still blocks ---
test_chained_commit_blocks() {
  setup_test_project
  INPUT='{"tool_input":{"command":"cd . && git commit -m \"bypass\""}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "chained git commit should still block"
  teardown_test_project
}

# --- Run all tests ---
echo "enforce-evaluate.sh"
test_non_commit_passthrough
test_commit_without_marker
test_commit_with_marker
test_chained_commit_blocks
run_tests
