#!/usr/bin/env bash
# test-integration-workflow.sh — End-to-end workflow integration test
# Simulates: session start → enforce advisory → marker → commit → stop
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

test_full_session_lifecycle() {
  setup_test_project

  # Add changelogFile to manifest for pre-commit-checks
  jq '.projectConfig._base.changelogFile = "CHANGELOG.md"' "$TEST_DIR/.claude/manifest.json" > "$TEST_DIR/.claude/manifest.json.tmp"
  mv "$TEST_DIR/.claude/manifest.json.tmp" "$TEST_DIR/.claude/manifest.json"

  # Copy hooks and rules into the project (simulates init.sh)
  mkdir -p "$TEST_DIR/.claude/framework/hooks" "$TEST_DIR/.claude/framework/rules"
  cp "$HOOK_DIR"/*.sh "$TEST_DIR/.claude/framework/hooks/"
  chmod +x "$TEST_DIR/.claude/framework/hooks/"*.sh

  # --- Phase 1: Session Start ---
  SESSION_OUTPUT=$(cd "$TEST_DIR" && bash "$HOOK_DIR/session-start.sh" 2>&1)
  assert_contains "$SESSION_OUTPUT" "CLAUDE DEV FRAMEWORK" "session-start should show banner"
  assert_contains "$SESSION_OUTPUT" "WORKFLOW ENFORCEMENT" "session-start should show workflow enforcement"

  # Verify session start marker was created
  assert_file_exists "/tmp/.claude_session_start_${TEST_HASH}" "session start marker should exist"

  # --- Phase 2: Enforce Evaluate Block (no marker) ---
  COMMIT_INPUT='{"tool_input":{"command":"git commit -m \"Add feature\""}}'
  EVAL_RESULT=$(run_hook "$HOOK_DIR/enforce-evaluate.sh" "$COMMIT_INPUT")
  assert_contains "$EVAL_RESULT" "BLOCKED" "enforce-evaluate should block without marker"

  # --- Phase 3: Create Marker, Retry ---
  touch "/tmp/.claude_evaluated_${TEST_HASH}"
  EVAL_RESULT2=$(run_hook "$HOOK_DIR/enforce-evaluate.sh" "$COMMIT_INPUT")
  assert_equals "" "$EVAL_RESULT2" "enforce-evaluate should pass with marker"

  # --- Phase 4: Enforce Superpowers Block (no marker) ---
  WRITE_INPUT='{"tool_input":{"file_path":"app.kt"}}'
  SP_RESULT=$(run_hook "$HOOK_DIR/enforce-superpowers.sh" "$WRITE_INPUT")
  assert_contains "$SP_RESULT" "BLOCKED" "enforce-superpowers should block without marker"

  touch "/tmp/.claude_superpowers_${TEST_HASH}"
  SP_RESULT2=$(run_hook "$HOOK_DIR/enforce-superpowers.sh" "$WRITE_INPUT")
  assert_equals "" "$SP_RESULT2" "enforce-superpowers should pass with marker"

  # --- Phase 5: Pre-commit Checks (source + changelog staged) ---
  echo "// feature code" > "$TEST_DIR/app.kt"
  echo "- Added feature" > "$TEST_DIR/CHANGELOG.md"
  git -C "$TEST_DIR" add app.kt CHANGELOG.md

  PRECOMMIT_EXIT=$(run_hook_exit_code "$HOOK_DIR/pre-commit-checks.sh" "$COMMIT_INPUT")
  assert_exit_code "0" "$PRECOMMIT_EXIT" "pre-commit should pass with source + changelog"

  # Actually commit
  git -C "$TEST_DIR" commit -m "Add feature" --quiet

  # --- Phase 6: Sync-tracker clears markers after commit ---
  POST_COMMIT='{"tool_input":{"command":"git commit -m \"Add feature\""},"tool_response":{"exit_code":"0"}}'
  run_hook "$HOOK_DIR/sync-tracker.sh" "$POST_COMMIT" >/dev/null
  assert_file_not_exists "/tmp/.claude_evaluated_${TEST_HASH}" "eval marker should be cleared after commit"
  assert_file_not_exists "/tmp/.claude_superpowers_${TEST_HASH}" "superpowers marker should be cleared after commit"

  # --- Phase 7: Stop Checklist (clean state) ---
  STOP_INPUT='{"stop_reason":"assistant"}'
  STOP_RESULT=$(run_hook "$HOOK_DIR/stop-checklist.sh" "$STOP_INPUT")
  STOP_EXIT=$(run_hook_exit_code "$HOOK_DIR/stop-checklist.sh" "$STOP_INPUT")
  assert_exit_code "0" "$STOP_EXIT" "stop should pass with clean state"
  assert_not_contains "$STOP_RESULT" "block" "stop should not block on clean state"

  teardown_test_project
}

# --- Run ---
echo "integration-workflow (end-to-end)"
test_full_session_lifecycle
run_tests
