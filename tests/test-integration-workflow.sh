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

  # --- Phase 3: Approval round trip (approval design B, spec test 12) ---
  # Stage the change, record the question, stop, then the user answers A1 twice.
  echo "// feature code" > "$TEST_DIR/app.kt"
  echo "- Added feature" > "$TEST_DIR/CHANGELOG.md"
  git -C "$TEST_DIR" add app.kt CHANGELOG.md
  cat > "$TEST_DIR/.claude/pending-approval.json" << 'JSON'
{"schema": 2, "question": "Commit the feature?", "options": [{"id": "A1", "text": "Commit app.kt and the changelog", "approves": "commit"}, {"id": "A2", "text": "Hold", "approves": "none"}], "recommendation": "A1", "offered_at": "2026-10-05T12:00:00Z"}
JSON
  STOP_OUT=$(run_hook "$HOOK_DIR/stop-checklist.sh" "$(jq -c . "$SCRIPT_DIR/fixtures/stop.json")")
  assert_not_contains "$STOP_OUT" '"decision"' "the agent may stop while the question is pending"
  assert_contains "$STOP_OUT" "Commit the feature?" "the stop hook shows the pending question"
  UPS=$(jq -c --arg d "$TEST_DIR" '.prompt = "A1" | .session_id = "s1" | .cwd = $d' "$SCRIPT_DIR/fixtures/userpromptsubmit.json")
  RENDER=$(run_hook "$HOOK_DIR/record-approval.sh" "$UPS")
  assert_equals "block" "$(jq -r .decision <<< "$RENDER")" "the first A1 shows the question and the staged change"
  assert_contains "$(jq -r .reason <<< "$RENDER")" "app.kt" "the render lists the staged change"
  EVAL_MID=$(run_hook_exit_code "$HOOK_DIR/enforce-evaluate.sh" "$COMMIT_INPUT")
  assert_exit_code "2" "$EVAL_MID" "rendering alone approves nothing"
  run_hook "$HOOK_DIR/record-approval.sh" "$UPS" >/dev/null
  assert_file_exists "/tmp/.claude_evaluated_${TEST_HASH}" "the confirming A1 creates the approval"
  EVAL_RESULT2=$(run_hook "$HOOK_DIR/enforce-evaluate.sh" "$COMMIT_INPUT")
  assert_equals "" "$EVAL_RESULT2" "enforce-evaluate should pass with the approval"
  EVAL_A=$(run_hook_exit_code "$HOOK_DIR/enforce-evaluate.sh" '{"tool_input":{"command":"git commit -am \"Add feature\""}}')
  assert_exit_code "2" "$EVAL_A" "the approval does not cover git commit -a"

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

  # --- Phase 6: Marker-tracker clears markers after commit ---
  # Real PostToolUse Bash input has no exit_code field; marker-tracker detects a
  # successful commit via HEAD movement (the real commit happened just above).
  POST_COMMIT='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"Add feature\""},"tool_response":{"stdout":"","stderr":"","interrupted":false}}'
  run_hook "$HOOK_DIR/marker-tracker.sh" "$POST_COMMIT" >/dev/null
  assert_file_not_exists "/tmp/.claude_evaluated_${TEST_HASH}" "eval marker should be cleared after commit"
  assert_equals "true" "$(tail -n 1 "$TEST_DIR/.claude/approvals.jsonl" | jq -r .matched)" "the committed tree is the approved one"
  assert_file_not_exists "/tmp/.claude_superpowers_${TEST_HASH}" "superpowers marker should be cleared after commit"

  # Commit the .claude framework files so the tree is genuinely clean for Phase 7.
  # A real installed project tracks .claude/; the R-10 `git status --porcelain`
  # check (correctly) reports the copied-in hook files as untracked source
  # otherwise. Mirrors setup_stop_test in tests/test-stop-checklist.sh.
  git -C "$TEST_DIR" add .claude
  git -C "$TEST_DIR" commit -m "chore: track .claude framework" --quiet

  # --- Phase 7: Stop Checklist (clean state) ---
  # Real Stop input: stop_hook_active loop guard, no stop_reason field.
  STOP_INPUT='{"hook_event_name":"Stop","stop_hook_active":false}'
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
  run_hook "$HOOK_DIR/marker-tracker.sh" "$INPUT_SKILL" >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_superpowers_${TEST_HASH}" "v4: brainstorming should create superpowers marker"

  # 3. Simulate writing-plans skill -> has_plan marker
  INPUT_PLAN='{"tool_name":"Skill","tool_input":{"skill":"superpowers:writing-plans"}}'
  run_hook "$HOOK_DIR/marker-tracker.sh" "$INPUT_PLAN" >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_has_plan_${TEST_HASH}" "v4: writing-plans should create has_plan marker"

  # 4. Source edit should be blocked by Planning Zone (has_plan but no plan_active)
  EXIT_CODE=$(run_hook_exit_code "$HOOK_DIR/enforce-plan-tracking.sh" "$INPUT_EDIT")
  assert_exit_code "2" "$EXIT_CODE" "v4: should block without plan_active"

  # 5. Simulate TaskUpdate to in_progress -> plan_active marker
  INPUT_TASK='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"in_progress"}}'
  run_hook "$HOOK_DIR/marker-tracker.sh" "$INPUT_TASK" >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_plan_active_${TEST_HASH}" "v4: TaskUpdate should create plan_active marker"

  # 6. Source edit should now pass both gates
  EXIT_CODE=$(run_hook_exit_code "$HOOK_DIR/enforce-superpowers.sh" "$INPUT_EDIT")
  assert_exit_code "0" "$EXIT_CODE" "v4: should pass superpowers with marker"
  EXIT_CODE=$(run_hook_exit_code "$HOOK_DIR/enforce-plan-tracking.sh" "$INPUT_EDIT")
  assert_exit_code "0" "$EXIT_CODE" "v4: should pass plan-tracking with marker"

  # 7. Simulate commit -> markers cleared (HEAD-movement detection; no exit_code field)
  INPUT_COMMIT='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"feat: test\""},"tool_response":{"stdout":"","stderr":"","interrupted":false}}'
  echo "# code" > "$TEST_DIR/app.py"
  git -C "$TEST_DIR" add app.py
  git -C "$TEST_DIR" commit -m "feat: test" --quiet
  run_hook "$HOOK_DIR/marker-tracker.sh" "$INPUT_COMMIT" >/dev/null 2>&1
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
