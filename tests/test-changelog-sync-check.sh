#!/usr/bin/env bash
# test-changelog-sync-check.sh — Tests for changelog-sync-check hook
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/changelog-sync-check.sh"

# --- Test: non-changelog file passes ---
test_non_changelog_passes() {
  setup_test_project
  jq '.projectConfig._base.changelogFile = "CHANGELOG.md"' "$TEST_DIR/.claude/manifest.json" > "$TEST_DIR/.claude/manifest.json.tmp"
  mv "$TEST_DIR/.claude/manifest.json.tmp" "$TEST_DIR/.claude/manifest.json"

  INPUT='{"tool_input":{"file_path":"app.kt"}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  assert_equals "" "$RESULT" "non-changelog file should produce no output"
  teardown_test_project
}

# --- Test: changelog with fresh sync marker passes ---
test_changelog_with_marker_passes() {
  setup_test_project
  jq '.projectConfig._base.changelogFile = "CHANGELOG.md" | .projectConfig._base.syncCommand = "bash sync.sh"' \
    "$TEST_DIR/.claude/manifest.json" > "$TEST_DIR/.claude/manifest.json.tmp"
  mv "$TEST_DIR/.claude/manifest.json.tmp" "$TEST_DIR/.claude/manifest.json"
  touch "/tmp/.claude_changelog_synced_${TEST_HASH}"

  INPUT='{"tool_input":{"file_path":"CHANGELOG.md"}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  assert_equals "" "$RESULT" "changelog with fresh marker should pass"
  teardown_test_project
}

# --- Test: changelog without marker and with syncCommand produces advisory ---
test_changelog_without_marker_advises() {
  setup_test_project
  jq '.projectConfig._base.changelogFile = "CHANGELOG.md" | .projectConfig._base.syncCommand = "bash sync.sh"' \
    "$TEST_DIR/.claude/manifest.json" > "$TEST_DIR/.claude/manifest.json.tmp"
  mv "$TEST_DIR/.claude/manifest.json.tmp" "$TEST_DIR/.claude/manifest.json"

  INPUT='{"tool_input":{"file_path":"CHANGELOG.md"}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  assert_contains "$RESULT" "additionalContext" "should produce advisory"
  assert_contains "$RESULT" "sync" "should mention sync"
  teardown_test_project
}

# A stand-in for GNU coreutils stat, first on PATH (#10). GNU `stat -f` means file
# system status: it prints a `File:` block on stdout and, for this call, exits 1.
# `-c %Y` prints the modification time (taken from whichever form this host's own
# stat accepts). Not checked against real GNU stat on every host, so it follows
# the behaviour measured in #10.
gnu_stat_first() {
  STUB_DIR=$(mktemp -d)
  cat > "$STUB_DIR/stat" <<'STUB'
#!/bin/sh
case "$1" in
  -f) printf '  File: "%s"\n    ID: 0        Namelen: 255     Type: apfs\n' "$3"; exit 1 ;;
  -c) /usr/bin/stat -c %Y "$3" 2>/dev/null || /usr/bin/stat -f %m "$3" ;;
  *) exit 1 ;;
esac
STUB
  chmod +x "$STUB_DIR/stat"
  SAVED_PATH="$PATH"; export PATH="$STUB_DIR:$PATH"
}
gnu_stat_restore() { export PATH="$SAVED_PATH"; rm -rf "$STUB_DIR"; }

changelog_manifest() {
  jq '.projectConfig._base.changelogFile = "CHANGELOG.md" | .projectConfig._base.syncCommand = "bash sync.sh"' \
    "$TEST_DIR/.claude/manifest.json" > "$TEST_DIR/.claude/manifest.json.tmp"
  mv "$TEST_DIR/.claude/manifest.json.tmp" "$TEST_DIR/.claude/manifest.json"
}

# --- Test (#10): a fresh marker passes with GNU stat first on PATH ---
test_fresh_marker_with_gnu_stat_first() {
  setup_test_project
  changelog_manifest
  touch "/tmp/.claude_changelog_synced_${TEST_HASH}"
  gnu_stat_first
  local input='{"tool_input":{"file_path":"CHANGELOG.md"}}' result code
  result=$(run_hook "$HOOK" "$input"); code=$(run_hook_exit_code "$HOOK" "$input")
  gnu_stat_restore
  assert_exit_code "0" "$code" "GNU stat first: the hook must not die on the marker age"
  assert_equals "" "$result" "GNU stat first: a fresh marker should pass silently"
  teardown_test_project
}

# --- Test (#10): a marker older than an hour still advises with GNU stat first
# (the fresh-marker test is the one that proves the real time is read) ---
test_stale_marker_with_gnu_stat_first() {
  setup_test_project
  changelog_manifest
  touch -t 200001010000 "/tmp/.claude_changelog_synced_${TEST_HASH}"
  gnu_stat_first
  local result; result=$(run_hook "$HOOK" '{"tool_input":{"file_path":"CHANGELOG.md"}}')
  gnu_stat_restore
  assert_contains "$result" "additionalContext" "GNU stat first: a stale marker should still advise"
  teardown_test_project
}

# --- Test (#10 review): a stat that prints a non-number and succeeds does not reach
# the arithmetic; the marker counts as stale and the advisory fires ---
test_non_numeric_stat_output_advises() {
  setup_test_project
  changelog_manifest
  touch "/tmp/.claude_changelog_synced_${TEST_HASH}"
  local bin result code input='{"tool_input":{"file_path":"CHANGELOG.md"}}'
  bin=$(mktemp -d)
  printf '#!/bin/sh\necho "not a number"\n' > "$bin/stat"; chmod +x "$bin/stat"
  result=$(PATH="$bin:$PATH" run_hook "$HOOK" "$input"); code=$(PATH="$bin:$PATH" run_hook_exit_code "$HOOK" "$input")
  rm -rf "$bin"
  assert_exit_code "0" "$code" "a non-numeric stat result must not crash the hook"
  assert_contains "$result" "additionalContext" "a non-numeric stat result counts as stale and advises"
  teardown_test_project
}

# --- Run all tests ---
echo "changelog-sync-check.sh"
test_non_changelog_passes
test_changelog_with_marker_passes
test_changelog_without_marker_advises
test_fresh_marker_with_gnu_stat_first
test_stale_marker_with_gnu_stat_first
test_non_numeric_stat_output_advises
run_tests
