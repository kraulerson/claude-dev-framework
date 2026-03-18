#!/usr/bin/env bash
# test-marker-persistence.sh — Tests for marker clearing after commit
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/sync-tracker.sh"

# --- Test: markers cleared after successful git commit ---
# Before the fix, markers persisted for the entire session,
# allowing subsequent changes to bypass evaluation/superpowers.
test_markers_cleared_after_commit() {
  setup_test_project

  # Create both markers (simulating completed evaluation + superpowers)
  touch "/tmp/.claude_evaluated_${TEST_HASH}"
  touch "/tmp/.claude_superpowers_${TEST_HASH}"

  # Simulate PostToolUse event for a successful git commit
  COMMIT_INPUT='{"tool_input":{"command":"git commit -m \"Add feature\""},"tool_response":{"exit_code":"0"}}'
  run_hook "$HOOK" "$COMMIT_INPUT" >/dev/null

  assert_file_not_exists "/tmp/.claude_evaluated_${TEST_HASH}" "evaluated marker should be cleared after commit"
  assert_file_not_exists "/tmp/.claude_superpowers_${TEST_HASH}" "superpowers marker should be cleared after commit"
  teardown_test_project
}

# --- Test: markers survive non-commit commands ---
test_markers_survive_non_commit() {
  setup_test_project

  touch "/tmp/.claude_evaluated_${TEST_HASH}"
  touch "/tmp/.claude_superpowers_${TEST_HASH}"

  # Simulate PostToolUse for a non-commit command
  STATUS_INPUT='{"tool_input":{"command":"git status"},"tool_response":{"exit_code":"0"}}'
  run_hook "$HOOK" "$STATUS_INPUT" >/dev/null

  assert_file_exists "/tmp/.claude_evaluated_${TEST_HASH}" "evaluated marker should survive non-commit"
  assert_file_exists "/tmp/.claude_superpowers_${TEST_HASH}" "superpowers marker should survive non-commit"
  teardown_test_project
}

# --- Test: markers survive failed commit ---
test_markers_survive_failed_commit() {
  setup_test_project

  touch "/tmp/.claude_evaluated_${TEST_HASH}"
  touch "/tmp/.claude_superpowers_${TEST_HASH}"

  # Simulate PostToolUse for a failed git commit
  FAIL_INPUT='{"tool_input":{"command":"git commit -m \"fail\""},"tool_response":{"exit_code":"1"}}'
  run_hook "$HOOK" "$FAIL_INPUT" >/dev/null

  assert_file_exists "/tmp/.claude_evaluated_${TEST_HASH}" "evaluated marker should survive failed commit"
  assert_file_exists "/tmp/.claude_superpowers_${TEST_HASH}" "superpowers marker should survive failed commit"
  teardown_test_project
}

# --- Run all tests ---
echo "marker-persistence (sync-tracker.sh)"
test_markers_cleared_after_commit
test_markers_survive_non_commit
test_markers_survive_failed_commit
run_tests
