#!/usr/bin/env bash
# test-session-end.sh — Tests for session-end cleanup hook
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/session-end.sh"

# --- Test: clears session-scoped markers, preserves eval audit log ---
test_clears_session_markers() {
  setup_test_project
  touch "/tmp/.claude_superpowers_${TEST_HASH}"
  touch "/tmp/.claude_evaluated_${TEST_HASH}"
  touch "/tmp/.claude_has_plan_${TEST_HASH}"
  touch "/tmp/.claude_plan_active_${TEST_HASH}"
  touch "/tmp/.claude_plan_closed_${TEST_HASH}"
  touch "/tmp/.claude_changelog_synced_${TEST_HASH}"
  touch "/tmp/.claude_c7_degraded_${TEST_HASH}"
  touch "/tmp/.claude_session_start_${TEST_HASH}"
  touch "/tmp/.claude_last_head_${TEST_HASH}"
  touch "/tmp/.claude_c7_${TEST_HASH}_react"
  touch "/tmp/.claude_stop_errors_hash_${TEST_HASH}_abc123"
  touch "/tmp/.claude_eval_log_${TEST_HASH}"
  touch "/tmp/.claude_approval_shown_${TEST_HASH}"

  run_hook "$HOOK" '{}' >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_approval_shown_${TEST_HASH}" "keeps the approval render record (bound to its session; a --resume reply picks)"

  assert_file_not_exists "/tmp/.claude_superpowers_${TEST_HASH}" "clears superpowers"
  assert_file_not_exists "/tmp/.claude_evaluated_${TEST_HASH}" "clears evaluated"
  assert_file_not_exists "/tmp/.claude_has_plan_${TEST_HASH}" "clears has_plan"
  assert_file_not_exists "/tmp/.claude_plan_active_${TEST_HASH}" "clears plan_active"
  assert_file_not_exists "/tmp/.claude_plan_closed_${TEST_HASH}" "clears plan_closed"
  assert_file_not_exists "/tmp/.claude_changelog_synced_${TEST_HASH}" "clears changelog_synced"
  assert_file_not_exists "/tmp/.claude_c7_degraded_${TEST_HASH}" "clears c7_degraded"
  assert_file_not_exists "/tmp/.claude_session_start_${TEST_HASH}" "clears session_start"
  assert_file_not_exists "/tmp/.claude_last_head_${TEST_HASH}" "clears last_head"
  assert_file_not_exists "/tmp/.claude_c7_${TEST_HASH}_react" "clears c7 lib markers"
  assert_file_not_exists "/tmp/.claude_stop_errors_hash_${TEST_HASH}_abc123" "clears stop_errors_hash"
  assert_file_exists "/tmp/.claude_eval_log_${TEST_HASH}" "preserves eval audit log"

  rm -f "/tmp/.claude_eval_log_${TEST_HASH}"
  teardown_test_project
}

# --- Test: exit code is 0 ---
test_exit_zero() {
  setup_test_project
  EXIT_CODE=$(run_hook_exit_code "$HOOK" '{}')
  assert_exit_code "0" "$EXIT_CODE" "session-end exits 0"
  teardown_test_project
}

# --- Run all tests ---
echo "session-end.sh"
test_clears_session_markers
test_exit_zero
run_tests
