#!/usr/bin/env bash
# test-skill-tracker-v4.sh — Tests for v4 additions to skill-tracker
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/skill-tracker.sh"

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

# --- Run all tests ---
echo "skill-tracker.sh (v4 plan markers)"
test_writing_plans_creates_has_plan
test_writing_plans_short_creates_has_plan
test_brainstorming_no_has_plan
run_tests
