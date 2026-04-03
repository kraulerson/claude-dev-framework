#!/usr/bin/env bash
# test-sync-tracker-v4.sh — Tests for v4 additions to sync-tracker
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/sync-tracker.sh"

# --- Test: successful commit clears plan_active marker ---
test_commit_clears_plan_active() {
  setup_test_project
  touch "/tmp/.claude_plan_active_${TEST_HASH}"
  INPUT='{"tool_input":{"command":"git commit -m \"test\""},"tool_response":{"exit_code":"0"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_not_exists "/tmp/.claude_plan_active_${TEST_HASH}" "commit should clear plan_active marker"
  teardown_test_project
}

# --- Test: failed commit does NOT clear plan_active marker ---
test_failed_commit_keeps_plan_active() {
  setup_test_project
  touch "/tmp/.claude_plan_active_${TEST_HASH}"
  INPUT='{"tool_input":{"command":"git commit -m \"test\""},"tool_response":{"exit_code":"1"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_plan_active_${TEST_HASH}" "failed commit should keep plan_active marker"
  teardown_test_project
}

# --- Run all tests ---
echo "sync-tracker.sh (v4 plan_active clearing)"
test_commit_clears_plan_active
test_failed_commit_keeps_plan_active
run_tests
