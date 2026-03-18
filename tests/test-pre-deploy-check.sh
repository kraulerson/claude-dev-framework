#!/usr/bin/env bash
# test-pre-deploy-check.sh — Tests for pre-deploy-check hook
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/pre-deploy-check.sh"

# --- Test: non-deploy command passes silently ---
test_non_deploy_passthrough() {
  setup_test_project
  INPUT='{"tool_input":{"command":"git status"}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  assert_equals "" "$RESULT" "non-deploy command should produce no output"
  teardown_test_project
}

# --- Test: deploy command with all commits pushed passes ---
test_deploy_pushed_passes() {
  setup_test_project
  setup_remote

  INPUT='{"tool_input":{"command":"docker compose up -d"}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  assert_equals "" "$RESULT" "deploy with all pushed should produce no output"
  teardown_test_project
}

# --- Test: deploy command with unpushed commits warns ---
test_deploy_unpushed_warns() {
  setup_test_project
  setup_remote
  commit_source_file "app.kt" "Add feature"

  INPUT='{"tool_input":{"command":"docker compose up -d"}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  assert_contains "$RESULT" "unpushed" "should warn about unpushed commits"
  assert_contains "$RESULT" "git push" "should suggest git push"
  teardown_test_project
}

# --- Test: deploy command with no upstream warns ---
test_deploy_no_upstream_warns() {
  setup_test_project

  INPUT='{"tool_input":{"command":"git pull origin main"}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  assert_contains "$RESULT" "no upstream" "should warn about missing upstream"
  teardown_test_project
}

# --- Test: git commit does NOT trigger deploy check ---
test_git_commit_not_deploy() {
  setup_test_project
  INPUT='{"tool_input":{"command":"git commit -m \"Add feature\""}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  assert_equals "" "$RESULT" "git commit should not trigger deploy check"
  teardown_test_project
}

# --- Run all tests ---
echo "pre-deploy-check.sh"
test_non_deploy_passthrough
test_deploy_pushed_passes
test_deploy_unpushed_warns
test_deploy_no_upstream_warns
test_git_commit_not_deploy
run_tests
