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
  assert_contains "$RESULT" "Superpowers" "should mention Superpowers skill"
  teardown_test_project
}

# --- Test: source file with superpowers marker passes ---
test_source_with_marker() {
  setup_test_project
  touch "/tmp/.claude_superpowers_${TEST_HASH}"
  INPUT='{"tool_input":{"file_path":"app.kt"}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  assert_equals "" "$RESULT" "source with superpowers marker should produce no output"
  teardown_test_project
}

# Hook input in the shape Claude Code sends: session keys, transcript under ~/.claude,
# and an absolute file path, as the file tools always send.
sp_input() {
  jq -nc --arg p "$1" --arg d "$TEST_DIR" --arg t "$HOME/.claude/projects/x/s.jsonl" \
    '{session_id:"s",transcript_path:$t,cwd:$d,permission_mode:"auto",hook_event_name:"PreToolUse",tool_name:"Edit",tool_input:{file_path:$p,old_string:"a",new_string:"b"}}'
}
enable_superpowers() { mkdir -p "$1"; echo "{\"enabledPlugins\":{\"superpowers@claude-plugins-official\":$2}}" > "$1/settings.json"; }

# --- Test (dogfood-3 row 7): git's ignore and attribute files and .editorconfig are
# configuration, not source; an unknown extension still counts as source (fail strict) ---
test_ignore_files_are_config() {
  local f
  setup_test_project
  enable_superpowers "$HOME/.claude" true
  for f in .gitignore sub/.gitignore .gitattributes .dockerignore .editorconfig; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(sp_input "$TEST_DIR/$f")")
    assert_exit_code "0" "$EXIT_CODE" "$f is not a source edit"
  done
  for f in app.kt scripts/run Makefile .envrc; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(sp_input "$TEST_DIR/$f")")
    assert_exit_code "2" "$EXIT_CODE" "$f is still a source edit"
  done
  rm -f "$HOME/.claude/settings.json"
  teardown_test_project
}

# --- Test (dogfood-2 row 27): with the plugin not enabled the block says so and gives
# the install command, instead of sending the agent after a skill that does not exist ---
test_not_installed_says_so() {
  setup_test_project
  RESULT=$(run_hook "$HOOK" "$(sp_input "$TEST_DIR/app.kt")")
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(sp_input "$TEST_DIR/app.kt")")
  assert_exit_code "2" "$EXIT_CODE" "still blocks the source edit"
  assert_contains "$RESULT" "plugin is not enabled" "says the plugin is not enabled"
  assert_contains "$RESULT" "claude plugin install --scope user superpowers@claude-plugins-official" "gives the install command"
  assert_not_contains "$RESULT" "Invoke the skill now" "does not send the agent to invoke a missing skill"
  teardown_test_project
}

# --- Test (dogfood-2 row 27): the plugin is looked up where this session's settings
# live — $CLAUDE_CONFIG_DIR when set, not ~/.claude — and a project setting wins ---
test_plugin_lookup_follows_config_dir() {
  local cfg
  setup_test_project
  cfg=$(mktemp -d)
  enable_superpowers "$HOME/.claude" true
  export CLAUDE_CONFIG_DIR="$cfg"
  RESULT=$(run_hook "$HOOK" "$(sp_input "$TEST_DIR/app.kt")")
  assert_contains "$RESULT" "plugin is not enabled" "~/.claude does not count when CLAUDE_CONFIG_DIR points elsewhere"
  enable_superpowers "$cfg" true
  RESULT=$(run_hook "$HOOK" "$(sp_input "$TEST_DIR/app.kt")")
  assert_not_contains "$RESULT" "plugin is not enabled" "enabled under CLAUDE_CONFIG_DIR counts"
  echo '{"enabledPlugins":{"superpowers@claude-plugins-official":false}}' > "$TEST_DIR/.claude/settings.json"
  RESULT=$(run_hook "$HOOK" "$(sp_input "$TEST_DIR/app.kt")")
  assert_contains "$RESULT" "plugin is not enabled" "a project setting that disables it wins"
  unset CLAUDE_CONFIG_DIR
  rm -rf "$cfg" "$HOME/.claude/settings.json"
  teardown_test_project
}

# --- Test (dogfood-2 row 28): with the plugin enabled the block states the marker's
# lifetime and does not demand brainstorming for an already-approved design ---
test_block_states_marker_lifetime() {
  setup_test_project
  enable_superpowers "$HOME/.claude" true
  RESULT=$(run_hook "$HOOK" "$(sp_input "$TEST_DIR/app.kt")")
  assert_contains "$RESULT" "cleared by a successful commit, by a new or cleared session, and at session end" "states when the marker is cleared"
  assert_contains "$RESULT" "superpowers:test-driven-development" "names the implementing skill for an approved design"
  assert_not_contains "$RESULT" "You MUST invoke superpowers:brainstorming" "does not demand brainstorming again"
  rm -f "$HOME/.claude/settings.json"
  teardown_test_project
}

# --- Test (run-1 sibling): a source-extension file outside the project (a scratch
# file) is not the project's source; inside, or reached through a link or `..`, it is ---
test_outside_project_passes() {
  local scratch
  setup_test_project
  scratch=$(mktemp -d)
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(sp_input "$scratch/probe.py")")
  assert_exit_code "0" "$EXIT_CODE" "a scratch .py outside the project is not blocked"
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(sp_input "$TEST_DIR/probe.py")")
  assert_exit_code "2" "$EXIT_CODE" "the same file inside the project is blocked"
  ln -s "$TEST_DIR" "$scratch/link"
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(sp_input "$scratch/link/probe.py")")
  assert_exit_code "2" "$EXIT_CODE" "a link into the project is still the project"
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(sp_input "$scratch/../$(basename "$TEST_DIR")/probe.py")")
  assert_exit_code "2" "$EXIT_CODE" "a path with .. counts as inside"
  rm -rf "$scratch"
  teardown_test_project
}

# --- Test (review): a hook newer than its _helpers.sh (a framework sync left half
# done) still blocks the source edit instead of letting it through ---
test_old_helpers_still_block() {
  local skew
  setup_test_project
  skew=$(mktemp -d)
  cp "$HOOK_DIR"/*.sh "$skew/"
  printf '\nunset -f superpowers_enabled plugin_settings_files path_outside_project\n' >> "$skew/_helpers.sh"
  EXIT_CODE=$(run_hook_exit_code "$skew/enforce-superpowers.sh" "$(sp_input "$TEST_DIR/app.kt")")
  assert_exit_code "2" "$EXIT_CODE" "an old _helpers.sh must not unblock a source edit"
  rm -rf "$skew"
  teardown_test_project
}

# --- Run all tests ---
echo "enforce-superpowers.sh"
test_doc_file_passes
test_test_file_passes
test_source_without_marker
test_source_with_marker
test_not_installed_says_so
test_plugin_lookup_follows_config_dir
test_block_states_marker_lifetime
test_outside_project_passes
test_old_helpers_still_block
test_ignore_files_are_config
run_tests
