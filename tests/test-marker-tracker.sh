#!/usr/bin/env bash
# test-marker-tracker.sh — Tests for unified marker-tracker PostToolUse hook
# Consolidates: test-skill-tracker-v4, test-plan-tracker, test-context7-tracker,
#               test-sync-tracker-v4, test-marker-persistence
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/marker-tracker.sh"
FIXTURE_BASH="$SCRIPT_DIR/fixtures/posttooluse-bash.json"

# =============================================
# Skill tracking (was skill-tracker.sh)
# =============================================

# --- Test: writing-plans creates has_plan marker ---
test_writing_plans_creates_has_plan() {
  setup_test_project
  INPUT='{"tool_name":"Skill","tool_input":{"skill":"superpowers:writing-plans"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_has_plan_${TEST_HASH}" "writing-plans should create has_plan marker"
  assert_file_exists "/tmp/.claude_superpowers_${TEST_HASH}" "writing-plans should also create superpowers marker"
  teardown_test_project
}

# --- Test: writing-plans (non-namespaced) creates has_plan marker ---
test_writing_plans_short_creates_has_plan() {
  setup_test_project
  INPUT='{"tool_name":"Skill","tool_input":{"skill":"writing-plans"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_has_plan_${TEST_HASH}" "writing-plans (short) should create has_plan marker"
  teardown_test_project
}

# --- Test: brainstorming does NOT create has_plan marker ---
test_brainstorming_no_has_plan() {
  setup_test_project
  INPUT='{"tool_name":"Skill","tool_input":{"skill":"superpowers:brainstorming"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_not_exists "/tmp/.claude_has_plan_${TEST_HASH}" "brainstorming should NOT create has_plan marker"
  assert_file_exists "/tmp/.claude_superpowers_${TEST_HASH}" "brainstorming should create superpowers marker"
  teardown_test_project
}

# =============================================
# Plan tracking (was plan-tracker.sh)
# =============================================

# --- Test: TaskUpdate in_progress creates plan_active marker ---
test_task_in_progress_creates_marker() {
  setup_test_project
  INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"in_progress"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_plan_active_${TEST_HASH}" "in_progress should create plan_active marker"
  teardown_test_project
}

# --- Test: TaskUpdate completed clears plan_active marker ---
test_task_completed_clears_marker() {
  setup_test_project
  touch "/tmp/.claude_plan_active_${TEST_HASH}"
  INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_not_exists "/tmp/.claude_plan_active_${TEST_HASH}" "completed should clear plan_active marker"
  teardown_test_project
}

# --- Test: TaskUpdate pending does nothing ---
test_task_pending_no_change() {
  setup_test_project
  INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"pending"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_not_exists "/tmp/.claude_plan_active_${TEST_HASH}" "pending should not create plan_active marker"
  teardown_test_project
}

# --- Test: non-TaskUpdate does not affect plan_active ---
test_non_task_update_no_plan_marker() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"echo hello"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_not_exists "/tmp/.claude_plan_active_${TEST_HASH}" "non-TaskUpdate should not create plan_active marker"
  teardown_test_project
}

# --- Test: TaskUpdate without status does nothing ---
test_task_update_no_status() {
  setup_test_project
  INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","subject":"New name"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_not_exists "/tmp/.claude_plan_active_${TEST_HASH}" "TaskUpdate without status should not create marker"
  teardown_test_project
}

# =============================================
# Context7 tracking (was context7-tracker.sh)
# =============================================

# --- Test: creates marker on resolve-library-id call ---
test_creates_marker_on_resolve() {
  setup_test_project
  INPUT='{"tool_name":"mcp__context7__resolve-library-id","tool_input":{"libraryName":"react"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_c7_${TEST_HASH}_react" "should create c7 marker for react"
  teardown_test_project
}

# --- Test: creates marker on get-library-docs call ---
test_creates_marker_on_get_docs() {
  setup_test_project
  INPUT='{"tool_name":"mcp__context7__get-library-docs","tool_input":{"context7CompatibleLibraryID":"/facebook/react","topic":"hooks"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_c7_${TEST_HASH}_facebook-react" "should create c7 marker for facebook/react"
  teardown_test_project
}

# --- Test: normalizes scoped package names ---
test_normalizes_scoped_names() {
  setup_test_project
  INPUT='{"tool_name":"mcp__context7__resolve-library-id","tool_input":{"libraryName":"@anthropic-ai/sdk"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_c7_${TEST_HASH}_anthropic-ai-sdk" "should normalize scoped name"
  teardown_test_project
}

# --- Test: creates marker on plugin-prefixed resolve-library-id call ---
test_creates_marker_on_plugin_resolve() {
  setup_test_project
  INPUT='{"tool_name":"mcp__plugin_context7_context7__resolve-library-id","tool_input":{"libraryName":"express"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_c7_${TEST_HASH}_express" "plugin-prefixed resolve should create c7 marker"
  teardown_test_project
}

# --- Test: creates marker on plugin-prefixed get-library-docs call ---
test_creates_marker_on_plugin_get_docs() {
  setup_test_project
  INPUT='{"tool_name":"mcp__plugin_context7_context7__get-library-docs","tool_input":{"context7CompatibleLibraryID":"/expressjs/express","topic":"routing"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_c7_${TEST_HASH}_expressjs-express" "plugin-prefixed get-docs should create c7 marker"
  teardown_test_project
}

# --- Test: creates marker on query-docs call ---
test_creates_marker_on_query_docs() {
  setup_test_project
  INPUT='{"tool_name":"mcp__context7__query-docs","tool_input":{"context7CompatibleLibraryID":"/facebook/react","topic":"hooks"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_c7_${TEST_HASH}_facebook-react" "query-docs should create c7 marker"
  teardown_test_project
}

# --- Test: query-docs with libraryId credits both full id and last segment ---
test_query_docs_libraryId_credits_both() {
  setup_test_project
  INPUT='{"tool_name":"mcp__context7__query-docs","tool_input":{"libraryId":"/vercel/next.js","query":"routing"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_c7_${TEST_HASH}_vercel-next.js" "query-docs libraryId creates full-id marker"
  assert_file_exists "/tmp/.claude_c7_${TEST_HASH}_next.js" "query-docs libraryId credits last path segment"
  teardown_test_project
}

# --- Test: ignores non-Context7 tools for c7 markers ---
test_ignores_other_tools_for_c7() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"echo hello"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  local count
  count=$(ls /tmp/.claude_c7_${TEST_HASH}_* 2>/dev/null | wc -l | xargs)
  assert_equals "0" "$count" "should not create c7 markers for non-Context7 tools"
  teardown_test_project
}

# --- Test: ignores Skill tool for c7 markers ---
test_ignores_skill_tool_for_c7() {
  setup_test_project
  INPUT='{"tool_name":"Skill","tool_input":{"skill":"superpowers:brainstorming"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  local count
  count=$(ls /tmp/.claude_c7_${TEST_HASH}_* 2>/dev/null | wc -l | xargs)
  assert_equals "0" "$count" "should not create c7 markers for Skill tool"
  teardown_test_project
}

# =============================================
# Sync tracking + post-commit reset (HEAD-movement based)
# =============================================

# --- Test: successful commit (HEAD moved) clears markers and updates last_head ---
test_successful_commit_clears_markers() {
  setup_test_project
  git -C "$TEST_DIR" rev-parse HEAD > "/tmp/.claude_last_head_${TEST_HASH}"
  touch "/tmp/.claude_evaluated_${TEST_HASH}"
  touch "/tmp/.claude_superpowers_${TEST_HASH}"
  touch "/tmp/.claude_plan_active_${TEST_HASH}"
  # Make a real commit so HEAD moves
  echo x >> "$TEST_DIR/README.md"
  git -C "$TEST_DIR" add .
  git -C "$TEST_DIR" commit -m "x" --quiet
  NEW_HEAD=$(git -C "$TEST_DIR" rev-parse HEAD)
  INPUT=$(jq -c --arg cmd "git commit -m x" '.tool_input.command=$cmd' "$FIXTURE_BASH")
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_not_exists "/tmp/.claude_evaluated_${TEST_HASH}" "successful commit clears evaluated marker"
  assert_file_not_exists "/tmp/.claude_superpowers_${TEST_HASH}" "successful commit clears superpowers marker"
  assert_file_not_exists "/tmp/.claude_plan_active_${TEST_HASH}" "successful commit clears plan_active marker"
  assert_equals "$NEW_HEAD" "$(cat /tmp/.claude_last_head_${TEST_HASH})" "last_head updated to new HEAD"
  rm -f "/tmp/.claude_last_head_${TEST_HASH}"
  teardown_test_project
}

# --- Test: failed commit (HEAD unchanged) keeps markers ---
test_failed_commit_keeps_markers() {
  setup_test_project
  git -C "$TEST_DIR" rev-parse HEAD > "/tmp/.claude_last_head_${TEST_HASH}"
  touch "/tmp/.claude_evaluated_${TEST_HASH}"
  touch "/tmp/.claude_superpowers_${TEST_HASH}"
  touch "/tmp/.claude_plan_active_${TEST_HASH}"
  # Do NOT commit — HEAD is unchanged from last_head
  INPUT=$(jq -c --arg cmd "git commit -m x" '.tool_input.command=$cmd' "$FIXTURE_BASH")
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_evaluated_${TEST_HASH}" "failed commit keeps evaluated marker"
  assert_file_exists "/tmp/.claude_superpowers_${TEST_HASH}" "failed commit keeps superpowers marker"
  assert_file_exists "/tmp/.claude_plan_active_${TEST_HASH}" "failed commit keeps plan_active marker"
  rm -f "/tmp/.claude_last_head_${TEST_HASH}"
  teardown_test_project
}

# --- Test: markers survive non-commit commands ---
test_markers_survive_non_commit() {
  setup_test_project
  git -C "$TEST_DIR" rev-parse HEAD > "/tmp/.claude_last_head_${TEST_HASH}"
  touch "/tmp/.claude_evaluated_${TEST_HASH}"
  touch "/tmp/.claude_superpowers_${TEST_HASH}"
  STATUS_INPUT=$(jq -c --arg cmd "git status" '.tool_input.command=$cmd' "$FIXTURE_BASH")
  run_hook "$HOOK" "$STATUS_INPUT" >/dev/null
  assert_file_exists "/tmp/.claude_evaluated_${TEST_HASH}" "evaluated marker should survive non-commit"
  assert_file_exists "/tmp/.claude_superpowers_${TEST_HASH}" "superpowers marker should survive non-commit"
  rm -f "/tmp/.claude_last_head_${TEST_HASH}"
  teardown_test_project
}

# --- Test: chained commit still clears markers when HEAD moved ---
test_chained_commit_clears_markers() {
  setup_test_project
  git -C "$TEST_DIR" rev-parse HEAD > "/tmp/.claude_last_head_${TEST_HASH}"
  touch "/tmp/.claude_evaluated_${TEST_HASH}"
  touch "/tmp/.claude_superpowers_${TEST_HASH}"
  echo x >> "$TEST_DIR/README.md"
  git -C "$TEST_DIR" add .
  git -C "$TEST_DIR" commit -m "x" --quiet
  INPUT=$(jq -c --arg cmd "cd . && git commit -m x" '.tool_input.command=$cmd' "$FIXTURE_BASH")
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_not_exists "/tmp/.claude_evaluated_${TEST_HASH}" "chained commit should clear evaluated marker"
  assert_file_not_exists "/tmp/.claude_superpowers_${TEST_HASH}" "chained commit should clear superpowers marker"
  rm -f "/tmp/.claude_last_head_${TEST_HASH}"
  teardown_test_project
}

# --- Test: interrupted sync does NOT create changelog_synced marker ---
test_sync_marker_created_when_not_interrupted() {
  setup_test_project
  INPUT=$(jq -c --arg cmd "bash sync-changelog.sh" '.tool_input.command=$cmd' "$FIXTURE_BASH")
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_changelog_synced_${TEST_HASH}" "completed sync should create changelog_synced marker"
  teardown_test_project
}

# =============================================
# Run all tests
# =============================================
echo "marker-tracker.sh (unified)"

# Skill tracking
test_writing_plans_creates_has_plan
test_writing_plans_short_creates_has_plan
test_brainstorming_no_has_plan

# Plan tracking
test_task_in_progress_creates_marker
test_task_completed_clears_marker
test_task_pending_no_change
test_non_task_update_no_plan_marker
test_task_update_no_status

# Context7 tracking
test_creates_marker_on_resolve
test_creates_marker_on_get_docs
test_creates_marker_on_plugin_resolve
test_creates_marker_on_plugin_get_docs
test_creates_marker_on_query_docs
test_query_docs_libraryId_credits_both
test_normalizes_scoped_names
test_ignores_other_tools_for_c7
test_ignores_skill_tool_for_c7

# Sync tracking + post-commit reset (HEAD-movement based)
test_successful_commit_clears_markers
test_failed_commit_keeps_markers
test_markers_survive_non_commit
test_chained_commit_clears_markers
test_sync_marker_created_when_not_interrupted

run_tests
