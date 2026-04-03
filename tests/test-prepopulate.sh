#!/usr/bin/env bash
# test-prepopulate.sh — Tests for --prepopulate flag in init.sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

INIT_SCRIPT="$(cd "$SCRIPT_DIR/.." && pwd)/scripts/init.sh"

# Helper: create a temp git repo suitable for init.sh
setup_init_project() {
  TEST_DIR=$(mktemp -d)
  git -C "$TEST_DIR" init --quiet
  git -C "$TEST_DIR" config user.email "test@test.com"
  git -C "$TEST_DIR" config user.name "Test"
  echo "init" > "$TEST_DIR/README.md"
  git -C "$TEST_DIR" add README.md
  git -C "$TEST_DIR" commit -m "Initial commit" --quiet
  # Set a different remote so init.sh doesn't think we're in the framework repo
  git -C "$TEST_DIR" remote add origin "https://github.com/test/test-project.git" 2>/dev/null || true
  # Remove sample hooks so init.sh doesn't enter migration mode
  rm -f "$TEST_DIR"/.git/hooks/pre-*
  # Create a package.json so detect-profile.sh auto-detects web-api
  echo '{"name":"test","dependencies":{"express":"^4.0.0"}}' > "$TEST_DIR/package.json"
  git -C "$TEST_DIR" add package.json
  git -C "$TEST_DIR" commit -m "Add package.json" --quiet
}

teardown_init_project() {
  [ -n "$TEST_DIR" ] && rm -rf "$TEST_DIR"
  unset TEST_DIR
}

# --- Test: valid prepopulate JSON is used ---
test_valid_prepopulate() {
  setup_init_project
  cat > "$TEST_DIR/discovery.json" << 'JSON'
{
  "branch:main": {
    "purpose": "main development branch",
    "devOS": "Darwin",
    "targetPlatform": "web",
    "buildTools": "typescript"
  },
  "futurePlatforms": null,
  "discoveryDate": "2026-04-03",
  "lastReviewDate": "2026-04-03"
}
JSON
  # Pipe "y" for detect-profile.sh prompt (discovery is skipped by prepopulate)
  OUTPUT=$(cd "$TEST_DIR" && echo "y" | bash "$INIT_SCRIPT" --skip-plugin-check --prepopulate "$TEST_DIR/discovery.json" 2>&1)
  assert_contains "$OUTPUT" "Using pre-populated discovery from" "should log prepopulate message"
  assert_contains "$OUTPUT" "Installation Complete" "should complete installation"

  # Verify discovery data made it into manifest
  DISC_PURPOSE=$(jq -r '.discovery["branch:main"].purpose' "$TEST_DIR/.claude/manifest.json" 2>/dev/null || echo "")
  assert_equals "main development branch" "$DISC_PURPOSE" "manifest should contain prepopulated discovery"

  teardown_init_project
}

# --- Test: missing file falls back with warning ---
test_missing_file_warns() {
  setup_init_project
  # Pipe "y" for profile + empty lines for fallback discovery interview
  OUTPUT=$(cd "$TEST_DIR" && printf 'y\n\n\n\nn\n\n\n' | bash "$INIT_SCRIPT" --skip-plugin-check --prepopulate "/nonexistent/file.json" 2>&1)
  assert_contains "$OUTPUT" "WARNING" "should warn about missing file"
  assert_contains "$OUTPUT" "not found" "should say file not found"
  teardown_init_project
}

# --- Test: invalid JSON falls back with warning ---
test_invalid_json_warns() {
  setup_init_project
  echo "not json at all {{{" > "$TEST_DIR/bad.json"
  OUTPUT=$(cd "$TEST_DIR" && printf 'y\n\n\n\nn\n\n\n' | bash "$INIT_SCRIPT" --skip-plugin-check --prepopulate "$TEST_DIR/bad.json" 2>&1)
  assert_contains "$OUTPUT" "WARNING" "should warn about invalid JSON"
  assert_contains "$OUTPUT" "not valid JSON" "should say not valid JSON"
  teardown_init_project
}

# --- Test: JSON without branch key falls back with warning ---
test_no_branch_key_warns() {
  setup_init_project
  cat > "$TEST_DIR/nobranch.json" << 'JSON'
{
  "futurePlatforms": null,
  "discoveryDate": "2026-04-03"
}
JSON
  OUTPUT=$(cd "$TEST_DIR" && printf 'y\n\n\n\nn\n\n\n' | bash "$INIT_SCRIPT" --skip-plugin-check --prepopulate "$TEST_DIR/nobranch.json" 2>&1)
  assert_contains "$OUTPUT" "WARNING" "should warn about missing branch key"
  assert_contains "$OUTPUT" "no branch" "should mention no branch key"
  teardown_init_project
}

# --- Test: prepopulate takes priority over reconfigure ---
test_prepopulate_overrides_reconfigure() {
  setup_init_project
  # First do a normal install so reconfigure has something to work with
  cd "$TEST_DIR" && printf 'y\n\n\n\nn\n\n\n' | bash "$INIT_SCRIPT" --skip-plugin-check 2>&1 >/dev/null

  cat > "$TEST_DIR/discovery.json" << 'JSON'
{
  "branch:main": {
    "purpose": "overridden by prepopulate",
    "devOS": "Linux",
    "targetPlatform": "api",
    "buildTools": "go"
  },
  "discoveryDate": "2026-04-03",
  "lastReviewDate": "2026-04-03"
}
JSON
  # "y" for migration proceed, "y" for profile detection (discovery skipped by prepopulate)
  OUTPUT=$(cd "$TEST_DIR" && printf 'y\ny\n' | bash "$INIT_SCRIPT" --skip-plugin-check --reconfigure --prepopulate "$TEST_DIR/discovery.json" 2>&1)
  assert_contains "$OUTPUT" "Using pre-populated discovery from" "prepopulate should take priority over reconfigure"

  DISC_PURPOSE=$(jq -r '.discovery["branch:main"].purpose' "$TEST_DIR/.claude/manifest.json" 2>/dev/null || echo "")
  assert_equals "overridden by prepopulate" "$DISC_PURPOSE" "prepopulated data should be in manifest"

  teardown_init_project
}

# --- Run all tests ---
echo "init.sh --prepopulate"
test_valid_prepopulate
test_missing_file_warns
test_invalid_json_warns
test_no_branch_key_warns
test_prepopulate_overrides_reconfigure
run_tests
