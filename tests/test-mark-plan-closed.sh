#!/usr/bin/env bash
# test-mark-plan-closed.sh — Tests for the sanctioned plan-closure marker script
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

SCRIPT="$HOOK_DIR/mark-plan-closed.sh"

# Run the script from the project root, the way Claude invokes it.
run_script() {
  (cd "$TEST_DIR" && bash "$SCRIPT" "$@" 2>&1)
}

run_script_exit_code() {
  (cd "$TEST_DIR" && bash "$SCRIPT" "$@" >/dev/null 2>&1; echo $?)
}

marker_path() {
  echo "/tmp/.claude_plan_closed_${TEST_HASH}"
}

# --- Test: a one-line summary creates the marker ---
test_summary_creates_marker() {
  setup_test_project
  EXIT_CODE=$(run_script_exit_code "planned vs actual matched, nothing deferred")
  assert_exit_code "0" "$EXIT_CODE" "summary should exit 0"
  assert_file_exists "$(marker_path)" "summary should create the plan-closed marker"
  teardown_test_project
}

# --- Test: prints exactly one confirmation line ---
test_prints_one_confirmation_line() {
  setup_test_project
  RESULT=$(run_script "planned vs actual matched")
  LINE_COUNT=$(printf '%s\n' "$RESULT" | wc -l | xargs)
  assert_equals "1" "$LINE_COUNT" "should print exactly one line"
  assert_contains "$RESULT" "Plan closure marker created" "should confirm marker creation"
  assert_contains "$RESULT" "planned vs actual matched" "confirmation should echo the summary"
  teardown_test_project
}

# --- Test: the marker records the summary ---
test_marker_records_summary() {
  setup_test_project
  run_script "dropped task 4, deferred the cache work" >/dev/null
  RECORDED=$(grep -cF "dropped task 4, deferred the cache work" "$(marker_path)" 2>/dev/null || echo 0)
  assert_equals "1" "$RECORDED" "marker should record the summary"
  teardown_test_project
}

# --- Test: no argument is refused and makes no marker ---
test_no_argument_refused() {
  setup_test_project
  RESULT=$(run_script)
  EXIT_CODE=$(run_script_exit_code)
  assert_exit_code "1" "$EXIT_CODE" "no argument should exit 1"
  assert_contains "$RESULT" "ERROR" "no argument should explain the refusal"
  assert_file_not_exists "$(marker_path)" "no argument must not create the marker"
  teardown_test_project
}

# --- Test: empty summary is refused and makes no marker ---
test_empty_summary_refused() {
  setup_test_project
  EXIT_CODE=$(run_script_exit_code "")
  assert_exit_code "1" "$EXIT_CODE" "empty summary should exit 1"
  assert_file_not_exists "$(marker_path)" "empty summary must not create the marker"
  teardown_test_project
}

# --- Test: whitespace-only summary is refused and makes no marker ---
test_whitespace_summary_refused() {
  setup_test_project
  EXIT_CODE=$(run_script_exit_code "   ")
  assert_exit_code "1" "$EXIT_CODE" "spaces-only summary should exit 1"
  assert_file_not_exists "$(marker_path)" "spaces-only summary must not create the marker"
  EXIT_CODE=$(run_script_exit_code "$(printf '\t \t')")
  assert_exit_code "1" "$EXIT_CODE" "tabs-only summary should exit 1"
  assert_file_not_exists "$(marker_path)" "tabs-only summary must not create the marker"
  teardown_test_project
}

# --- Test: a multi-line summary is refused (the record is one line) ---
test_multiline_summary_refused() {
  setup_test_project
  EXIT_CODE=$(run_script_exit_code "$(printf 'line one\nline two')")
  assert_exit_code "1" "$EXIT_CODE" "multi-line summary should exit 1"
  assert_file_not_exists "$(marker_path)" "multi-line summary must not create the marker"
  teardown_test_project
}

# --- Test: an unquoted summary (extra arguments) is refused, not truncated ---
test_extra_arguments_refused() {
  setup_test_project
  EXIT_CODE=$(run_script_exit_code planned work done)
  assert_exit_code "1" "$EXIT_CODE" "extra arguments should exit 1"
  assert_file_not_exists "$(marker_path)" "extra arguments must not create the marker"
  teardown_test_project
}

# --- Test: --note with an existing, non-empty closure note creates the marker ---
test_note_path_creates_marker() {
  setup_test_project
  printf 'Planned vs actual: matched.\nDeferred: none.\n' > "$TEST_DIR/closure.md"
  RESULT=$(run_script --note closure.md)
  EXIT_CODE=$(run_script_exit_code --note closure.md)
  assert_exit_code "0" "$EXIT_CODE" "existing note should exit 0"
  assert_file_exists "$(marker_path)" "existing note should create the marker"
  assert_contains "$RESULT" "closure.md" "confirmation should name the note"
  teardown_test_project
}

# --- Test: --note with a path that does not exist is refused ---
test_note_missing_path_refused() {
  setup_test_project
  RESULT=$(run_script --note no-such-note.md)
  EXIT_CODE=$(run_script_exit_code --note no-such-note.md)
  assert_exit_code "1" "$EXIT_CODE" "missing note should exit 1"
  assert_contains "$RESULT" "ERROR: Closure note not found" "missing note should explain the refusal"
  assert_file_not_exists "$(marker_path)" "missing note must not create the marker"
  teardown_test_project
}

# --- Test: --note with an empty file is refused ---
test_note_empty_file_refused() {
  setup_test_project
  : > "$TEST_DIR/empty.md"
  EXIT_CODE=$(run_script_exit_code --note empty.md)
  assert_exit_code "1" "$EXIT_CODE" "empty note should exit 1"
  assert_file_not_exists "$(marker_path)" "empty note must not create the marker"
  teardown_test_project
}

# --- Test: --note with a whitespace-only file is refused ---
test_note_whitespace_file_refused() {
  setup_test_project
  printf '  \n\t\n\n' > "$TEST_DIR/blank.md"
  EXIT_CODE=$(run_script_exit_code --note blank.md)
  assert_exit_code "1" "$EXIT_CODE" "whitespace-only note should exit 1"
  assert_file_not_exists "$(marker_path)" "whitespace-only note must not create the marker"
  teardown_test_project
}

# --- Test: --note pointing at a directory is refused ---
test_note_directory_refused() {
  setup_test_project
  mkdir -p "$TEST_DIR/notes"
  RESULT=$(run_script --note notes)
  EXIT_CODE=$(run_script_exit_code --note notes)
  assert_exit_code "1" "$EXIT_CODE" "directory as note should exit 1"
  assert_contains "$RESULT" "ERROR: Closure note not found" "directory as note should be reported as not a note"
  assert_file_not_exists "$(marker_path)" "directory as note must not create the marker"
  teardown_test_project
}

# --- Test: --note without a path is refused ---
test_note_without_path_refused() {
  setup_test_project
  RESULT=$(run_script --note)
  EXIT_CODE=$(run_script_exit_code --note)
  assert_exit_code "1" "$EXIT_CODE" "--note without a path should exit 1"
  assert_contains "$RESULT" "ERROR: --note takes exactly one path" "--note without a path should explain the refusal"
  assert_file_not_exists "$(marker_path)" "--note without a path must not create the marker"
  teardown_test_project
}

# --- Test: --note with extra arguments is refused ---
test_note_extra_arguments_refused() {
  setup_test_project
  echo "Closure: matched the plan." > "$TEST_DIR/closure.md"
  EXIT_CODE=$(run_script_exit_code --note closure.md stray)
  assert_exit_code "1" "$EXIT_CODE" "--note with extra arguments should exit 1"
  assert_file_not_exists "$(marker_path)" "--note with extra arguments must not create the marker"
  teardown_test_project
}

# --- Test: a note path containing spaces works ---
test_note_path_with_spaces() {
  setup_test_project
  mkdir -p "$TEST_DIR/my notes"
  echo "Closure: matched the plan." > "$TEST_DIR/my notes/closure note.md"
  EXIT_CODE=$(run_script_exit_code --note "my notes/closure note.md")
  assert_exit_code "0" "$EXIT_CODE" "note path with spaces should exit 0"
  assert_file_exists "$(marker_path)" "note path with spaces should create the marker"
  teardown_test_project
}

# --- Test: a note literally named "-" is read as a file, not as stdin ---
test_note_named_dash_reads_file() {
  setup_test_project
  echo "Closure: matched the plan." > "$TEST_DIR/-"
  EXIT_CODE=$(cd "$TEST_DIR" && bash "$SCRIPT" --note - </dev/null >/dev/null 2>&1; echo $?)
  assert_exit_code "0" "$EXIT_CODE" "note named - should exit 0 with stdin closed"
  assert_file_exists "$(marker_path)" "note named - should create the marker"
  teardown_test_project
}

# --- Test: the usage text says the summary is plain text ---
test_usage_says_plain_text() {
  setup_test_project
  RESULT=$(run_script)
  assert_contains "$RESULT" "(plain text, no shell punctuation)" "usage should say the summary is plain text"
  teardown_test_project
}

# --- Test: a note path containing a newline is refused (the record is one line) ---
test_note_path_with_newline_refused() {
  setup_test_project
  mkdir -p "$TEST_DIR/n"
  local weird
  weird="$(printf 'n/a\nb.md')"
  echo "Closure: matched the plan." > "$TEST_DIR/$weird"
  EXIT_CODE=$(run_script_exit_code --note "$weird")
  assert_exit_code "1" "$EXIT_CODE" "note path with a newline should exit 1"
  assert_file_not_exists "$(marker_path)" "note path with a newline must not create the marker"
  teardown_test_project
}

# --- Test: a note whose name starts with a dash is read as a file, not an option ---
test_note_path_starting_with_dash() {
  setup_test_project
  echo "Closure: matched the plan." > "$TEST_DIR/-dash.md"
  EXIT_CODE=$(run_script_exit_code --note -dash.md)
  assert_exit_code "0" "$EXIT_CODE" "note named with a leading dash should exit 0"
  assert_file_exists "$(marker_path)" "note named with a leading dash should create the marker"
  teardown_test_project
}

# --- Test: the record starts with a timestamp ---
test_marker_record_has_timestamp() {
  setup_test_project
  run_script "planned vs actual matched" >/dev/null
  STAMPED=$(grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2} \| planned vs actual matched$' "$(marker_path)" 2>/dev/null || echo 0)
  assert_equals "1" "$STAMPED" "marker record should be 'timestamp | summary'"
  teardown_test_project
}

# --- Test: a note is recorded with its label ---
test_marker_records_note_label() {
  setup_test_project
  echo "Closure: matched the plan." > "$TEST_DIR/closure.md"
  run_script --note closure.md >/dev/null
  LABELLED=$(grep -cF "| note: closure.md" "$(marker_path)" 2>/dev/null || echo 0)
  assert_equals "1" "$LABELLED" "marker record should carry the note: label and path"
  teardown_test_project
}

# --- Test: a refusal goes to stderr, with nothing on stdout ---
test_refusal_goes_to_stderr() {
  setup_test_project
  STDOUT=$(cd "$TEST_DIR" && bash "$SCRIPT" "" 2>/dev/null)
  STDERR=$(cd "$TEST_DIR" && bash "$SCRIPT" "" 2>&1 >/dev/null)
  assert_equals "" "$STDOUT" "refusal should print nothing on stdout"
  assert_contains "$STDERR" "ERROR: The closure summary is empty" "refusal should be on stderr"
  teardown_test_project
}

# --- Test: printf directives and backslashes in the summary are recorded verbatim ---
test_summary_printf_directives_verbatim() {
  setup_test_project
  local summary='done 100%s of %d items \n end'
  RESULT=$(run_script "$summary")
  RECORDED=$(grep -cF "| $summary" "$(marker_path)" 2>/dev/null || echo 0)
  assert_equals "1" "$RECORDED" "percent directives and backslashes should be recorded verbatim"
  assert_contains "$RESULT" '100%s of %d items' "confirmation should echo directives literally"
  teardown_test_project
}

# --- Test: quotes, dollar signs and backticks in the summary are inert ---
test_summary_metacharacters_inert() {
  setup_test_project
  local summary found
  summary="closed \"q\" 'q' \$(touch $TEST_DIR/pwned1) \`touch $TEST_DIR/pwned2\` \$HOME"
  RESULT=$(run_script "$summary")
  EXIT_CODE=$(run_script_exit_code "$summary")
  assert_exit_code "0" "$EXIT_CODE" "metacharacter summary should exit 0"
  assert_file_not_exists "$TEST_DIR/pwned1" "command substitution in the summary must not run"
  assert_file_not_exists "$TEST_DIR/pwned2" "backticks in the summary must not run"
  found=no
  case "$RESULT" in *'$HOME'*) found=yes ;; esac
  assert_equals "yes" "$found" "dollar-variable should be echoed literally, not expanded"
  RECORDED=$(grep -cF "$summary" "$(marker_path)" 2>/dev/null || echo 0)
  assert_equals "1" "$RECORDED" "marker should record the summary verbatim"
  teardown_test_project
}

# --- Test: the marker is keyed by the shared project hash, not the cwd ---
test_marker_uses_project_hash() {
  setup_test_project
  local other_dir other_hash
  other_dir=$(mktemp -d)
  other_hash=$(echo -n "$other_dir" | shasum -a 256 | cut -c1-12)
  (cd "$other_dir" && bash "$SCRIPT" "closed from elsewhere" >/dev/null 2>&1)
  assert_file_exists "$(marker_path)" "marker should be keyed by CLAUDE_PROJECT_DIR"
  assert_file_not_exists "/tmp/.claude_plan_closed_${other_hash}" "marker must not be keyed by the cwd"
  rm -f "/tmp/.claude_plan_closed_${other_hash}"
  rm -rf "$other_dir"
  teardown_test_project
}

# --- Run all tests ---
echo "mark-plan-closed.sh"
test_summary_creates_marker
test_prints_one_confirmation_line
test_marker_records_summary
test_no_argument_refused
test_empty_summary_refused
test_whitespace_summary_refused
test_multiline_summary_refused
test_extra_arguments_refused
test_note_path_creates_marker
test_note_missing_path_refused
test_note_empty_file_refused
test_note_whitespace_file_refused
test_note_directory_refused
test_note_without_path_refused
test_note_extra_arguments_refused
test_note_path_with_spaces
test_note_path_starting_with_dash
test_note_named_dash_reads_file
test_usage_says_plain_text
test_note_path_with_newline_refused
test_marker_record_has_timestamp
test_marker_records_note_label
test_refusal_goes_to_stderr
test_summary_printf_directives_verbatim
test_summary_metacharacters_inert
test_marker_uses_project_hash
run_tests
