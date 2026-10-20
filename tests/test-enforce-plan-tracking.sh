#!/usr/bin/env bash
# test-enforce-plan-tracking.sh — Tests for enforce-plan-tracking hook
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/enforce-plan-tracking.sh"

# --- Test: doc file passes regardless ---
test_doc_file_passes() {
  setup_test_project
  INPUT='{"tool_input":{"file_path":"README.md"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "doc file should pass"
  teardown_test_project
}

# --- Test: test file passes regardless ---
test_test_file_passes() {
  setup_test_project
  INPUT='{"tool_input":{"file_path":"tests/test_app.py"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "test file should pass"
  teardown_test_project
}

# --- Test: source file passes when no has_plan marker (zone not armed) ---
test_source_passes_without_plan() {
  setup_test_project
  INPUT='{"tool_input":{"file_path":"app.py"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "should pass when Planning Zone not armed"
  teardown_test_project
}

# --- Test: source file blocks when has_plan exists but no plan_active ---
test_blocks_without_plan_active() {
  setup_test_project
  touch "/tmp/.claude_has_plan_${TEST_HASH}"
  INPUT='{"tool_input":{"file_path":"app.py"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  RESULT=$(run_hook "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block when has_plan but no plan_active"
  assert_contains "$RESULT" "BLOCKED" "should say BLOCKED"
  assert_contains "$RESULT" "Planning Zone" "should mention Planning Zone"
  teardown_test_project
}

# --- Test: source file passes when both markers exist ---
test_passes_with_both_markers() {
  setup_test_project
  touch "/tmp/.claude_has_plan_${TEST_HASH}"
  touch "/tmp/.claude_plan_active_${TEST_HASH}"
  INPUT='{"tool_input":{"file_path":"app.py"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "should pass with both plan markers"
  teardown_test_project
}

# --- Test: config file passes regardless ---
test_config_file_passes() {
  setup_test_project
  touch "/tmp/.claude_has_plan_${TEST_HASH}"
  INPUT='{"tool_input":{"file_path":"config.json"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "config file should pass even with has_plan"
  teardown_test_project
}

# --- Test (#38): the block message names both routes to mark the task, and that a
# commit clears the mark ---
test_block_message_names_both_routes() {
  setup_test_project
  touch "/tmp/.claude_has_plan_${TEST_HASH}"
  RESULT=$(run_hook "$HOOK" '{"tool_input":{"file_path":"app.py"}}')
  assert_contains "$RESULT" "TaskUpdate" "block message names TaskUpdate"
  assert_contains "$RESULT" "ToolSearch" "block message says how to load a deferred TaskUpdate"
  assert_contains "$RESULT" 'bash .claude/framework/hooks/mark-plan-active.sh "<task>"' "block message names the script, runnable"
  assert_contains "$RESULT" "as its own Bash call from the project root" "block message says how the script must be run"
  assert_contains "$RESULT" "Each commit clears" "block message says a commit clears the mark"
  teardown_test_project
}

# --- Test (#38): the script's mark passes the zone ---
test_passes_after_mark_plan_active() {
  setup_test_project
  touch "/tmp/.claude_has_plan_${TEST_HASH}"
  (cd "$TEST_DIR" && bash "$HOOK_DIR/mark-plan-active.sh" "Task 1: add the parser" >/dev/null 2>&1)
  EXIT_CODE=$(run_hook_exit_code "$HOOK" '{"tool_input":{"file_path":"app.py"}}')
  assert_exit_code "0" "$EXIT_CODE" "should pass after mark-plan-active.sh"
  teardown_test_project
}

# --- Test (#39): a source file written through Bash needs an active task too ---
bash_hook_input() {
  jq -nc --arg c "$1" --arg d "$TEST_DIR" '{cwd:$d,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}'
}
test_bash_source_write() {
  setup_test_project
  touch "/tmp/.claude_has_plan_${TEST_HASH}"
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(bash_hook_input "sed -i '' 's/a/b/' app.py")")
  assert_exit_code "2" "$EXIT_CODE" "sed -i on a source file blocks without an active task"
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(bash_hook_input 'echo x > notes.md')")
  assert_exit_code "0" "$EXIT_CODE" "a Bash write of a doc passes"
  touch "/tmp/.claude_plan_active_${TEST_HASH}"
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(bash_hook_input "sed -i '' 's/a/b/' app.py")")
  assert_exit_code "0" "$EXIT_CODE" "with an active task a Bash write passes"
  teardown_test_project
}

# --- Run all tests ---
echo "enforce-plan-tracking.sh"
test_doc_file_passes
test_test_file_passes
test_source_passes_without_plan
test_blocks_without_plan_active
test_passes_with_both_markers
test_config_file_passes
test_block_message_names_both_routes
test_passes_after_mark_plan_active
test_bash_source_write
run_tests
