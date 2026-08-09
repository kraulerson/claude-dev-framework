#!/usr/bin/env bash
# test-headless-prompts.sh — Headless (no-TTY) behavior of interactive scripts.
# Covers the unguarded-prompt-under-set-e class: detect-profile.sh, init.sh
# (profile detection, discovery, archive mode), sync.sh conflicts, push-up.sh,
# and cdf-refresh.sh. Every invocation uses </dev/null so results don't depend
# on whether the test runner itself has a TTY.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

# init.sh/sync.sh/detect-profile.sh hardcode $HOME/.claude-dev-framework, so we
# point HOME at a temp dir holding a copy of the WORKING TREE (not a git clone —
# a clone would test committed code, not the code under review). The fake .git
# dir satisfies init.sh's existence check; actual git commands inside the fake
# clone fail and every such call site has a documented fallback.
setup_fake_env() {
  FAKE_HOME=$(mktemp -d)
  CLONE="$FAKE_HOME/.claude-dev-framework"
  mkdir -p "$CLONE/.git" "$FAKE_HOME/.claude"
  cp -R "$REPO/hooks" "$REPO/rules" "$REPO/gates" "$REPO/profiles" \
        "$REPO/scripts" "$REPO/migrations" "$CLONE/"
  cp "$REPO/FRAMEWORK_VERSION" "$CLONE/"
  OLD_HOME="$HOME"
  export HOME="$FAKE_HOME"
}

teardown_fake_env() {
  export HOME="$OLD_HOME"
  [ -n "${FAKE_HOME:-}" ] && rm -rf "$FAKE_HOME"
  [ -n "${PROJ:-}" ] && rm -rf "$(dirname "$PROJ")"
  unset FAKE_HOME CLONE OLD_HOME PROJ
}

# Fresh temp git project. $1 = "with-claude" to pre-create .claude/ (repair
# shape), $2 = "with-node" to plant signals that suggest the web-api profile.
make_project() {
  PROJ=$(mktemp -d)/proj
  mkdir -p "$PROJ"
  git -C "$(dirname "$PROJ")" init --quiet "$PROJ" 2>/dev/null || git -C "$PROJ" init --quiet
  git -C "$PROJ" config user.email "test@test.com"
  git -C "$PROJ" config user.name "Test"
  [ "${1:-}" = "with-claude" ] && mkdir -p "$PROJ/.claude"
  [ "${2:-}" = "with-node" ] && echo '{"name":"x","dependencies":{"express":"^4"}}' > "$PROJ/package.json"
}

# --- detect-profile.sh -------------------------------------------------------

# Headless + detectable signals: exits 0, stdout is exactly the suggested
# profile (nothing else — callers parse stdout), never reaches the push prompt.
test_detect_headless_takes_suggested() {
  setup_fake_env
  make_project no-claude with-node
  local out err rc
  out=$(cd "$PROJ" && bash "$CLONE/scripts/detect-profile.sh" </dev/null 2>/tmp/hp_err.$$); rc=$?
  err=$(cat /tmp/hp_err.$$; rm -f /tmp/hp_err.$$)
  assert_exit_code "0" "$rc" "headless detect with signals should exit 0"
  assert_equals "web-api" "$out" "stdout should be exactly the suggested profile"
  assert_contains "$err" "web-api" "stderr should explain the non-interactive choice"
  assert_not_contains "$out$err" "Push this profile" "headless must never reach the push prompt"
  teardown_fake_env
}

# Headless + no signals: no safe default exists — exit non-zero naming the
# missing input instead of silently emitting an empty/garbage profile.
test_detect_headless_no_signals_errors() {
  setup_fake_env
  make_project
  local out err rc
  out=$(cd "$PROJ" && bash "$CLONE/scripts/detect-profile.sh" </dev/null 2>/tmp/hp_err.$$); rc=$?
  err=$(cat /tmp/hp_err.$$; rm -f /tmp/hp_err.$$)
  [ "$rc" -ne 0 ]; assert_exit_code "0" "$?" "headless detect without signals should exit non-zero"
  assert_contains "$err" "no TTY" "stderr should say why it cannot prompt"
  assert_contains "$err" "Pass a profile explicitly" "stderr should name the escape hatch"
  assert_not_contains "$out$err" "Push this profile" "headless must never reach the push prompt"
  teardown_fake_env
}

# Regression pin: the explicit-argument path stays prompt-free and headless-safe.
test_detect_arg_path_unchanged() {
  setup_fake_env
  make_project
  local out rc
  out=$(cd "$PROJ" && bash "$CLONE/scripts/detect-profile.sh" web-api </dev/null 2>/dev/null); rc=$?
  assert_exit_code "0" "$rc" "arg path should exit 0 headless"
  assert_equals "web-api" "$out" "arg path should echo the validated profile"
  teardown_fake_env
}

# --- init.sh -----------------------------------------------------------------

# The Solo repair shape: .claude/ exists, manifest missing, bare headless init.
# This is the downstream defect — init must complete and regenerate the manifest.
test_init_headless_repair_writes_manifest() {
  setup_fake_env
  make_project with-claude with-node
  local rc
  (cd "$PROJ" && bash "$CLONE/scripts/init.sh" </dev/null >/dev/null 2>&1); rc=$?
  assert_exit_code "0" "$rc" "bare headless init.sh (repair shape) should exit 0"
  assert_file_exists "$PROJ/.claude/manifest.json" "manifest must exist after headless repair"
  local profile
  profile=$(jq -r '.profile // empty' "$PROJ/.claude/manifest.json" 2>/dev/null)
  assert_equals "web-api" "$profile" "manifest should carry the auto-detected profile"
  teardown_fake_env
}

# Fresh project (no .claude/): headless init must also survive the discovery
# interview — empty discovery with a warning, not a mid-install death.
test_init_headless_fresh_project_completes() {
  setup_fake_env
  make_project no-claude with-node
  local rc
  (cd "$PROJ" && bash "$CLONE/scripts/init.sh" </dev/null >/dev/null 2>&1); rc=$?
  assert_exit_code "0" "$rc" "bare headless init.sh on fresh project should exit 0"
  assert_file_exists "$PROJ/.claude/manifest.json" "manifest must exist after fresh headless init"
  local disc
  disc=$(jq -c '.discovery' "$PROJ/.claude/manifest.json" 2>/dev/null)
  assert_equals "{}" "$disc" "headless discovery should record empty discovery, not fail"
  teardown_fake_env
}

# Archive mode's candidate prompt is the same class: headless lists and exits 0.
test_init_archive_headless() {
  setup_fake_env
  make_project with-claude
  cat > "$PROJ/.claude/manifest.json" << 'EOF'
{"frameworkVersion":"4.3.0","files":{"project/rules/custom.md":{"candidateForGlobal":true}}}
EOF
  local out rc
  out=$(cd "$PROJ" && bash "$CLONE/scripts/init.sh" --archive </dev/null 2>&1); rc=$?
  assert_exit_code "0" "$rc" "headless archive mode should exit 0"
  assert_contains "$out" "Unpushed global candidates" "archive mode should still report candidates"
  teardown_fake_env
}

# --- sync.sh -----------------------------------------------------------------

# Headless conflict resolution: keep the local version (matching the
# interactive default for unrecognized input), keep counting, exit 0.
test_sync_headless_conflict_keeps_local() {
  setup_fake_env
  make_project with-claude
  # rules/ must pre-exist (init.sh creates it; sync.sh's rules loop assumes it)
  mkdir -p "$PROJ/.claude/framework/hooks" "$PROJ/.claude/framework/rules"
  echo "LOCAL MODIFIED CONTENT" > "$PROJ/.claude/framework/hooks/session-start.sh"
  echo '{}' > "$PROJ/.claude/settings.json"
  cat > "$PROJ/.claude/manifest.json" << 'EOF'
{"frameworkVersion":"4.3.0","profile":"web-api",
 "activeRules":[],"activeHooks":["session-start"],
 "files":{"framework/hooks/session-start.sh":{"globalHash":"000000000000"}},
 "projectConfig":{"_base":{"sourceExtensions":[".js"],"protectedBranches":["main"]},"branches":[]},
 "discovery":{}}
EOF
  local out rc
  out=$(cd "$PROJ" && bash "$CLONE/scripts/sync.sh" </dev/null 2>&1); rc=$?
  assert_exit_code "0" "$rc" "headless sync with a conflict should exit 0"
  assert_contains "$out" "CONFLICT" "conflict should still be reported"
  assert_contains "$out" "Kept local" "headless conflict resolution should keep local"
  assert_equals "LOCAL MODIFIED CONTENT" "$(cat "$PROJ/.claude/framework/hooks/session-start.sh")" \
    "local file must not be overwritten headless"
  teardown_fake_env
}

# --- push-up.sh --------------------------------------------------------------

# No safe default exists for pushing to the shared framework repo: refuse
# fast with a clear error, before dumping file content or touching git.
test_pushup_headless_refuses() {
  setup_fake_env
  make_project
  echo "# a rule" > "$PROJ/my-rule.md"
  local out err rc
  out=$(cd "$PROJ" && bash "$CLONE/scripts/push-up.sh" my-rule.md --global </dev/null 2>/tmp/hp_err.$$); rc=$?
  err=$(cat /tmp/hp_err.$$; rm -f /tmp/hp_err.$$)
  [ "$rc" -ne 0 ]; assert_exit_code "0" "$?" "headless push-up should exit non-zero"
  assert_contains "$err" "interactive" "error should say a terminal is required"
  assert_not_contains "$out" "File Content" "should refuse before dumping content"
  teardown_fake_env
}

# --- cdf-refresh.sh ----------------------------------------------------------

# Belt-and-braces: caller said interactive but there is no TTY — behave as
# non-interactive (skip with warning) instead of prompting into the void.
test_cdf_refresh_no_tty_skips() {
  setup_fake_env
  make_project with-claude
  mkdir -p "$PROJ/.claude/framework"
  local out rc
  out=$(bash -c "source '$CLONE/scripts/cdf-refresh.sh' && refresh_cdf_assets '$PROJ' '$FAKE_HOME/no-such-clone' 'false'" </dev/null 2>&1); rc=$?
  assert_exit_code "0" "$rc" "no-TTY refresh with missing clone should skip, exit 0"
  assert_contains "$out" "skipping CDF asset refresh" "should print the non-interactive skip warning"
  assert_not_contains "$out" "Clone CDF now" "must not print the interactive prompt headless"
  teardown_fake_env
}

# --- Run all tests -----------------------------------------------------------
echo "headless prompts (detect-profile, init, sync, push-up, cdf-refresh)"
test_detect_headless_takes_suggested
test_detect_headless_no_signals_errors
test_detect_arg_path_unchanged
test_init_headless_repair_writes_manifest
test_init_headless_fresh_project_completes
test_init_archive_headless
test_sync_headless_conflict_keeps_local
test_pushup_headless_refuses
test_cdf_refresh_no_tty_skips
run_tests
