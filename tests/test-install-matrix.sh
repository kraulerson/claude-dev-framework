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
run_tests
