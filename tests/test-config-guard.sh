#!/usr/bin/env bash
# test-config-guard.sh — Tests for config-guard hook
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/config-guard.sh"

# =============================================
# Write/Edit tool blocking (.claude/ config files)
# =============================================

# --- Test: blocks Write to .claude/settings.json ---
test_blocks_write_settings() {
  setup_test_project
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"'"$TEST_DIR"'/.claude/settings.json","content":"{}"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block Write to settings.json"
  teardown_test_project
}

# --- Test: blocks Edit to .claude/manifest.json ---
test_blocks_edit_manifest() {
  setup_test_project
  INPUT='{"tool_name":"Edit","tool_input":{"file_path":"'"$TEST_DIR"'/.claude/manifest.json","old_string":"old","new_string":"new"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block Edit to manifest.json"
  teardown_test_project
}

# --- Test: blocks Write to settings.local.json ---
test_blocks_write_settings_local() {
  setup_test_project
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"'"$TEST_DIR"'/.claude/settings.local.json","content":"{}"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block Write to settings.local.json"
  teardown_test_project
}

# --- Test: blocks Write to framework hook file ---
test_blocks_write_framework_hook() {
  setup_test_project
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"'"$TEST_DIR"'/.claude/framework/hooks/enforce-evaluate.sh","content":"exit 0"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block Write to framework hook file"
  teardown_test_project
}

# --- Test: allows Write to non-framework .claude files ---
test_allows_write_other_claude_files() {
  setup_test_project
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"'"$TEST_DIR"'/.claude/my-notes.md","content":"notes"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "should allow Write to non-framework .claude files"
  teardown_test_project
}

# --- Test: allows Write to normal project files ---
test_allows_write_normal_files() {
  setup_test_project
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"'"$TEST_DIR"'/src/main.py","content":"print()"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "should allow Write to normal project files"
  teardown_test_project
}

# =============================================
# Bash tool blocking (hook file modification)
# =============================================

# --- Test: blocks sed on hook files ---
test_blocks_sed_on_hooks() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"sed -i '"'"''"'"' '"'"'s/exit 2/exit 0/'"'"' .claude/framework/hooks/enforce-superpowers.sh"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block sed on hook files"
  teardown_test_project
}

# --- Test: blocks echo redirect to settings.json ---
test_blocks_echo_redirect_settings() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"echo '"'"'{}'"'"' > .claude/settings.json"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block echo redirect to settings.json"
  teardown_test_project
}

# --- Test: blocks rm on hook files ---
test_blocks_rm_on_hooks() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"rm .claude/framework/hooks/enforce-superpowers.sh"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block rm on hook files"
  teardown_test_project
}

# --- Test: blocks chmod on hook files ---
test_blocks_chmod_on_hooks() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"chmod -x .claude/framework/hooks/enforce-evaluate.sh"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block chmod on hook files"
  teardown_test_project
}

# --- Test: allows reading hook files via cat ---
test_allows_cat_hook_files() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"cat .claude/framework/hooks/enforce-superpowers.sh"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "should allow reading hook files"
  teardown_test_project
}

# --- Test: allows grep on hook files ---
test_allows_grep_hook_files() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"grep -r exit .claude/framework/hooks/"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "should allow grep on hook files"
  teardown_test_project
}

# --- Test: allows mark-evaluated.sh (sanctioned script) ---
test_allows_mark_evaluated() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"bash .claude/framework/hooks/mark-evaluated.sh \"user approved\""}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "should allow mark-evaluated.sh"
  teardown_test_project
}

# --- Test: allows non-framework bash commands ---
test_allows_normal_bash() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"git status"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "should allow normal bash commands"
  teardown_test_project
}

# =============================================
# Environment variable protection
# =============================================

# --- Test: blocks CLAUDE_PROJECT_DIR override ---
test_blocks_project_dir_override() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"CLAUDE_PROJECT_DIR=/tmp git commit -m test"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block CLAUDE_PROJECT_DIR override"
  teardown_test_project
}

# --- Test: allows CLAUDE_PROJECT_DIR in read-only context ---
test_allows_project_dir_read() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"echo $CLAUDE_PROJECT_DIR"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "should allow reading CLAUDE_PROJECT_DIR"
  teardown_test_project
}

# --- Run all tests ---
echo "config-guard.sh"
test_blocks_write_settings
test_blocks_edit_manifest
test_blocks_write_settings_local
test_blocks_write_framework_hook
test_allows_write_other_claude_files
test_allows_write_normal_files
test_blocks_sed_on_hooks
test_blocks_echo_redirect_settings
test_blocks_rm_on_hooks
test_blocks_chmod_on_hooks
test_allows_cat_hook_files
test_allows_grep_hook_files
test_allows_mark_evaluated
test_allows_normal_bash
test_blocks_project_dir_override
test_allows_project_dir_read
run_tests
