#!/usr/bin/env bash
# test-stop-checklist.sh — Tests for stop-checklist hook
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/stop-checklist.sh"
STOP_INPUT='{"stop_reason":"assistant"}'
USER_STOP_INPUT='{"stop_reason":"user"}'

# --- Test: user-initiated stop always passes ---
test_user_stop_always_passes() {
  setup_test_project
  echo "// dirty" > "$TEST_DIR/app.kt"
  git -C "$TEST_DIR" add app.kt

  RESULT=$(run_hook "$HOOK" "$USER_STOP_INPUT")
  EXIT=$(run_hook_exit_code "$HOOK" "$USER_STOP_INPUT")
  assert_exit_code "0" "$EXIT" "user stop should exit 0"
  assert_not_contains "$RESULT" "block" "user stop should produce no block output"
  teardown_test_project
}

# --- Test: clean state passes ---
test_clean_state_passes() {
  setup_test_project
  commit_source_file "app.kt" "Add app"

  RESULT=$(run_hook "$HOOK" "$STOP_INPUT")
  EXIT=$(run_hook_exit_code "$HOOK" "$STOP_INPUT")
  assert_exit_code "0" "$EXIT" "clean state should exit 0"
  assert_not_contains "$RESULT" "block" "clean state should produce no block output"
  teardown_test_project
}

# --- Test: uncommitted source file blocks ---
test_uncommitted_source_blocks() {
  setup_test_project
  echo "// new code" > "$TEST_DIR/feature.kt"
  git -C "$TEST_DIR" add feature.kt

  RESULT=$(run_hook "$HOOK" "$STOP_INPUT")
  assert_contains "$RESULT" "Uncommitted source" "should warn about uncommitted source files"
  teardown_test_project
}

# --- Test: multi-commit bug fix detection (REGRESSION for Bug #1) ---
# This test verifies that a bug fix commit is caught even when
# followed by a non-fix commit. Before the fix, only git log -1
# was checked, so the fix commit was invisible.
test_multi_commit_bugfix_detection() {
  setup_test_project

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
  setup_test_project

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
  setup_test_project

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
  setup_test_project

  git -C "$TEST_DIR" rev-parse HEAD > "/tmp/.claude_session_start_${TEST_HASH}"

  mkdir -p "$TEST_DIR/.github/workflows"
  echo "name: ci" > "$TEST_DIR/.github/workflows/ci.yml"
  git -C "$TEST_DIR" add .github/workflows/ci.yml
  git -C "$TEST_DIR" commit -m "fix: CI initial failures" --quiet

  RESULT=$(run_hook "$HOOK" "$STOP_INPUT")
  assert_not_contains "$RESULT" "bug fix" "config-only fix commit should not flag untested fix"
  teardown_test_project
}

# --- Run all tests ---
echo "stop-checklist.sh"
test_user_stop_always_passes
test_clean_state_passes
test_uncommitted_source_blocks
test_multi_commit_bugfix_detection
test_bugfix_with_test_passes
test_merge_commit_with_fix_subject_not_flagged
test_config_only_fix_not_flagged
run_tests
