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
  assert_contains "$SESSION_OUTPUT" "FRAMEWORK COMPLIANCE DIRECTIVE" "session-start should show directive"
  assert_contains "$SESSION_OUTPUT" "ZONES ARMED" "session-start should show zones"

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

# --- Test: v4 full lifecycle ---
# Design (superpowers) -> Plan (writing-plans + TaskUpdate) -> Edit -> Commit
test_v4_full_lifecycle() {
  setup_test_project

  # 1. Source edit should be blocked (no superpowers marker)
  INPUT_EDIT='{"tool_input":{"file_path":"app.py"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK_DIR/enforce-superpowers.sh" "$INPUT_EDIT")
  assert_exit_code "2" "$EXIT_CODE" "v4: should block without superpowers"

  # 2. Simulate brainstorming skill -> superpowers marker
  INPUT_SKILL='{"tool_name":"Skill","tool_input":{"skill":"superpowers:brainstorming"}}'
  run_hook "$HOOK_DIR/skill-tracker.sh" "$INPUT_SKILL" >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_superpowers_${TEST_HASH}" "v4: brainstorming should create superpowers marker"

  # 3. Simulate writing-plans skill -> has_plan marker
  INPUT_PLAN='{"tool_name":"Skill","tool_input":{"skill":"superpowers:writing-plans"}}'
  run_hook "$HOOK_DIR/skill-tracker.sh" "$INPUT_PLAN" >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_has_plan_${TEST_HASH}" "v4: writing-plans should create has_plan marker"

  # 4. Source edit should be blocked by Planning Zone (has_plan but no plan_active)
  EXIT_CODE=$(run_hook_exit_code "$HOOK_DIR/enforce-plan-tracking.sh" "$INPUT_EDIT")
  assert_exit_code "2" "$EXIT_CODE" "v4: should block without plan_active"

  # 5. Simulate TaskUpdate to in_progress -> plan_active marker
  INPUT_TASK='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"in_progress"}}'
  run_hook "$HOOK_DIR/plan-tracker.sh" "$INPUT_TASK" >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_plan_active_${TEST_HASH}" "v4: TaskUpdate should create plan_active marker"

  # 6. Source edit should now pass both gates
  EXIT_CODE=$(run_hook_exit_code "$HOOK_DIR/enforce-superpowers.sh" "$INPUT_EDIT")
  assert_exit_code "0" "$EXIT_CODE" "v4: should pass superpowers with marker"
  EXIT_CODE=$(run_hook_exit_code "$HOOK_DIR/enforce-plan-tracking.sh" "$INPUT_EDIT")
  assert_exit_code "0" "$EXIT_CODE" "v4: should pass plan-tracking with marker"

  # 7. Simulate commit -> markers cleared
  INPUT_COMMIT='{"tool_input":{"command":"git commit -m \"feat: test\""},"tool_response":{"exit_code":"0"}}'
  echo "# code" > "$TEST_DIR/app.py"
  git -C "$TEST_DIR" add app.py
  git -C "$TEST_DIR" commit -m "feat: test" --quiet
  run_hook "$HOOK_DIR/sync-tracker.sh" "$INPUT_COMMIT" >/dev/null 2>&1
  assert_file_not_exists "/tmp/.claude_superpowers_${TEST_HASH}" "v4: commit should clear superpowers marker"
  assert_file_not_exists "/tmp/.claude_plan_active_${TEST_HASH}" "v4: commit should clear plan_active marker"
  assert_file_exists "/tmp/.claude_has_plan_${TEST_HASH}" "v4: commit should NOT clear has_plan marker"

  teardown_test_project
}

# --- Run ---
echo "integration-workflow (end-to-end)"
test_full_session_lifecycle
test_v4_full_lifecycle
run_tests
