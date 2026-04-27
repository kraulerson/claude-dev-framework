#!/usr/bin/env bash
# tests/test-cdf-refresh.sh — refresh_cdf_assets regression test.
#
# Validates `refresh_cdf_assets()` from `scripts/cdf-refresh.sh`.
# The function copies CDF hooks/rules/gates into a downstream project's
# .claude/framework/ subtree and updates the project's manifest with the
# CDF version + commit. CDF-only projects (no Solo Orchestrator) call
# this directly; Solo Orchestrator's upgrade-project.sh sources this
# library to refresh CDF assets on each project upgrade.
#
# Originally written for Solo Orchestrator BL-001; migrated upstream so
# CDF-only projects can use it standalone.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB="$REPO_ROOT/scripts/cdf-refresh.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# Build a fake CDF clone we control. Real CDF is not used — tests must be
# hermetic and not mutate the user's actual ~/.claude-dev-framework.
make_fake_cdf() {
  local cdf="$1" version="$2"
  mkdir -p "$cdf/hooks" "$cdf/rules" "$cdf/gates"
  echo "$version" > "$cdf/FRAMEWORK_VERSION"

  cat > "$cdf/hooks/test-hook.sh" <<EOF
#!/usr/bin/env bash
# Hook content for CDF $version
echo "hook v$version"
EOF
  chmod +x "$cdf/hooks/test-hook.sh"
  echo "stdlib v$version" > "$cdf/hooks/known-stdlib.txt"
  echo "# Rule v$version" > "$cdf/rules/test-rule.md"
  cat > "$cdf/gates/test-gate.sh" <<EOF
#!/usr/bin/env bash
echo "gate v$version"
EOF
  chmod +x "$cdf/gates/test-gate.sh"

  # Make CDF a real git repo so HEAD commit lookup works.
  git -C "$cdf" init -q
  git -C "$cdf" config user.email "test@test.local"
  git -C "$cdf" config user.name "test"
  git -C "$cdf" add -A
  git -C "$cdf" commit -q -m "CDF $version"
}

# Build a project with stale hooks/rules/gates and an old manifest.
make_stale_project() {
  local proj="$1" old_version="$2" old_commit="$3"
  mkdir -p "$proj/.claude/framework/hooks" \
           "$proj/.claude/framework/rules" \
           "$proj/.claude/framework/gates"

  cat > "$proj/.claude/framework/hooks/test-hook.sh" <<EOF
#!/usr/bin/env bash
echo "hook v$old_version"
EOF
  chmod +x "$proj/.claude/framework/hooks/test-hook.sh"
  echo "# Rule v$old_version" > "$proj/.claude/framework/rules/test-rule.md"
  cat > "$proj/.claude/framework/gates/test-gate.sh" <<EOF
#!/usr/bin/env bash
echo "gate v$old_version"
EOF
  chmod +x "$proj/.claude/framework/gates/test-gate.sh"

  cat > "$proj/.claude/manifest.json" <<EOF
{
  "frameworkVersion": "$old_version",
  "frameworkCommit": "$old_commit",
  "mode": "personal",
  "host": "github"
}
EOF
}

setup() {
  TMP=$(mktemp -d)
  CDF="$TMP/cdf"
  PROJ="$TMP/proj"
  make_fake_cdf "$CDF" "9.9.9"
  make_stale_project "$PROJ" "1.0.0" "deadbeefdeadbeef"
}
teardown() {
  rm -rf "$TMP"
}

# Source the library for in-process testing. Library should expose
# refresh_cdf_assets() as a pure function.
source_lib_or_skip() {
  if [ ! -f "$LIB" ]; then
    fail_ "$1" "scripts/lib/cdf-refresh.sh does not exist (RED expected before implementation)"
    teardown
    return 1
  fi
  # shellcheck disable=SC1090
  source "$LIB"
  return 0
}

# Run refresh in a subshell so `set -e` in this test script doesn't abort
# on a non-zero return; we want to assert behavior, not bubble up failures.
_run_refresh() {
  local proj="$1" cdf="$2" non_interactive="${3:-true}"
  ( refresh_cdf_assets "$proj" "$cdf" "$non_interactive" >/dev/null 2>&1 ) || return $?
}

# T1: hook content gets refreshed from CDF clone.
t1_refreshes_hook_content() {
  setup
  source_lib_or_skip "T1" || return
  if ! _run_refresh "$PROJ" "$CDF"; then
    fail_ "T1" "refresh_cdf_assets exited non-zero"
    teardown; return
  fi
  if ! grep -q "hook v9.9.9" "$PROJ/.claude/framework/hooks/test-hook.sh"; then
    fail_ "T1" "hook still has stale content; expected 'hook v9.9.9'"
    teardown; return
  fi
  pass "T1: hook refreshed from CDF clone (1.0.0 -> 9.9.9)"
  teardown
}

# T2: rules content gets refreshed (.md files).
t2_refreshes_rules_content() {
  setup
  source_lib_or_skip "T2" || return
  _run_refresh "$PROJ" "$CDF" || true
  if ! grep -q "Rule v9.9.9" "$PROJ/.claude/framework/rules/test-rule.md"; then
    fail_ "T2" "rule still has stale content; expected 'Rule v9.9.9'"
    teardown; return
  fi
  pass "T2: rule refreshed from CDF clone"
  teardown
}

# T3: gates content gets refreshed (.sh files).
t3_refreshes_gates_content() {
  setup
  source_lib_or_skip "T3" || return
  _run_refresh "$PROJ" "$CDF" || true
  if ! grep -q "gate v9.9.9" "$PROJ/.claude/framework/gates/test-gate.sh"; then
    fail_ "T3" "gate still has stale content; expected 'gate v9.9.9'"
    teardown; return
  fi
  if [ ! -x "$PROJ/.claude/framework/gates/test-gate.sh" ]; then
    fail_ "T3" "gate file is not executable post-refresh"
    teardown; return
  fi
  pass "T3: gate refreshed from CDF clone and executable"
  teardown
}

# T4: manifest.frameworkVersion gets updated to CDF's FRAMEWORK_VERSION.
t4_updates_manifest_version() {
  setup
  source_lib_or_skip "T4" || return
  _run_refresh "$PROJ" "$CDF" || true
  local v
  v=$(jq -r '.frameworkVersion // empty' "$PROJ/.claude/manifest.json")
  if [ "$v" != "9.9.9" ]; then
    fail_ "T4" "manifest.frameworkVersion is '$v'; expected '9.9.9'"
    teardown; return
  fi
  pass "T4: manifest.frameworkVersion updated to 9.9.9"
  teardown
}

# T5: manifest.frameworkCommit gets updated to CDF HEAD commit.
t5_updates_manifest_commit() {
  setup
  source_lib_or_skip "T5" || return
  _run_refresh "$PROJ" "$CDF" || true
  local cdf_head
  cdf_head=$(git -C "$CDF" rev-parse HEAD)
  local manifest_commit
  manifest_commit=$(jq -r '.frameworkCommit // empty' "$PROJ/.claude/manifest.json")
  if [ "$manifest_commit" != "$cdf_head" ]; then
    fail_ "T5" "manifest.frameworkCommit is '$manifest_commit'; expected '$cdf_head'"
    teardown; return
  fi
  pass "T5: manifest.frameworkCommit updated to CDF HEAD"
  teardown
}

# T6: missing CDF clone + non-interactive — skip with warning, exit 0,
# leave project files unchanged.
t6_missing_clone_non_interactive_skip() {
  setup
  source_lib_or_skip "T6" || return
  local stale_hook_before
  stale_hook_before=$(cat "$PROJ/.claude/framework/hooks/test-hook.sh")
  # Point at a non-existent clone path.
  local out rc=0
  out=$( refresh_cdf_assets "$PROJ" "$TMP/no-such-cdf" "true" 2>&1 ) || rc=$?
  if [ "$rc" -ne 0 ]; then
    fail_ "T6" "expected exit 0 on missing clone in non-interactive; got $rc"
    teardown; return
  fi
  if [[ "$out" != *"CDF clone not found"* ]]; then
    fail_ "T6" "expected warning about missing clone; got: $out"
    teardown; return
  fi
  if [ "$(cat "$PROJ/.claude/framework/hooks/test-hook.sh")" != "$stale_hook_before" ]; then
    fail_ "T6" "project hook was modified despite missing CDF"
    teardown; return
  fi
  pass "T6: missing CDF + non-interactive skips with warning, leaves project untouched"
  teardown
}

# T7: dirty CDF (pull --ff-only fails) — warn but still copy from
# working tree. The fake CDF in setup() has no upstream, so `git pull`
# will fail; this is exactly the dirty-pull path.
t7_dirty_pull_warns_and_continues() {
  setup
  source_lib_or_skip "T7" || return
  local out rc=0
  out=$( refresh_cdf_assets "$PROJ" "$CDF" "true" 2>&1 ) || rc=$?
  if [ "$rc" -ne 0 ]; then
    fail_ "T7" "expected exit 0 even on pull failure; got $rc"
    teardown; return
  fi
  if [[ "$out" != *"pull --ff-only failed"* ]]; then
    fail_ "T7" "expected pull-failed warning; got: $out"
    teardown; return
  fi
  if ! grep -q "hook v9.9.9" "$PROJ/.claude/framework/hooks/test-hook.sh"; then
    fail_ "T7" "hook not refreshed despite pull-fail fallback"
    teardown; return
  fi
  pass "T7: dirty pull warns but still refreshes from CDF working tree"
  teardown
}

# T8: idempotent — running twice yields the same result, no errors.
t8_idempotent() {
  setup
  source_lib_or_skip "T8" || return
  _run_refresh "$PROJ" "$CDF" || true
  local first_hash
  first_hash=$(shasum "$PROJ/.claude/framework/hooks/test-hook.sh" | awk '{print $1}')
  if ! _run_refresh "$PROJ" "$CDF"; then
    fail_ "T8" "second run exited non-zero"
    teardown; return
  fi
  local second_hash
  second_hash=$(shasum "$PROJ/.claude/framework/hooks/test-hook.sh" | awk '{print $1}')
  if [ "$first_hash" != "$second_hash" ]; then
    fail_ "T8" "hook hash differs across runs ($first_hash vs $second_hash)"
    teardown; return
  fi
  pass "T8: idempotent across two runs"
  teardown
}

# T9: known-stdlib.txt (a non-.sh hook file) is copied too.
t9_copies_known_stdlib_txt() {
  setup
  source_lib_or_skip "T9" || return
  _run_refresh "$PROJ" "$CDF" || true
  if [ ! -f "$PROJ/.claude/framework/hooks/known-stdlib.txt" ]; then
    fail_ "T9" "known-stdlib.txt was not copied"
    teardown; return
  fi
  if ! grep -q "stdlib v9.9.9" "$PROJ/.claude/framework/hooks/known-stdlib.txt"; then
    fail_ "T9" "known-stdlib.txt content stale"
    teardown; return
  fi
  pass "T9: known-stdlib.txt (non-.sh hook file) copied"
  teardown
}

echo "== tests/test-cdf-refresh.sh =="
t1_refreshes_hook_content
t2_refreshes_rules_content
t3_refreshes_gates_content
t4_updates_manifest_version
t5_updates_manifest_commit
t6_missing_clone_non_interactive_skip
t7_dirty_pull_warns_and_continues
t8_idempotent
t9_copies_known_stdlib_txt

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
