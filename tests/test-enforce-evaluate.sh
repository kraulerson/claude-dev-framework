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

# --- Test: --no-verify blocked ---
test_no_verify_blocked() {
  setup_test_project
  touch "/tmp/.claude_evaluated_${TEST_HASH}"
  INPUT='{"tool_input":{"command":"git commit --no-verify -m \"bypass hooks\""}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "--no-verify should block even with evaluate marker"
  teardown_test_project
}

# --- Test: --amend warns but allows ---
test_amend_warns() {
  setup_test_project
  touch "/tmp/.claude_evaluated_${TEST_HASH}"
  INPUT='{"tool_input":{"command":"git commit --amend -m \"rewrite\""}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "--amend should allow (advisory only)"
  assert_contains "$RESULT" "WARNING" "--amend should produce a warning"
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

# --- Test: -n short flag blocked even with evaluated marker ---
test_short_n_flag_blocked() {
  setup_test_project
  touch "/tmp/.claude_evaluated_${TEST_HASH}"
  INPUT='{"tool_input":{"command":"git commit -n -m \"bypass hooks\""}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "-n should block even with evaluate marker"
  assert_contains "$RESULT" "shorthand for --no-verify" "should mention the -n flag is shorthand"
  teardown_test_project
}

# --- Test: core.hooksPath override blocked ---
test_hookspath_override_blocked() {
  setup_test_project
  touch "/tmp/.claude_evaluated_${TEST_HASH}"
  INPUT='{"tool_input":{"command":"git -c core.hooksPath=/dev/null commit -m \"x\""}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "core.hooksPath override should block"
  assert_contains "$RESULT" "core.hooksPath" "should mention core.hooksPath"
  teardown_test_project
}

# --- Test: --no-verif (git long-option abbreviation) is blocked (R-12) ---
test_no_verify_abbreviation_blocked() {
  setup_test_project
  touch "/tmp/.claude_evaluated_${TEST_HASH}"
  INPUT='{"tool_input":{"command":"git commit --no-verif -m \"x\""}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "--no-verif abbreviation should block even with marker"
  assert_contains "$RESULT" "no-verify" "should mention --no-verify"
  teardown_test_project
}

# --- Test: core.hooksPath set in a SEPARATE non-commit command is blocked (R-12) ---
test_hookspath_separate_command_blocked() {
  setup_test_project
  touch "/tmp/.claude_evaluated_${TEST_HASH}"
  INPUT='{"tool_input":{"command":"git config core.hooksPath /dev/null"}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "git config core.hooksPath (non-commit) should block"
  assert_contains "$RESULT" "core.hooksPath" "should mention core.hooksPath"
  teardown_test_project
}

# --- Test: -m message flag does NOT trip the -n detector ---
test_message_flag_not_flagged() {
  setup_test_project
  touch "/tmp/.claude_evaluated_${TEST_HASH}"
  INPUT='{"tool_input":{"command":"git commit -m \"Add feature\""}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "-m must not trip the -n detector"
  assert_equals "" "$RESULT" "-m commit with marker should produce no output"
  teardown_test_project
}

# --- Run all tests ---
echo "enforce-evaluate.sh"
test_non_commit_passthrough
test_commit_without_marker
test_commit_with_marker
test_chained_commit_blocks
test_no_verify_blocked
test_amend_warns
test_short_n_flag_blocked
test_hookspath_override_blocked
test_no_verify_abbreviation_blocked
test_hookspath_separate_command_blocked
test_message_flag_not_flagged
run_tests
