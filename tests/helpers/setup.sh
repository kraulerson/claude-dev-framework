#!/usr/bin/env bash
# setup.sh — Shared test setup/teardown for framework hook tests

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/hooks"

# Create a temporary git repo with a basic manifest for testing
setup_test_project() {
  TEST_DIR=$(mktemp -d)
  mkdir -p "$TEST_DIR/.claude"

  # Initialize git repo with an initial commit
  git -C "$TEST_DIR" init --quiet
  git -C "$TEST_DIR" config user.email "test@test.com"
  git -C "$TEST_DIR" config user.name "Test"
  echo "init" > "$TEST_DIR/README.md"
  git -C "$TEST_DIR" add README.md
  git -C "$TEST_DIR" commit -m "Initial commit" --quiet

  # Write a minimal manifest
  cat > "$TEST_DIR/.claude/manifest.json" << 'MANIFEST'
{
  "frameworkVersion": "1.1.0",
  "profile": "mobile-app",
  "activeRules": ["evaluate-before-implement", "test-per-bugfix"],
  "activeHooks": ["enforce-evaluate", "stop-checklist", "marker-tracker"],
  "projectConfig": {
    "_base": {
      "sourceExtensions": [".py", ".js", ".ts", ".kt", ".swift"],
      "protectedBranches": ["main"]
    },
    "branches": []
  },
  "discovery": {}
}
MANIFEST

  export CLAUDE_PROJECT_DIR="$TEST_DIR"
  export TEST_HASH
  TEST_HASH=$(echo -n "$TEST_DIR" | shasum -a 256 | cut -c1-12)
}

# Clean up temp directory and markers
teardown_test_project() {
  # Clean up any marker files this test created
  rm -f "/tmp/.claude_evaluated_${TEST_HASH}"
  rm -f "/tmp/.claude_superpowers_${TEST_HASH}"
  rm -f "/tmp/.claude_session_start_${TEST_HASH}"
  rm -f "/tmp/.claude_changelog_synced_${TEST_HASH}"
  rm -f "/tmp/.claude_plan_closed_${TEST_HASH}"
  rm -f "/tmp/.claude_plan_active_${TEST_HASH}"
  rm -f "/tmp/.claude_has_plan_${TEST_HASH}"
  rm -f "/tmp/.claude_c7_degraded_${TEST_HASH}"
  rm -f /tmp/.claude_c7_${TEST_HASH}_*

  # Remove temp directory and remote
  [ -n "$TEST_DIR" ] && rm -rf "$TEST_DIR" "${TEST_DIR}_remote.git"
  unset CLAUDE_PROJECT_DIR TEST_DIR TEST_HASH
}

# Helper: add and commit a source file in the test repo
commit_source_file() {
  local filename="$1" message="$2"
  echo "// code" > "$TEST_DIR/$filename"
  git -C "$TEST_DIR" add "$filename"
  git -C "$TEST_DIR" commit -m "$message" --quiet
}

# Helper: add and commit a source file + test file
commit_source_with_test() {
  local filename="$1" testfile="$2" message="$3"
  echo "// code" > "$TEST_DIR/$filename"
  echo "// test" > "$TEST_DIR/$testfile"
  git -C "$TEST_DIR" add "$filename" "$testfile"
  git -C "$TEST_DIR" commit -m "$message" --quiet
}

# Helper: set up a bare remote and push, establishing upstream tracking
setup_remote() {
  local remote_dir="${TEST_DIR}_remote.git"
  git clone --bare "$TEST_DIR" "$remote_dir" --quiet 2>/dev/null
  git -C "$TEST_DIR" remote add origin "$remote_dir" 2>/dev/null || git -C "$TEST_DIR" remote set-url origin "$remote_dir"
  local branch
  branch=$(git -C "$TEST_DIR" rev-parse --abbrev-ref HEAD)
  git -C "$TEST_DIR" push -u origin "$branch" --quiet 2>/dev/null
}

# Helper: run a hook from within the test project directory
# Usage: RESULT=$(run_hook "$HOOK" "$JSON_INPUT")
run_hook() {
  local hook="$1" input="$2"
  (cd "$TEST_DIR" && echo "$input" | bash "$hook" 2>&1)
}

run_hook_exit_code() {
  local hook="$1" input="$2"
  (cd "$TEST_DIR" && echo "$input" | bash "$hook" >/dev/null 2>&1; echo $?)
}
