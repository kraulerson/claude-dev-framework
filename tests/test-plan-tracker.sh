#!/usr/bin/env bash
# test-plan-tracker.sh — Tests for plan-tracker PostToolUse hook
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/plan-tracker.sh"

# --- Test: creates plan_active marker on TaskUpdate to in_progress ---
test_creates_marker_on_in_progress() {
  setup_test_project
  INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"in_progress"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_plan_active_${TEST_HASH}" "should create plan_active marker"
  teardown_test_project
}

# --- Test: clears plan_active marker on TaskUpdate to completed ---
test_clears_marker_on_completed() {
  setup_test_project
  touch "/tmp/.claude_plan_active_${TEST_HASH}"
  INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_not_exists "/tmp/.claude_plan_active_${TEST_HASH}" "should clear plan_active marker on completed"
  teardown_test_project
}

# --- Test: ignores non-TaskUpdate tools ---
test_ignores_other_tools() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"echo hello"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_not_exists "/tmp/.claude_plan_active_${TEST_HASH}" "should not create marker for non-TaskUpdate"
  teardown_test_project
}

# --- Test: ignores TaskUpdate without status change ---
test_ignores_no_status() {
  setup_test_project
  INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","subject":"New name"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_not_exists "/tmp/.claude_plan_active_${TEST_HASH}" "should not create marker for TaskUpdate without status"
  teardown_test_project
}

# --- Test: does not create marker on TaskUpdate to pending ---
test_ignores_pending() {
  setup_test_project
  INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"pending"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_not_exists "/tmp/.claude_plan_active_${TEST_HASH}" "should not create marker for pending status"
  teardown_test_project
}

# --- Run all tests ---
echo "plan-tracker.sh"
test_creates_marker_on_in_progress
test_clears_marker_on_completed
test_ignores_other_tools
test_ignores_no_status
test_ignores_pending
run_tests
