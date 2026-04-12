#!/usr/bin/env bash
# test-branch-safety.sh — Tests for branch-safety hook
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/branch-safety.sh"

# --- Test: non-push command passes ---
test_non_push_passes() {
  setup_test_project
  INPUT='{"tool_input":{"command":"git status"}}'
  EXIT=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT" "non-push should pass"
  teardown_test_project
}

# --- Test: push from protected branch blocks ---
test_push_protected_blocks() {
  setup_test_project
  # Default test project is on main, which is in protectedBranches
  INPUT='{"tool_input":{"command":"git push origin main"}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  EXIT=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT" "push from protected branch should block"
  assert_contains "$RESULT" "PUSH BLOCKED" "should say push blocked"
  teardown_test_project
}

# --- Test: push from non-protected branch passes ---
test_push_dev_branch_passes() {
  setup_test_project
  git -C "$TEST_DIR" checkout -b feature/test --quiet
  INPUT='{"tool_input":{"command":"git push origin feature/test"}}'
  EXIT=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT" "push from dev branch should pass"
  teardown_test_project
}

# --- Test: chained git push from protected branch blocks ---
test_chained_push_protected_blocks() {
  setup_test_project
  INPUT='{"tool_input":{"command":"echo ok && git push origin main"}}'
  EXIT=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT" "chained push from protected branch should block"
  teardown_test_project
}

# --- Run all tests ---
echo "branch-safety.sh"
test_non_push_passes
test_push_protected_blocks
test_push_dev_branch_passes
test_chained_push_protected_blocks
run_tests
