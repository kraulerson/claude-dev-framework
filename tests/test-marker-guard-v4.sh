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

# --- Test: blocks echo redirect to marker path ---
test_blocks_echo_redirect() {
  setup_test_project
  INPUT='{"tool_input":{"command":"echo \"\" > /tmp/.claude_superpowers_abc123"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block echo redirect to marker"
  teardown_test_project
}

# --- Test: blocks printf redirect to marker path ---
test_blocks_printf_redirect() {
  setup_test_project
  INPUT='{"tool_input":{"command":"printf \"\" > /tmp/.claude_superpowers_abc123"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block printf redirect to marker"
  teardown_test_project
}

# --- Test: blocks cp to marker path ---
test_blocks_cp_to_marker() {
  setup_test_project
  INPUT='{"tool_input":{"command":"cp /dev/null /tmp/.claude_evaluated_abc123"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block cp to marker"
  teardown_test_project
}

# --- Test: blocks python file creation at marker path ---
test_blocks_python_marker() {
  setup_test_project
  INPUT="{\"tool_input\":{\"command\":\"python3 -c \\\"open('/tmp/.claude_superpowers_abc123','w')\\\"\"}}"
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block python marker creation"
  teardown_test_project
}

# --- Test: blocks tee to marker path ---
test_blocks_tee_marker() {
  setup_test_project
  INPUT='{"tool_input":{"command":"tee /tmp/.claude_has_plan_abc123 < /dev/null"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block tee to marker path"
  teardown_test_project
}

# --- Test: still allows mark-evaluated.sh ---
test_allows_mark_evaluated_script() {
  setup_test_project
  INPUT='{"tool_input":{"command":"bash .claude/framework/hooks/mark-evaluated.sh \"user approved\""}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "should allow mark-evaluated.sh"
  teardown_test_project
}

# --- Test: still allows non-marker tmp files ---
test_allows_unrelated_tmp_files() {
  setup_test_project
  INPUT='{"tool_input":{"command":"echo test > /tmp/.claude_other_file"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "should allow non-marker tmp files"
  teardown_test_project
}

# --- Test: blocks Write tool to a marker path (R-07) ---
test_blocks_write_to_marker() {
  setup_test_project
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"/tmp/.claude_evaluated_x","content":""}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block Write to marker path"
  teardown_test_project
}

# --- Test: blocks Edit tool to a marker path (R-07) ---
test_blocks_edit_to_marker() {
  setup_test_project
  INPUT='{"tool_name":"Edit","tool_input":{"file_path":"/tmp/.claude_superpowers_x","old_string":"a","new_string":"b"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block Edit to marker path"
  teardown_test_project
}

# --- Test: blocks NotebookEdit tool to a marker path (R-07) ---
test_blocks_notebookedit_to_marker() {
  setup_test_project
  INPUT='{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"/tmp/.claude_plan_active_x","new_source":""}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block NotebookEdit to marker path"
  teardown_test_project
}

# --- Test: allows Write tool to a normal path ---
test_allows_write_normal_path() {
  setup_test_project
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"'"$TEST_DIR"'/src/main.py","content":"print()"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "should allow Write to normal path"
  teardown_test_project
}

# --- Test: blocks Bash touch of last_head state marker ---
test_blocks_last_head_marker() {
  setup_test_project
  INPUT='{"tool_input":{"command":"touch /tmp/.claude_last_head_x"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block last_head marker creation"
  teardown_test_project
}

# --- Test: injection via chained mark-evaluated.sh does not unlock (R-11) ---
test_blocks_mark_evaluated_injection() {
  setup_test_project
  INPUT='{"tool_input":{"command":"touch /tmp/.claude_superpowers_x && echo mark-evaluated.sh"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "chained mark-evaluated.sh must not unlock the guard"
  teardown_test_project
}

# --- Test: plain lone mark-evaluated.sh invocation is allowed ---
test_allows_lone_mark_evaluated() {
  setup_test_project
  INPUT='{"tool_input":{"command":"bash .claude/framework/hooks/mark-evaluated.sh \"reason text\""}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "lone mark-evaluated.sh should be allowed"
  teardown_test_project
}

# --- Test: non-canonical marker path (/./) still blocked (R-07) ---
test_blocks_noncanonical_write_marker() {
  setup_test_project
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"/tmp/./.claude_evaluated_x","content":""}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block Write to /tmp/./.claude_ marker path"
  teardown_test_project
}

# --- Test: double-slash marker path still blocked (R-07) ---
test_blocks_double_slash_write_marker() {
  setup_test_project
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"/tmp//.claude_evaluated_x","content":""}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block Write to /tmp//.claude_ marker path"
  teardown_test_project
}

# --- Test: dot-dot marker path still blocked (R-07) ---
test_blocks_dotdot_write_marker() {
  setup_test_project
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"/tmp/foo/../.claude_evaluated_x","content":""}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block Write to /tmp/foo/../.claude_ marker path"
  teardown_test_project
}

# --- Test: bare marker name via Bash (no /tmp/ prefix) still blocked (R-07) ---
test_blocks_bare_marker_name_bash() {
  setup_test_project
  INPUT='{"tool_input":{"command":"cd /tmp && touch .claude_evaluated_x"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block cd /tmp && touch .claude_evaluated_x"
  teardown_test_project
}

# --- Test: lone mark-evaluated.sh with a redirect to a marker is blocked (R-11) ---
test_blocks_mark_evaluated_redirect() {
  setup_test_project
  INPUT='{"tool_input":{"command":"bash .claude/framework/hooks/mark-evaluated.sh reason 2>/tmp/.claude_plan_active_x"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "redirect after mark-evaluated.sh must not unlock the guard"
  teardown_test_project
}

# --- Test: direct creation of the plan-closed marker is still refused ---
test_blocks_plan_closed_direct_create() {
  setup_test_project
  INPUT='{"tool_input":{"command":"touch /tmp/.claude_plan_closed_abc123"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block direct plan_closed marker creation"
  teardown_test_project
}

# --- Test: direct deletion of the plan-closed marker is still refused ---
test_blocks_plan_closed_direct_delete() {
  setup_test_project
  INPUT='{"tool_input":{"command":"rm -f /tmp/.claude_plan_closed_abc123"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block direct plan_closed marker deletion"
  teardown_test_project
}

# --- Test: Write tool to the plan-closed marker is still refused ---
test_blocks_write_to_plan_closed() {
  setup_test_project
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"/tmp/.claude_plan_closed_abc123","content":"closed"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block Write to the plan_closed marker"
  teardown_test_project
}

# --- Test (parity control): lone mark-evaluated.sh is allowed even when its reason names a marker ---
test_allows_mark_evaluated_reason_naming_marker() {
  setup_test_project
  INPUT='{"tool_input":{"command":"bash .claude/framework/hooks/mark-evaluated.sh \"approved: clear /tmp/.claude_evaluated_x handling\""}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "lone mark-evaluated.sh is allowed whatever its reason says"
  teardown_test_project
}

# --- Test: lone mark-plan-closed.sh is allowed exactly as mark-evaluated.sh is ---
test_allows_lone_mark_plan_closed() {
  setup_test_project
  INPUT='{"tool_input":{"command":"bash .claude/framework/hooks/mark-plan-closed.sh \"closed: /tmp/.claude_plan_closed_x lifecycle documented\""}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "lone mark-plan-closed.sh should be allowed whatever its summary says"
  teardown_test_project
}

# --- Test: lone mark-plan-closed.sh --note form is allowed ---
test_allows_lone_mark_plan_closed_note() {
  setup_test_project
  INPUT='{"tool_input":{"command":"bash .claude/framework/hooks/mark-plan-closed.sh --note docs/.claude_plan_closed_notes.md"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "lone mark-plan-closed.sh --note should be allowed"
  teardown_test_project
}

# --- Test: chained mark-plan-closed.sh does not unlock the guard ---
test_blocks_mark_plan_closed_injection() {
  setup_test_project
  INPUT='{"tool_input":{"command":"touch /tmp/.claude_plan_closed_x && echo mark-plan-closed.sh"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "chained mark-plan-closed.sh must not unlock the guard"
  teardown_test_project
}

# --- Test: a command that merely mentions mark-plan-closed.sh does not unlock the guard ---
test_blocks_mark_plan_closed_mention() {
  setup_test_project
  INPUT='{"tool_input":{"command":"touch /tmp/.claude_plan_closed_x mark-plan-closed.sh"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "mentioning mark-plan-closed.sh as an argument must not unlock the guard"
  teardown_test_project
}

# --- Test: lone mark-plan-closed.sh with a redirect to a marker is blocked ---
test_blocks_mark_plan_closed_redirect() {
  setup_test_project
  INPUT='{"tool_input":{"command":"bash .claude/framework/hooks/mark-plan-closed.sh summary 2>/tmp/.claude_plan_active_x"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "redirect after mark-plan-closed.sh must not unlock the guard"
  teardown_test_project
}

# --- Test: command substitution in the summary does not unlock the guard ---
test_blocks_mark_plan_closed_substitution() {
  setup_test_project
  INPUT='{"tool_input":{"command":"bash .claude/framework/hooks/mark-plan-closed.sh \"$(touch /tmp/.claude_superpowers_x)\""}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "substitution inside the summary must not unlock the guard"
  teardown_test_project
}

# --- Chain arm, one separator each: the lone-prefixed form followed by a
# separator must fall through to the marker check, never unlock the guard ---
test_blocks_mark_plan_closed_semicolon() {
  setup_test_project
  INPUT='{"tool_input":{"command":"bash .claude/framework/hooks/mark-plan-closed.sh s ; touch /tmp/.claude_plan_closed_x"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "semicolon after mark-plan-closed.sh must not unlock the guard"
  teardown_test_project
}

test_blocks_mark_plan_closed_ampersand() {
  setup_test_project
  INPUT='{"tool_input":{"command":"bash .claude/framework/hooks/mark-plan-closed.sh s & touch /tmp/.claude_plan_closed_x"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "ampersand after mark-plan-closed.sh must not unlock the guard"
  teardown_test_project
}

test_blocks_mark_plan_closed_pipe() {
  setup_test_project
  INPUT='{"tool_input":{"command":"bash .claude/framework/hooks/mark-plan-closed.sh s | tee /tmp/.claude_plan_closed_x"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "pipe after mark-plan-closed.sh must not unlock the guard"
  teardown_test_project
}

test_blocks_mark_plan_closed_backtick() {
  setup_test_project
  INPUT='{"tool_input":{"command":"bash .claude/framework/hooks/mark-plan-closed.sh `touch /tmp/.claude_plan_closed_x`"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "backticks in the summary must not unlock the guard"
  teardown_test_project
}

test_blocks_mark_plan_closed_stdin_redirect() {
  setup_test_project
  INPUT='{"tool_input":{"command":"bash .claude/framework/hooks/mark-plan-closed.sh s < /tmp/.claude_plan_closed_x"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "stdin redirect after mark-plan-closed.sh must not unlock the guard"
  teardown_test_project
}

test_blocks_mark_plan_closed_newline() {
  setup_test_project
  # The JSON \n decodes to a real newline in the command string.
  INPUT='{"tool_input":{"command":"bash .claude/framework/hooks/mark-plan-closed.sh s\ntouch /tmp/.claude_plan_closed_x"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "newline after mark-plan-closed.sh must not unlock the guard"
  teardown_test_project
}

test_blocks_mark_plan_closed_unquoted_substitution() {
  setup_test_project
  INPUT='{"tool_input":{"command":"bash .claude/framework/hooks/mark-plan-closed.sh $(touch /tmp/.claude_plan_closed_x)"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "unquoted substitution as the summary must not unlock the guard"
  teardown_test_project
}

test_blocks_mark_plan_closed_glued_redirect() {
  setup_test_project
  INPUT='{"tool_input":{"command":"bash .claude/framework/hooks/mark-plan-closed.sh s>/tmp/.claude_plan_closed_x"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "glued output redirect must not unlock the guard"
  INPUT='{"tool_input":{"command":"bash .claude/framework/hooks/mark-plan-closed.sh s</tmp/.claude_plan_closed_x"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "glued input redirect must not unlock the guard"
  teardown_test_project
}

# --- Test: a name that merely starts with the script name does not unlock ---
test_blocks_mark_plan_closed_name_tail() {
  setup_test_project
  INPUT='{"tool_input":{"command":"bash .claude/framework/hooks/mark-plan-closed.sh.bak /tmp/.claude_plan_closed_x"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "mark-plan-closed.sh.bak must not unlock the guard"
  teardown_test_project
}

# --- Test: an assignment prefix naming a script does not unlock (a first word
# `x=mark-evaluated.sh` is a variable assignment, and the rest runs) ---
test_blocks_assignment_prefix() {
  local name
  for name in mark-evaluated.sh mark-plan-closed.sh; do
    setup_test_project
    INPUT='{"tool_input":{"command":"x='"$name"' touch /tmp/.claude_evaluated_abc123"}}'
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
    assert_exit_code "2" "$EXIT_CODE" "x=$name prefix must not unlock the guard"
    teardown_test_project
  done
}

# --- Test: a first word that expands at run time does not unlock (`$IFS` becomes
# whitespace, so `touch$IFS<marker>$IFS#mark-evaluated.sh` runs touch) ---
test_blocks_expanding_first_word() {
  local name
  for name in mark-evaluated.sh mark-plan-closed.sh; do
    setup_test_project
    INPUT='{"tool_input":{"command":"touch$IFS/tmp/.claude_evaluated_abc123$IFS#'"$name"'"}}'
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
    assert_exit_code "2" "$EXIT_CODE" "an \$IFS first word ending in $name must not unlock the guard"
    teardown_test_project
  done
}

# --- Test: the absolute and ./ path forms still unlock (enforce-evaluate.sh
# prints the absolute form) ---
test_allows_path_forms() {
  local cmd
  for cmd in 'bash /Users/dev/my-proj/.claude/framework/hooks/mark-evaluated.sh \"approved: retries=3\"' \
             'bash ./.claude/framework/hooks/mark-plan-closed.sh \"closed\"' \
             '~/.claude-dev-framework/hooks/mark-evaluated.sh \"approved\"'; do
    setup_test_project
    INPUT='{"tool_input":{"command":"'"$cmd"'"}}'
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
    assert_exit_code "0" "$EXIT_CODE" "path form must still be allowed: $cmd"
    teardown_test_project
  done
}

# --- Test: only the two sanctioned names unlock, not any mark-*.sh (a sanctioned
# name later in the line reaches the allowance, which must still refuse) ---
test_blocks_other_mark_script() {
  setup_test_project
  INPUT='{"tool_input":{"command":"bash .claude/framework/hooks/mark-other.sh mark-evaluated.sh /tmp/.claude_evaluated_abc123"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "an unsanctioned mark-*.sh must not unlock the guard"
  teardown_test_project
}

# --- Test: the block message points at the sanctioned scripts ---
test_block_message_names_scripts() {
  setup_test_project
  INPUT='{"tool_input":{"command":"touch /tmp/.claude_plan_closed_abc123"}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  assert_contains "$RESULT" "mark-plan-closed.sh" "block message should name mark-plan-closed.sh"
  assert_contains "$RESULT" "mark-evaluated.sh" "block message should name mark-evaluated.sh"
  assert_not_contains "$RESULT" "created automatically" "block message must not claim every marker is automatic"
  assert_contains "$RESULT" "run the sanctioned script as a lone command" "block message should say how the script must be run"
  teardown_test_project
}

# --- Run all tests ---
echo "marker-guard.sh (v4 markers)"
test_blocks_plan_active
test_blocks_has_plan
test_blocks_c7
test_allows_normal_touch
test_blocks_echo_redirect
test_blocks_printf_redirect
test_blocks_cp_to_marker
test_blocks_python_marker
test_blocks_tee_marker
test_allows_mark_evaluated_script
test_allows_unrelated_tmp_files
test_blocks_write_to_marker
test_blocks_edit_to_marker
test_blocks_notebookedit_to_marker
test_allows_write_normal_path
test_blocks_last_head_marker
test_blocks_mark_evaluated_injection
test_allows_lone_mark_evaluated
test_blocks_noncanonical_write_marker
test_blocks_double_slash_write_marker
test_blocks_dotdot_write_marker
test_blocks_bare_marker_name_bash
test_blocks_mark_evaluated_redirect
test_blocks_plan_closed_direct_create
test_blocks_plan_closed_direct_delete
test_blocks_write_to_plan_closed
test_allows_mark_evaluated_reason_naming_marker
test_allows_lone_mark_plan_closed
test_allows_lone_mark_plan_closed_note
test_blocks_mark_plan_closed_injection
test_blocks_mark_plan_closed_mention
test_blocks_mark_plan_closed_redirect
test_blocks_mark_plan_closed_substitution
test_blocks_mark_plan_closed_semicolon
test_blocks_mark_plan_closed_ampersand
test_blocks_mark_plan_closed_pipe
test_blocks_mark_plan_closed_backtick
test_blocks_mark_plan_closed_stdin_redirect
test_blocks_mark_plan_closed_newline
test_blocks_mark_plan_closed_unquoted_substitution
test_blocks_mark_plan_closed_glued_redirect
test_blocks_mark_plan_closed_name_tail
test_blocks_assignment_prefix
test_blocks_expanding_first_word
test_allows_path_forms
test_blocks_other_mark_script
test_block_message_names_scripts
run_tests
