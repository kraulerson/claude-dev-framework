#!/usr/bin/env bash
# test-stop-checklist.sh — Tests for stop-checklist hook
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/stop-checklist.sh"
# Real Stop input (see tests/fixtures/stop.json): stop_hook_active=false, no reason field.
STOP_INPUT=$(jq -c . "$SCRIPT_DIR/fixtures/stop.json")
# Loop-guard input: stop_hook_active=true means a prior block this turn.
ACTIVE_INPUT='{"hook_event_name":"Stop","stop_hook_active":true}'

# The shared setup leaves .claude/ untracked; the R-10 `git status --porcelain`
# check would report it as uncommitted source. A real installed project tracks
# .claude/, so commit it here to establish a genuine clean baseline.
setup_stop_test() {
  setup_test_project
  git -C "$TEST_DIR" add .claude
  git -C "$TEST_DIR" commit -m "chore: track .claude manifest" --quiet
}

# --- Test: stop_hook_active=true short-circuits (loop guard) ---
test_stop_hook_active_short_circuits() {
  setup_stop_test
  # Dirty tree that would otherwise block.
  echo "// dirty" > "$TEST_DIR/app.kt"
  git -C "$TEST_DIR" add app.kt

  RESULT=$(run_hook "$HOOK" "$ACTIVE_INPUT")
  EXIT=$(run_hook_exit_code "$HOOK" "$ACTIVE_INPUT")
  assert_exit_code "0" "$EXIT" "stop_hook_active=true should exit 0"
  assert_equals "" "$RESULT" "stop_hook_active=true should produce empty output"
  teardown_test_project
}

# --- Test: clean state passes ---
test_clean_state_passes() {
  setup_stop_test
  commit_source_file "app.kt" "Add app"

  RESULT=$(run_hook "$HOOK" "$STOP_INPUT")
  EXIT=$(run_hook_exit_code "$HOOK" "$STOP_INPUT")
  assert_exit_code "0" "$EXIT" "clean state should exit 0"
  assert_not_contains "$RESULT" "block" "clean state should produce no block output"
  teardown_test_project
}

# --- Test: uncommitted source file blocks ---
test_uncommitted_source_blocks() {
  setup_stop_test
  echo "// new code" > "$TEST_DIR/feature.kt"
  git -C "$TEST_DIR" add feature.kt

  RESULT=$(run_hook "$HOOK" "$STOP_INPUT")
  assert_contains "$RESULT" "Uncommitted source" "should warn about uncommitted source files"
  teardown_test_project
}

# --- Test: untracked source file (never git-added) blocks (R-10) ---
# git status --porcelain reports untracked files as "??"; the old git-diff-only
# construction missed them entirely. An untracked .py must now be detected.
test_untracked_source_blocks() {
  setup_stop_test
  echo "x = 1" > "$TEST_DIR/new.py"   # never `git add`

  RESULT=$(run_hook "$HOOK" "$STOP_INPUT")
  assert_contains "$RESULT" "Uncommitted source" "untracked source file should block"
  teardown_test_project
}

# --- Test: untracked path containing a space still detected (quote stripping) (R-10) ---
# git status --porcelain quotes paths with spaces; the sed pipeline strips the
# surrounding quotes so the path is still recognized as source.
test_untracked_path_with_space_detected() {
  setup_stop_test
  echo "x = 1" > "$TEST_DIR/my file.py"   # never `git add`; path has a space

  RESULT=$(run_hook "$HOOK" "$STOP_INPUT")
  assert_contains "$RESULT" "Uncommitted source" "untracked path with a space should block"
  teardown_test_project
}

# --- Test: end-of-session advisory is emitted as Stop additionalContext (R-14) ---
# Clean tree with commits but no superpowers marker → advisory JSON, not stderr.
test_advisory_emitted_as_additional_context() {
  setup_stop_test
  git -C "$TEST_DIR" rev-parse HEAD > "/tmp/.claude_session_start_${TEST_HASH}"
  commit_source_file "app.kt" "Add app feature"

  RESULT=$(run_hook "$HOOK" "$STOP_INPUT")
  EXIT=$(run_hook_exit_code "$HOOK" "$STOP_INPUT")
  assert_exit_code "0" "$EXIT" "advisory path should exit 0"
  assert_not_contains "$RESULT" "block" "advisory path should not block"
  assert_contains "$RESULT" '"hookEventName": "Stop"' "advisory should carry Stop hookEventName"
  assert_contains "$RESULT" "additionalContext" "advisory should be delivered as additionalContext"
  assert_contains "$RESULT" "Design Zone" "advisory content should include the design-zone note"
  teardown_test_project
}

# --- Test: multi-commit bug fix detection (REGRESSION for Bug #1) ---
# This test verifies that a bug fix commit is caught even when
# followed by a non-fix commit. Before the fix, only git log -1
# was checked, so the fix commit was invisible.
test_multi_commit_bugfix_detection() {
  setup_stop_test

  # Record session start (simulates what session-start.sh does)
  git -C "$TEST_DIR" rev-parse HEAD > "/tmp/.claude_session_start_${TEST_HASH}"

  # Commit 1: bug fix without test
  commit_source_file "login.kt" "Fix login crash on empty password"

  # Commit 2: clean refactor (no fix keywords)
  commit_source_file "utils.kt" "Refactor string utilities"

  RESULT=$(run_hook "$HOOK" "$STOP_INPUT")
  assert_contains "$RESULT" "bug fix" "should detect untested bug fix in earlier commit"
  assert_contains "$RESULT" "regression test" "should mention missing regression test"
  teardown_test_project
}

# --- Test: bug fix WITH test passes ---
test_bugfix_with_test_passes() {
  setup_stop_test

  git -C "$TEST_DIR" rev-parse HEAD > "/tmp/.claude_session_start_${TEST_HASH}"

  # Bug fix commit that includes a test file
  commit_source_with_test "login.kt" "LoginTest.kt" "Fix login crash on empty password"

  RESULT=$(run_hook "$HOOK" "$STOP_INPUT")
  assert_not_contains "$RESULT" "bug fix" "fix with test should not warn"
  teardown_test_project
}

# --- Test: merge commit with "fix" in subject should NOT flag (REGRESSION for Bug: merge false-positive) ---
# git log --name-only emits no files for merge commits by default, so a merge
# subject like "Merge branch 'fix/...'" used to falsely register as an untested fix.
test_merge_commit_with_fix_subject_not_flagged() {
  setup_stop_test

  git -C "$TEST_DIR" rev-parse HEAD > "/tmp/.claude_session_start_${TEST_HASH}"

  # Create a side branch, make a commit there (with a test, so it's clean),
  # then merge back with --no-ff to force a real merge commit whose default
  # subject is "Merge branch 'fix/...'".
  git -C "$TEST_DIR" checkout -b fix/ci-failures --quiet
  commit_source_with_test "ci.kt" "CITest.kt" "Fix CI timeout"
  git -C "$TEST_DIR" checkout main --quiet 2>/dev/null || git -C "$TEST_DIR" checkout master --quiet
  git -C "$TEST_DIR" merge --no-ff fix/ci-failures --quiet -m "Merge branch 'fix/ci-failures'"

  RESULT=$(run_hook "$HOOK" "$STOP_INPUT")
  assert_not_contains "$RESULT" "bug fix" "merge commit with fix-named branch should not flag untested fix"
  teardown_test_project
}

# --- Test: config-only fix commit should NOT flag (REGRESSION for Bug: asymmetric source check) ---
# A "fix:" commit touching only .yml/.md has no source files changed, so it
# cannot carry a code-level regression test — it must not be flagged.
test_config_only_fix_not_flagged() {
  setup_stop_test

  git -C "$TEST_DIR" rev-parse HEAD > "/tmp/.claude_session_start_${TEST_HASH}"

  mkdir -p "$TEST_DIR/.github/workflows"
  echo "name: ci" > "$TEST_DIR/.github/workflows/ci.yml"
  git -C "$TEST_DIR" add .github/workflows/ci.yml
  git -C "$TEST_DIR" commit -m "fix: CI initial failures" --quiet

  RESULT=$(run_hook "$HOOK" "$STOP_INPUT")
  assert_not_contains "$RESULT" "bug fix" "config-only fix commit should not flag untested fix"
  teardown_test_project
}

# Closure is recorded through the sanctioned script, never by touching the marker.
mark_plan_closed() {
  (cd "$TEST_DIR" && bash "$HOOK_DIR/mark-plan-closed.sh" "planned vs actual matched" >/dev/null 2>&1) || true
}

# --- Test: the plan-closure advisory names the script that satisfies it ---
test_planning_advisory_names_the_script() {
  setup_stop_test
  git -C "$TEST_DIR" rev-parse HEAD > "/tmp/.claude_session_start_${TEST_HASH}"
  commit_source_file "app.kt" "Add app feature"

  RESULT=$(run_hook "$HOOK" "$STOP_INPUT")
  assert_contains "$RESULT" "Planning Zone" "advisory should ask for plan closure before marking"
  assert_contains "$RESULT" "mark-plan-closed.sh" "advisory should name the script to run"
  CONTEXT=$(echo "$RESULT" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null || echo "")
  assert_contains "$CONTEXT" 'then run: bash .claude/framework/hooks/mark-plan-closed.sh "one-line summary"' "advisory should render a runnable command"
  teardown_test_project
}

# --- Test: once closure is marked the plan-closure advisory is gone, the rest stays ---
test_planning_advisory_absent_after_marking() {
  setup_stop_test
  git -C "$TEST_DIR" rev-parse HEAD > "/tmp/.claude_session_start_${TEST_HASH}"
  commit_source_file "app.kt" "Add app feature"

  BEFORE=$(run_hook "$HOOK" "$STOP_INPUT")
  assert_contains "$BEFORE" "Planning Zone" "advisory present before marking"

  mark_plan_closed

  AFTER=$(run_hook "$HOOK" "$STOP_INPUT")
  EXIT=$(run_hook_exit_code "$HOOK" "$STOP_INPUT")
  assert_exit_code "0" "$EXIT" "stop should still exit 0 after marking"
  assert_not_contains "$AFTER" "Planning Zone" "advisory absent after marking"
  assert_contains "$AFTER" "Design Zone" "unrelated advisory is unaffected by marking"
  assert_contains "$AFTER" "Session produced 1 commit(s)" "commit count line stays while an advisory remains"
  teardown_test_project
}

# --- Test: with no advisory left the hook prints nothing at all ---
test_no_output_when_no_advisory_remains() {
  setup_stop_test
  git -C "$TEST_DIR" rev-parse HEAD > "/tmp/.claude_session_start_${TEST_HASH}"
  commit_source_file "app.kt" "Add app feature"
  touch "/tmp/.claude_superpowers_${TEST_HASH}"

  mark_plan_closed

  RESULT=$(run_hook "$HOOK" "$STOP_INPUT")
  EXIT=$(run_hook_exit_code "$HOOK" "$STOP_INPUT")
  assert_exit_code "0" "$EXIT" "no remaining advisory should exit 0"
  assert_equals "" "$RESULT" "no remaining advisory should print nothing, commit count included"
  teardown_test_project
}

# --- Test: the handoff advisory and its commit count survive closure ---
test_handoff_advisory_survives_closure() {
  setup_stop_test
  jq '.projectConfig._base.contextHistoryFile = "HISTORY.md"' "$TEST_DIR/.claude/manifest.json" > "$TEST_DIR/.claude/manifest.json.tmp"
  mv "$TEST_DIR/.claude/manifest.json.tmp" "$TEST_DIR/.claude/manifest.json"
  git -C "$TEST_DIR" add .claude
  git -C "$TEST_DIR" commit -m "chore: configure context history" --quiet
  git -C "$TEST_DIR" rev-parse HEAD > "/tmp/.claude_session_start_${TEST_HASH}"
  commit_source_file "app.kt" "Add app feature"
  touch "/tmp/.claude_superpowers_${TEST_HASH}"

  mark_plan_closed

  RESULT=$(run_hook "$HOOK" "$STOP_INPUT")
  assert_not_contains "$RESULT" "Planning Zone" "closure advisory absent after marking"
  assert_contains "$RESULT" "Discovery Zone" "handoff advisory still delivered"
  assert_contains "$RESULT" "Session produced 1 commit(s)" "commit count line still delivered with the handoff advisory"
  teardown_test_project
}

# --- Run all tests ---
echo "stop-checklist.sh"
test_stop_hook_active_short_circuits
test_clean_state_passes
test_uncommitted_source_blocks
test_untracked_source_blocks
test_untracked_path_with_space_detected
test_advisory_emitted_as_additional_context
test_multi_commit_bugfix_detection
test_bugfix_with_test_passes
test_merge_commit_with_fix_subject_not_flagged
test_config_only_fix_not_flagged
test_planning_advisory_names_the_script
test_planning_advisory_absent_after_marking
test_no_output_when_no_advisory_remains
test_handoff_advisory_survives_closure
run_tests
