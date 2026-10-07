#!/usr/bin/env bash
# test-marker-guard-v4.sh — Tests for v4 marker types in marker-guard
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/marker-guard.sh"

# Hook input built with jq, so a command needs no JSON escaping; $2 sets the
# input's cwd (the agent's working directory), omitted when empty.
mg_input() { jq -nc --arg c "$1" --arg d "${2:-}" '{tool_name:"Bash",tool_input:{command:$c}} + (if $d == "" then {} else {cwd:$d} end)'; }
# A PATH holding only the tools the guards need minus `tr`, so the guard's own
# pipeline fails mid-run: an internal failure must block, not let the call through
# (Claude Code treats any exit other than 2 as non-blocking) (#11 review).
run_without_tr() {
  local bin c; bin=$(mktemp -d)
  for c in cat dirname jq grep sed; do ln -s "$(command -v "$c")" "$bin/$c"; done
  (cd "$TEST_DIR" && printf '%s' "$2" | PATH="$bin" /bin/bash "$1" 2>&1; echo "rc=$?")
  rm -rf "$bin"
}

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

# --- Test: marker-guard judges only marker names; a plain mark-evaluated.sh call that
# names none is config-guard's to refuse (approval design B), not this hook's ---
test_allows_mark_evaluated_script() {
  setup_test_project
  INPUT='{"tool_input":{"command":"bash .claude/framework/hooks/mark-evaluated.sh \"user approved\""}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "marker-guard leaves a marker-free mark-evaluated.sh call to config-guard"
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

# --- Test: plain lone mark-evaluated.sh naming no marker passes marker-guard (config-guard refuses it) ---
test_allows_lone_mark_evaluated() {
  setup_test_project
  INPUT='{"tool_input":{"command":"bash .claude/framework/hooks/mark-evaluated.sh \"reason text\""}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "marker-guard leaves a marker-free mark-evaluated.sh call to config-guard"
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

# --- Test (approval design B): mark-evaluated.sh is no longer sanctioned, so a call that
# names a marker is refused like any other command naming one ---
test_blocks_mark_evaluated_reason_naming_marker() {
  setup_test_project
  INPUT='{"tool_input":{"command":"bash .claude/framework/hooks/mark-evaluated.sh \"approved: clear /tmp/.claude_evaluated_x handling\""}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "mark-evaluated.sh naming a marker is refused"
  teardown_test_project
}

# --- Test: lone mark-plan-closed.sh is allowed whatever its summary names ---
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
    # Without `#`, so the only character outside the path allowlist is `$`.
    setup_test_project
    INPUT='{"tool_input":{"command":"touch$IFS/tmp/.claude_evaluated_abc123$IFS/dev/null$IFS'"$name"'"}}'
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
    assert_exit_code "2" "$EXIT_CODE" "a #-free \$IFS first word ending in $name must not unlock the guard"
    teardown_test_project
  done
}

# --- Test: the project's own scripts unlock by relative, ./ and absolute path
# (an absolute path still works where the project path has no space). Each names a marker, so only
# the allowance can pass it. ---
test_allows_path_forms() {
  local cmd
  setup_test_project
  for cmd in "bash $TEST_DIR/.claude/framework/hooks/mark-plan-closed.sh \"closed: retries=3 for /tmp/.claude_plan_closed_x\"" \
             'bash ./.claude/framework/hooks/mark-plan-closed.sh "closed: /tmp/.claude_plan_closed_x"' \
             'bash .claude/framework/hooks/mark-plan-closed.sh "closed: /tmp/.claude_plan_closed_x"'; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(mg_input "$cmd")")
    assert_exit_code "0" "$EXIT_CODE" "path form must still be allowed: $cmd"
  done
  teardown_test_project
}

# --- Test: a project path with + @ , : % still unlocks ---
test_allows_project_path_with_punctuation() {
  setup_test_project
  local proj="$TEST_DIR/my+proj@2,v1:x%y" saved="$CLAUDE_PROJECT_DIR"
  mkdir -p "$proj/.claude/framework/hooks"
  export CLAUDE_PROJECT_DIR="$proj"
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(mg_input "bash $proj/.claude/framework/hooks/mark-plan-closed.sh \"closed: /tmp/.claude_plan_closed_x\"")")
  export CLAUDE_PROJECT_DIR="$saved"
  assert_exit_code "0" "$EXIT_CODE" "a project path with + @ , : % must still be allowed"
  teardown_test_project
}

# --- Test (#11 case 1): a script with a sanctioned name outside the project's
# hooks folder does not unlock ---
test_blocks_sanctioned_name_elsewhere() {
  local cmd
  setup_test_project
  mkdir -p "$TEST_DIR/evil"
  for cmd in 'bash evil/mark-evaluated.sh /tmp/.claude_evaluated_abc123' \
             'bash /tmp/mark-plan-closed.sh /tmp/.claude_plan_closed_abc123' \
             '~/.claude-dev-framework/hooks/mark-evaluated.sh "approved: /tmp/.claude_evaluated_abc123"'; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(mg_input "$cmd")")
    assert_exit_code "2" "$EXIT_CODE" "must not unlock: $cmd"
  done
  teardown_test_project
}

# --- Test (#11 case 1): a relative script path is resolved from the agent's cwd ---
test_relative_script_resolved_from_cwd() {
  setup_test_project
  local other cmd='bash .claude/framework/hooks/mark-plan-closed.sh "closed: /tmp/.claude_plan_closed_abc123"'
  other=$(mktemp -d); mkdir -p "$other/.claude/framework/hooks"
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(mg_input "$cmd" "$other")")
  assert_exit_code "2" "$EXIT_CODE" "a relative script under another cwd must not unlock"
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(mg_input "$cmd" "$TEST_DIR")")
  assert_exit_code "0" "$EXIT_CODE" "the same command from the project root still unlocks"
  rm -rf "$other"
  teardown_test_project
}

# --- Test (#11 case 2): a command longer than the pipe buffer is still inspected ---
test_blocks_long_multiline_command() {
  setup_test_project
  local cmd
  cmd="touch /tmp/.claude_evaluated_abc123
# $(head -c 200000 /dev/zero | tr '\0' x)"
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(mg_input "$cmd")")
  assert_exit_code "2" "$EXIT_CODE" "a 200 KB multi-line command naming a marker must be blocked"
  teardown_test_project
}

# --- Test (#11 review): other letter cases name the same marker on a case-insensitive disk ---
test_blocks_marker_case_variants() {
  local cmd
  setup_test_project
  for cmd in 'touch /tmp/.Claude_evaluated_abc123' 'touch /tmp/.CLAUDE_EVALUATED_abc123'; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(mg_input "$cmd")")
    assert_exit_code "2" "$EXIT_CODE" "must be blocked: $cmd"
  done
  for cmd in /tmp/.Claude_evaluated_abc123 /private/tmp/.CLAUDE_superpowers_abc123 /TMP/.claude_evaluated_abc123 \
             /tmp/../tmp/.claude_evaluated_abc123 /Users/../tmp/.claude_evaluated_abc123; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(jq -nc --arg p "$cmd" '{tool_name:"Write",tool_input:{file_path:$p,content:"x"}}')")
    assert_exit_code "2" "$EXIT_CODE" "Write must be blocked: $cmd"
  done
  teardown_test_project
}

# A PATH with the guards' tools but no jq (#11 review).
run_without_jq() {
  local bin c; bin=$(mktemp -d)
  for c in cat dirname grep sed tr; do ln -s "$(command -v "$c")" "$bin/$c"; done
  (cd "$TEST_DIR" && printf '%s' "$2" | PATH="$bin" /bin/bash "$1" 2>&1; echo "rc=$?")
  rm -rf "$bin"
}

# --- Test (#11 review): without a working jq the guard refuses every call. The input
# is real-shaped: Claude Code always sends transcript_path, which lies under ~/.claude. ---
test_without_jq_blocks_marker_calls() {
  local out bin
  setup_test_project
  out=$(run_without_jq "$HOOK" '{"session_id":"s1","transcript_path":"/Users/someone/.claude/projects/p/s1.jsonl","cwd":"/tmp","permission_mode":"default","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls -la"}}')
  assert_contains "$out" "rc=2" "without jq, marker-guard must refuse the call"
  assert_contains "$out" "jq is not installed" "the block names the missing jq"
  bin=$(mktemp -d)
  printf '#!/bin/sh\nexit 1\n' > "$bin/jq"; chmod +x "$bin/jq"
  out=$(cd "$TEST_DIR" && printf '%s' '{"session_id":"s1","transcript_path":"/Users/someone/.claude/projects/p/s1.jsonl","cwd":"/tmp","permission_mode":"default","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls -la"}}' | PATH="$bin:$PATH" /bin/bash "$HOOK" 2>&1; echo "rc=$?")
  assert_contains "$out" "rc=2" "with a broken jq, marker-guard must refuse the call"
  rm -rf "$bin"
  teardown_test_project
}

# --- Test (#11 review): an internal failure blocks rather than allowing the call ---
test_internal_failure_blocks() {
  local out
  setup_test_project
  out=$(run_without_tr "$HOOK" "$(jq -nc '{tool_name:"Write",tool_input:{file_path:"/tmp/.claude_evaluated_abc123",content:"x"}}')")
  assert_contains "$out" "rc=2" "marker-guard must block when its own pipeline fails"
  assert_contains "$out" "failed internally" "the block says the guard failed internally"
  teardown_test_project
}

# --- Test (#11 review): a name that only ends in a sanctioned name does not unlock ---
test_blocks_prefixed_sanctioned_name() {
  setup_test_project
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(mg_input 'bash .claude/framework/hooks/xmark-evaluated.sh /tmp/.claude_evaluated_abc123')")
  assert_exit_code "2" "$EXIT_CODE" "xmark-evaluated.sh in the hooks folder must not unlock"
  teardown_test_project
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
  assert_contains "$RESULT" "pending-approval.json" "block message should name the question route for the evaluation marker"
  assert_not_contains "$RESULT" "created automatically" "block message must not claim every marker is automatic"
  assert_contains "$RESULT" "as a lone command" "block message should say how the script must be run"
  teardown_test_project
}

# --- Test (approval design B): the approval render record is a framework marker ---
test_blocks_approval_shown_marker() {
  local cmd
  setup_test_project
  for cmd in 'touch /tmp/.claude_approval_shown_abc123' 'echo {} > /tmp/.claude_approval_shown_abc123' \
             'rm -f /tmp/.claude_approval_shown_abc123'; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(mg_input "$cmd")")
    assert_exit_code "2" "$EXIT_CODE" "must be refused: $cmd"
  done
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(jq -nc '{tool_name:"Write",tool_input:{file_path:"/tmp/.claude_approval_shown_abc123",content:"{}"}}')")
  assert_exit_code "2" "$EXIT_CODE" "Write to the render record is refused"
  teardown_test_project
}

# --- Test (self-approval finding, PR 1): a marker name split by quotes or a backslash is
# still that name to the shell (`.claude_eval""uated_x` writes .claude_evaluated_x), so
# one plain command after reading HEAD, the index tree and the digests wrote a valid
# approval marker past both guards on aba947b. Every protected name, every split ---
test_blocks_quote_split_marker_names() {
  local name split left right cmd
  setup_test_project
  for name in superpowers evaluated plan_closed plan_active has_plan skill_active c7 c7_degraded \
              changelog_synced session_start last_head stop_errors_hash eval_log approval_shown; do
    left="${name:0:1}"; right="${name:1}"
    for split in '""' "''" '\'; do
      cmd="printf '%s' '{\"tree\":\"t\"}' > /tmp/.claude_${left}${split}${right}_abc123"
      EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(mg_input "$cmd" "$TEST_DIR")")
      assert_exit_code "2" "$EXIT_CODE" "must be refused: $cmd"
    done
  done
  for cmd in 'touch /tmp/.cla""ude_evaluated_abc123' "cp x /tmp/'.claude_approval'_shown_abc123" \
             'mv x "/tmp/.claude_"evaluated_abc123'; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(mg_input "$cmd" "$TEST_DIR")")
    assert_exit_code "2" "$EXIT_CODE" "must be refused: $cmd"
  done
  teardown_test_project
}

# --- Test (self-approval finding, PR 1): quotes and backslashes in ordinary commands that
# name no marker still pass ---
test_quotes_without_marker_names_pass() {
  local cmd
  setup_test_project
  for cmd in "git commit -m \"fix: don't split\"" 'echo "a\b" | grep -c "a"' "grep -rn 'claude_' docs/" \
             "printf '%s\n' x" 'ls /tmp/.claude-dev-framework' 'echo ".claude_" "evaluated"' \
             "sed -n '1,5p' \"Claude Projects/x.md\""; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(mg_input "$cmd" "$TEST_DIR")")
    assert_exit_code "0" "$EXIT_CODE" "must still pass: $cmd"
  done
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
test_blocks_mark_evaluated_reason_naming_marker
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
test_allows_project_path_with_punctuation
test_blocks_sanctioned_name_elsewhere
test_relative_script_resolved_from_cwd
test_blocks_long_multiline_command
test_blocks_marker_case_variants
test_internal_failure_blocks
test_without_jq_blocks_marker_calls
test_blocks_prefixed_sanctioned_name
test_blocks_other_mark_script
test_block_message_names_scripts
test_blocks_approval_shown_marker
test_blocks_quote_split_marker_names
test_quotes_without_marker_names_pass
run_tests
