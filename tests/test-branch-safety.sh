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

# --- Test: force push blocked on any branch ---
test_force_push_blocked() {
  setup_test_project
  git -C "$TEST_DIR" checkout -b feature/test --quiet
  INPUT='{"tool_input":{"command":"git push --force origin feature/test"}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  EXIT=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT" "force push should block"
  assert_contains "$RESULT" "BLOCKED" "should say blocked"
  teardown_test_project
}

# --- Test: force push with -f flag blocked ---
test_force_push_short_flag_blocked() {
  setup_test_project
  git -C "$TEST_DIR" checkout -b feature/test --quiet
  INPUT='{"tool_input":{"command":"git push -f origin feature/test"}}'
  EXIT=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT" "force push with -f should block"
  teardown_test_project
}

# --- Test: force-with-lease blocked ---
test_force_with_lease_blocked() {
  setup_test_project
  git -C "$TEST_DIR" checkout -b feature/test --quiet
  INPUT='{"tool_input":{"command":"git push --force-with-lease origin feature/test"}}'
  EXIT=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT" "force-with-lease should block"
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

# --- Test: refspec force syntax (+branch) blocked ---
test_refspec_force_blocked() {
  setup_test_project
  INPUT='{"tool_input":{"command":"git push origin +main"}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  EXIT=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT" "refspec force push should block"
  assert_contains "$RESULT" "Refspec force syntax" "should mention refspec force syntax"
  teardown_test_project
}

# --- Test: refspec force syntax blocked even on a dev branch ---
test_refspec_force_dev_branch_blocked() {
  setup_test_project
  git -C "$TEST_DIR" checkout -b feature/test --quiet
  INPUT='{"tool_input":{"command":"git push origin +feature/test"}}'
  EXIT=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT" "refspec force push should block on dev branch too"
  teardown_test_project
}

# --- Test: normal push to non-protected branch still passes (no false positive) ---
test_normal_push_dev_branch_passes() {
  setup_test_project
  git -C "$TEST_DIR" checkout -b feature/test --quiet
  INPUT='{"tool_input":{"command":"git push origin feature/test"}}'
  EXIT=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT" "normal push to dev branch should pass"
  teardown_test_project
}

# --- Test: a `+` after a shell separator is not a force refspec ---
# Regression: the detector must not reach across && ; || into a later command.
test_chained_plus_after_push_passes() {
  setup_test_project
  git -C "$TEST_DIR" checkout -b feature/test --quiet
  INPUT='{"tool_input":{"command":"git push origin feature/test && chmod +x deploy.sh"}}'
  EXIT=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT" "chmod +x after && should not read as force push"
  INPUT='{"tool_input":{"command":"git push origin feature/test; echo \"+1 deployed\""}}'
  EXIT=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT" "quoted +1 after ; should not read as force push"
  teardown_test_project
}

# --- Test: force refspec smuggled through git config is blocked ---
test_config_force_refspec_blocked() {
  setup_test_project
  git -C "$TEST_DIR" checkout -b feature/test --quiet
  INPUT='{"tool_input":{"command":"git -c remote.origin.push=+main push origin"}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  EXIT=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT" "-c force refspec should block"
  assert_contains "$RESULT" "BLOCKED" "should say blocked"
  INPUT='{"tool_input":{"command":"git config remote.origin.push +refs/heads/main"}}'
  EXIT=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT" "git config force refspec should block"
  teardown_test_project
}

# --- Run all tests ---
echo "branch-safety.sh"
test_non_push_passes
test_push_protected_blocks
test_push_dev_branch_passes
test_force_push_blocked
test_force_push_short_flag_blocked
test_force_with_lease_blocked
test_chained_push_protected_blocks
test_refspec_force_blocked
test_refspec_force_dev_branch_blocked
test_chained_plus_after_push_passes
test_config_force_refspec_blocked
test_normal_push_dev_branch_passes
run_tests
