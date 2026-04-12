#!/usr/bin/env bash
# test-marker-guard-v4.sh — Tests for v4 marker types in marker-guard
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/marker-guard.sh"

# --- Test: blocks manual plan_active marker creation ---
test_blocks_plan_active() {
  setup_test_project
  INPUT='{"tool_input":{"command":"touch /tmp/.claude_plan_active_abc123"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block plan_active marker creation"
  teardown_test_project
}

# --- Test: blocks manual has_plan marker creation ---
test_blocks_has_plan() {
  setup_test_project
  INPUT='{"tool_input":{"command":"touch /tmp/.claude_has_plan_abc123"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block has_plan marker creation"
  teardown_test_project
}

# --- Test: blocks manual c7 marker creation ---
test_blocks_c7() {
  setup_test_project
  INPUT='{"tool_input":{"command":"touch /tmp/.claude_c7_abc123_react"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block c7 marker creation"
  teardown_test_project
}

# --- Test: allows non-marker touch commands ---
test_allows_normal_touch() {
  setup_test_project
  INPUT='{"tool_input":{"command":"touch /tmp/myfile.txt"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "should allow normal touch commands"
  teardown_test_project
}

# --- Test: blocks echo redirect to marker path ---
test_blocks_echo_redirect() {
  setup_test_project
  INPUT='{"tool_input":{"command":"echo \"\" > /tmp/.claude_superpowers_abc123"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block echo redirect to marker"
  teardown_test_project
}

# --- Test: blocks printf redirect to marker path ---
test_blocks_printf_redirect() {
  setup_test_project
  INPUT='{"tool_input":{"command":"printf \"\" > /tmp/.claude_superpowers_abc123"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block printf redirect to marker"
  teardown_test_project
}

# --- Test: blocks cp to marker path ---
test_blocks_cp_to_marker() {
  setup_test_project
  INPUT='{"tool_input":{"command":"cp /dev/null /tmp/.claude_evaluated_abc123"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block cp to marker"
  teardown_test_project
}

# --- Test: blocks python file creation at marker path ---
test_blocks_python_marker() {
  setup_test_project
  INPUT="{\"tool_input\":{\"command\":\"python3 -c \\\"open('/tmp/.claude_superpowers_abc123','w')\\\"\"}}"
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block python marker creation"
  teardown_test_project
}

# --- Test: blocks tee to marker path ---
test_blocks_tee_marker() {
  setup_test_project
  INPUT='{"tool_input":{"command":"tee /tmp/.claude_has_plan_abc123 < /dev/null"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block tee to marker path"
  teardown_test_project
}

# --- Test: still allows mark-evaluated.sh ---
test_allows_mark_evaluated_script() {
  setup_test_project
  INPUT='{"tool_input":{"command":"bash .claude/framework/hooks/mark-evaluated.sh \"user approved\""}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "should allow mark-evaluated.sh"
  teardown_test_project
}

# --- Test: still allows non-marker tmp files ---
test_allows_unrelated_tmp_files() {
  setup_test_project
  INPUT='{"tool_input":{"command":"echo test > /tmp/.claude_other_file"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "should allow non-marker tmp files"
  teardown_test_project
}

# --- Run all tests ---
echo "marker-guard.sh (v4 markers)"
test_blocks_plan_active
test_blocks_has_plan
test_blocks_c7
test_allows_normal_touch
test_blocks_echo_redirect
test_blocks_printf_redirect
test_blocks_cp_to_marker
test_blocks_python_marker
test_blocks_tee_marker
test_allows_mark_evaluated_script
test_allows_unrelated_tmp_files
run_tests
