#!/usr/bin/env bash
# test-stop-checklist-pending-approval.sh — Pending-approval sentinel honored by stop-checklist
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/stop-checklist.sh"
STOP_INPUT='{"stop_reason":"assistant"}'

write_valid_sentinel() {
  cat > "$TEST_DIR/.claude/pending-approval.json" <<'JSON'
{
  "question": "commit structure",
  "options": ["A1: single commit", "A2: two commits"],
  "recommendation": "A1",
  "offered_at": "2026-04-24T15:30:00Z"
}
JSON
}

# --- Test: dirty source + valid sentinel → silent exit 0 ---
test_dirty_tree_valid_sentinel_silent() {
  setup_test_project
  echo "// dirty" > "$TEST_DIR/feature.kt"
  git -C "$TEST_DIR" add feature.kt
  write_valid_sentinel

  RESULT=$(run_hook "$HOOK" "$STOP_INPUT")
  EXIT=$(run_hook_exit_code "$HOOK" "$STOP_INPUT")

  assert_equals "0" "$EXIT" "sentinel present → exit 0"
  assert_not_contains "$RESULT" "block" "sentinel present → no block JSON"
  assert_not_contains "$RESULT" "Unfinished" "sentinel present → no unfinished-steps message"
  teardown_test_project
}

# --- Test: dirty source + malformed sentinel → still silent exit 0 ---
test_dirty_tree_malformed_sentinel_silent() {
  setup_test_project
  echo "// dirty" > "$TEST_DIR/feature.kt"
  git -C "$TEST_DIR" add feature.kt
  echo "{ not valid json" > "$TEST_DIR/.claude/pending-approval.json"

  RESULT=$(run_hook "$HOOK" "$STOP_INPUT")
  EXIT=$(run_hook_exit_code "$HOOK" "$STOP_INPUT")

  assert_equals "0" "$EXIT" "malformed sentinel still honored → exit 0"
  assert_not_contains "$RESULT" "block" "malformed sentinel → no block JSON"
  teardown_test_project
}

# --- Test: dirty source + empty sentinel → silent exit 0 ---
test_dirty_tree_empty_sentinel_silent() {
  setup_test_project
  echo "// dirty" > "$TEST_DIR/feature.kt"
  git -C "$TEST_DIR" add feature.kt
  : > "$TEST_DIR/.claude/pending-approval.json"

  RESULT=$(run_hook "$HOOK" "$STOP_INPUT")
  EXIT=$(run_hook_exit_code "$HOOK" "$STOP_INPUT")

  assert_equals "0" "$EXIT" "empty sentinel still honored → exit 0"
  assert_not_contains "$RESULT" "block" "empty sentinel → no block JSON"
  teardown_test_project
}

# --- Test: dirty source + no sentinel → block JSON (existing behavior preserved) ---
test_dirty_tree_no_sentinel_blocks() {
  setup_test_project
  echo "// dirty" > "$TEST_DIR/feature.kt"
  git -C "$TEST_DIR" add feature.kt

  RESULT=$(run_hook "$HOOK" "$STOP_INPUT")

  assert_contains "$RESULT" "block" "no sentinel → existing block behavior preserved"
  assert_contains "$RESULT" "Uncommitted source" "expected uncommitted-source error"
  teardown_test_project
}

# --- Test: clean tree + sentinel → silent exit 0 (sentinel honored even without errors) ---
test_clean_tree_sentinel_silent() {
  setup_test_project
  git -C "$TEST_DIR" rev-parse HEAD > "/tmp/.claude_session_start_${TEST_HASH}"
  write_valid_sentinel

  RESULT=$(run_hook "$HOOK" "$STOP_INPUT")
  EXIT=$(run_hook_exit_code "$HOOK" "$STOP_INPUT")

  assert_equals "0" "$EXIT" "clean tree + sentinel → exit 0"
  # Advisory output goes to stderr (captured by run_hook via 2>&1). Sentinel should suppress it too.
  assert_not_contains "$RESULT" "Design Zone" "sentinel should also suppress stderr advisory"
  assert_not_contains "$RESULT" "Planning Zone" "sentinel should also suppress stderr advisory"
  teardown_test_project
}

# --- Run all tests ---
echo "stop-checklist pending-approval"
test_dirty_tree_valid_sentinel_silent
test_dirty_tree_malformed_sentinel_silent
test_dirty_tree_empty_sentinel_silent
test_dirty_tree_no_sentinel_blocks
test_clean_tree_sentinel_silent
run_tests
