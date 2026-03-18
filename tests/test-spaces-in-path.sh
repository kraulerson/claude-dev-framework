#!/usr/bin/env bash
# test-spaces-in-path.sh — Verify hooks work when project path contains spaces
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

FRAMEWORK_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

test_generate_settings_quotes_paths() {
  # Source shared functions
  source "$FRAMEWORK_DIR/scripts/_shared.sh"

  # Generate settings and extract all command values
  local output
  output=$(generate_settings_json session-start enforce-evaluate stop-checklist)

  # Every command value should start and end with a literal double-quote
  local all_commands
  all_commands=$(echo "$output" | jq -r '.. | .command? // empty')
  while IFS= read -r cmd; do
    [ -z "$cmd" ] && continue
    local first="${cmd:0:1}"
    local last="${cmd: -1}"
    assert_equals '"' "$first" "command should start with quote: $cmd"
    assert_equals '"' "$last" "command should end with quote: $cmd"
  done <<< "$all_commands"
}

test_hooks_execute_with_spaces_in_path() {
  # Create a temp dir with spaces in the name
  local BASE_TEMP
  BASE_TEMP=$(mktemp -d)
  TEST_DIR="$BASE_TEMP/project with spaces"
  mkdir -p "$TEST_DIR/.claude"

  # Initialize git repo
  git -C "$TEST_DIR" init --quiet
  git -C "$TEST_DIR" config user.email "test@test.com"
  git -C "$TEST_DIR" config user.name "Test"
  echo "init" > "$TEST_DIR/README.md"
  git -C "$TEST_DIR" add README.md
  git -C "$TEST_DIR" commit -m "Initial commit" --quiet

  # Write manifest
  cat > "$TEST_DIR/.claude/manifest.json" << 'MANIFEST'
{
  "frameworkVersion": "1.1.0",
  "profile": "mobile-app",
  "activeRules": ["evaluate-before-implement"],
  "activeHooks": ["enforce-evaluate", "stop-checklist"],
  "projectConfig": {
    "_base": {
      "sourceExtensions": [".py", ".js", ".ts", ".kt", ".swift"],
      "protectedBranches": ["main"]
    },
    "branches": []
  },
  "discovery": {}
}
MANIFEST

  # Copy hooks into the spaced project path
  mkdir -p "$TEST_DIR/.claude/framework/hooks"
  cp "$FRAMEWORK_DIR/hooks/"*.sh "$TEST_DIR/.claude/framework/hooks/"
  chmod +x "$TEST_DIR/.claude/framework/hooks/"*.sh

  export CLAUDE_PROJECT_DIR="$TEST_DIR"
  TEST_HASH=$(echo -n "$TEST_DIR" | shasum -a 256 | cut -c1-12)

  # Test session-start hook executes without error
  local session_output session_exit
  session_output=$(cd "$TEST_DIR" && bash "$TEST_DIR/.claude/framework/hooks/session-start.sh" 2>&1)
  session_exit=$?
  assert_exit_code "0" "$session_exit" "session-start should succeed with spaces in path"
  assert_contains "$session_output" "CLAUDE DEV FRAMEWORK" "session-start should show banner with spaced path"

  # Test enforce-evaluate hook executes without error
  local eval_output eval_exit
  eval_output=$(cd "$TEST_DIR" && echo '{"tool_input":{"command":"git commit -m test"}}' | bash "$TEST_DIR/.claude/framework/hooks/enforce-evaluate.sh" 2>&1)
  eval_exit=$?
  assert_exit_code "0" "$eval_exit" "enforce-evaluate should succeed with spaces in path"

  # Test stop-checklist hook executes without error
  local stop_output stop_exit
  stop_output=$(cd "$TEST_DIR" && echo '{"stop_reason":"user"}' | bash "$TEST_DIR/.claude/framework/hooks/stop-checklist.sh" 2>&1)
  stop_exit=$?
  assert_exit_code "0" "$stop_exit" "stop-checklist should succeed with spaces in path"

  # Clean up
  rm -f "/tmp/.claude_evaluated_${TEST_HASH}"
  rm -f "/tmp/.claude_superpowers_${TEST_HASH}"
  rm -f "/tmp/.claude_session_start_${TEST_HASH}"
  rm -f "/tmp/.claude_changelog_synced_${TEST_HASH}"
  rm -f "/tmp/.claude_plan_closed_${TEST_HASH}"
  rm -rf "$BASE_TEMP"
  unset CLAUDE_PROJECT_DIR TEST_DIR TEST_HASH
}

# --- Run ---
echo "spaces-in-path (quoting)"
test_generate_settings_quotes_paths
test_hooks_execute_with_spaces_in_path
run_tests
