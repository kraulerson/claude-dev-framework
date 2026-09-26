#!/usr/bin/env bash
# test-init-help.sh — init.sh --help and unknown flags exit BEFORE any write.
# Regression: an unknown flag (including --help) used to be ignored, so asking
# for help ran a full install into the current directory.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

setup() {
  FAKE_HOME=$(mktemp -d)
  CLONE="$FAKE_HOME/.claude-dev-framework"
  mkdir -p "$CLONE/.git"
  cp -R "$REPO/hooks" "$REPO/rules" "$REPO/gates" "$REPO/profiles" \
        "$REPO/scripts" "$REPO/migrations" "$CLONE/"
  cp "$REPO/FRAMEWORK_VERSION" "$CLONE/"
  PROJ="$FAKE_HOME/proj"
  git init --quiet "$PROJ"
  rm -f "$PROJ/.git/hooks/pre-"*
  echo '{"name":"x","dependencies":{"express":"^4"}}' > "$PROJ/package.json"
  BEFORE=$(tree_now)
}
teardown() { rm -rf "$FAKE_HOME"; unset FAKE_HOME CLONE PROJ BEFORE; }
run_init() { (cd "$PROJ" && HOME="$FAKE_HOME" bash "$CLONE/scripts/init.sh" "$@" </dev/null 2>&1); }
# ALL of the fake HOME — the project, its .git and HOME itself — with file
# CONTENTS, not just names: a first version compared project file names only,
# and a write into .git, into $HOME, or a `git config` change all passed it.
tree_now() {
  (cd "$FAKE_HOME" && { find . -type d; find . -type f -exec cksum {} +; } | LC_ALL=C sort)
}

test_help_long() {
  setup
  local out rc; out=$(run_init --help); rc=$?
  assert_exit_code "0" "$rc" "--help exits 0"
  assert_contains "$out" "Usage:" "--help prints usage"
  assert_equals "$BEFORE" "$(tree_now)" "--help writes nothing into the project"
  teardown
}
test_help_short() {
  setup
  local out rc; out=$(run_init -h); rc=$?
  assert_exit_code "0" "$rc" "-h exits 0"
  assert_contains "$out" "Usage:" "-h prints usage"
  assert_equals "$BEFORE" "$(tree_now)" "-h writes nothing into the project"
  teardown
}
test_help_after_other_flags() {
  setup
  local out rc; out=$(run_init --skip-plugin-check --help); rc=$?
  assert_exit_code "0" "$rc" "--help after another flag still exits 0"
  assert_equals "$BEFORE" "$(tree_now)" "--help after another flag writes nothing"
  teardown
}
test_unknown_flag_refused() {
  setup
  local out rc; out=$(run_init --skip-plugin-check --bogus); rc=$?
  assert_exit_code "2" "$rc" "an unknown flag exits 2"
  assert_contains "$out" "unknown option: --bogus" "the refusal names the flag"
  assert_contains "$out" "nothing was changed" "the refusal says nothing was written"
  assert_equals "$BEFORE" "$(tree_now)" "an unknown flag writes nothing into the project"
  teardown
}
test_value_required() {
  local flag out rc
  for flag in --profile --prepopulate; do
    setup
    out=$(run_init --skip-plugin-check "$flag"); rc=$?
    assert_exit_code "2" "$rc" "$flag with no value exits 2"
    assert_contains "$out" "ERROR: $flag needs a value" "the refusal names $flag"
    assert_equals "$BEFORE" "$(tree_now)" "$flag with no value writes nothing"
    teardown
    setup
    out=$(run_init "$flag" --help); rc=$?
    assert_exit_code "2" "$rc" "$flag followed by an option is a missing value"
    assert_equals "$BEFORE" "$(tree_now)" "$flag --help writes nothing"
    teardown
  done
}
test_unknown_profile_refused() {
  setup
  local out rc; out=$(run_init --skip-plugin-check --profile nosuch); rc=$?
  assert_exit_code "2" "$rc" "an unknown profile exits 2"
  assert_contains "$out" "unknown profile: nosuch" "the refusal names the profile"
  assert_contains "$out" "web-api" "the refusal lists the real profiles"
  assert_equals "$BEFORE" "$(tree_now)" "an unknown profile writes nothing"
  teardown
  setup
  out=$(run_init --skip-plugin-check --profile _base); rc=$?
  assert_exit_code "2" "$rc" "the internal _base profile is not selectable"
  teardown
}
test_known_flags_still_install() {
  setup
  local out rc; out=$(run_init --skip-plugin-check --profile web-api); rc=$?
  assert_exit_code "0" "$rc" "known flags still run the install"
  assert_file_exists "$PROJ/.claude/manifest.json" "the install still writes the manifest"
  teardown
}

echo "init.sh --help and unknown flags"
test_help_long
test_help_short
test_help_after_other_flags
test_unknown_flag_refused
test_value_required
test_unknown_profile_refused
test_known_flags_still_install
run_tests
