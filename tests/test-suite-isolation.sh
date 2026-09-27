#!/usr/bin/env bash
# test-suite-isolation.sh — the suite tests this checkout, never the operator's live
# install at ~/.claude-dev-framework (#12): it must pass without one, and must not
# fetch in one.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

# --- Test: test-prepopulate.sh passes with no live install at all ---
test_prepopulate_without_live_install() {
  local home out rc
  home=$(mktemp -d)
  out=$(HOME="$home" bash "$SCRIPT_DIR/test-prepopulate.sh" </dev/null 2>&1); rc=$?
  assert_exit_code "0" "$rc" "test-prepopulate.sh must pass with no ~/.claude-dev-framework"
  assert_contains "$out" " 0 failed" "test-prepopulate.sh reports no failures without a live install"
  rm -rf "$home"
}

# Modification time of the checkout's own FETCH_HEAD (worktrees included), or
# "none"; empty when this tree is not a git checkout.
checkout_fetch_head_mtime() {
  local fh
  fh=$(git -C "$SCRIPT_DIR/.." rev-parse --path-format=absolute --git-path FETCH_HEAD 2>/dev/null) || return 0
  [ -e "$fh" ] || { echo none; return 0; }
  stat -c %Y "$fh" 2>/dev/null || stat -f %m "$fh"
}

# --- Test: the files that run session-start.sh leave the live clone alone ---
# The operator's clone gets a local origin with a main branch, so session-start's
# `git fetch origin main` would succeed there and write FETCH_HEAD. The checkout
# under test must not be fetched in either (a lab HOME linked to it would be).
test_session_start_tests_do_not_fetch_live_clone() {
  local home clone f before
  before=$(checkout_fetch_head_mtime)
  home=$(mktemp -d); clone="$home/.claude-dev-framework"
  git init --quiet --bare "$home/origin.git"
  git clone --quiet "$home/origin.git" "$clone" 2>/dev/null
  git -C "$clone" -c user.name=t -c user.email=t@t commit --quiet --allow-empty -m init
  git -C "$clone" push --quiet origin HEAD:main 2>/dev/null
  for f in test-session-start-v4.sh test-stop-checklist.sh test-spaces-in-path.sh test-integration-workflow.sh; do
    HOME="$home" bash "$SCRIPT_DIR/$f" </dev/null >/dev/null 2>&1
    if [ -e "$clone/.git/FETCH_HEAD" ]; then
      assert_equals "untouched" "fetched" "$f must not fetch in the live ~/.claude-dev-framework"
      rm -f "$clone/.git/FETCH_HEAD"
    else
      assert_equals "untouched" "untouched" "$f leaves the live ~/.claude-dev-framework alone"
    fi
  done
  if [ -n "$before" ]; then
    assert_equals "$before" "$(checkout_fetch_head_mtime)" "the checkout under test is not fetched in"
  fi
  rm -rf "$home"
}

echo "suite isolation (#12)"
test_prepopulate_without_live_install
test_session_start_tests_do_not_fetch_live_clone
run_tests
