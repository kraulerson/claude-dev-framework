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

# --- Test: a refspec whose destination is protected blocks from any branch (#18) ---
test_refspec_destination_protected_blocks() {
  setup_test_project
  git -C "$TEST_DIR" checkout -b feature/test --quiet
  local cmd
  for cmd in "git push origin HEAD:main" \
             "git push origin feature/test:main" \
             "git push origin +feature/test:main" \
             "git push origin HEAD:refs/heads/main" \
             "git push origin refs/heads/main" \
             "git push origin feature/test HEAD:main" \
             "git push origin :main" \
             "git push origin --delete main" \
             "; git push origin HEAD:main" \
             "echo ok && git push -u origin \"HEAD:main\""; do
    INPUT=$(jq -n --arg c "$cmd" '{tool_input: {command: $c}}')
    RESULT=$(run_hook "$HOOK" "$INPUT")
    EXIT=$(run_hook_exit_code "$HOOK" "$INPUT")
    assert_exit_code "2" "$EXIT" "'$cmd' from feature/test should block"
    assert_contains "$RESULT" "PUSH BLOCKED" "'$cmd' should say push blocked"
  done
  teardown_test_project
}

# --- Test: --all, --branches, --mirror, ":" and a wildcard reach every branch ---
test_all_branches_push_blocks_when_protected() {
  setup_test_project
  git -C "$TEST_DIR" checkout -b feature/test --quiet
  local cmd
  for cmd in "git push --all origin" "git push origin --branches" "git push --mirror origin" \
             "git push origin :" "git push origin 'refs/heads/*:refs/heads/*'"; do
    INPUT=$(jq -n --arg c "$cmd" '{tool_input: {command: $c}}')
    EXIT=$(run_hook_exit_code "$HOOK" "$INPUT")
    assert_exit_code "2" "$EXIT" "'$cmd' should block while a branch is protected"
  done
  teardown_test_project
}

# --- Test: with no protected branches, --all is allowed ---
test_all_branches_push_passes_without_protected() {
  setup_test_project
  git -C "$TEST_DIR" checkout -b feature/test --quiet
  jq '.projectConfig._base.protectedBranches = []' "$TEST_DIR/.claude/manifest.json" \
    > "$TEST_DIR/manifest.tmp" && mv "$TEST_DIR/manifest.tmp" "$TEST_DIR/.claude/manifest.json"
  INPUT='{"tool_input":{"command":"git push --all origin"}}'
  EXIT=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT" "--all with no protected branches should pass"
  teardown_test_project
}

# --- Test: unprotected destinations and non-push commands still pass ---
test_refspec_destination_unprotected_passes() {
  setup_test_project
  git -C "$TEST_DIR" checkout -b feature/test --quiet
  local cmd
  for cmd in "git push origin HEAD:feature/test" \
             "git push origin HEAD:refs/heads/feature/test" \
             "git push origin HEAD:mainline" \
             "git push origin refs/tags/main" \
             "git push origin feature/test && git log main" \
             "git commit -m \"block push to main\"" \
             "git stash push -- main" \
             "git push"; do
    INPUT=$(jq -n --arg c "$cmd" '{tool_input: {command: $c}}')
    EXIT=$(run_hook_exit_code "$HOOK" "$INPUT")
    assert_exit_code "0" "$EXIT" "'$cmd' from feature/test should pass"
  done
  teardown_test_project
}

# --- Test: a bare push from a protected branch still blocks ---
test_bare_push_protected_blocks() {
  setup_test_project
  git -C "$TEST_DIR" checkout -B main --quiet
  INPUT='{"tool_input":{"command":"git push"}}'
  EXIT=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT" "bare push from protected branch should block"
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
test_refspec_destination_protected_blocks
test_all_branches_push_blocks_when_protected
test_all_branches_push_passes_without_protected
test_refspec_destination_unprotected_passes
test_bare_push_protected_blocks
run_tests
