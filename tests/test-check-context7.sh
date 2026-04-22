#!/usr/bin/env bash
# test-check-context7.sh — Tests for check_context7() in _helpers.sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

HELPERS="$(cd "$SCRIPT_DIR/.." && pwd)/hooks/_helpers.sh"

# check_context7 reads $HOME/.claude/settings.json and $HOME/.claude.json — we
# redirect HOME at a temp dir per test so real user configs don't leak in.
setup_fake_home() {
  FAKE_HOME=$(mktemp -d)
  mkdir -p "$FAKE_HOME/.claude"
  OLD_HOME="$HOME"
  export HOME="$FAKE_HOME"
}

teardown_fake_home() {
  export HOME="$OLD_HOME"
  [ -n "$FAKE_HOME" ] && rm -rf "$FAKE_HOME"
  unset FAKE_HOME OLD_HOME
}

run_check() {
  (source "$HELPERS" && check_context7; echo $?)
}

# --- Test: no config files → returns 1 ---
test_no_config_returns_1() {
  setup_fake_home
  EXIT=$(run_check)
  assert_equals "1" "$EXIT" "no config files should return 1"
  teardown_fake_home
}

# --- Test: direct MCP in ~/.claude/settings.json ---
test_mcp_in_settings_json() {
  setup_fake_home
  echo '{"mcpServers":{"context7":{"type":"stdio","command":"npx"}}}' > "$FAKE_HOME/.claude/settings.json"
  EXIT=$(run_check)
  assert_equals "0" "$EXIT" "direct MCP in settings.json should return 0"
  teardown_fake_home
}

# --- Test: legacy name "context7-mcp" in settings.json still detected ---
test_legacy_mcp_name() {
  setup_fake_home
  echo '{"mcpServers":{"context7-mcp":{"type":"stdio","command":"npx"}}}' > "$FAKE_HOME/.claude/settings.json"
  EXIT=$(run_check)
  assert_equals "0" "$EXIT" "legacy context7-mcp name should return 0"
  teardown_fake_home
}

# --- Test: direct MCP in ~/.claude.json (what `claude mcp add -s user` writes) ---
test_mcp_in_claude_json() {
  setup_fake_home
  echo '{"mcpServers":{"context7":{"type":"stdio","command":"npx"}}}' > "$FAKE_HOME/.claude.json"
  EXIT=$(run_check)
  assert_equals "0" "$EXIT" "MCP in ~/.claude.json should return 0"
  teardown_fake_home
}

# --- Test: plugin install via .enabledPlugins ---
test_plugin_install() {
  setup_fake_home
  echo '{"enabledPlugins":{"context7@claude-plugins-official":true}}' > "$FAKE_HOME/.claude/settings.json"
  EXIT=$(run_check)
  assert_equals "0" "$EXIT" "plugin-installed context7 should return 0"
  teardown_fake_home
}

# --- Test: plugin entry present but disabled (value=false) → not detected ---
test_plugin_disabled() {
  setup_fake_home
  echo '{"enabledPlugins":{"context7@claude-plugins-official":false}}' > "$FAKE_HOME/.claude/settings.json"
  EXIT=$(run_check)
  assert_equals "1" "$EXIT" "disabled plugin entry should return 1"
  teardown_fake_home
}

# --- Test: settings.json with neither mcpServers nor context7 plugin ---
test_unrelated_settings_returns_1() {
  setup_fake_home
  echo '{"enabledPlugins":{"superpowers@claude-plugins-official":true}}' > "$FAKE_HOME/.claude/settings.json"
  EXIT=$(run_check)
  assert_equals "1" "$EXIT" "unrelated plugins should return 1"
  teardown_fake_home
}

# --- Test: regex does NOT false-match a hypothetical context7-lookalike plugin ---
test_regex_tight_anchoring() {
  setup_fake_home
  echo '{"enabledPlugins":{"context7plus@foo":true}}' > "$FAKE_HOME/.claude/settings.json"
  EXIT=$(run_check)
  assert_equals "1" "$EXIT" "context7plus@foo must not false-match context7"
  teardown_fake_home
}

# --- Test: case-insensitive matching on plugin key ---
test_plugin_case_insensitive() {
  setup_fake_home
  echo '{"enabledPlugins":{"Context7@foo":true}}' > "$FAKE_HOME/.claude/settings.json"
  EXIT=$(run_check)
  assert_equals "0" "$EXIT" "Context7@foo should match case-insensitively"
  teardown_fake_home
}

# --- Test: MCP in settings.json takes priority over plugin absence ---
test_multiple_paths_any_wins() {
  setup_fake_home
  echo '{"mcpServers":{"context7":{"type":"stdio"}},"enabledPlugins":{"context7@foo":false}}' > "$FAKE_HOME/.claude/settings.json"
  EXIT=$(run_check)
  assert_equals "0" "$EXIT" "any path matching should return 0"
  teardown_fake_home
}

# --- Run all tests ---
echo "check_context7 (_helpers.sh)"
test_no_config_returns_1
test_mcp_in_settings_json
test_legacy_mcp_name
test_mcp_in_claude_json
test_plugin_install
test_plugin_disabled
test_unrelated_settings_returns_1
test_regex_tight_anchoring
test_plugin_case_insensitive
test_multiple_paths_any_wins
run_tests
