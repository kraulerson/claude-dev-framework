#!/usr/bin/env bash
# test-install-matrix.sh — Full simulated install test matrix
# Tests init.sh across combinations of:
#   - Fresh install vs. prepopulated discovery
#   - No deps, Superpowers only, Context7 only, both deps
#
# Uses HOME override to simulate different dependency states without
# actually installing/uninstalling plugins or MCP servers.
#
# Stdin ordering for clean install (no existing .claude/):
#   1. Context7 install prompt [y/N] (if C7 missing)
#   2. Profile detection prompt [y/n/name]
#   3. Discovery interview (6 questions) OR skipped by --prepopulate
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT_SCRIPT="$REPO_DIR/scripts/init.sh"

# shellcheck source=/dev/null
source "$REPO_DIR/scripts/_shared.sh"

# --- Helpers ---

setup_project() {
  PROJECT_DIR=$(mktemp -d)
  git -C "$PROJECT_DIR" init --quiet
  git -C "$PROJECT_DIR" config user.email "test@test.com"
  git -C "$PROJECT_DIR" config user.name "Test"
  echo "init" > "$PROJECT_DIR/README.md"
  git -C "$PROJECT_DIR" add README.md
  git -C "$PROJECT_DIR" commit -m "Initial commit" --quiet
  git -C "$PROJECT_DIR" remote add origin "https://github.com/test/test-project.git" 2>/dev/null || true
  rm -f "$PROJECT_DIR"/.git/hooks/pre-*
  echo '{"name":"test","dependencies":{"express":"^4.0.0"}}' > "$PROJECT_DIR/package.json"
  git -C "$PROJECT_DIR" add package.json
  git -C "$PROJECT_DIR" commit -m "Add package.json" --quiet
}

# Usage: setup_home [superpowers] [context7]
setup_home() {
  local sp="${1:-false}" c7="${2:-false}"
  FAKE_HOME=$(mktemp -d)
  mkdir -p "$FAKE_HOME/.claude"

  local sp_block='{}'
  [ "$sp" = "true" ] && sp_block='{"superpowers@claude-plugins-official": true}'

  local c7_block='null'
  [ "$c7" = "true" ] && c7_block='{"context7": {"command": "npx", "args": ["-y", "@upstash/context7-mcp@latest"]}}'

  jq -n \
    --argjson ep "$sp_block" \
    --argjson mc "$c7_block" \
    '{enabledPlugins: $ep, mcpServers: (if $mc then $mc else {} end)}' \
    > "$FAKE_HOME/.claude/settings.json"

  ln -s "$REPO_DIR" "$FAKE_HOME/.claude-dev-framework"
}

setup_prepopulate() {
  cat > "$PROJECT_DIR/discovery.json" << 'JSON'
{
  "branch:main": {
    "purpose": "matrix test project",
    "devOS": "Darwin",
    "targetPlatform": "web",
    "buildTools": "typescript"
  },
  "futurePlatforms": null,
  "discoveryDate": "2026-04-03",
  "lastReviewDate": "2026-04-03"
}
JSON
}

run_init() {
  (
    cd "$PROJECT_DIR" && \
    HOME="$FAKE_HOME" \
    bash "$INIT_SCRIPT" "$@" 2>&1
  )
}

teardown() {
  [ -n "${PROJECT_DIR:-}" ] && rm -rf "$PROJECT_DIR"
  [ -n "${FAKE_HOME:-}" ] && rm -rf "$FAKE_HOME"
  unset PROJECT_DIR FAKE_HOME
}

# =====================================================================
# TEST 1: Fresh install, no plugins/skills installed
# Stdin: n (decline C7) → y (accept profile) → 6x empty (discovery)
# =====================================================================
test_fresh_no_deps() {
  setup_project
  setup_home "false" "false"

  OUTPUT=$(printf 'n\ny\n\n\n\nn\n\n\n' | run_init)

  assert_contains "$OUTPUT" "Superpowers plugin: NOT INSTALLED" "fresh/no-deps: should detect missing Superpowers"
  assert_contains "$OUTPUT" "Context7 MCP: NOT INSTALLED" "fresh/no-deps: should detect missing Context7"
  assert_contains "$OUTPUT" "Installation Complete" "fresh/no-deps: should complete installation"
  assert_file_exists "$PROJECT_DIR/.claude/manifest.json" "fresh/no-deps: manifest should exist"

  teardown
}

# =====================================================================
# TEST 2: Fresh install, Superpowers installed, no Context7
# Stdin: n (decline C7) → y (accept profile) → 6x empty (discovery)
# =====================================================================
test_fresh_superpowers_only() {
  setup_project
  setup_home "true" "false"

  OUTPUT=$(printf 'n\ny\n\n\n\nn\n\n\n' | run_init)

  assert_contains "$OUTPUT" "Superpowers plugin: INSTALLED" "fresh/sp-only: should detect Superpowers"
  assert_contains "$OUTPUT" "Context7 MCP: NOT INSTALLED" "fresh/sp-only: should detect missing Context7"
  assert_contains "$OUTPUT" "Installation Complete" "fresh/sp-only: should complete"

  teardown
}

# =====================================================================
# TEST 3: Fresh install, Context7 installed, no Superpowers
# Stdin: (no C7 prompt) → y (accept profile) → 6x empty (discovery)
# =====================================================================
test_fresh_context7_only() {
  setup_project
  setup_home "false" "true"

  OUTPUT=$(printf 'y\n\n\n\nn\n\n\n' | run_init)

  assert_contains "$OUTPUT" "Superpowers plugin: NOT INSTALLED" "fresh/c7-only: should detect missing Superpowers"
  assert_contains "$OUTPUT" "Context7 MCP: INSTALLED" "fresh/c7-only: should detect Context7"
  assert_contains "$OUTPUT" "Installation Complete" "fresh/c7-only: should complete"

  teardown
}

# =====================================================================
# TEST 4: Fresh install, both plugins installed
# Stdin: (no C7 prompt) → y (accept profile) → 6x empty (discovery)
# =====================================================================
test_fresh_both_deps() {
  setup_project
  setup_home "true" "true"

  OUTPUT=$(printf 'y\n\n\n\nn\n\n\n' | run_init)

  assert_contains "$OUTPUT" "Superpowers plugin: INSTALLED" "fresh/both: should detect Superpowers"
  assert_contains "$OUTPUT" "Context7 MCP: INSTALLED" "fresh/both: should detect Context7"
  assert_contains "$OUTPUT" "Installation Complete" "fresh/both: should complete"

  teardown
}

# =====================================================================
# TEST 5: Prepopulate, no plugins/skills installed
# Stdin: n (decline C7) → y (accept profile)
# =====================================================================
test_prepopulate_no_deps() {
  setup_project
  setup_home "false" "false"
  setup_prepopulate

  OUTPUT=$(printf 'n\ny\n' | run_init --prepopulate "$PROJECT_DIR/discovery.json")

  assert_contains "$OUTPUT" "Using pre-populated discovery from" "prepop/no-deps: should use prepopulated data"
  assert_contains "$OUTPUT" "Superpowers plugin: NOT INSTALLED" "prepop/no-deps: should detect missing Superpowers"
  assert_contains "$OUTPUT" "Context7 MCP: NOT INSTALLED" "prepop/no-deps: should detect missing Context7"
  assert_contains "$OUTPUT" "Installation Complete" "prepop/no-deps: should complete"
  assert_not_contains "$OUTPUT" "Discovery Interview" "prepop/no-deps: should NOT show interview"

  DISC_PURPOSE=$(jq -r '.discovery["branch:main"].purpose' "$PROJECT_DIR/.claude/manifest.json" 2>/dev/null || echo "")
  assert_equals "matrix test project" "$DISC_PURPOSE" "prepop/no-deps: manifest should have prepopulated data"

  teardown
}

# =====================================================================
# TEST 6: Prepopulate, Superpowers installed, no Context7
# Stdin: n (decline C7) → y (accept profile)
# =====================================================================
test_prepopulate_superpowers_only() {
  setup_project
  setup_home "true" "false"
  setup_prepopulate

  OUTPUT=$(printf 'n\ny\n' | run_init --prepopulate "$PROJECT_DIR/discovery.json")

  assert_contains "$OUTPUT" "Using pre-populated discovery from" "prepop/sp-only: should use prepopulated data"
  assert_contains "$OUTPUT" "Superpowers plugin: INSTALLED" "prepop/sp-only: should detect Superpowers"
  assert_contains "$OUTPUT" "Context7 MCP: NOT INSTALLED" "prepop/sp-only: should detect missing Context7"
  assert_contains "$OUTPUT" "Installation Complete" "prepop/sp-only: should complete"

  teardown
}

# =====================================================================
# TEST 7: Prepopulate, Context7 installed, no Superpowers
# Stdin: (no C7 prompt) → y (accept profile)
# =====================================================================
test_prepopulate_context7_only() {
  setup_project
  setup_home "false" "true"
  setup_prepopulate

  OUTPUT=$(printf 'y\n' | run_init --prepopulate "$PROJECT_DIR/discovery.json")

  assert_contains "$OUTPUT" "Using pre-populated discovery from" "prepop/c7-only: should use prepopulated data"
  assert_contains "$OUTPUT" "Superpowers plugin: NOT INSTALLED" "prepop/c7-only: should detect missing Superpowers"
  assert_contains "$OUTPUT" "Context7 MCP: INSTALLED" "prepop/c7-only: should detect Context7"
  assert_contains "$OUTPUT" "Installation Complete" "prepop/c7-only: should complete"

  teardown
}

# =====================================================================
# TEST 8: Prepopulate, both plugins installed
# Stdin: (no C7 prompt) → y (accept profile)
# =====================================================================
test_prepopulate_both_deps() {
  setup_project
  setup_home "true" "true"
  setup_prepopulate

  OUTPUT=$(printf 'y\n' | run_init --prepopulate "$PROJECT_DIR/discovery.json")

  assert_contains "$OUTPUT" "Using pre-populated discovery from" "prepop/both: should use prepopulated data"
  assert_contains "$OUTPUT" "Superpowers plugin: INSTALLED" "prepop/both: should detect Superpowers"
  assert_contains "$OUTPUT" "Context7 MCP: INSTALLED" "prepop/both: should detect Context7"
  assert_contains "$OUTPUT" "Installation Complete" "prepop/both: should complete"
  assert_not_contains "$OUTPUT" "Discovery Interview" "prepop/both: should NOT show interview"

  DISC_PURPOSE=$(jq -r '.discovery["branch:main"].purpose' "$PROJECT_DIR/.claude/manifest.json" 2>/dev/null || echo "")
  assert_equals "matrix test project" "$DISC_PURPOSE" "prepop/both: manifest should have prepopulated data"

  teardown
}

# =====================================================================
# TEST 9: --skip-plugin-check skips all dependency checks
# Stdin: y (accept profile)
# =====================================================================
test_skip_plugin_check() {
  setup_project
  setup_home "false" "false"
  setup_prepopulate

  OUTPUT=$(printf 'y\n' | run_init --skip-plugin-check --prepopulate "$PROJECT_DIR/discovery.json")

  assert_not_contains "$OUTPUT" "Superpowers" "skip-check: should NOT mention Superpowers"
  assert_not_contains "$OUTPUT" "Context7" "skip-check: should NOT mention Context7"
  assert_not_contains "$OUTPUT" "DEPENDENCY CHECK" "skip-check: should NOT show dependency section"
  assert_not_contains "$OUTPUT" "Checking Dependencies" "skip-check: should NOT show dependency section (clean)"
  assert_contains "$OUTPUT" "Installation Complete" "skip-check: should complete"

  teardown
}

# =====================================================================
# TEST 10: Context7 install declined shows degraded message
# Stdin: n (decline C7) → y (accept profile) → 6x empty (discovery)
# =====================================================================
test_context7_declined() {
  setup_project
  setup_home "true" "false"

  OUTPUT=$(printf 'n\ny\n\n\n\nn\n\n\n' | run_init)

  assert_contains "$OUTPUT" "Skipped. Implementation Zone will be degraded" "declined: should warn about degraded zone"
  assert_contains "$OUTPUT" "Installation Complete" "declined: should still complete"

  teardown
}

# =====================================================================
# TEST 11: generate_settings_json — matchers, new hooks, no pre-compact
# =====================================================================
test_generate_settings_matchers() {
  local out
  out=$(generate_settings_json session-start compliance-reinforce enforce-superpowers \
    stop-checklist session-end marker-guard config-guard marker-tracker \
    enforce-plan-tracking enforce-context7 changelog-sync-check scalability-check \
    verification-gate pre-compact-reminder)

  # Valid JSON
  echo "$out" | jq -e '.' >/dev/null 2>&1
  assert_equals "0" "$?" "generate: output is valid JSON"

  # NotebookEdit matcher present on the file-tool hooks
  assert_contains "$out" "Write|Edit|NotebookEdit" "generate: file-tool matchers include NotebookEdit"

  # marker-guard / config-guard cover Bash + file tools
  assert_contains "$out" "Bash|Write|Edit|NotebookEdit" "generate: guard matchers include Bash+file tools"

  # New event groups exist
  assert_contains "$out" "SessionEnd" "generate: SessionEnd group present"
  assert_contains "$out" "UserPromptSubmit" "generate: UserPromptSubmit group present"

  # New hook commands registered
  assert_contains "$out" "session-end.sh" "generate: session-end registered"
  assert_contains "$out" "compliance-reinforce.sh" "generate: compliance-reinforce registered"

  # pre-compact-reminder removed entirely (no case entry)
  assert_not_contains "$out" "pre-compact-reminder" "generate: pre-compact-reminder not registered"
  assert_not_contains "$out" "PreCompact" "generate: no PreCompact event"
}

# =====================================================================
# TEST 12: generate_settings_json — permissions.deny block
# =====================================================================
test_generate_settings_permissions() {
  local out
  out=$(generate_settings_json session-start marker-guard)

  assert_contains "$out" "permissions" "generate: permissions key present"

  # Deny rule for markers present
  local has_rule
  has_rule=$(echo "$out" | jq -r '.permissions.deny | index("Edit(//tmp/.claude_*)") // empty' 2>/dev/null || echo "")
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -n "$has_rule" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILURES="${FAILURES}  FAIL: generate: deny contains Edit(//tmp/.claude_*)\n    got: '$(echo "$out" | jq -c '.permissions.deny')'\n"
  fi

  # Config deny rule present
  local has_config
  has_config=$(echo "$out" | jq -r '.permissions.deny | index("Edit(/.claude/settings.json)") // empty' 2>/dev/null || echo "")
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -n "$has_config" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILURES="${FAILURES}  FAIL: generate: deny contains Edit(/.claude/settings.json)\n"
  fi

  # No Write(path) rule: Claude Code never consults one (Edit(path) covers Write) and
  # warns about each at startup (dogfood run 1)
  assert_equals "0" "$(echo "$out" | jq '[.permissions.deny[] | select(startswith("Write("))] | length')" \
    "generate: no Write(path) deny rule"
}

# =====================================================================
# TEST 12b: merge_hooks_into_settings — drops the framework's legacy Write(path)
# rules from an older install, keeps the user's own
# =====================================================================
test_merge_drops_legacy_write_rules() {
  local tmp settings_json
  tmp=$(mktemp -d)
  echo '{"permissions":{"deny":["Write(/.claude/settings.json)","Write(//tmp/.claude_*)","Write(/secrets/**)","WebFetch"]}}' > "$tmp/settings.json"
  settings_json=$(generate_settings_json session-start marker-guard)
  merge_hooks_into_settings "$settings_json" "$tmp/settings.json"
  assert_equals "0" "$(jq '[.permissions.deny[] | select(. == "Write(/.claude/settings.json)" or . == "Write(//tmp/.claude_*)")] | length' "$tmp/settings.json")" \
    "merge: the framework's legacy Write rules are removed"
  assert_equals "1" "$(jq '[.permissions.deny[] | select(. == "Write(/secrets/**)")] | length' "$tmp/settings.json")" \
    "merge: a user's own Write rule is kept"
  assert_equals "1" "$(jq '[.permissions.deny[] | select(. == "Edit(/.claude/settings.json)")] | length' "$tmp/settings.json")" \
    "merge: the Edit twin is present"
  rm -rf "$tmp"
}

# =====================================================================
# TEST 13: merge_hooks_into_settings — preserves user deny rules
# =====================================================================
test_merge_preserves_user_deny() {
  local tmp settings_json
  tmp=$(mktemp -d)
  # Seed an existing settings file with a user-defined deny rule and other key
  echo '{"model":"opus","permissions":{"deny":["WebFetch"]}}' > "$tmp/settings.json"

  settings_json=$(generate_settings_json session-start marker-guard)
  merge_hooks_into_settings "$settings_json" "$tmp/settings.json"

  # User rule preserved
  local has_web
  has_web=$(jq -r '.permissions.deny | index("WebFetch") // empty' "$tmp/settings.json" 2>/dev/null || echo "")
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -n "$has_web" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILURES="${FAILURES}  FAIL: merge: preserves user deny rule WebFetch\n"
  fi

  # Framework rule also merged in
  local has_marker
  has_marker=$(jq -r '.permissions.deny | index("Edit(//tmp/.claude_*)") // empty' "$tmp/settings.json" 2>/dev/null || echo "")
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -n "$has_marker" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILURES="${FAILURES}  FAIL: merge: adds framework deny rule Edit(//tmp/.claude_*)\n"
  fi

  # Other user keys preserved
  local model
  model=$(jq -r '.model' "$tmp/settings.json" 2>/dev/null || echo "")
  assert_equals "opus" "$model" "merge: preserves unrelated user key"

  # Hooks merged
  local has_hooks
  has_hooks=$(jq -r '.hooks | keys | length' "$tmp/settings.json" 2>/dev/null || echo "0")
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "$has_hooks" -gt 0 ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILURES="${FAILURES}  FAIL: merge: hooks object merged in\n"
  fi

  rm -rf "$tmp"
}

# --- Run all tests ---
echo "install-matrix (simulated installs)"
test_fresh_no_deps
test_fresh_superpowers_only
test_fresh_context7_only
test_fresh_both_deps
test_prepopulate_no_deps
test_prepopulate_superpowers_only
test_prepopulate_context7_only
test_prepopulate_both_deps
test_skip_plugin_check
test_context7_declined
test_generate_settings_matchers
test_generate_settings_permissions
test_merge_drops_legacy_write_rules
test_merge_preserves_user_deny
run_tests
