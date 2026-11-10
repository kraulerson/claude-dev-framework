#!/usr/bin/env bash
# test-hook-failure-policy.sh — guard hooks fail closed (#49)
# A PreToolUse hook that times out, crashes or cannot start lets the action go ahead
# unless its entry says "onFailure":"block", which Claude Code honours from 2.1.295.
# generate_settings_json reads `claude --version` from PATH: it writes the policy when
# that Claude Code has it, and otherwise writes the timeouts alone and warns once.
# Inside a Claude Code session, a claude that is missing or prints no version stops
# init.sh, sync.sh and migrations/v4.sh before they write anything.
# Each case runs with PATH set to a temp bin alone: symlinks to the tools the scripts use
# and a fake claude (or none), so no claude elsewhere on the machine can be found.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=/dev/null
source "$REPO_DIR/scripts/_shared.sh"

ALL_HOOKS=(session-start session-end compliance-reinforce enforce-evaluate enforce-superpowers
  pre-commit-checks branch-safety stop-checklist changelog-sync-check marker-tracker
  scalability-check pre-deploy-check marker-guard config-guard enforce-plan-tracking
  enforce-context7 verification-gate)
# The PreToolUse hooks that block (exit 2); verification-gate gets 600 s, the rest 30.
BLOCKING='enforce-evaluate|enforce-superpowers|pre-commit-checks|branch-safety|marker-guard|config-guard|enforce-plan-tracking|enforce-context7|verification-gate'
# Lifecycle hooks, record-approval (never blocks the prompt) and the advisory checks.
NO_POLICY='session-start|session-end|stop-checklist|compliance-reinforce|record-approval|changelog-sync-check|scalability-check|pre-deploy-check'
TOOLS="bash sh env jq grep egrep head tail cut sed awk tr sort uniq wc cat cp mv ln rm mkdir
  rmdir chmod touch find xargs basename dirname readlink stat date mktemp shasum diff cmp git
  ls tee od uname perl python3 sleep id hostname"

# make_bin [CLAUDE_OUTPUT_LINE...] — a temp bin of symlinks to TOOLS and, given lines, a
# claude that prints them. Prints the bin's path.
make_bin() {
  local bin t p; bin=$(mktemp -d)
  for t in $TOOLS; do
    p=$(command -v "$t" 2>/dev/null) || continue
    case "$p" in /*) ln -s "$p" "$bin/$t" ;; esac
  done
  if [ $# -gt 0 ]; then
    { echo '#!/bin/sh'; for t in "$@"; do printf 'echo "%s"\n' "$t"; done; } > "$bin/claude"
    chmod +x "$bin/claude"
  fi
  echo "$bin"
}
BIN_NEW=$(make_bin "2.1.319 (Claude Code)")
BIN_OLD=$(make_bin "2.1.294 (Claude Code)")
BIN_GARBAGE=$(make_bin "Claude Code (dev build)")
BIN_HUGE=$(make_bin "2.1.99999999999999999999 (Claude Code)")
BIN_NONE=$(make_bin)

# gen_with BIN CLAUDECODE HOOK... — generate_settings_json with PATH=BIN only
gen_with() {
  local bin="$1" cc="$2"; shift 2
  ( PATH="$bin"; CLAUDECODE="$cc"; generate_settings_json "$@" )
}

# Every hook entry, one per line: event|script|timeout|onFailure|keys
entry_lines() {
  jq -r '.hooks | to_entries[] | .key as $e | .value[].hooks[]
    | "\($e)|\(.command | sub(".*/"; ""))|\(.timeout // "-")|\(.onFailure // "-")|\(keys | join(","))"' <<< "$1"
}

# =====================================================================
# a. A Claude Code with onFailure: blocking guards fail closed, the rest keep their shape
# =====================================================================
check_supported() {
  local cc="$1" tmp out; tmp=$(mktemp -d)
  out=$(gen_with "$BIN_NEW" "$cc" "${ALL_HOOKS[@]}" 2>"$tmp/err")
  assert_equals "" "$(cat "$tmp/err")" "supported (CLAUDECODE='$cc'): no warning"
  assert_equals "18" "$(entry_lines "$out" | wc -l | tr -d ' ')" "supported: 18 entries (17 hooks and record-approval)"
  assert_equals "10" "$(entry_lines "$out" | grep -c '|block|')" \
    "supported: 10 entries block (9 blocking PreToolUse hooks, marker-tracker)"
  assert_equals "9" "$(entry_lines "$out" | grep -cE "^PreToolUse\|($BLOCKING)\.sh\|[0-9]+\|block\|command,onFailure,timeout,type$")" \
    "supported: the 9 blocking PreToolUse hooks carry timeout and onFailure"
  assert_equals "" "$(entry_lines "$out" | grep -E "^PreToolUse\|($BLOCKING)\.sh\|" | grep -v '^PreToolUse|verification-gate.sh|' | grep -v '|30|block|')" \
    "supported: every blocking PreToolUse hook but verification-gate has timeout 30"
  assert_equals "PreToolUse|verification-gate.sh|600|block|command,onFailure,timeout,type" \
    "$(entry_lines "$out" | grep '|verification-gate.sh|')" \
    "supported: verification-gate runs the linters, timeout 600"
  assert_equals "PostToolUse|marker-tracker.sh|30|block|command,onFailure,timeout,type" \
    "$(entry_lines "$out" | grep '|marker-tracker.sh|')" "supported: marker-tracker blocks, timeout 30"
  assert_equals "8" "$(entry_lines "$out" | grep -cE "\|($NO_POLICY)\.sh\|-\|-\|command,type$")" \
    "supported: the 8 others (4 lifecycle hooks, record-approval, 3 advisory checks) keep type+command only"
  assert_equals "number" "$(jq -r '[.hooks[][].hooks[] | select(.timeout) | .timeout | type] | unique | join(",")' <<< "$out")" \
    "supported: every timeout is a number"
  rm -rf "$tmp"
}
test_supported_version_blocks() {
  check_supported ""
  check_supported 1
}

# =====================================================================
# b. Older, unreadable or (outside a session) missing Claude Code: timeouts only, one
# loud warning with the fix for that case, valid JSON
# =====================================================================
check_unsupported() {
  local label="$1" bin="$2" cc="$3" names="$4" fix="$5" tmp out rc; tmp=$(mktemp -d)
  out=$(gen_with "$bin" "$cc" "${ALL_HOOKS[@]}" 2>"$tmp/err"); rc=$?
  assert_equals "0" "$rc" "unsupported ($label): generates"
  echo "$out" | jq empty 2>/dev/null
  assert_equals "0" "$?" "unsupported ($label): stdout is valid JSON"
  assert_equals "0" "$(jq '[.hooks[][].hooks[] | select(has("onFailure"))] | length' <<< "$out")" \
    "unsupported ($label): no entry has onFailure"
  assert_equals "10" "$(jq '[.hooks[][].hooks[] | select(.timeout | type == "number")] | length' <<< "$out")" \
    "unsupported ($label): the 10 guard entries keep their timeout"
  assert_equals "1" "$(grep -c 'WARNING' "$tmp/err")" "unsupported ($label): exactly one warning"
  assert_equals "1" "$(grep -c '2\.1\.295' "$tmp/err")" "unsupported ($label): warning names the 2.1.295 floor"
  assert_equals "1" "$(grep -c 'will not fail closed when they time out, crash or cannot start' "$tmp/err")" \
    "unsupported ($label): warning says what is lost"
  assert_equals "1" "$(grep -c 'sync\.sh' "$tmp/err")" "unsupported ($label): warning says to re-run sync.sh"
  assert_equals "1" "$(grep -cF "$names" "$tmp/err")" "unsupported ($label): warning names '$names'"
  assert_equals "1" "$(grep -cF "$fix" "$tmp/err")" "unsupported ($label): warning gives the fix '$fix'"
  assert_equals "0" "$(grep -c 'integer expression expected' "$tmp/err")" "unsupported ($label): no shell arithmetic error"
  rm -rf "$tmp"
}
test_unsupported_versions_warn() {
  local old='Fix: run `claude update`, then re-run sync.sh in this project.'
  local unreadable='Fix: run `claude --version`; if it is older than 2.1.295, run `claude update`; then re-run sync.sh in this project.'
  # A genuinely old Claude Code is possible inside a session too: same warning there.
  check_unsupported "2.1.294, CLAUDECODE=''" "$BIN_OLD" "" "Claude Code 2.1.294" "$old"
  check_unsupported "2.1.294, CLAUDECODE=1" "$BIN_OLD" 1 "Claude Code 2.1.294" "$old"
  check_unsupported "unreadable, CLAUDECODE=''" "$BIN_GARBAGE" "" "version could not be read" "$unreadable"
  # A part longer than 9 digits is not a version: unreadable, not an arithmetic error
  check_unsupported "2.1.<20 digits>, CLAUDECODE=''" "$BIN_HUGE" "" "version could not be read" "$unreadable"
  check_unsupported "not found, CLAUDECODE=''" "$BIN_NONE" "" "not found on PATH" \
    'Fix: install Claude Code 2.1.295 or later (https://claude.com/claude-code) so that `claude` is on PATH, then re-run sync.sh in this project.'
  # `claude update` cannot run without a claude on PATH
  assert_equals "0" "$(gen_with "$BIN_NONE" "" config-guard 2>&1 >/dev/null | grep -c 'claude update')" \
    "unsupported (not found): the fix does not say claude update"
}

# =====================================================================
# b2. Inside a Claude Code session, a claude that is missing or prints no version: refuse
# =====================================================================
REFUSAL='ERROR: claude is not on this shell'"'"'s PATH or prints no version (an alias or an app-bundled Claude Code is not visible to scripts), yet this runs inside a Claude Code session. Nothing was written. Run init.sh or sync.sh from a terminal outside Claude Code, with claude on PATH.'
check_generator_refuses() {
  local label="$1" bin="$2" tmp out rc; tmp=$(mktemp -d)
  out=$(gen_with "$bin" 1 "${ALL_HOOKS[@]}" 2>"$tmp/err"); rc=$?
  assert_equals "1" "$rc" "refuse ($label): generate_settings_json returns 1"
  assert_equals "" "$out" "refuse ($label): nothing on stdout"
  assert_equals "$REFUSAL" "$(cat "$tmp/err")" "refuse ($label): stderr is the refusal alone"
  ( PATH="$bin"; CLAUDECODE=1; cdf_require_claude_in_session 2>/dev/null )
  assert_equals "1" "$?" "refuse ($label): cdf_require_claude_in_session returns 1"
  rm -rf "$tmp"
}
test_session_refuses() {
  local bin
  check_generator_refuses "no claude" "$BIN_NONE"
  check_generator_refuses "unreadable" "$BIN_GARBAGE"
  for bin in "$BIN_NEW" "$BIN_OLD"; do
    ( PATH="$bin"; CLAUDECODE=1; cdf_require_claude_in_session 2>/dev/null )
    assert_equals "0" "$?" "session check: passes with a claude that prints a version"
  done
  ( PATH="$BIN_NONE"; CLAUDECODE=; cdf_require_claude_in_session 2>/dev/null )
  assert_equals "0" "$?" "session check: passes with CLAUDECODE empty"
  ( PATH="$BIN_NONE"; unset CLAUDECODE; cdf_require_claude_in_session 2>/dev/null )
  assert_equals "0" "$?" "session check: passes with CLAUDECODE unset"
}

# path_state NAME — NAME under TEST_DIR/.claude: its listing and checksums, or "absent"
path_state() {
  [ -e "$TEST_DIR/.claude/$1" ] || { echo absent; return; }
  (cd "$TEST_DIR/.claude" && find "$1" | LC_ALL=C sort && find "$1" -type f -exec shasum {} + | LC_ALL=C sort)
}
# run_script BIN CLAUDECODE SCRIPT ARG... — a framework script from TEST_DIR, PATH=BIN only
run_script() {
  local bin="$1" cc="$2" script="$3"; shift 3
  (cd "$TEST_DIR" && CLAUDECODE="$cc" PATH="$bin" bash "$HOME/.claude-dev-framework/$script" "$@" </dev/null)
}
# check_script_refuses LABEL BIN SCRIPT ARG... — refused in a session, nothing written
check_script_refuses() {
  local label="$1" bin="$2" tmp rc p; shift 2; tmp=$(mktemp -d)
  for p in settings.json manifest.json framework; do path_state "$p" > "$tmp/before.$p"; done
  run_script "$bin" 1 "$@" >"$tmp/out" 2>"$tmp/err"; rc=$?
  assert_equals "non-zero" "$([ "$rc" -ne 0 ] && echo non-zero || echo "rc=$rc")" "$label: stops with a non-zero exit"
  assert_equals "$(cat "$tmp/before.settings.json")" "$(path_state settings.json)" "$label: settings.json unchanged"
  assert_equals "$(cat "$tmp/before.manifest.json")" "$(path_state manifest.json)" "$label: manifest unchanged"
  assert_equals "$(cat "$tmp/before.framework")" "$(path_state framework)" "$label: .claude/framework/ unchanged"
  assert_contains "$(cat "$tmp/err")" "ERROR: claude is not on this shell's PATH or prints no version" "$label: says why"
  rm -rf "$tmp"
}

# =====================================================================
# b3. sync.sh, init.sh and migrations/v4.sh stop before writing anything
# =====================================================================
test_scripts_refuse_in_session() {
  # A project installed by init.sh with a Claude Code that has onFailure
  setup_test_project
  rm -rf "$TEST_DIR/.claude"
  run_script "$BIN_NEW" "" scripts/init.sh --skip-plugin-check --profile web-api >/dev/null 2>&1
  assert_equals "block" "$(jq -r '.hooks.PreToolUse[0].hooks[0].onFailure' "$TEST_DIR/.claude/settings.json")" \
    "installed: settings block on failure"
  # Out of date, so a sync that ran would rewrite the manifest and a framework file
  jq '.frameworkVersion = "4.0.0" | del(.lastSyncDate)' "$TEST_DIR/.claude/manifest.json" > "$TEST_DIR/manifest.tmp"
  mv "$TEST_DIR/manifest.tmp" "$TEST_DIR/.claude/manifest.json"
  echo "# stale" >> "$TEST_DIR/.claude/framework/hooks/config-guard.sh"
  check_script_refuses "sync (no claude)" "$BIN_NONE" scripts/sync.sh
  check_script_refuses "sync (unreadable)" "$BIN_GARBAGE" scripts/sync.sh
  check_script_refuses "v4 (no claude)" "$BIN_NONE" migrations/v4.sh
  teardown_test_project

  # A project with its own settings, never installed
  setup_test_project
  rm -rf "$TEST_DIR/.claude"; mkdir -p "$TEST_DIR/.claude"
  echo '{"model":"opus","permissions":{"deny":["WebFetch"]}}' > "$TEST_DIR/.claude/settings.json"
  check_script_refuses "init (no claude)" "$BIN_NONE" scripts/init.sh --skip-plugin-check --profile web-api
  check_script_refuses "init (unreadable)" "$BIN_GARBAGE" scripts/init.sh --skip-plugin-check --profile web-api
  assert_contains "$(run_script "$BIN_NONE" 1 scripts/init.sh --help 2>&1)" "Usage:" "init --help: still prints usage"
  teardown_test_project
}

# =====================================================================
# c. Numeric three-part compare against the 2.1.295 floor; parts of 1 to 9 digits
# =====================================================================
test_version_compare() {
  local v tmp; tmp=$(mktemp -d)
  for v in 2.1.295 2.1.319 2.2.0 3.0.0 2.1.1000 10.0.0 2.1.999999999; do
    cdf_on_failure_supported "$v"
    assert_equals "0" "$?" "compare: $v is supported"
  done
  for v in 2.1.294 2.1.29 2.0.999 1.9.9 1.99.999 0.0.0 "" 2.1 2.1.99999999999999999999 99999999999999999999.0.0; do
    cdf_on_failure_supported "$v" 2>>"$tmp/err"
    assert_equals "1" "$?" "compare: '$v' is not supported"
  done
  assert_equals "" "$(cat "$tmp/err")" "compare: no stderr (no integer expression error)"
  rm -rf "$tmp"
}

# =====================================================================
# c2. The version is the first X.Y.Z of the first line of claude --version, nothing else
# =====================================================================
test_version_lookup() {
  local bin line2
  bin=$(make_bin "2.1.300 (Claude Code)" "9.9.9")
  line2=$(make_bin "Claude Code" "2.1.300")
  assert_equals "2.1.300" "$(PATH="$bin"; cdf_claude_code_version)" \
    "lookup: first X.Y.Z of the first line of claude --version"
  assert_equals "" "$(PATH="$line2"; cdf_claude_code_version)" "lookup: a version on line 2 only is not read"
  assert_equals "" "$(PATH="$BIN_GARBAGE"; cdf_claude_code_version)" "lookup: no X.Y.Z prints nothing"
  assert_equals "" "$(PATH="$BIN_HUGE"; cdf_claude_code_version 2>&1)" "lookup: a part over 9 digits prints nothing"
  assert_equals "" "$(PATH="$BIN_NONE"; cdf_claude_code_version)" "lookup: no claude on PATH prints nothing"
  assert_equals "" "$(export CDF_CLAUDE_CODE_VERSION=2.1.319; PATH="$BIN_NONE"; cdf_claude_code_version)" \
    "lookup: no environment override"
  rm -rf "$bin" "$line2"
}

# =====================================================================
# d. A merge over old-shape framework entries writes the new fields, keeps the project's
# =====================================================================
test_merge_carries_policy() {
  local tmp gen; tmp=$(mktemp -d)
  cat > "$tmp/settings.json" <<'JSON'
{"permissions":{"deny":["WebFetch"]},
 "hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[
   {"type":"command","command":"\"$CLAUDE_PROJECT_DIR\"/.claude/framework/hooks/config-guard.sh"},
   {"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR\"/scripts/project-gate.sh"}]}],
  "SessionStart":[{"hooks":[{"type":"command","command":"\"$CLAUDE_PROJECT_DIR\"/.claude/framework/hooks/session-start.sh"}]}]}}
JSON
  gen=$(gen_with "$BIN_NEW" "" session-start config-guard verification-gate)
  merge_hooks_into_settings "$gen" "$tmp/settings.json"
  jq empty "$tmp/settings.json" 2>/dev/null
  assert_equals "0" "$?" "merge: result is valid JSON"
  assert_equals '{"type":"command","command":"\"$CLAUDE_PROJECT_DIR\"/.claude/framework/hooks/config-guard.sh","timeout":30,"onFailure":"block"}' \
    "$(jq -c '.hooks.PreToolUse[].hooks[] | select(.command | endswith("/config-guard.sh"))' "$tmp/settings.json")" \
    "merge: config-guard entry carries timeout and onFailure"
  assert_equals '600|block' \
    "$(jq -r '.hooks.PreToolUse[].hooks[] | select(.command | endswith("/verification-gate.sh")) | "\(.timeout)|\(.onFailure)"' "$tmp/settings.json")" \
    "merge: verification-gate entry carries timeout 600 and onFailure"
  assert_equals '[{"type":"command","command":"\"$CLAUDE_PROJECT_DIR\"/.claude/framework/hooks/session-start.sh"}]' \
    "$(jq -c '.hooks.SessionStart[0].hooks' "$tmp/settings.json")" \
    "merge: session-start entry keeps type+command only"
  assert_equals '{"matcher":"Bash","hooks":[{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR\"/scripts/project-gate.sh"}]}' \
    "$(jq -c '.hooks.PreToolUse[0]' "$tmp/settings.json")" "merge: project hook unchanged"
  assert_equals "1" "$(jq '[.permissions.deny[] | select(. == "WebFetch")] | length' "$tmp/settings.json")" \
    "merge: user deny rule kept"
  rm -rf "$tmp"
}

echo "hook-failure-policy (onFailure block, version gate)"
test_supported_version_blocks
test_unsupported_versions_warn
test_session_refuses
test_scripts_refuse_in_session
test_version_compare
test_version_lookup
test_merge_carries_policy
rm -rf "$BIN_NEW" "$BIN_OLD" "$BIN_GARBAGE" "$BIN_HUGE" "$BIN_NONE"
run_tests
