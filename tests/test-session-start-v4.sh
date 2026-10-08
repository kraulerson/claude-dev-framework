#!/usr/bin/env bash
# test-session-start-v4.sh — Tests for rewritten session-start hook
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/session-start.sh"

# --- Test: output contains compliance directive ---
test_has_directive() {
  setup_test_project
  RESULT=$(run_hook "$HOOK" '{"source":"startup"}')
  assert_contains "$RESULT" "FRAMEWORK COMPLIANCE DIRECTIVE" "should contain directive"
  teardown_test_project
}

# --- Test: output contains ZONES ARMED section ---
test_has_zones() {
  setup_test_project
  RESULT=$(run_hook "$HOOK" '{"source":"startup"}')
  assert_contains "$RESULT" "ZONES ARMED" "should contain zones section"
  assert_contains "$RESULT" "Discovery" "should list Discovery zone"
  assert_contains "$RESULT" "Design" "should list Design zone"
  assert_contains "$RESULT" "Planning" "should list Planning zone"
  assert_contains "$RESULT" "Implementation" "should list Implementation zone"
  assert_contains "$RESULT" "Verification" "should list Verification zone"
  teardown_test_project
}

# --- Test: output does NOT contain old ACTIVE RULES section ---
test_no_rules_listing() {
  setup_test_project
  RESULT=$(run_hook "$HOOK" '{"source":"startup"}')
  assert_not_contains "$RESULT" "ACTIVE RULES" "should not list individual rules"
  teardown_test_project
}

# --- Test: output contains profile/branch/rules summary line ---
test_summary_line() {
  setup_test_project
  RESULT=$(run_hook "$HOOK" '{"source":"startup"}')
  assert_contains "$RESULT" "Profile:" "should contain Profile"
  assert_contains "$RESULT" "Branch:" "should contain Branch"
  assert_contains "$RESULT" "Rules:" "should contain Rules count"
  teardown_test_project
}

# --- Test: output does NOT contain old banner format ---
test_no_old_banner() {
  setup_test_project
  RESULT=$(run_hook "$HOOK" '{"source":"startup"}')
  assert_not_contains "$RESULT" "=== CLAUDE DEV FRAMEWORK" "should not have old banner"
  assert_not_contains "$RESULT" "WORKFLOW ENFORCEMENT" "should not have old workflow section"
  teardown_test_project
}

# --- Test: exit code is always 0 ---
test_exit_zero() {
  setup_test_project
  EXIT_CODE=$(run_hook_exit_code "$HOOK" '{"source":"startup"}')
  assert_exit_code "0" "$EXIT_CODE" "should always exit 0"
  teardown_test_project
}

# --- Test: existing output assertions still pass with empty stdin (manual run) ---
test_empty_stdin_still_outputs() {
  setup_test_project
  RESULT=$(run_hook "$HOOK" "")
  assert_contains "$RESULT" "FRAMEWORK COMPLIANCE DIRECTIVE" "empty stdin treated as startup"
  assert_contains "$RESULT" "ZONES ARMED" "empty stdin still emits zones"
  teardown_test_project
}

# --- Test: startup clears pre-seeded workflow markers (R-06) ---
test_startup_clears_markers() {
  setup_test_project
  touch "/tmp/.claude_superpowers_${TEST_HASH}"
  touch "/tmp/.claude_evaluated_${TEST_HASH}"
  touch "/tmp/.claude_c7_${TEST_HASH}_react"
  touch "/tmp/.claude_approval_shown_${TEST_HASH}"
  run_hook "$HOOK" '{"source":"startup"}' >/dev/null 2>&1
  assert_file_not_exists "/tmp/.claude_approval_shown_${TEST_HASH}" "startup clears the approval render record"
  assert_file_not_exists "/tmp/.claude_superpowers_${TEST_HASH}" "startup clears superpowers"
  assert_file_not_exists "/tmp/.claude_evaluated_${TEST_HASH}" "startup clears evaluated"
  assert_file_not_exists "/tmp/.claude_c7_${TEST_HASH}_react" "startup clears c7 markers"
  rm -f "/tmp/.claude_last_head_${TEST_HASH}"
  teardown_test_project
}

# --- Test: resume does NOT clear markers or overwrite session_start (R-20) ---
test_resume_preserves_markers() {
  setup_test_project
  touch "/tmp/.claude_superpowers_${TEST_HASH}"
  touch "/tmp/.claude_evaluated_${TEST_HASH}"
  echo "SEEDED_HEAD_VALUE" > "/tmp/.claude_session_start_${TEST_HASH}"
  touch "/tmp/.claude_approval_shown_${TEST_HASH}"
  run_hook "$HOOK" '{"source":"resume"}' >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_approval_shown_${TEST_HASH}" "resume keeps the approval render record (headless --resume)"
  assert_file_exists "/tmp/.claude_superpowers_${TEST_HASH}" "resume preserves superpowers"
  assert_file_exists "/tmp/.claude_evaluated_${TEST_HASH}" "resume preserves evaluated"
  SS=$(cat "/tmp/.claude_session_start_${TEST_HASH}" 2>/dev/null || echo "")
  assert_equals "SEEDED_HEAD_VALUE" "$SS" "resume does not overwrite existing session_start"
  rm -f "/tmp/.claude_last_head_${TEST_HASH}"
  teardown_test_project
}

# --- Test: compact source emits post-compaction recovery message (R-05) ---
test_compact_recovery_message() {
  setup_test_project
  RESULT=$(run_hook "$HOOK" '{"source":"compact"}')
  assert_contains "$RESULT" "POST-COMPACTION RECOVERY" "compact emits recovery guidance"
  rm -f "/tmp/.claude_last_head_${TEST_HASH}"
  teardown_test_project
}

# --- Test: startup writes both session_start and last_head files ---
test_startup_writes_head_markers() {
  setup_test_project
  run_hook "$HOOK" '{"source":"startup"}' >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_session_start_${TEST_HASH}" "startup writes session_start"
  assert_file_exists "/tmp/.claude_last_head_${TEST_HASH}" "startup writes last_head"
  EXPECTED=$(git -C "$TEST_DIR" rev-parse HEAD)
  ACTUAL=$(cat "/tmp/.claude_last_head_${TEST_HASH}" 2>/dev/null || echo "")
  assert_equals "$EXPECTED" "$ACTUAL" "last_head equals current HEAD"
  rm -f "/tmp/.claude_last_head_${TEST_HASH}"
  teardown_test_project
}

# The plan-closed marker follows the same lifecycle as the other workflow
# markers. It is created through the sanctioned script so the precondition
# (marker exists) proves the clear/preserve assertion is not vacuous.
mark_plan_closed() {
  (cd "$TEST_DIR" && bash "$HOOK_DIR/mark-plan-closed.sh" "closure documented" >/dev/null 2>&1) || true
}

# --- Test: startup clears the plan-closed marker ---
test_startup_clears_plan_closed() {
  setup_test_project
  mark_plan_closed
  assert_file_exists "/tmp/.claude_plan_closed_${TEST_HASH}" "precondition: marker exists before startup"
  run_hook "$HOOK" '{"source":"startup"}' >/dev/null 2>&1
  assert_file_not_exists "/tmp/.claude_plan_closed_${TEST_HASH}" "startup clears plan_closed"
  rm -f "/tmp/.claude_last_head_${TEST_HASH}"
  teardown_test_project
}

# --- Test: clear (a fresh source) clears the plan-closed marker ---
test_clear_clears_plan_closed() {
  setup_test_project
  mark_plan_closed
  assert_file_exists "/tmp/.claude_plan_closed_${TEST_HASH}" "precondition: marker exists before clear"
  run_hook "$HOOK" '{"source":"clear"}' >/dev/null 2>&1
  assert_file_not_exists "/tmp/.claude_plan_closed_${TEST_HASH}" "clear clears plan_closed"
  rm -f "/tmp/.claude_last_head_${TEST_HASH}"
  teardown_test_project
}

# --- Test: resume preserves the plan-closed marker ---
test_resume_preserves_plan_closed() {
  setup_test_project
  mark_plan_closed
  run_hook "$HOOK" '{"source":"resume"}' >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_plan_closed_${TEST_HASH}" "resume preserves plan_closed"
  rm -f "/tmp/.claude_last_head_${TEST_HASH}"
  teardown_test_project
}

# --- Test: compact preserves the plan-closed marker ---
test_compact_preserves_plan_closed() {
  setup_test_project
  mark_plan_closed
  run_hook "$HOOK" '{"source":"compact"}' >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_plan_closed_${TEST_HASH}" "compact preserves plan_closed"
  rm -f "/tmp/.claude_last_head_${TEST_HASH}"
  teardown_test_project
}

# --- Test: the directive points at the sanctioned scripts, not "automatic" ---
test_directive_names_sanctioned_scripts() {
  setup_test_project
  RESULT=$(run_hook "$HOOK" '{"source":"startup"}')
  assert_contains "$RESULT" "mark-plan-closed.sh" "directive should name mark-plan-closed.sh"
  assert_contains "$RESULT" "pending-approval.json" "directive should name the approval route"
  assert_not_contains "$RESULT" "mark-evaluated.sh" "the directive no longer offers mark-evaluated.sh to the agent"
  assert_not_contains "$RESULT" "Markers are created automatically" "directive must not claim every marker is automatic"
  assert_contains "$RESULT" "never create one yourself" "directive should forbid creating a marker"
  assert_contains "$RESULT" 'a lone `git commit -m' "directive states the lone-commit rule (dogfood-3 row 14a)"
  assert_contains "$RESULT" "no cd" "directive says a cd prefix breaks it"
  rm -f "/tmp/.claude_last_head_${TEST_HASH}"
  teardown_test_project
}

# --- Run all tests ---
# --- Test (dogfood-2 row 27): the Superpowers status reads the settings this session
# uses — $CLAUDE_CONFIG_DIR when set — and the warning gives the install command ---
test_superpowers_status_follows_config_dir() {
  local cfg
  setup_test_project
  cfg=$(mktemp -d)
  mkdir -p "$HOME/.claude"
  echo '{"enabledPlugins":{"superpowers@claude-plugins-official":true}}' > "$HOME/.claude/settings.json"
  export CLAUDE_CONFIG_DIR="$cfg"
  RESULT=$(run_hook "$HOOK" '{"source":"startup"}')
  assert_contains "$RESULT" "Superpowers MISSING" "~/.claude does not count when CLAUDE_CONFIG_DIR points elsewhere"
  assert_contains "$RESULT" "claude plugin install --scope user superpowers@claude-plugins-official" "the warning gives the install command"
  echo '{"enabledPlugins":{"superpowers@claude-plugins-official":true}}' > "$cfg/settings.json"
  RESULT=$(run_hook "$HOOK" '{"source":"startup"}')
  assert_contains "$RESULT" "Superpowers verified" "enabled under CLAUDE_CONFIG_DIR is verified"
  unset CLAUDE_CONFIG_DIR
  rm -rf "$cfg" "$HOME/.claude/settings.json"
  teardown_test_project
}

# --- Test (dogfood-3 row 21): the Context7 status is read where this session's settings
# live — $CLAUDE_CONFIG_DIR when set (its settings.json and its .claude.json, where
# `claude mcp add -s user` writes) — not ~/.claude ---
test_context7_status_follows_config_dir() {
  local cfg
  setup_test_project
  cfg=$(mktemp -d)
  echo '{"mcpServers":{"context7":{"type":"http"}}}' > "$HOME/.claude.json"
  export CLAUDE_CONFIG_DIR="$cfg"
  RESULT=$(run_hook "$HOOK" '{"source":"startup"}')
  assert_contains "$RESULT" "Context7 not installed" "~/.claude.json does not count when CLAUDE_CONFIG_DIR points elsewhere"
  echo '{"mcpServers":{"context7":{"type":"http"}}}' > "$cfg/.claude.json"
  RESULT=$(run_hook "$HOOK" '{"source":"startup"}')
  assert_contains "$RESULT" "Context7 ready" "registered in CLAUDE_CONFIG_DIR/.claude.json is ready"
  unset CLAUDE_CONFIG_DIR
  rm -rf "$cfg" "$HOME/.claude.json"
  teardown_test_project
}

# --- Test (dogfood-3 row 22): an overdue discovery review says to run init.sh
# --reconfigure only in a project init.sh made. In a Solo-adopted project (manifest
# adoption.adopted) init.sh --reconfigure would rewrite the whole manifest, dropping
# Solo's adoption record and the project's sourceExtensions, so it is not suggested ---
test_discovery_review_not_for_adopted() {
  setup_test_project
  jq '.discovery = {lastReviewDate: "2026-01-01"}' "$TEST_DIR/.claude/manifest.json" > "$TEST_DIR/m" && mv "$TEST_DIR/m" "$TEST_DIR/.claude/manifest.json"
  RESULT=$(run_hook "$HOOK" '{"source":"startup"}')
  assert_contains "$RESULT" "init.sh --reconfigure" "an init.sh project is told to review"
  jq '.adoption = {schemaVersion: 2, adopted: true}' "$TEST_DIR/.claude/manifest.json" > "$TEST_DIR/m" && mv "$TEST_DIR/m" "$TEST_DIR/.claude/manifest.json"
  RESULT=$(run_hook "$HOOK" '{"source":"startup"}')
  assert_not_contains "$RESULT" "init.sh --reconfigure" "an adopted project is not sent to init.sh"
  assert_not_contains "$RESULT" "Discovery review overdue" "an adopted project gets no discovery-review warning"
  teardown_test_project
}

# --- #30: every source prints the time near the top, so a resumed or compacted
# session knows today. 1789663560 is Thu 17 Sep 2026 16:46 UTC. ---
test_now_line_every_source() {
  local src out zones now_at
  setup_test_project
  for src in startup resume clear compact; do
    out=$(CDF_NOW=1789663560 TZ=UTC run_hook "$HOOK" "{\"source\":\"$src\"}")
    assert_equals "Now: Thu 17 Sep 2026, 16:46 UTC." "$(echo "$out" | grep '^Now: ')" "$src prints the Now line"
    now_at=$(echo "$out" | grep -n '^Now: ' | cut -d: -f1)
    zones=$(echo "$out" | grep -n '^ZONES ARMED' | cut -d: -f1)
    assert_equals "yes" "$([ -n "$now_at" ] && [ "$now_at" -lt "$zones" ] && echo yes || echo no)" "$src prints it above ZONES ARMED"
  done
  rm -f "/tmp/.claude_last_head_${TEST_HASH}"
  teardown_test_project
}

test_directive_says_use_now() {
  setup_test_project
  RESULT=$(run_hook "$HOOK" '{"source":"startup"}')
  assert_contains "$RESULT" 'Before you write a relative day (today, tomorrow, next week) or judge a deadline, use the latest `Now:` line, not memory.' \
    "directive tells the agent to use the Now line"
  rm -f "/tmp/.claude_last_head_${TEST_HASH}"
  teardown_test_project
}

# A failing date prints no time rather than a wrong one; the rest is unchanged.
# Both reads fail: the clock (no CDF_NOW) and the formatting (CDF_NOW pinned).
test_broken_date_omits_now() {
  local shim out code pin
  setup_test_project
  shim=$(mktemp -d)
  printf '#!/bin/bash\nexit 1\n' > "$shim/date"
  chmod +x "$shim/date"
  for pin in "" 1789663560; do
    out=$(CDF_NOW="$pin" PATH="$shim:$PATH" run_hook "$HOOK" '{"source":"compact"}')
    code=$(CDF_NOW="$pin" PATH="$shim:$PATH" run_hook_exit_code "$HOOK" '{"source":"compact"}')
    assert_equals "0" "$code" "exits 0 when date fails (CDF_NOW='$pin')"
    assert_not_contains "$out" "^Now:" "no Now line when date fails (CDF_NOW='$pin')"
    assert_contains "$out" "ZONES ARMED" "zones still printed when date fails (CDF_NOW='$pin')"
    assert_contains "$out" "POST-COMPACTION RECOVERY" "compact recovery still printed when date fails (CDF_NOW='$pin')"
  done
  rm -rf "$shim" "/tmp/.claude_last_head_${TEST_HASH}"
  teardown_test_project
}

# --- A hook newer than its _helpers.sh (a sync left half done) has no cdf_now_line:
# the directive, the zones and the compact recovery still print ---
test_old_helpers_still_print_frame() {
  local skew out code
  setup_test_project
  skew=$(mktemp -d)
  cp "$HOOK_DIR"/*.sh "$skew/"
  printf '\nunset -f cdf_now_line\n' >> "$skew/_helpers.sh"
  out=$(CDF_NOW=1789663560 run_hook "$skew/session-start.sh" '{"source":"compact"}')
  code=$(CDF_NOW=1789663560 run_hook_exit_code "$skew/session-start.sh" '{"source":"compact"}')
  assert_equals "0" "$code" "exits 0 with an old _helpers.sh"
  assert_contains "$out" "FRAMEWORK COMPLIANCE DIRECTIVE" "directive printed with an old _helpers.sh"
  assert_contains "$out" "ZONES ARMED" "zones printed with an old _helpers.sh"
  assert_contains "$out" "POST-COMPACTION RECOVERY" "compact recovery printed with an old _helpers.sh"
  assert_not_contains "$out" "^Now:" "no Now line with an old _helpers.sh"
  rm -rf "$skew" "/tmp/.claude_last_head_${TEST_HASH}"
  teardown_test_project
}

echo "session-start.sh (v4 rewrite)"
test_has_directive
test_has_zones
test_no_rules_listing
test_summary_line
test_no_old_banner
test_exit_zero
test_empty_stdin_still_outputs
test_startup_clears_markers
test_resume_preserves_markers
test_compact_recovery_message
test_startup_writes_head_markers
test_startup_clears_plan_closed
test_clear_clears_plan_closed
test_resume_preserves_plan_closed
test_compact_preserves_plan_closed
test_directive_names_sanctioned_scripts
test_superpowers_status_follows_config_dir
test_context7_status_follows_config_dir
test_discovery_review_not_for_adopted
test_now_line_every_source
test_directive_says_use_now
test_broken_date_omits_now
test_old_helpers_still_print_frame
run_tests
