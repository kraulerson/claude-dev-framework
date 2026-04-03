#!/usr/bin/env bash
# test-context7-tracker.sh — Tests for context7-tracker PostToolUse hook
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/context7-tracker.sh"

# --- Test: creates marker on resolve-library-id call ---
test_creates_marker_on_resolve() {
  setup_test_project
  INPUT='{"tool_name":"mcp__context7__resolve-library-id","tool_input":{"libraryName":"react"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_c7_${TEST_HASH}_react" "should create c7 marker for react"
  teardown_test_project
}

# --- Test: creates marker on get-library-docs call ---
test_creates_marker_on_get_docs() {
  setup_test_project
  INPUT='{"tool_name":"mcp__context7__get-library-docs","tool_input":{"context7CompatibleLibraryID":"/facebook/react","topic":"hooks"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_c7_${TEST_HASH}_facebook-react" "should create c7 marker for facebook/react"
  teardown_test_project
}

# --- Test: normalizes scoped package names ---
test_normalizes_scoped_names() {
  setup_test_project
  INPUT='{"tool_name":"mcp__context7__resolve-library-id","tool_input":{"libraryName":"@anthropic-ai/sdk"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_c7_${TEST_HASH}_anthropic-ai-sdk" "should normalize scoped name"
  teardown_test_project
}

# --- Test: ignores non-Context7 tools ---
test_ignores_other_tools() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"echo hello"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  local count
  count=$(ls /tmp/.claude_c7_${TEST_HASH}_* 2>/dev/null | wc -l | xargs)
  assert_equals "0" "$count" "should not create markers for non-Context7 tools"
  teardown_test_project
}

# --- Test: ignores Skill tool (not Context7 MCP) ---
test_ignores_skill_tool() {
  setup_test_project
  INPUT='{"tool_name":"Skill","tool_input":{"skill":"superpowers:brainstorming"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  local count
  count=$(ls /tmp/.claude_c7_${TEST_HASH}_* 2>/dev/null | wc -l | xargs)
  assert_equals "0" "$count" "should not create markers for Skill tool"
  teardown_test_project
}

# --- Run all tests ---
echo "context7-tracker.sh"
test_creates_marker_on_resolve
test_creates_marker_on_get_docs
test_normalizes_scoped_names
test_ignores_other_tools
test_ignores_skill_tool
run_tests
