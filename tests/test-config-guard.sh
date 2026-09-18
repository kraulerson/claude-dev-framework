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
# Read-only git inspection of protected paths (BL-021)
# =============================================
# Operators need to inspect framework state via git without resorting to
# subagents. Read-only git subcommands are allowed even when the path
# argument lands inside a protected zone; mutating subcommands stay blocked.

# --- Test: allows git diff on settings.json ---
test_allows_git_diff_settings() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"git diff .claude/settings.json"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "should allow git diff on settings.json"
  teardown_test_project
}

# --- Test: allows git log on manifest.json ---
test_allows_git_log_manifest() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"git log .claude/manifest.json"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "should allow git log on manifest.json"
  teardown_test_project
}

# --- Test: allows git show on framework hook ---
test_allows_git_show_framework_hook() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"git show HEAD:.claude/framework/hooks/enforce-superpowers.sh"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "should allow git show on framework hook"
  teardown_test_project
}

# --- Test: allows git blame on manifest.json ---
test_allows_git_blame_manifest() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"git blame .claude/manifest.json"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "should allow git blame on manifest.json"
  teardown_test_project
}

# --- Test: blocks git add on manifest.json (mutating) ---
test_blocks_git_add_manifest() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"git add .claude/manifest.json"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block git add on manifest.json"
  teardown_test_project
}

# --- Test: blocks git checkout HEAD -- on settings.json (mutating) ---
test_blocks_git_checkout_settings() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"git checkout HEAD -- .claude/settings.json"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block git checkout on settings.json"
  teardown_test_project
}

# --- Test: blocks git rm on framework hook (mutating) ---
test_blocks_git_rm_framework_hook() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"git rm .claude/framework/hooks/enforce-evaluate.sh"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block git rm on framework hook"
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

# =============================================
# Bare .claude destruction (R-12) + relative paths + NotebookEdit + injection
# =============================================

# --- Test: blocks rm -rf .claude (bare, no trailing slash) ---
test_blocks_rm_bare_claude() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"rm -rf .claude"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block rm -rf .claude"
  teardown_test_project
}

# --- Test: allows rm -rf .claude-backup (must not false-positive) ---
test_allows_rm_claude_backup() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"rm -rf .claude-backup"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "should allow rm -rf .claude-backup"
  teardown_test_project
}

# --- Test: blocks Write with a relative .claude/settings.json path ---
test_blocks_write_relative_settings() {
  setup_test_project
  INPUT='{"tool_name":"Write","tool_input":{"file_path":".claude/settings.json","content":"{}"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block Write to relative .claude/settings.json"
  teardown_test_project
}

# --- Test: blocks NotebookEdit to a framework path ---
test_blocks_notebookedit_framework() {
  setup_test_project
  INPUT='{"tool_name":"NotebookEdit","tool_input":{"notebook_path":".claude/framework/x.ipynb","new_source":""}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block NotebookEdit to framework path"
  teardown_test_project
}

# --- Test: injection via chained mark-evaluated.sh does not unlock (R-11) ---
test_blocks_mark_evaluated_injection() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"sed -i '"'"''"'"' .claude/manifest.json && echo mark-evaluated.sh"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "chained mark-evaluated.sh must not unlock the guard"
  teardown_test_project
}

# --- Test: rm -rf .claude/ (trailing slash) is blocked (R-12) ---
test_blocks_rm_claude_trailing_slash() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"rm -rf .claude/"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block rm -rf .claude/ with trailing slash"
  teardown_test_project
}

# --- Test: rm -rf .claude/* (glob) is blocked (R-12) ---
test_blocks_rm_claude_glob() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"rm -rf .claude/*"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block rm -rf .claude/* glob"
  teardown_test_project
}

# --- Test: rm -rf .claude/framework (subdir path) is blocked (R-12) ---
test_blocks_rm_claude_subdir() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"rm -rf .claude/framework/hooks"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block rm -rf .claude/framework/hooks"
  teardown_test_project
}

# --- Test: mv .claude/ to another dir is blocked (R-12) ---
test_blocks_mv_claude_slash() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"mv .claude/ /tmp/x"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block mv .claude/ /tmp/x"
  teardown_test_project
}

# --- Test: lone mark-evaluated.sh with a redirect must not unlock (R-11) ---
test_blocks_mark_evaluated_redirect() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"bash .claude/framework/hooks/mark-evaluated.sh reason > .claude/settings.json"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "redirect after mark-evaluated.sh must not unlock the guard"
  teardown_test_project
}

# --- Test: allows lone mark-plan-closed.sh (sanctioned script) ---
test_allows_mark_plan_closed() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"bash .claude/framework/hooks/mark-plan-closed.sh \"planned vs actual matched\""}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "should allow mark-plan-closed.sh"
  teardown_test_project
}

# --- Test: allows lone mark-plan-closed.sh in its --note form ---
test_allows_mark_plan_closed_note() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"bash .claude/framework/hooks/mark-plan-closed.sh --note docs/closure.md"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "should allow mark-plan-closed.sh --note"
  teardown_test_project
}

# --- Test: chained mark-plan-closed.sh does not unlock ---
test_blocks_mark_plan_closed_injection() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"sed -i '"'"''"'"' .claude/manifest.json && echo mark-plan-closed.sh"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "chained mark-plan-closed.sh must not unlock the guard"
  teardown_test_project
}

# --- Test: a command that merely mentions mark-plan-closed.sh does not unlock ---
test_blocks_mark_plan_closed_mention() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"cp mark-plan-closed.sh .claude/framework/hooks/stop-checklist.sh"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "mentioning mark-plan-closed.sh as an argument must not unlock the guard"
  teardown_test_project
}

# --- Test: lone mark-plan-closed.sh with a redirect must not unlock ---
test_blocks_mark_plan_closed_redirect() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"bash .claude/framework/hooks/mark-plan-closed.sh summary > .claude/settings.json"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "redirect after mark-plan-closed.sh must not unlock the guard"
  teardown_test_project
}

# --- Chain arm, one separator each: the lone-prefixed form followed by a
# separator must fall through to the framework-path check, never unlock.
# The tails use tee, which only the framework-path check stops; an rm tail
# would be caught by the earlier destructive-command check instead. ---
test_blocks_mark_plan_closed_semicolon() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"bash .claude/framework/hooks/mark-plan-closed.sh s ; tee .claude/settings.json"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "semicolon after mark-plan-closed.sh must not unlock the guard"
  teardown_test_project
}

test_blocks_mark_plan_closed_ampersand() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"bash .claude/framework/hooks/mark-plan-closed.sh s & tee .claude/settings.json"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "ampersand after mark-plan-closed.sh must not unlock the guard"
  teardown_test_project
}

test_blocks_mark_plan_closed_pipe() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"bash .claude/framework/hooks/mark-plan-closed.sh s | tee .claude/settings.json"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "pipe after mark-plan-closed.sh must not unlock the guard"
  teardown_test_project
}

test_blocks_mark_plan_closed_backtick() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"bash .claude/framework/hooks/mark-plan-closed.sh `tee .claude/settings.json`"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "backticks in the summary must not unlock the guard"
  teardown_test_project
}

test_blocks_mark_plan_closed_stdin_redirect() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"bash .claude/framework/hooks/mark-plan-closed.sh s < .claude/settings.json"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "stdin redirect after mark-plan-closed.sh must not unlock the guard"
  teardown_test_project
}

test_blocks_mark_plan_closed_newline() {
  setup_test_project
  # The JSON \n decodes to a real newline in the command string.
  INPUT='{"tool_name":"Bash","tool_input":{"command":"bash .claude/framework/hooks/mark-plan-closed.sh s\ntee .claude/settings.json"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "newline after mark-plan-closed.sh must not unlock the guard"
  teardown_test_project
}

test_blocks_mark_plan_closed_substitution() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"bash .claude/framework/hooks/mark-plan-closed.sh \"$(tee .claude/settings.json)\""}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "substitution inside the summary must not unlock the guard"
  teardown_test_project
}

test_blocks_mark_plan_closed_unquoted_substitution() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"bash .claude/framework/hooks/mark-plan-closed.sh $(tee .claude/settings.json)"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "unquoted substitution as the summary must not unlock the guard"
  teardown_test_project
}

test_blocks_mark_plan_closed_glued_redirect() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"bash .claude/framework/hooks/mark-plan-closed.sh s>.claude/settings.json"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "glued output redirect must not unlock the guard"
  INPUT='{"tool_name":"Bash","tool_input":{"command":"bash .claude/framework/hooks/mark-plan-closed.sh s<.claude/settings.json"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "glued input redirect must not unlock the guard"
  teardown_test_project
}

# --- Test: a name that merely starts with the script name does not unlock ---
test_blocks_mark_plan_closed_name_tail() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"bash .claude/framework/hooks/mark-plan-closed.sh.bak s"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "mark-plan-closed.sh.bak must not unlock the guard"
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
test_allows_git_diff_settings
test_allows_git_log_manifest
test_allows_git_show_framework_hook
test_allows_git_blame_manifest
test_blocks_git_add_manifest
test_blocks_git_checkout_settings
test_blocks_git_rm_framework_hook
test_blocks_rm_bare_claude
test_allows_rm_claude_backup
test_blocks_write_relative_settings
test_blocks_notebookedit_framework
test_blocks_mark_evaluated_injection
test_blocks_rm_claude_trailing_slash
test_blocks_rm_claude_glob
test_blocks_rm_claude_subdir
test_blocks_mv_claude_slash
test_blocks_mark_evaluated_redirect
test_allows_mark_plan_closed
test_allows_mark_plan_closed_note
test_blocks_mark_plan_closed_injection
test_blocks_mark_plan_closed_mention
test_blocks_mark_plan_closed_redirect
test_blocks_mark_plan_closed_semicolon
test_blocks_mark_plan_closed_ampersand
test_blocks_mark_plan_closed_pipe
test_blocks_mark_plan_closed_backtick
test_blocks_mark_plan_closed_stdin_redirect
test_blocks_mark_plan_closed_newline
test_blocks_mark_plan_closed_substitution
test_blocks_mark_plan_closed_unquoted_substitution
test_blocks_mark_plan_closed_glued_redirect
test_blocks_mark_plan_closed_name_tail
run_tests
