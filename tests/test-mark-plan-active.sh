#!/usr/bin/env bash
# test-mark-plan-active.sh — Tests for the sanctioned active-plan-task marker script (#38)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

SCRIPT="$HOOK_DIR/mark-plan-active.sh"

# Run the script from the project root, the way Claude invokes it.
run_script() {
  (cd "$TEST_DIR" && bash "$SCRIPT" "$@" 2>&1)
}

run_script_exit_code() {
  (cd "$TEST_DIR" && bash "$SCRIPT" "$@" >/dev/null 2>&1; echo $?)
}

marker_path() {
  echo "/tmp/.claude_plan_active_${TEST_HASH}"
}

# A written plan arms the Planning Zone (marker-tracker.sh, on writing-plans).
arm_plan() {
  touch "/tmp/.claude_has_plan_${TEST_HASH}"
}

# --- Test: with a written plan, a one-line task creates the marker ---
test_task_creates_marker() {
  setup_test_project
  arm_plan
  EXIT_CODE=$(run_script_exit_code "Task 2: parse the config file")
  assert_exit_code "0" "$EXIT_CODE" "task should exit 0"
  assert_file_exists "$(marker_path)" "task should create the plan_active marker"
  teardown_test_project
}

# --- Test: without a written plan there is nothing to activate ---
test_refuses_without_plan() {
  setup_test_project
  RESULT=$(run_script "Task 2: parse the config file")
  EXIT_CODE=$(run_script_exit_code "Task 2: parse the config file")
  assert_exit_code "1" "$EXIT_CODE" "no has_plan marker should exit 1"
  assert_contains "$RESULT" "ERROR: No written plan" "refusal should say there is no plan to activate"
  assert_file_not_exists "$(marker_path)" "no has_plan marker must not create the marker"
  teardown_test_project
}

# --- Test: prints exactly one confirmation line ---
test_prints_one_confirmation_line() {
  setup_test_project
  arm_plan
  RESULT=$(run_script "Task 2: parse the config file")
  LINE_COUNT=$(printf '%s\n' "$RESULT" | wc -l | xargs)
  assert_equals "1" "$LINE_COUNT" "should print exactly one line"
  assert_contains "$RESULT" "Active plan task marker created" "should confirm marker creation"
  assert_contains "$RESULT" "Task 2: parse the config file" "confirmation should echo the task"
  teardown_test_project
}

# --- Test: the record is 'timestamp | task', one line per call, appended ---
test_marker_appends_task_record() {
  setup_test_project
  arm_plan
  run_script "Task 2: parse the config file" >/dev/null
  run_script "Task 2: parse the config file, resumed" >/dev/null
  STAMPED=$(grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2} \| Task 2: parse the config file$' "$(marker_path)" 2>/dev/null || echo 0)
  assert_equals "1" "$STAMPED" "marker record should be 'timestamp | task'"
  LINES=$(wc -l < "$(marker_path)" | xargs)
  assert_equals "2" "$LINES" "a second call should append a line, not replace the first"
  teardown_test_project
}

# --- Test: no argument is refused and makes no marker ---
test_no_argument_refused() {
  setup_test_project
  arm_plan
  RESULT=$(run_script)
  EXIT_CODE=$(run_script_exit_code)
  assert_exit_code "1" "$EXIT_CODE" "no argument should exit 1"
  assert_contains "$RESULT" "ERROR" "no argument should explain the refusal"
  assert_file_not_exists "$(marker_path)" "no argument must not create the marker"
  teardown_test_project
}

# --- Test: empty and whitespace-only tasks are refused and make no marker ---
test_blank_task_refused() {
  setup_test_project
  arm_plan
  EXIT_CODE=$(run_script_exit_code "")
  assert_exit_code "1" "$EXIT_CODE" "empty task should exit 1"
  EXIT_CODE=$(run_script_exit_code "   ")
  assert_exit_code "1" "$EXIT_CODE" "spaces-only task should exit 1"
  EXIT_CODE=$(run_script_exit_code "$(printf '\t \t')")
  assert_exit_code "1" "$EXIT_CODE" "tabs-only task should exit 1"
  assert_file_not_exists "$(marker_path)" "a blank task must not create the marker"
  teardown_test_project
}

# --- Test: a multi-line task is refused (the record is one line) ---
test_multiline_task_refused() {
  setup_test_project
  arm_plan
  EXIT_CODE=$(run_script_exit_code "$(printf 'line one\nline two')")
  assert_exit_code "1" "$EXIT_CODE" "multi-line task should exit 1"
  assert_file_not_exists "$(marker_path)" "multi-line task must not create the marker"
  teardown_test_project
}

# --- Test: an unquoted task (extra arguments) is refused, not truncated ---
test_extra_arguments_refused() {
  setup_test_project
  arm_plan
  EXIT_CODE=$(run_script_exit_code Task 2 parse)
  assert_exit_code "1" "$EXIT_CODE" "extra arguments should exit 1"
  assert_file_not_exists "$(marker_path)" "extra arguments must not create the marker"
  teardown_test_project
}

# --- Test: the usage text says the task is plain text ---
test_usage_says_plain_text() {
  setup_test_project
  arm_plan
  RESULT=$(run_script)
  assert_contains "$RESULT" "(plain text, no shell punctuation)" "usage should say the task is plain text"
  teardown_test_project
}

# --- Test: a refusal goes to stderr, with nothing on stdout ---
test_refusal_goes_to_stderr() {
  setup_test_project
  arm_plan
  STDOUT=$(cd "$TEST_DIR" && bash "$SCRIPT" "" 2>/dev/null)
  STDERR=$(cd "$TEST_DIR" && bash "$SCRIPT" "" 2>&1 >/dev/null)
  assert_equals "" "$STDOUT" "refusal should print nothing on stdout"
  assert_contains "$STDERR" "ERROR: The task is empty" "refusal should be on stderr"
  teardown_test_project
}

# --- Test: quotes, dollar signs, backticks and printf directives in the task are inert ---
test_task_metacharacters_inert() {
  setup_test_project
  arm_plan
  local task found
  task="task \"q\" 'q' \$(touch $TEST_DIR/pwned1) \`touch $TEST_DIR/pwned2\` \$HOME 100%s \\n"
  RESULT=$(run_script "$task")
  assert_file_not_exists "$TEST_DIR/pwned1" "command substitution in the task must not run"
  assert_file_not_exists "$TEST_DIR/pwned2" "backticks in the task must not run"
  found=no
  case "$RESULT" in *'$HOME 100%s'*) found=yes ;; esac
  assert_equals "yes" "$found" "dollar-variable and directives should be echoed literally"
  RECORDED=$(grep -cF "| $task" "$(marker_path)" 2>/dev/null || echo 0)
  assert_equals "1" "$RECORDED" "marker should record the task verbatim"
  teardown_test_project
}

# --- Test: the markers are keyed by the shared project hash, not the cwd ---
test_marker_uses_project_hash() {
  setup_test_project
  arm_plan
  local other_dir other_hash
  other_dir=$(mktemp -d)
  other_hash=$(echo -n "$other_dir" | shasum -a 256 | cut -c1-12)
  (cd "$other_dir" && bash "$SCRIPT" "Task 2 from elsewhere" >/dev/null 2>&1)
  assert_file_exists "$(marker_path)" "marker should be keyed by CLAUDE_PROJECT_DIR"
  assert_file_not_exists "/tmp/.claude_plan_active_${other_hash}" "marker must not be keyed by the cwd"
  rm -f "/tmp/.claude_plan_active_${other_hash}"
  rm -rf "$other_dir"
  teardown_test_project
}

# --- Test: Planning Zone passes after the script runs, and blocks again after a commit
# (the mark covers one task; the next needs a fresh one) ---
test_unlocks_planning_zone_until_commit() {
  setup_test_project
  arm_plan
  local edit='{"tool_input":{"file_path":"app.py"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK_DIR/enforce-plan-tracking.sh" "$edit")
  assert_exit_code "2" "$EXIT_CODE" "source edit blocks before the task is marked"
  run_script "Task 2: parse the config file" >/dev/null
  EXIT_CODE=$(run_hook_exit_code "$HOOK_DIR/enforce-plan-tracking.sh" "$edit")
  assert_exit_code "0" "$EXIT_CODE" "source edit passes once the script marked the task"
  echo "# code" > "$TEST_DIR/app.py"
  git -C "$TEST_DIR" add app.py
  git -C "$TEST_DIR" commit -m "feat: task 2" --quiet
  run_hook "$HOOK_DIR/marker-tracker.sh" '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"feat: task 2\""},"tool_response":{"stdout":"","stderr":"","interrupted":false}}' >/dev/null 2>&1
  assert_file_not_exists "$(marker_path)" "a commit clears the mark"
  EXIT_CODE=$(run_hook_exit_code "$HOOK_DIR/enforce-plan-tracking.sh" "$edit")
  assert_exit_code "2" "$EXIT_CODE" "the next task's edit blocks until it is marked"
  rm -f "/tmp/.claude_last_head_${TEST_HASH}"
  teardown_test_project
}

# --- Run all tests ---
echo "mark-plan-active.sh"
test_task_creates_marker
test_refuses_without_plan
test_prints_one_confirmation_line
test_marker_appends_task_record
test_no_argument_refused
test_blank_task_refused
test_multiline_task_refused
test_extra_arguments_refused
test_usage_says_plain_text
test_refusal_goes_to_stderr
test_task_metacharacters_inert
test_marker_uses_project_hash
test_unlocks_planning_zone_until_commit
run_tests
