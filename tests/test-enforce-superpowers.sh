#!/usr/bin/env bash
# test-enforce-superpowers.sh — Tests for enforce-superpowers hook
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/enforce-superpowers.sh"

# --- Test: doc/config file passes silently ---
test_doc_file_passes() {
  setup_test_project
  INPUT='{"tool_input":{"file_path":"README.md"}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  assert_equals "" "$RESULT" "doc file should produce no output"
  teardown_test_project
}

# --- Test: test file passes silently ---
test_test_file_passes() {
  setup_test_project
  INPUT='{"tool_input":{"file_path":"tests/LoginTest.kt"}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  assert_equals "" "$RESULT" "test file should produce no output"
  teardown_test_project
}

# --- Test: source file without marker blocks with exit 2 ---
test_source_without_marker() {
  setup_test_project
  INPUT='{"tool_input":{"file_path":"app.kt"}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block with exit 2"
  assert_contains "$RESULT" "BLOCKED" "should say BLOCKED"
  assert_contains "$RESULT" "Superpowers" "should mention Superpowers"
  teardown_test_project
}

# --- Test: source file with marker passes ---
test_source_with_marker() {
  setup_test_project
  touch "/tmp/.claude_superpowers_${TEST_HASH}"
  INPUT='{"tool_input":{"file_path":"app.kt"}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  assert_equals "" "$RESULT" "source with marker should produce no output"
  teardown_test_project
}

# --- Run all tests ---
echo "enforce-superpowers.sh"
test_doc_file_passes
test_test_file_passes
test_source_without_marker
test_source_with_marker
run_tests
