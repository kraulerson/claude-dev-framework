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

# --- Run all tests ---
echo "marker-guard.sh (v4 markers)"
test_blocks_plan_active
test_blocks_has_plan
test_blocks_c7
test_allows_normal_touch
run_tests
