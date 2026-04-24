#!/usr/bin/env bash
# test-stop-checklist-dedup.sh — Session-scope error dedup in stop-checklist hook
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/stop-checklist.sh"
STOP_INPUT='{"stop_reason":"assistant"}'

# Returns the expected marker path for the current test project.
errors_marker_path() {
  local session_sha
  session_sha=$(cat "/tmp/.claude_session_start_${TEST_HASH}" 2>/dev/null || echo "no-session")
  echo "/tmp/.claude_stop_errors_hash_${TEST_HASH}_${session_sha}"
}

# --- Test: first firing emits block and writes marker ---
test_first_fire_emits_block_and_writes_marker() {
  setup_test_project
  git -C "$TEST_DIR" rev-parse HEAD > "/tmp/.claude_session_start_${TEST_HASH}"
  echo "// dirty" > "$TEST_DIR/feature.kt"
  git -C "$TEST_DIR" add feature.kt

  RESULT=$(run_hook "$HOOK" "$STOP_INPUT")
  assert_contains "$RESULT" "block" "first firing on dirty tree should emit block"
  assert_file_exists "$(errors_marker_path)" "first firing should write errors marker"
  teardown_test_project
}

# --- Test: second firing with identical errors is silent ---
test_second_fire_identical_errors_silent() {
  setup_test_project
  git -C "$TEST_DIR" rev-parse HEAD > "/tmp/.claude_session_start_${TEST_HASH}"
  echo "// dirty" > "$TEST_DIR/feature.kt"
  git -C "$TEST_DIR" add feature.kt

  run_hook "$HOOK" "$STOP_INPUT" >/dev/null
  MARKER=$(errors_marker_path)
  HASH_BEFORE=$(cat "$MARKER")

  RESULT2=$(run_hook "$HOOK" "$STOP_INPUT")
  EXIT2=$(run_hook_exit_code "$HOOK" "$STOP_INPUT")
  HASH_AFTER=$(cat "$MARKER")

  assert_equals "0" "$EXIT2" "second firing should exit 0"
  assert_not_contains "$RESULT2" "block" "second firing with same errors should be silent"
  assert_equals "$HASH_BEFORE" "$HASH_AFTER" "marker content should be unchanged"
  teardown_test_project
}

# --- Test: different errors re-emit block and update marker ---
test_different_errors_reemit_and_update_marker() {
  setup_test_project
  git -C "$TEST_DIR" rev-parse HEAD > "/tmp/.claude_session_start_${TEST_HASH}"

  # First firing: dirty source → error "Uncommitted source changes..."
  echo "// dirty" > "$TEST_DIR/feature.kt"
  git -C "$TEST_DIR" add feature.kt
  run_hook "$HOOK" "$STOP_INPUT" >/dev/null
  MARKER=$(errors_marker_path)
  HASH_FIRST=$(cat "$MARKER")

  # Commit the staged file as an untested "fix:" → tree clean, but fix scan now triggers a different error.
  git -C "$TEST_DIR" commit -m "fix: correct feature behavior" --quiet

  RESULT2=$(run_hook "$HOOK" "$STOP_INPUT")
  HASH_SECOND=$(cat "$MARKER")

  assert_contains "$RESULT2" "block" "different error set should emit block again"
  assert_contains "$RESULT2" "regression test" "new error should be the untested-fix error"
  [ "$HASH_FIRST" != "$HASH_SECOND" ] && SECOND_CHANGED=yes || SECOND_CHANGED=no
  assert_equals "yes" "$SECOND_CHANGED" "marker hash should change when error set changes"
  teardown_test_project
}

# --- Test: empty errors removes marker ---
test_empty_errors_removes_marker() {
  setup_test_project
  git -C "$TEST_DIR" rev-parse HEAD > "/tmp/.claude_session_start_${TEST_HASH}"

  # Seed: dirty tree produces a block and a marker.
  echo "// dirty" > "$TEST_DIR/feature.kt"
  git -C "$TEST_DIR" add feature.kt
  run_hook "$HOOK" "$STOP_INPUT" >/dev/null
  MARKER=$(errors_marker_path)
  assert_file_exists "$MARKER" "marker should exist after first firing"

  # Clean up the tree — errors should now be empty.
  git -C "$TEST_DIR" commit -m "feat: add feature" --quiet

  RESULT=$(run_hook "$HOOK" "$STOP_INPUT")
  assert_not_contains "$RESULT" "block" "clean tree should produce no block"
  assert_file_not_exists "$MARKER" "marker should be removed when errors are empty"
  teardown_test_project
}

# --- Test: marker filename includes session-start SHA ---
test_marker_name_includes_session_sha() {
  setup_test_project
  SESSION_SHA=$(git -C "$TEST_DIR" rev-parse HEAD)
  echo "$SESSION_SHA" > "/tmp/.claude_session_start_${TEST_HASH}"
  echo "// dirty" > "$TEST_DIR/feature.kt"
  git -C "$TEST_DIR" add feature.kt

  run_hook "$HOOK" "$STOP_INPUT" >/dev/null
  EXPECTED="/tmp/.claude_stop_errors_hash_${TEST_HASH}_${SESSION_SHA}"
  assert_file_exists "$EXPECTED" "marker filename should be HASH_SESSION_SHA"
  teardown_test_project
}

# --- Run all tests ---
echo "stop-checklist dedup"
test_first_fire_emits_block_and_writes_marker
test_second_fire_identical_errors_silent
test_different_errors_reemit_and_update_marker
test_empty_errors_removes_marker
test_marker_name_includes_session_sha
run_tests
