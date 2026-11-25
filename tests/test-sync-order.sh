#!/usr/bin/env bash
# test-sync-order.sh — sync.sh sources _shared.sh after it pulls the framework (#53), so
# the first sync after a release regenerates settings with the new generator.
# Lab: ~/.claude-dev-framework (the lab HOME's) is a git clone of a bare origin whose
# main then gains a _shared.sh whose generate_settings_json leaves a marker file.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
lab_git() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@"; }

test_sync_uses_pulled_generator() {
  local lab clone rc
  setup_test_project
  lab=$(mktemp -d)
  mkdir -p "$lab/src"
  cp -R "$REPO_DIR/hooks" "$REPO_DIR/rules" "$REPO_DIR/gates" "$REPO_DIR/profiles" \
        "$REPO_DIR/scripts" "$REPO_DIR/migrations" "$REPO_DIR/FRAMEWORK_VERSION" "$lab/src/"
  lab_git -C "$lab/src" init --quiet
  lab_git -C "$lab/src" checkout --quiet -B main
  lab_git -C "$lab/src" add -A
  lab_git -C "$lab/src" commit --quiet -m "release N"
  lab_git clone --quiet --bare "$lab/src" "$lab/origin.git"
  clone="$HOME/.claude-dev-framework"
  rm -rf "$clone"
  lab_git clone --quiet "$lab/origin.git" "$clone"

  # Release N+1 on origin: generate_settings_json leaves a marker.
  awk '{ print } /^generate_settings_json\(\) \{$/ { print "  echo new-generator >> \"$HOME/generator-marker\"" }' \
    "$lab/src/scripts/_shared.sh" > "$lab/new.sh" && mv "$lab/new.sh" "$lab/src/scripts/_shared.sh"
  assert_equals "1" "$(grep -c 'generator-marker' "$lab/src/scripts/_shared.sh")" "lab: the new generator carries the marker"
  lab_git -C "$lab/src" commit --quiet -am "release N+1"
  lab_git -C "$lab/src" push --quiet "$lab/origin.git" main

  mkdir -p "$TEST_DIR/.claude/framework/rules" "$TEST_DIR/.claude/framework/gates"
  (cd "$TEST_DIR" && bash "$clone/scripts/sync.sh" >"$lab/out" 2>&1 </dev/null); rc=$?
  assert_equals "0" "$rc" "sync.sh exits 0"
  assert_equals "$(git -C "$lab/origin.git" rev-parse main)" "$(git -C "$clone" rev-parse HEAD)" "sync.sh pulled release N+1"
  assert_file_exists "$HOME/generator-marker" "one sync run used the pulled generator"
  rm -rf "$lab"
  teardown_test_project
}

test_sync_uses_pulled_generator

run_tests
