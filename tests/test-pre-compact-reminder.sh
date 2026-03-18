#!/usr/bin/env bash
# test-pre-compact-reminder.sh — Tests for pre-compact-reminder hook
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/pre-compact-reminder.sh"
# PreCompact hooks receive empty JSON input
COMPACT_INPUT='{}'

# --- Test: no context history file configured passes ---
test_no_ctx_file_passes() {
  setup_test_project
  RESULT=$(run_hook "$HOOK" "$COMPACT_INPUT")
  assert_equals "" "$RESULT" "no context file configured should produce no output"
  teardown_test_project
}

# --- Test: context history file not modified produces advisory ---
test_clean_ctx_file_advises() {
  setup_test_project
  jq '.projectConfig._base.contextHistoryFile = "CONTEXT.md"' "$TEST_DIR/.claude/manifest.json" > "$TEST_DIR/.claude/manifest.json.tmp"
  mv "$TEST_DIR/.claude/manifest.json.tmp" "$TEST_DIR/.claude/manifest.json"
  echo "old context" > "$TEST_DIR/CONTEXT.md"
  git -C "$TEST_DIR" add CONTEXT.md
  git -C "$TEST_DIR" commit -m "Add context" --quiet

  RESULT=$(run_hook "$HOOK" "$COMPACT_INPUT")
  assert_contains "$RESULT" "additionalContext" "should produce advisory"
  assert_contains "$RESULT" "CONTEXT.md" "should mention context file"
  teardown_test_project
}

# --- Run all tests ---
echo "pre-compact-reminder.sh"
test_no_ctx_file_passes
test_clean_ctx_file_advises
run_tests
