#!/usr/bin/env bash
# test-stop-checklist-pending-approval.sh — Pending-approval sentinel honored by stop-checklist
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/stop-checklist.sh"
# Real Stop input (see tests/fixtures/stop.json): stop_hook_active=false, no reason field.
STOP_INPUT=$(jq -c . "$SCRIPT_DIR/fixtures/stop.json")

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
  # Sentinel exits before the advisory branch, so no additionalContext JSON is emitted either.
  assert_not_contains "$RESULT" "Design Zone" "sentinel should also suppress the advisory"
  assert_not_contains "$RESULT" "Planning Zone" "sentinel should also suppress the advisory"
  teardown_test_project
}

# --- Test (dogfood-2 row 21): the uncommitted-source block names the route out when
# the commit waits on the user — the pending-approval sentinel — and that route works ---
test_block_names_pending_approval_route() {
  setup_test_project
  echo "// dirty" > "$TEST_DIR/feature.kt"
  git -C "$TEST_DIR" add feature.kt

  RESULT=$(run_hook "$HOOK" "$STOP_INPUT")
  REASON=$(echo "$RESULT" | jq -r '.reason // empty' 2>/dev/null)
  assert_contains "$REASON" "Uncommitted source" "still asks for the commit"
  assert_contains "$REASON" "waiting on the user's approval" "says what to do when the commit waits on approval"
  assert_contains "$REASON" ".claude/pending-approval.json" "names the sentinel file"

  write_valid_sentinel
  # Drop the dedup record, so silence below comes from the sentinel, not from the
  # same error set having been shown once already.
  rm -f /tmp/.claude_stop_errors_hash_${TEST_HASH}_*
  RESULT=$(run_hook "$HOOK" "$STOP_INPUT")
  assert_not_contains "$RESULT" "block" "following the route lets the agent stop: no block once the question is recorded"
  teardown_test_project
}

# --- Test (approval design B, interim safety): a v1 or invalid question still lets the
# agent stop, and says it cannot be answered and how to rewrite it ---
test_v1_sentinel_explained() {
  setup_test_project
  echo "// dirty" > "$TEST_DIR/feature.kt"; git -C "$TEST_DIR" add feature.kt
  write_valid_sentinel
  RESULT=$(run_hook "$HOOK" "$STOP_INPUT")
  MSG=$(jq -r '.systemMessage // empty' <<< "$RESULT" 2>/dev/null)
  assert_not_contains "$RESULT" '"decision"' "a v1 question still lets the agent stop"
  assert_contains "$MSG" "cannot be answered" "the user is told the question cannot be answered"
  assert_contains "$MSG" '"schema": 2' "the message gives the schema-2 shape to rewrite it with"
  teardown_test_project
}

# --- Test (approval design B): a schema-2 question is shown to the user as a courtesy;
# the stop is not blocked and no render record is written ---
test_v2_sentinel_courtesy() {
  setup_test_project
  cat > "$TEST_DIR/.claude/pending-approval.json" << 'JSON'
{"schema": 2, "question": "Commit the parser fix?", "options": [{"id": "A1", "text": "Commit it", "approves": "commit"}, {"id": "A2", "text": "Hold", "approves": "none"}], "recommendation": "A1", "offered_at": "2026-10-05T12:00:00Z"}
JSON
  RESULT=$(run_hook "$HOOK" "$STOP_INPUT")
  MSG=$(jq -r '.systemMessage // empty' <<< "$RESULT" 2>/dev/null)
  assert_not_contains "$RESULT" '"decision"' "a pending question lets the agent stop"
  assert_contains "$MSG" "Commit the parser fix?" "the question is named"
  assert_contains "$MSG" "reply with the option id" "the user is told how to answer"
  assert_file_not_exists "/tmp/.claude_approval_shown_${TEST_HASH}" "the stop hook writes no render record"
  teardown_test_project
}

# --- Test (approval design B, spec 9): a commit whose tree differs from the approved one
# is reported once as an unfinished step ---
test_mismatched_commit_reported() {
  setup_test_project
  git -C "$TEST_DIR" rev-parse HEAD > "/tmp/.claude_session_start_${TEST_HASH}"
  echo x > "$TEST_DIR/f.txt"; git -C "$TEST_DIR" add f.txt; git -C "$TEST_DIR" commit -qm "docs"
  SHA=$(git -C "$TEST_DIR" rev-parse HEAD)
  printf '{"event":"commit","commit":"%s","approved_tree":"a","committed_tree":"b","matched":false}\n' "$SHA" > "$TEST_DIR/.claude/approvals.jsonl"
  RESULT=$(run_hook "$HOOK" "$STOP_INPUT")
  assert_contains "$RESULT" "does not match the tree the user approved" "the mismatch is reported"
  assert_contains "$RESULT" "${SHA:0:8}" "the commit is named"
  RESULT=$(run_hook "$HOOK" "$STOP_INPUT")
  assert_equals "" "$RESULT" "it is reported once"
  printf '{"event":"commit","commit":"%s","matched":true}\n' "$SHA" > "$TEST_DIR/.claude/approvals.jsonl"
  rm -f /tmp/.claude_stop_errors_hash_${TEST_HASH}_*
  RESULT=$(run_hook "$HOOK" "$STOP_INPUT")
  assert_not_contains "$RESULT" "does not match" "a matching commit is not reported"
  teardown_test_project
}

# --- Test (implementation review 1): a pending question does not hide a mismatched
# commit; it is reported once, and the question is still shown ---
test_mismatch_reported_with_pending_question() {
  setup_test_project
  git -C "$TEST_DIR" rev-parse HEAD > "/tmp/.claude_session_start_${TEST_HASH}"
  echo x > "$TEST_DIR/f.txt"; git -C "$TEST_DIR" add f.txt; git -C "$TEST_DIR" commit -qm "docs"
  SHA=$(git -C "$TEST_DIR" rev-parse HEAD)
  printf '{"event":"commit","commit":"%s","approved_tree":"a","committed_tree":"b","matched":false}\n' "$SHA" > "$TEST_DIR/.claude/approvals.jsonl"
  cat > "$TEST_DIR/.claude/pending-approval.json" << 'JSON'
{"schema": 2, "question": "Commit the next fix?", "options": [{"id": "A1", "text": "Commit it", "approves": "commit"}, {"id": "A2", "text": "Hold", "approves": "none"}], "recommendation": "A1", "offered_at": "2026-10-05T12:00:00Z"}
JSON
  RESULT=$(run_hook "$HOOK" "$STOP_INPUT")
  assert_contains "$RESULT" "does not match the tree the user approved" "the mismatch is reported despite the pending question"
  assert_contains "$RESULT" "${SHA:0:8}" "the commit is named"
  assert_contains "$RESULT" "Commit the next fix?" "the pending question is still shown"
  RESULT=$(run_hook "$HOOK" "$STOP_INPUT")
  assert_not_contains "$RESULT" "does not match" "the mismatch is reported once"
  assert_not_contains "$RESULT" '"decision"' "after that the pending question lets the agent stop"
  teardown_test_project
}

# --- Run all tests ---
echo "stop-checklist pending-approval"
test_dirty_tree_valid_sentinel_silent
test_dirty_tree_malformed_sentinel_silent
test_dirty_tree_empty_sentinel_silent
test_dirty_tree_no_sentinel_blocks
test_clean_tree_sentinel_silent
test_block_names_pending_approval_route
test_v1_sentinel_explained
test_v2_sentinel_courtesy
test_mismatched_commit_reported
test_mismatch_reported_with_pending_question
run_tests
