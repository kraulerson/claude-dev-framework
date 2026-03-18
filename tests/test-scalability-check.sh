#!/usr/bin/env bash
# test-scalability-check.sh — Tests for scalability-check hook
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/scalability-check.sh"

# --- Test: non-source file passes ---
test_non_source_passes() {
  setup_test_project
  jq '.discovery.futurePlatforms = "web dashboard"' "$TEST_DIR/.claude/manifest.json" > "$TEST_DIR/.claude/manifest.json.tmp"
  mv "$TEST_DIR/.claude/manifest.json.tmp" "$TEST_DIR/.claude/manifest.json"

  INPUT='{"tool_input":{"file_path":"README.md"}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  assert_equals "" "$RESULT" "non-source file should produce no output"
  teardown_test_project
}

# --- Test: non-architectural source file passes ---
test_non_architectural_passes() {
  setup_test_project
  jq '.discovery.futurePlatforms = "web dashboard"' "$TEST_DIR/.claude/manifest.json" > "$TEST_DIR/.claude/manifest.json.tmp"
  mv "$TEST_DIR/.claude/manifest.json.tmp" "$TEST_DIR/.claude/manifest.json"

  INPUT='{"tool_input":{"file_path":"utils.kt"}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  assert_equals "" "$RESULT" "non-architectural file should produce no output"
  teardown_test_project
}

# --- Test: architectural file with futurePlatforms produces advisory ---
test_architectural_advises() {
  setup_test_project
  jq '.discovery.futurePlatforms = "web dashboard"' "$TEST_DIR/.claude/manifest.json" > "$TEST_DIR/.claude/manifest.json.tmp"
  mv "$TEST_DIR/.claude/manifest.json.tmp" "$TEST_DIR/.claude/manifest.json"

  INPUT='{"tool_input":{"file_path":"UserRepository.kt"}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  assert_contains "$RESULT" "additionalContext" "should produce advisory"
  assert_contains "$RESULT" "web dashboard" "should mention future platforms"
  teardown_test_project
}

# --- Run all tests ---
echo "scalability-check.sh"
test_non_source_passes
test_non_architectural_passes
test_architectural_advises
run_tests
