#!/usr/bin/env bash
# test-config-guard.sh — Tests for config-guard hook
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/config-guard.sh"

# Hook input built with jq, so a command needs no JSON escaping; $2 sets the
# input's cwd (the agent's working directory), omitted when empty.
cg_input() { jq -nc --arg c "$1" --arg d "${2:-}" '{tool_name:"Bash",tool_input:{command:$c}} + (if $d == "" then {} else {cwd:$d} end)'; }
cg_write_input() { jq -nc --arg p "$1" '{tool_name:"Write",tool_input:{file_path:$p,content:"x"}}'; }
# A PATH holding only the tools the guards need minus `tr`, so the guard's own
# pipeline fails mid-run: an internal failure must block, not let the call through
# (Claude Code treats any exit other than 2 as non-blocking) (#11 review).
run_without_tr() {
  local bin c; bin=$(mktemp -d)
  for c in cat dirname jq grep sed; do ln -s "$(command -v "$c")" "$bin/$c"; done
  (cd "$TEST_DIR" && printf '%s' "$2" | PATH="$bin" /bin/bash "$1" 2>&1; echo "rc=$?")
  rm -rf "$bin"
}

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

# --- Test (approval design B): mark-evaluated.sh is the user's own override, run in a
# separate terminal; the agent may not run it in any form ---
test_blocks_mark_evaluated() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"bash .claude/framework/hooks/mark-evaluated.sh \"user approved\""}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  RESULT=$(run_hook "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "the agent may not run mark-evaluated.sh"
  assert_contains "$RESULT" "pending-approval.json" "the message names the question route"
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

# --- Test: allows git add on manifest.json (staging copies the file into the index and
# changes nothing on disk; the framework's own steps ask for it — dogfood-2 row 23) ---
test_allows_git_add_manifest() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"git add .claude/manifest.json"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "should allow git add on manifest.json"
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

# --- Test: an assignment prefix naming a script does not unlock ---
test_blocks_assignment_prefix() {
  local name
  for name in mark-evaluated.sh mark-plan-closed.sh; do
    setup_test_project
    INPUT='{"tool_name":"Bash","tool_input":{"command":"x='"$name"' cp /tmp/evil.sh .claude/framework/hooks/enforce-evaluate.sh"}}'
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
    assert_exit_code "2" "$EXIT_CODE" "x=$name prefix must not unlock the guard"
    teardown_test_project
  done
}

# --- Test: a first word that expands at run time does not unlock ---
test_blocks_expanding_first_word() {
  local name
  for name in mark-evaluated.sh mark-plan-closed.sh; do
    setup_test_project
    INPUT='{"tool_name":"Bash","tool_input":{"command":"cp$IFS/tmp/evil.sh$IFS.claude/framework/hooks/enforce-evaluate.sh$IFS#'"$name"'"}}'
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
    assert_exit_code "2" "$EXIT_CODE" "an \$IFS first word ending in $name must not unlock the guard"
    teardown_test_project
    # Without `#`, so the only character outside the path allowlist is `$`.
    setup_test_project
    INPUT='{"tool_name":"Bash","tool_input":{"command":"cp$IFS/tmp/evil.sh$IFS.claude/framework/hooks/enforce-evaluate.sh$IFS/dev/null$IFS'"$name"'"}}'
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
    assert_exit_code "2" "$EXIT_CODE" "a #-free \$IFS first word ending in $name must not unlock the guard"
    teardown_test_project
  done
}

# --- Test: the project's own scripts unlock by relative, ./ and absolute path
# (an absolute path still works where the project path has no space) ---
test_allows_path_forms() {
  local cmd
  setup_test_project
  for cmd in "bash $TEST_DIR/.claude/framework/hooks/mark-plan-closed.sh \"closed: retries=3\"" \
             'bash ./.claude/framework/hooks/mark-plan-closed.sh "closed"' \
             'bash .claude/framework/hooks/mark-plan-closed.sh "closed"'; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_input "$cmd")")
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
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_input "bash $proj/.claude/framework/hooks/mark-plan-closed.sh \"closed\"")")
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
  for cmd in 'bash evil/mark-plan-closed.sh .claude/settings.json' \
             'bash /tmp/mark-evaluated.sh .claude/manifest.json'; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_input "$cmd")")
    assert_exit_code "2" "$EXIT_CODE" "must not unlock: $cmd"
  done
  teardown_test_project
}

# --- Test (#11 case 1): a relative script path is resolved from the agent's cwd ---
test_relative_script_resolved_from_cwd() {
  setup_test_project
  local other cmd='bash .claude/framework/hooks/mark-plan-closed.sh "closed"'
  other=$(mktemp -d); mkdir -p "$other/.claude/framework/hooks"
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_input "$cmd" "$other")")
  assert_exit_code "2" "$EXIT_CODE" "a relative script under another cwd must not unlock"
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_input "$cmd" "$TEST_DIR")")
  assert_exit_code "0" "$EXIT_CODE" "the same command from the project root still unlocks"
  rm -rf "$other"
  teardown_test_project
}

# --- Test (#11 case 2): a command longer than the pipe buffer is still inspected, by
# each check separately (protected path, rm of .claude, CLAUDE_PROJECT_DIR=) ---
test_blocks_long_multiline_command() {
  local pad cmd
  setup_test_project
  pad=$(head -c 200000 /dev/zero | tr '\0' x)
  for cmd in 'cp /dev/null .claude/settings.json' 'rm -rf .claude/plans' 'CLAUDE_PROJECT_DIR=/x true'; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_input "$cmd
# $pad")")
    assert_exit_code "2" "$EXIT_CODE" "a 200 KB multi-line command must still be blocked: $cmd"
  done
  teardown_test_project
}

# --- Test (#11 case 3): a literal path into a temp fixture is not the project's config ---
test_allows_temp_fixture_paths() {
  local base fx cmd
  setup_test_project
  base=$(mktemp -d); fx="$base/fx"; mkdir -p "$fx/.claude/framework/hooks"
  for cmd in "echo '{}' > $fx/.claude/manifest.json" \
             "cp /dev/null $fx/.claude/settings.json" \
             "cp /dev/null $fx/.claude/framework/hooks/x.sh" \
             "cp /dev/null $fx/.Claude/Settings.json" \
             "mkdir -p $fx/.claude/framework/hooks" \
             "cat /dev/null > \"$fx/.claude/settings.local.json\"" \
             "bash $fx/.claude/framework/hooks/config-guard.sh < /dev/null"; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_input "$cmd")")
    assert_exit_code "0" "$EXIT_CODE" "temp fixture path must be allowed: $cmd"
  done
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_write_input "$fx/.claude/manifest.json")")
  assert_exit_code "0" "$EXIT_CODE" "Write to a temp fixture manifest must be allowed"
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_write_input "$fx/.claude/framework/hooks/x.sh")")
  assert_exit_code "0" "$EXIT_CODE" "Write to a temp fixture hook must be allowed"
  rm -rf "$base"
  teardown_test_project
}

# --- Test (#11 case 3): a path the text alone cannot pin to a temp fixture stays blocked ---
test_blocks_unpinnable_fixture_paths() {
  local base fx cmd
  setup_test_project
  base=$(mktemp -d); fx="$base/fx"; mkdir -p "$fx/.claude"
  ln -s "$TEST_DIR" "$base/link"
  for cmd in "cp /dev/null $TEST_DIR/.claude/settings.json" \
             'cp /dev/null $FX/.claude/settings.json' \
             "cp /dev/null $base/link/.claude/settings.json" \
             "cp /dev/null $fx/../fx/.claude/settings.json" \
             "cp /dev/null $base/*/.claude/settings.json" \
             "cp /dev/null \"a $fx/.claude/settings.json\"" \
             "cp /dev/null a\\ $fx/.claude/settings.json" \
             "cp /dev/null x\"$fx/.claude/settings.json\"" \
             "cp /dev/null ~/.claude/settings.json" \
             "cp /dev/null ~$fx/.claude/settings.json" \
             "cp /dev/null x=$fx/.claude/settings.json" \
             "cp /dev/null $fx/.claude/settings.json; cp /dev/null .claude/settings.json" \
             "cp /dev/null $fx/.claude/settings.json .Claude/settings.json" \
             'echo hello # .claude/manifest.json' \
             "ln -s $TEST_DIR $base/x1 && cp /dev/null $base/x1/.claude/settings.json" \
             "ln -s $TEST_DIR $base/x2; cp /dev/null $base/x2/.claude/settings.json" \
             "ln -s $TEST_DIR $base/x3
cp /dev/null $base/x3/.claude/settings.json" \
             "ln -s $TEST_DIR $base/x4 & cp /dev/null $base/x4/.claude/settings.json" \
             "true | cp /dev/null $fx/.claude/settings.json" \
             "cat > $fx/.claude/manifest.json <<'EOF'
{}
EOF" \
             "cp /dev/null \`true\` $fx/.claude/settings.json" \
             "cp /dev/null \$(true) $fx/.claude/settings.json" \
             "cp /dev/null $fx/.claude/settings.json # note" \
             "cp /dev/null \${X:-} $fx/.claude/settings.json" \
             "cp /dev/null \$'x' $fx/.claude/settings.json" \
             "printf %s $(head -c 17000 /dev/zero | tr '\0' a) > $fx/.claude/settings.json"; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_input "$cmd")")
    assert_exit_code "2" "$EXIT_CODE" "must stay blocked: $cmd"
  done
  for cmd in "$TEST_DIR/.claude/manifest.json" "$base/link/.claude/settings.json" \
             "$fx/../fx/.claude/manifest.json" "/Users/nobody/proj/.claude/manifest.json"; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_write_input "$cmd")")
    assert_exit_code "2" "$EXIT_CODE" "Write must stay blocked: $cmd"
  done
  rm -rf "$base"
  teardown_test_project
}

# --- Test (#11 comment): a read-only first word no longer admits the rest of the line,
# and read-only tools' writing/executing options do not count as read-only ---
test_blocks_read_only_word_with_payload() {
  local cmd
  setup_test_project
  for cmd in 'cat /dev/null; cp /dev/null .claude/settings.json' \
             'git log -1; cp /dev/null .claude/settings.json' \
             'grep -q x /dev/null && cp /dev/null .claude/manifest.json' \
             "awk 'BEGIN{system(\"cp /dev/null .claude/settings.json\")}'" \
             'rg --pre cp x .claude/settings.json' \
             'git diff --output=.claude/settings.json' \
             'git grep -Ocp x -- .claude/settings.json' \
             'bat --pager=cp .claude/settings.json' \
             'less -o .claude/settings.json /dev/null'; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_input "$cmd")")
    assert_exit_code "2" "$EXIT_CODE" "must stay blocked: $cmd"
  done
  RESULT=$(run_hook "$HOOK" "$(cg_input 'cat .claude/settings.json | tee /tmp/x')")
  assert_contains "$RESULT" "chain only read-only commands" "the block message says what inspection may chain"
  for cmd in 'cat .claude/settings.json' 'rg -n x .claude/settings.json' \
             'git log --oneline -- .claude/manifest.json' 'grep -c x .claude/manifest.json' \
             'git log -SOops -- .claude/manifest.json'; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_input "$cmd")")
    assert_exit_code "0" "$EXIT_CODE" "a lone read-only command must still be allowed: $cmd"
  done
  teardown_test_project
}

# --- Test (#11 review): the bare .claude, .claude/framework and .claude/framework/hooks
# directories are protected as copy/move destinations ---
test_blocks_bare_protected_dirs() {
  local cmd
  setup_test_project
  for cmd in 'cp /tmp/x.sh .claude/framework/hooks' 'cp -r /tmp/fx/.claude/framework .claude/' \
             'mv /tmp/h .claude/framework' 'cp /tmp/x.sh ".claude/framework/hooks"' \
             'cp -r /tmp/hooks .claude/framework/.' 'rm -rf .Claude/plans'; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_input "$cmd")")
    assert_exit_code "2" "$EXIT_CODE" "must be blocked: $cmd"
  done
  # Mentioning .claude as a word is not a write (#11 review): only the framework
  # directories are protected as bare destinations.
  for cmd in 'mkdir -p .claude/plans' 'ls .claude' 'cp /tmp/x .claude/plans/y.md' \
             'cat ~/.claude.json' 'ls ~/.claude-dev-framework' \
             'git commit -m "update .claude config"' 'find . -name .claude' 'du -sh .claude' \
             'tar czf backup.tgz .claude' 'echo edited .claude, done' \
             'jq . package.json # writes to .claude later'; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_input "$cmd")")
    assert_exit_code "0" "$EXIT_CODE" "must still be allowed: $cmd"
  done
  teardown_test_project
}

# --- Test (#11 review): a non-canonical spelling (//, /./, x/../) still names the
# protected path, for Bash and Write ---
test_blocks_noncanonical_paths() {
  local cmd
  setup_test_project
  for cmd in 'cp /tmp/x.sh .claude/framework/./hooks/config-guard.sh' \
             'cp /tmp/x.sh .claude//framework/hooks/config-guard.sh' \
             'cp /tmp/x.sh .claude/framework/x/../hooks/config-guard.sh' \
             'cp /tmp/s .claude/./settings.json' 'cp /tmp/s .claude//manifest.json' \
             'cp -r /tmp/h .claude/framework/x/..' 'rm -rf .//.claude' \
             'cp /tmp/x.sh ".claude/a b/../framework/hooks/config-guard.sh"' \
             "cp /tmp/x.sh .claude/'framework'/hooks/config-guard.sh" \
             'cp /tmp/x.sh .claude/fra\mework/hooks/config-guard.sh' \
             "cp /tmp/s .claude/sett''ings.json"; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_input "$cmd")")
    assert_exit_code "2" "$EXIT_CODE" "must be blocked: $cmd"
  done
  # An ordinary file reached through `..` is still allowed (the normalizer must not crash).
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_write_input "/Users/../$TEST_DIR/notes.md")")
  assert_exit_code "0" "$EXIT_CODE" "Write to an ordinary file through /Users/../ must be allowed"
  for cmd in "$TEST_DIR/.claude//settings.json" "$TEST_DIR/.claude/./manifest.json" \
             "$TEST_DIR/.claude/x/../settings.json" "/Users/../$TEST_DIR/.claude/settings.json" \
             "/private/../$TEST_DIR/.claude/framework/hooks/x.sh"; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_write_input "$cmd")")
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
test_without_jq_blocks_framework_calls() {
  local out bin
  setup_test_project
  out=$(run_without_jq "$HOOK" '{"session_id":"s1","transcript_path":"/Users/someone/.claude/projects/p/s1.jsonl","cwd":"/tmp","permission_mode":"default","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls -la"}}')
  assert_contains "$out" "rc=2" "without jq, config-guard must refuse the call"
  assert_contains "$out" "jq is not installed" "the block names the missing jq"
  bin=$(mktemp -d)
  printf '#!/bin/sh\nexit 1\n' > "$bin/jq"; chmod +x "$bin/jq"
  out=$(cd "$TEST_DIR" && printf '%s' '{"session_id":"s1","transcript_path":"/Users/someone/.claude/projects/p/s1.jsonl","cwd":"/tmp","permission_mode":"default","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls -la"}}' | PATH="$bin:$PATH" /bin/bash "$HOOK" 2>&1; echo "rc=$?")
  assert_contains "$out" "rc=2" "with a broken jq, config-guard must refuse the call"
  rm -rf "$bin"
  teardown_test_project
}

# --- Test (#11 review): an internal failure blocks rather than allowing the call ---
test_internal_failure_blocks() {
  local out
  setup_test_project
  out=$(run_without_tr "$HOOK" "$(cg_write_input "$TEST_DIR/.claude/settings.json")")
  assert_contains "$out" "rc=2" "config-guard must block when its own pipeline fails"
  assert_contains "$out" "failed internally" "the block says the guard failed internally"
  teardown_test_project
}

# --- Test (#11 review): other letter cases name the same files on a case-insensitive disk ---
test_blocks_case_variants() {
  local cmd
  setup_test_project
  for cmd in 'cp /dev/null .Claude/settings.json' 'cp /dev/null .claude/Settings.JSON' \
             'cp /tmp/x.sh .CLAUDE/Framework/Hooks/config-guard.sh'; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_input "$cmd")")
    assert_exit_code "2" "$EXIT_CODE" "must be blocked: $cmd"
  done
  for cmd in "$TEST_DIR/.Claude/settings.json" "$TEST_DIR/.claude/Framework/hooks/x.sh"; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_write_input "$cmd")")
    assert_exit_code "2" "$EXIT_CODE" "Write must be blocked: $cmd"
  done
  teardown_test_project
}

# --- Test (#11 review): a name that only ends in a sanctioned name does not unlock ---
test_blocks_prefixed_sanctioned_name() {
  setup_test_project
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_input 'bash .claude/framework/hooks/xmark-evaluated.sh "approved"')")
  assert_exit_code "2" "$EXIT_CODE" "xmark-evaluated.sh in the hooks folder must not unlock"
  teardown_test_project
}

# --- Test: only the two sanctioned names unlock, not any mark-*.sh (a sanctioned
# name later in the line reaches the allowance, which must still refuse) ---
test_blocks_other_mark_script() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"bash .claude/framework/hooks/mark-other.sh mark-plan-closed.sh"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "an unsanctioned mark-*.sh must not unlock the guard"
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

# Hook input in the shape Claude Code sends: session keys, the transcript under
# ~/.claude/projects, the agent's cwd. $2 is the cwd.
cg_real_input() {
  jq -nc --arg c "$1" --arg d "$2" --arg t "$HOME/.claude/projects/x/s.jsonl" \
    '{session_id:"s",transcript_path:$t,cwd:$d,permission_mode:"auto",hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c,description:"x"}}'
}

# A project whose path has a space, as the dogfood project had; sets PROJ.
setup_spaced_project() {
  setup_test_project
  PROJ="$TEST_DIR/Claude Projects/k-pdf dogfood"
  mkdir -p "$PROJ/.claude/framework/hooks"
  cp "$TEST_DIR/.claude/manifest.json" "$PROJ/.claude/"
  export CLAUDE_PROJECT_DIR="$PROJ"
}

# --- Test (dogfood-2 rows 7, 13): read-only inspection of .claude passes when every
# command in the chain only reads — the exact dogfood commands included ---
test_allows_read_only_chains() {
  local cmd
  setup_spaced_project
  while IFS= read -r cmd; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_real_input "$cmd" "$PROJ")")
    assert_exit_code "0" "$EXIT_CODE" "read-only chain must be allowed: $cmd"
  done << 'CMDS'
ls .claude .claude/framework; jq . .claude/manifest.json
cd "$HOME/Documents/Claude Projects/k-pdf-dogfood-2" && ls -l .git/hooks | grep -v sample; ls .claude .claude/framework | head -20; jq . .claude/manifest.json | head -20; sed -n 1,15p .github/workflows/ci.yml; ls -d .venv; git check-ignore .venv; ls *.md
cd "$HOME/Documents/Claude Projects/k-pdf-dogfood-2" && git status --short; git diff --stat | tail -12; git diff -- .claude/manifest.json | head -40; head -8 PROJECT_INTAKE.md
git show HEAD:.claude/settings.json
git show HEAD:.claude/settings.json 2>/dev/null | jq .permissions 2>&1
git ls-tree -r --name-only HEAD .claude/framework/hooks/ | wc -l
CMDS
  teardown_test_project
}

# --- Test (dogfood-2 row 23): plain git add of framework-written .claude files passes,
# alone or chained, so the framework's own "stage these files" steps can run ---
test_allows_git_add_staging() {
  local cmd
  setup_spaced_project
  while IFS= read -r cmd; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_real_input "$cmd" "$PROJ")")
    assert_exit_code "0" "$EXIT_CODE" "staging must be allowed: $cmd"
  done << 'CMDS'
cd "$HOME/Documents/Claude Projects/k-pdf-dogfood-2" && git add .claude/manifest.json && git add .claude/process-state.json && git add .claude/intake-progress.json && git add .claude/bypass-audit.json && git add .claude/adoption/assessment-record.json && git add .claude/adoption/verdict.md && git add CLAUDE.md && git add FEATURES.md && git add RELEASE_NOTES.md && git add docs/phase-0/adoption-plan.md && git status --short
git add -- .claude/settings.json .claude/framework/hooks/config-guard.sh
CMDS
  teardown_test_project
}

# --- Test: a chain that writes, executes or cannot be followed stays blocked, and so
# does git add with an option (--chmod changes the committed mode, -f, -p) ---
test_blocks_unsafe_chains() {
  local cmd
  setup_spaced_project
  while IFS= read -r cmd; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_real_input "$cmd" "$PROJ")")
    assert_exit_code "2" "$EXIT_CODE" "must stay blocked: $cmd"
  done << 'CMDS'
git add --chmod=-x .claude/framework/hooks/config-guard.sh
git add -f .claude/settings.local.json
git add .claude/manifest.json && git checkout -- .claude/settings.json
ls .claude/settings.json && cp /dev/null .claude/settings.json
cat .claude/settings.json | tee .claude/framework/hooks/x.sh
jq . .claude/manifest.json > .claude/settings.json
jq . .claude/manifest.json >> /tmp/x
cat .claude/settings.json | bash
sed -n 1w.claude/settings.json .claude/manifest.json
sed -i 1d .claude/settings.json
git diff --output=.claude/settings.json; ls
cat $(echo .claude/settings.json)
ls .claude/settings.json &>/dev/null
cd .claude/framework/hooks && cp /tmp/x config-guard.sh
X=1 cat .claude/settings.json
git diff --ext-diff .claude/settings.json
git log -p --textconv -- .claude/manifest.json
git show --ext-diff HEAD:.claude/settings.json | head
CMDS
  # A quote inside a comment must not hide the next line from the split (the closing
  # quote is in a second comment, so the text alone looks like one quoted word).
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_real_input "ls .claude # it's
cp /dev/null .claude/settings.json # it's" "$PROJ")")
  assert_exit_code "2" "$EXIT_CODE" "a comment's quote must not swallow the next line"
  teardown_test_project
}

# --- Test (dogfood-2 rows 23, 30): mark-evaluated.sh inside a cd/pipe chain stays
# blocked (the allowance is a lone command), and the message says how to run it ---
test_mark_chain_names_lone_form() {
  local cmd
  setup_spaced_project
  for cmd in 'cd "$HOME/Documents/Claude Projects/k-pdf-dogfood-2" && bash .claude/framework/hooks/mark-evaluated.sh "Karl approved design A1 and instructed one commit of the preferences fix (2 files)" 2>&1 | tail -3' \
             'cd "$HOME/Documents/Claude Projects/k-pdf-dogfood-2" && bash "$CLAUDE_PROJECT_DIR/.claude/framework/hooks/mark-evaluated.sh" "Karl approved A1" 2>&1 | tail -3'; do
    RESULT=$(run_hook "$HOOK" "$(cg_real_input "$cmd" "$PROJ")")
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_real_input "$cmd" "$PROJ")")
    assert_exit_code "2" "$EXIT_CODE" "a chained mark-evaluated.sh stays blocked: $cmd"
    assert_contains "$RESULT" "pending-approval.json" "the message names the question route"
  done
  # Approval design B: even the lone form is the user's own override now, not the agent's.
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_real_input 'bash .claude/framework/hooks/mark-evaluated.sh "Karl approved A1"' "$PROJ")")
  assert_exit_code "2" "$EXIT_CODE" "the lone mark-evaluated.sh form is refused too"
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_real_input 'bash .claude/framework/hooks/mark-plan-closed.sh "closed"' "$PROJ")")
  assert_exit_code "0" "$EXIT_CODE" "the lone mark-plan-closed.sh form from the spaced project root is allowed"
  teardown_test_project
}

# --- Test (review): a config-guard newer than its _helpers.sh (a framework sync left
# half done) refuses a write to a protected file rather than allowing it ---
test_old_helpers_still_block_writes() {
  local skew
  setup_test_project
  skew=$(mktemp -d)
  cp "$HOOK_DIR"/*.sh "$skew/"
  printf '\nunset -f command_only_reads shell_segments\n' >> "$skew/_helpers.sh"
  EXIT_CODE=$(run_hook_exit_code "$skew/config-guard.sh" "$(cg_input 'git add .claude/manifest.json; cp /dev/null .claude/settings.json')")
  assert_exit_code "2" "$EXIT_CODE" "an old _helpers.sh must not unblock a write"
  rm -rf "$skew"
  teardown_test_project
}

# --- Test (approval design B, spec 9b): git's hooks, config and info files are
# protected, so no hook can be planted to change a commit after it was approved;
# reads and ordinary git commands still pass, and temp fixture repos stay writable ---
test_git_paths_protected() {
  local p cmd fx
  setup_test_project
  for p in "$TEST_DIR/.git/hooks/pre-commit" "$TEST_DIR/.git/config" "$TEST_DIR/.git/info/attributes" \
           "$TEST_DIR/.git/info/exclude" ".git/hooks/post-commit" "$TEST_DIR/.GIT/Hooks/pre-commit" \
           "$TEST_DIR/.git//hooks/pre-commit"; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_write_input "$p")")
    assert_exit_code "2" "$EXIT_CODE" "Write must be refused: $p"
  done
  RESULT=$(run_hook "$HOOK" "$(cg_write_input "$TEST_DIR/.git/info/exclude")")
  assert_contains "$RESULT" ".gitignore" "an info/exclude refusal says to use .gitignore"
  for cmd in 'cat > .git/hooks/pre-commit' 'cp /tmp/x .git/hooks/post-commit' 'tee .git/config < /dev/null' \
             'printf x >> .git/info/exclude' 'cp /tmp/x .git/hooks' 'ln -s /tmp/h .GIT/hooks/pre-commit'; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_input "$cmd")")
    assert_exit_code "2" "$EXIT_CODE" "Bash must be refused: $cmd"
  done
  for cmd in 'cat .git/config' 'ls .git/hooks' 'git remote add o https://example.invalid/r.git' \
             'git config user.email e@example.invalid' 'git status' 'cat .gitignore' 'ls .github/workflows'; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_input "$cmd")")
    assert_exit_code "0" "$EXIT_CODE" "must still pass: $cmd"
  done
  fx=$(mktemp -d); mkdir -p "$fx/r/.git/hooks"
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_write_input "$fx/r/.git/hooks/pre-commit")")
  assert_exit_code "0" "$EXIT_CODE" "Write into a temp fixture repo's hooks is allowed"
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_input "cp /dev/null $fx/r/.git/hooks/pre-commit")")
  assert_exit_code "0" "$EXIT_CODE" "Bash copy into a temp fixture repo's hooks is allowed"
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_input "cp /dev/null $fx/r/.git/config")")
  assert_exit_code "0" "$EXIT_CODE" "Bash copy into a temp fixture repo's config is allowed"
  rm -rf "$fx"
  teardown_test_project
}

# --- Test (approval design B): the approval audit .claude/approvals.jsonl is written
# only by the framework; the agent can read and stage it ---
test_approvals_log_protected() {
  local cmd
  setup_test_project
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_write_input "$TEST_DIR/.claude/approvals.jsonl")")
  assert_exit_code "2" "$EXIT_CODE" "Write to approvals.jsonl must be refused"
  for cmd in 'echo "{}" >> .claude/approvals.jsonl' 'rm .claude/approvals.jsonl' 'sed -i "" 1d .claude/approvals.jsonl'; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_input "$cmd")")
    assert_exit_code "2" "$EXIT_CODE" "must be refused: $cmd"
  done
  for cmd in 'cat .claude/approvals.jsonl' 'git add .claude/approvals.jsonl' 'jq . .claude/approvals.jsonl'; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_input "$cmd")")
    assert_exit_code "0" "$EXIT_CODE" "must still pass: $cmd"
  done
  teardown_test_project
}

# --- Test (approval design B, spec 10): no form of mark-evaluated.sh is sanctioned ---
test_mark_evaluated_never_sanctioned() {
  local cmd
  setup_test_project
  for cmd in 'bash .claude/framework/hooks/mark-evaluated.sh "approved"' \
             'bash ./.claude/framework/hooks/mark-evaluated.sh "approved"' \
             "bash $TEST_DIR/.claude/framework/hooks/mark-evaluated.sh \"approved\"" \
             '.claude/framework/hooks/mark-evaluated.sh "approved"'; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_input "$cmd" "$TEST_DIR")")
    assert_exit_code "2" "$EXIT_CODE" "must be refused: $cmd"
  done
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_input 'bash .claude/framework/hooks/mark-plan-closed.sh "closed"' "$TEST_DIR")")
  assert_exit_code "0" "$EXIT_CODE" "mark-plan-closed.sh stays sanctioned"
  teardown_test_project
}

# --- Test (self-approval finding, PR 1): no copy of a hook that writes or clears a marker
# or an approval runs, in any directory, under any interpreter, with CLAUDECODE cleared.
# On aba947b each of these passed every guard, and the first two produced an approval:
# the guards protected only the project's .claude/framework/hooks/ ---
test_state_hooks_refused_anywhere() {
  local cmd ups
  setup_test_project
  ups='{"prompt":"A1","session_id":"s","transcript_path":"/Users/x/.claude/projects/p/s.jsonl","cwd":"/p","permission_mode":"auto","hook_event_name":"UserPromptSubmit","prompt_id":"x"}'
  for cmd in 'CLAUDECODE= bash ~/.claude-dev-framework/hooks/mark-evaluated.sh "approved"' \
             'env -u CLAUDECODE bash ~/.claude-dev-framework/hooks/mark-evaluated.sh approved' \
             'env -i PATH=/usr/bin:/bin bash ~/.claude-dev-framework/hooks/mark-evaluated.sh approved' \
             'unset CLAUDECODE; sh ~/.claude-dev-framework/hooks/mark-evaluated.sh approved' \
             'CLAUDECODE= zsh $HOME/.claude-dev-framework/hooks/mark-evaluated.sh approved' \
             'CLAUDECODE= source ~/.claude-dev-framework/hooks/mark-evaluated.sh approved' \
             'CLAUDECODE= . ~/.claude-dev-framework/hooks/mark-evaluated.sh approved' \
             'cd ~/.claude-dev-framework && CLAUDECODE= bash hooks/mark-evaluated.sh approved' \
             'cd /src/claude-dev-framework/hooks && CLAUDECODE= bash mark-evaluated.sh approved' \
             'bash "/Users/x/Documents/Claude Projects/claude-dev-framework/hooks/Mark-Evaluated.SH" ok' \
             'bash /src/cdf/hooks/mark-eval""uated.sh ok' \
             'bash /src/cdf/hooks/mark-eval\uated.sh ok' \
             'sh -c "CLAUDECODE= bash /src/cdf/hooks/mark-evaluated.sh approved"' \
             'cp ~/.claude-dev-framework/hooks/mark-evaluated.sh /tmp/m.sh' \
             'cat /src/cdf/hooks/record-approval.sh > /tmp/r.sh' \
             'cp -R ~/.claude-dev-framework/hooks /tmp/h' \
             'CLAUDECODE= bash ~/.claude-dev-framework/hooks/mark-e*.sh ok' \
             "printf '%s' '$ups' | bash ~/.claude-dev-framework/hooks/record-approval.sh" \
             "printf '%s' '$ups' | bash /tmp/cdf/hooks/record-approval.sh" \
             "echo '{\"tool_name\":\"Skill\",\"tool_input\":{\"skill\":\"superpowers:brainstorming\"}}' | bash ~/.claude-dev-framework/hooks/marker-tracker.sh" \
             'bash ~/.claude-dev-framework/hooks/session-start.sh </dev/null' \
             'bash ~/.claude-dev-framework/hooks/session-end.sh' \
             "echo '{}' | bash /src/cdf/hooks/stop-checklist.sh" \
             'bash ~/.claude-dev-framework/hooks/mark-plan-closed.sh "closed"'; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_real_input "$cmd" "$TEST_DIR")")
    assert_exit_code "2" "$EXIT_CODE" "must be refused: $cmd"
  done
  RESULT=$(run_hook "$HOOK" "$(cg_real_input 'CLAUDECODE= bash ~/.claude-dev-framework/hooks/mark-evaluated.sh "approved"' "$TEST_DIR")")
  assert_contains "$RESULT" "separate terminal" "the refusal says the override is the user's"
  teardown_test_project
}

# --- Test (self-approval finding, PR 1): reading, listing, searching and staging those
# scripts, the documented framework sync and the sanctioned mark-plan-closed.sh still pass ---
test_state_hooks_reads_pass() {
  local cmd
  setup_test_project
  for cmd in 'ls ~/.claude-dev-framework/hooks' \
             'cat ~/.claude-dev-framework/hooks/mark-evaluated.sh' \
             'head -40 /src/cdf/hooks/record-approval.sh' \
             'git log --oneline -- hooks/mark-evaluated.sh' \
             'grep -r marker-tracker docs/' \
             'grep -rn record-approval.sh docs/ | head -5' \
             'git add hooks/record-approval.sh' \
             'cd ~/.claude-dev-framework && git pull && cd - && bash ~/.claude-dev-framework/scripts/sync.sh' \
             'bash tests/test-record-approval.sh' \
             'bash .claude/framework/hooks/mark-plan-closed.sh "closed"'; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_real_input "$cmd" "$TEST_DIR")")
    assert_exit_code "0" "$EXIT_CODE" "must still pass: $cmd"
  done
  teardown_test_project
}

# --- Test (dogfood-3 rows 1, 5, 6, 10, 13, 14b): a framework path named only inside
# prose — a question, a commit message, text appended to a file outside the project —
# is not a target, and read-only inspection with find, cmp, a for loop or an if passes.
# A protected path counts where it is a path: at the start of a word or after / = : ,
# @ { and the like, never after a blank or ( inside quoted text, where it is part of a
# longer name ("a .claude" is not .claude). Commands taken from the dogfood transcript ---
test_dogfood3_prose_and_reads_pass() {
  local cmd
  setup_test_project
  while IFS= read -r cmd; do
    cmd=$(printf '%b' "$cmd")
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_real_input "$cmd" "$TEST_DIR")")
    assert_exit_code "0" "$EXIT_CODE" "must pass: $cmd"
  done << 'CMDS'
cd "/Users/karl/Documents/Claude Projects/k-pdf-dogfood-3" && git status --short; ls -la .git/hooks | grep -v sample; ls .claude .claude/framework | head -30; ls .venv >/dev/null 2>&1 && echo venv-present; git check-ignore -v .venv; cat .claude/manifest.json | head -20; ls *.md; grep -c . CLAUDE.md; ls tests | head -3; find tests -name 'test_*.py' | wc -l; find k_pdf -name '*.py' | wc -l
cd "/Users/karl/Documents/Claude Projects/k-pdf-dogfood-3" && A=.claude/adoption-archive/2026-10-07T01-19-20Z-25707; for f in .claude/settings.json .claude/manifest.json CLAUDE.md PROJECT_BIBLE.md PRODUCT_MANIFESTO.md; do if git show "0bb0465:$f" | cmp -s - "$A/$f"; then echo "IDENTICAL archived: $f"; else echo "DIFFERS: $f"; fi; done; git diff --quiet 0bb0465 HEAD -- PROJECT_BIBLE.md PRODUCT_MANIFESTO.md && echo "Bible+Manifesto unchanged in tree"
cmp .claude/settings.json /tmp/settings.json
diff .claude/manifest.json /tmp/manifest.json
printf '%s\\n' '- [Stage 2] git diff --name-status 0bb0465 HEAD = 119 A, 3 M (.claude/manifest.json, .claude/settings.json, CLAUDE.md), 0 deleted; untracked .claude/last-checked-commit.txt (runtime files).' >> ~/dogfood-2026-10/k-pdf-dogfood-3-FINDINGS.md
cd "/Users/karl/Documents/Claude Projects/k-pdf-dogfood-3" && bash scripts/pending-approval.sh --offer "Save the staged Guardrails 4.4.0 update plus the .gitignore fix as one chore change? (Stage .claude/framework/hooks/pre-commit-checks.sh first with ! git add; runtime files last-checked-commit.txt and tool-usage.json stay out.)" --options "A1: Save it as one chore change" "A2: Hold - do not save" --recommendation "A1" --approves A1
git commit -m "chore: update Guardrails to 4.4.0 and anchor lib/ ignore rule" -m "Refreshes .claude/framework via refresh-guardrails.sh and anchors lib/ to /lib/ so scripts/lib is tracked." -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
git commit -m "docs: explain (.claude/settings.json) and .git/hooks in the guide"
CMDS
  teardown_test_project
}

# --- Test (dogfood-3, the protections that stay): a protected path that is a real target
# — quoted, with a space in the folder, after = or {, piped from a read into a writer, in
# a loop body, behind a find action or an assignment that changes how a read runs — is
# still refused, and so is a line whose text the split cannot follow ---
test_dogfood3_targets_still_refused() {
  local cmd
  setup_test_project
  while IFS= read -r cmd; do
    cmd=$(printf '%b' "$cmd")
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(cg_real_input "$cmd" "$TEST_DIR")")
    assert_exit_code "2" "$EXIT_CODE" "must be refused: $cmd"
  done << 'CMDS'
cp x ".claude/settings.json"
cp x "/Users/karl/Documents/Claude Projects/p/.claude/settings.json"
cp x "$CLAUDE_PROJECT_DIR"/.claude/settings.json
cp x {.claude/settings.json,y}
install -m 644 x --target-directory=.claude/framework/hooks
echo .claude/settings.json | xargs rm
find .claude -name '*.sh' -delete
find .claude/framework -name x -exec rm {} \;
find .claude/framework/hooks -name x -delete
find .claude/framework -name x -exec rm {} +
find .git/hooks -name pre-commit -delete
find .git/hooks -name x -exec cp /tmp/evil {} +
for f in .claude/settings.json; do rm $f; done
if true; then tee .claude/settings.json < /dev/null; fi
PATH=/tmp/evil; cat .claude/settings.json
GIT_EXTERNAL_DIFF=/tmp/x; git diff .claude/settings.json
RIPGREP_CONFIG_PATH=/tmp/rgrc; rg x .claude/settings.json
BAT_PAGER=/tmp/x; cat .claude/settings.json
jq . .claude/manifest.json; bash scripts/resume.sh | head -20
git commit -m "see `cat .claude/settings.json`"
sed -i '' s/a/b/ .claude/framework/hooks/config-guard.sh
sed -n 'w .claude/settings.json' /tmp/evil.json
awk '{ print > "x .claude/settings.json" }' /tmp/x
git grep -O'sh -c "cp /tmp/x .claude/settings.json"' foo
bash -c 'cp /tmp/x .claude/settings.json'
git() { sed "$@"; }; git commit -m 'w .claude/settings.json'
PATH=/tmp/fake git commit -m 'w .claude/settings.json'
export PATH=/tmp/fake; git log --format=' .claude/settings.json'
git -c core.pager='tee x .claude/settings.json' log -p
echo $IFS.claude/settings.json > /tmp/x
printf '%s' "x .claude/settings.json" > .claude/settings.json
cat >> /tmp/notes.md <<'EOF'\ncp x .claude/settings.json\nEOF
CMDS
  teardown_test_project
}

# --- Test (dogfood-3 rows 1, 19): the refusal names the framework path and the command in
# the line that is not read-only, and says a script run breaks a read-only chain ---
test_dogfood3_refusal_names_the_part() {
  setup_test_project
  RESULT=$(run_hook "$HOOK" "$(cg_real_input 'jq -r .frameworkVersion .claude/manifest.json; grep -c record-approval .claude/settings.json; bash scripts/resume.sh | head -20' "$TEST_DIR")")
  assert_contains "$RESULT" "bash scripts/resume.sh" "the refusal names the command that is not read-only"
  assert_contains "$RESULT" ".claude/manifest.json" "the refusal names the framework path"
  assert_contains "$RESULT" "separate" "the refusal says to run it as a separate command"
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
test_blocks_mark_evaluated
test_allows_normal_bash
test_blocks_project_dir_override
test_allows_project_dir_read
test_allows_git_diff_settings
test_allows_git_log_manifest
test_allows_git_show_framework_hook
test_allows_git_blame_manifest
test_allows_git_add_manifest
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
test_blocks_assignment_prefix
test_blocks_expanding_first_word
test_allows_path_forms
test_allows_project_path_with_punctuation
test_blocks_sanctioned_name_elsewhere
test_relative_script_resolved_from_cwd
test_blocks_long_multiline_command
test_allows_temp_fixture_paths
test_blocks_unpinnable_fixture_paths
test_blocks_read_only_word_with_payload
test_blocks_other_mark_script
test_blocks_bare_protected_dirs
test_blocks_noncanonical_paths
test_internal_failure_blocks
test_without_jq_blocks_framework_calls
test_blocks_case_variants
test_blocks_prefixed_sanctioned_name
test_allows_read_only_chains
test_allows_git_add_staging
test_blocks_unsafe_chains
test_mark_chain_names_lone_form
test_old_helpers_still_block_writes
test_git_paths_protected
test_approvals_log_protected
test_mark_evaluated_never_sanctioned
test_state_hooks_refused_anywhere
test_state_hooks_reads_pass
test_dogfood3_prose_and_reads_pass
test_dogfood3_targets_still_refused
test_dogfood3_refusal_names_the_part
run_tests
