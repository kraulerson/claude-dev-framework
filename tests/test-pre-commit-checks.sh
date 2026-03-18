#!/usr/bin/env bash
# test-pre-commit-checks.sh — Tests for pre-commit-checks hook
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/pre-commit-checks.sh"
COMMIT_INPUT='{"tool_input":{"command":"git commit -m \"test\""}}'

# --- Test: non-commit command passes ---
test_non_commit_passes() {
  setup_test_project
  INPUT='{"tool_input":{"command":"git status"}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  EXIT=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT" "non-commit should pass"
  teardown_test_project
}

# --- Test: doc-only commit passes ---
test_doc_only_passes() {
  setup_test_project
  echo "docs" > "$TEST_DIR/README.md"
  git -C "$TEST_DIR" add README.md
  EXIT=$(run_hook_exit_code "$HOOK" "$COMMIT_INPUT")
  assert_exit_code "0" "$EXIT" "doc-only commit should pass"
  teardown_test_project
}

# --- Test: source file without changelog blocks ---
test_source_without_changelog_blocks() {
  setup_test_project
  # Add changelogFile to manifest
  jq '.projectConfig._base.changelogFile = "CHANGELOG.md"' "$TEST_DIR/.claude/manifest.json" > "$TEST_DIR/.claude/manifest.json.tmp"
  mv "$TEST_DIR/.claude/manifest.json.tmp" "$TEST_DIR/.claude/manifest.json"

  echo "// code" > "$TEST_DIR/app.kt"
  git -C "$TEST_DIR" add app.kt
  EXIT=$(run_hook_exit_code "$HOOK" "$COMMIT_INPUT")
  assert_exit_code "2" "$EXIT" "source without changelog should block with exit 2"
  teardown_test_project
}

# --- Run all tests ---
echo "pre-commit-checks.sh"
test_non_commit_passes
test_doc_only_passes
test_source_without_changelog_blocks
run_tests
