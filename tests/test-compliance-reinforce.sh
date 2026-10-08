#!/usr/bin/env bash
# test-compliance-reinforce.sh — Tests for the compliance-reinforce UserPromptSubmit hook
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/compliance-reinforce.sh"

echo "compliance-reinforce"

# --- exit code is 0 (advisory) ---
test_exit_zero() {
  setup_test_project
  CODE=$(run_hook_exit_code "$HOOK" '{}')
  assert_equals "0" "$CODE" "compliance-reinforce: exits 0 on empty input"
  teardown_test_project
}

# --- stdout is valid JSON with the correct hookEventName ---
test_json_output() {
  setup_test_project
  OUTPUT=$(run_hook "$HOOK" '{}')

  # Valid JSON
  echo "$OUTPUT" | jq -e '.' >/dev/null 2>&1
  assert_equals "0" "$?" "compliance-reinforce: stdout parses as JSON"

  EVENT=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null || echo "")
  assert_equals "UserPromptSubmit" "$EVENT" "compliance-reinforce: hookEventName is UserPromptSubmit"

  CTX=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null || echo "")
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -n "$CTX" ] && [ "$CTX" != "null" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILURES="${FAILURES}  FAIL: compliance-reinforce: additionalContext is non-empty\n    got: '${CTX}'\n"
  fi

  teardown_test_project
}

# --- #30: the time leads the line, so a resumed or compacted session knows today ---
# CDF_NOW pins the clock (epoch seconds); 1789663560 is Thu 17 Sep 2026 16:46 UTC.
REMINDER="FRAMEWORK REMINDER: Enforcement hooks are active. Follow blocked-hook instructions exactly; never bypass, forge markers, or classify work as trivial to skip the workflow."
reinforce_ctx() {
  run_hook "$HOOK" '{}' | jq -r '.hookSpecificOutput.additionalContext'
}

test_now_leads_the_line() {
  setup_test_project
  OUTPUT=$(CDF_NOW=1789663560 TZ=UTC run_hook "$HOOK" '{}')
  echo "$OUTPUT" | jq -e '.' >/dev/null 2>&1
  assert_equals "0" "$?" "compliance-reinforce: stdout with the time parses as JSON"
  CTX=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.additionalContext')
  assert_equals "Now: Thu 17 Sep 2026, 16:46 UTC. $REMINDER" "$CTX" "compliance-reinforce: the Now line leads the reminder"
  assert_equals "1" "$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.additionalContext' | wc -l | tr -d ' ')" \
    "compliance-reinforce: the context stays one line"
  teardown_test_project
}

# Local time, in English whatever the user's locale.
test_now_is_local_and_english() {
  setup_test_project
  CTX=$(CDF_NOW=1789663560 TZ=BST-1 reinforce_ctx)
  assert_equals "Now: Thu 17 Sep 2026, 17:46 BST. $REMINDER" "$CTX" "compliance-reinforce: the time is local (TZ)"
  CTX=$(CDF_NOW=1789663560 TZ=UTC LC_ALL=fr_FR.UTF-8 reinforce_ctx)
  assert_equals "Now: Thu 17 Sep 2026, 16:46 UTC. $REMINDER" "$CTX" "compliance-reinforce: day and month names are English under another locale"
  teardown_test_project
}

# Without the override the real clock is read.
test_now_reads_the_clock() {
  setup_test_project
  CTX=$(reinforce_ctx)
  TESTS_RUN=$((TESTS_RUN + 1))
  if echo "$CTX" | grep -Eq '^Now: [A-Z][a-z]{2} [0-9]{2} [A-Z][a-z]{2} [0-9]{4}, [0-9]{2}:[0-9]{2} [^ ]+\. FRAMEWORK REMINDER:'; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILURES="${FAILURES}  FAIL: compliance-reinforce: without CDF_NOW the clock is read\n    got: '${CTX}'\n"
  fi
  teardown_test_project
}

# A failing date prints no time rather than a wrong one; the reminder still goes out.
# Both reads fail: the clock (no CDF_NOW) and the formatting (CDF_NOW pinned).
test_broken_date_omits_now() {
  local shim pin
  setup_test_project
  shim=$(mktemp -d)
  printf '#!/bin/bash\nexit 1\n' > "$shim/date"
  chmod +x "$shim/date"
  for pin in "" 1789663560; do
    OUTPUT=$(CDF_NOW="$pin" PATH="$shim:$PATH" run_hook "$HOOK" '{}')
    CODE=$(CDF_NOW="$pin" PATH="$shim:$PATH" run_hook_exit_code "$HOOK" '{}')
    assert_equals "0" "$CODE" "compliance-reinforce: exits 0 when date fails (CDF_NOW='$pin')"
    echo "$OUTPUT" | jq -e '.' >/dev/null 2>&1
    assert_equals "0" "$?" "compliance-reinforce: stdout parses as JSON when date fails (CDF_NOW='$pin')"
    assert_equals "$REMINDER" "$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.additionalContext')" \
      "compliance-reinforce: no Now line when date fails, the reminder unchanged (CDF_NOW='$pin')"
  done
  rm -rf "$shim"
  teardown_test_project
}

# A CDF_NOW that is not all digits prints no time: BSD date reads the leading digits of
# "123abc" (and "garbage" as 0) instead of failing, which would give a wrong date.
test_bad_cdf_now_omits_now() {
  local pin
  setup_test_project
  for pin in garbage 123abc -1; do
    OUTPUT=$(CDF_NOW="$pin" run_hook "$HOOK" '{}')
    CODE=$(CDF_NOW="$pin" run_hook_exit_code "$HOOK" '{}')
    assert_equals "0" "$CODE" "compliance-reinforce: exits 0 with CDF_NOW='$pin'"
    echo "$OUTPUT" | jq -e '.' >/dev/null 2>&1
    assert_equals "0" "$?" "compliance-reinforce: stdout parses as JSON with CDF_NOW='$pin'"
    assert_equals "$REMINDER" "$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)" \
      "compliance-reinforce: no Now line with CDF_NOW='$pin', the reminder unchanged"
  done
  teardown_test_project
}

# --- A hook newer than its _helpers.sh (a sync left half done) has no cdf_now_line:
# the reminder still goes out, without the time ---
test_old_helpers_still_remind() {
  local skew
  setup_test_project
  skew=$(mktemp -d)
  cp "$HOOK_DIR"/*.sh "$skew/"
  printf '\nunset -f cdf_now_line\n' >> "$skew/_helpers.sh"
  OUTPUT=$(CDF_NOW=1789663560 run_hook "$skew/compliance-reinforce.sh" '{}')
  CODE=$(CDF_NOW=1789663560 run_hook_exit_code "$skew/compliance-reinforce.sh" '{}')
  assert_equals "0" "$CODE" "compliance-reinforce: exits 0 with an old _helpers.sh"
  echo "$OUTPUT" | jq -e '.' >/dev/null 2>&1
  assert_equals "0" "$?" "compliance-reinforce: stdout parses as JSON with an old _helpers.sh"
  assert_equals "$REMINDER" "$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)" \
    "compliance-reinforce: the reminder unchanged, no Now line, with an old _helpers.sh"
  rm -rf "$skew"
  teardown_test_project
}

test_exit_zero
test_json_output
test_now_leads_the_line
test_now_is_local_and_english
test_now_reads_the_clock
test_broken_date_omits_now
test_bad_cdf_now_omits_now
test_old_helpers_still_remind
run_tests
