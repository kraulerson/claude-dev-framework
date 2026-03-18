#!/usr/bin/env bash
# test-changelog-sync-check.sh — Tests for changelog-sync-check hook
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/changelog-sync-check.sh"

# --- Test: non-changelog file passes ---
test_non_changelog_passes() {
  setup_test_project
  jq '.projectConfig._base.changelogFile = "CHANGELOG.md"' "$TEST_DIR/.claude/manifest.json" > "$TEST_DIR/.claude/manifest.json.tmp"
  mv "$TEST_DIR/.claude/manifest.json.tmp" "$TEST_DIR/.claude/manifest.json"

  INPUT='{"tool_input":{"file_path":"app.kt"}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  assert_equals "" "$RESULT" "non-changelog file should produce no output"
  teardown_test_project
}

# --- Test: changelog with fresh sync marker passes ---
test_changelog_with_marker_passes() {
  setup_test_project
  jq '.projectConfig._base.changelogFile = "CHANGELOG.md" | .projectConfig._base.syncCommand = "bash sync.sh"' \
    "$TEST_DIR/.claude/manifest.json" > "$TEST_DIR/.claude/manifest.json.tmp"
  mv "$TEST_DIR/.claude/manifest.json.tmp" "$TEST_DIR/.claude/manifest.json"
  touch "/tmp/.claude_changelog_synced_${TEST_HASH}"

  INPUT='{"tool_input":{"file_path":"CHANGELOG.md"}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  assert_equals "" "$RESULT" "changelog with fresh marker should pass"
  teardown_test_project
}

# --- Test: changelog without marker and with syncCommand produces advisory ---
test_changelog_without_marker_advises() {
  setup_test_project
  jq '.projectConfig._base.changelogFile = "CHANGELOG.md" | .projectConfig._base.syncCommand = "bash sync.sh"' \
    "$TEST_DIR/.claude/manifest.json" > "$TEST_DIR/.claude/manifest.json.tmp"
  mv "$TEST_DIR/.claude/manifest.json.tmp" "$TEST_DIR/.claude/manifest.json"

  INPUT='{"tool_input":{"file_path":"CHANGELOG.md"}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  assert_contains "$RESULT" "additionalContext" "should produce advisory"
  assert_contains "$RESULT" "sync" "should mention sync"
  teardown_test_project
}

# --- Run all tests ---
echo "changelog-sync-check.sh"
test_non_changelog_passes
test_changelog_with_marker_passes
test_changelog_without_marker_advises
run_tests
