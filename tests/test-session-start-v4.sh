#!/usr/bin/env bash
# test-session-start-v4.sh — Tests for rewritten session-start hook
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/session-start.sh"

# --- Test: output contains compliance directive ---
test_has_directive() {
  setup_test_project
  RESULT=$(run_hook "$HOOK" "")
  assert_contains "$RESULT" "FRAMEWORK COMPLIANCE DIRECTIVE" "should contain directive"
  teardown_test_project
}

# --- Test: output contains ZONES ARMED section ---
test_has_zones() {
  setup_test_project
  RESULT=$(run_hook "$HOOK" "")
  assert_contains "$RESULT" "ZONES ARMED" "should contain zones section"
  assert_contains "$RESULT" "Discovery" "should list Discovery zone"
  assert_contains "$RESULT" "Design" "should list Design zone"
  assert_contains "$RESULT" "Planning" "should list Planning zone"
  assert_contains "$RESULT" "Implementation" "should list Implementation zone"
  assert_contains "$RESULT" "Verification" "should list Verification zone"
  teardown_test_project
}

# --- Test: output does NOT contain old ACTIVE RULES section ---
test_no_rules_listing() {
  setup_test_project
  RESULT=$(run_hook "$HOOK" "")
  assert_not_contains "$RESULT" "ACTIVE RULES" "should not list individual rules"
  teardown_test_project
}

# --- Test: output contains profile/branch/rules summary line ---
test_summary_line() {
  setup_test_project
  RESULT=$(run_hook "$HOOK" "")
  assert_contains "$RESULT" "Profile:" "should contain Profile"
  assert_contains "$RESULT" "Branch:" "should contain Branch"
  assert_contains "$RESULT" "Rules:" "should contain Rules count"
  teardown_test_project
}

# --- Test: output does NOT contain old banner format ---
test_no_old_banner() {
  setup_test_project
  RESULT=$(run_hook "$HOOK" "")
  assert_not_contains "$RESULT" "=== CLAUDE DEV FRAMEWORK" "should not have old banner"
  assert_not_contains "$RESULT" "WORKFLOW ENFORCEMENT" "should not have old workflow section"
  teardown_test_project
}

# --- Test: exit code is always 0 ---
test_exit_zero() {
  setup_test_project
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "")
  assert_exit_code "0" "$EXIT_CODE" "should always exit 0"
  teardown_test_project
}

# --- Run all tests ---
echo "session-start.sh (v4 rewrite)"
test_has_directive
test_has_zones
test_no_rules_listing
test_summary_line
test_no_old_banner
test_exit_zero
run_tests
