#!/usr/bin/env bash
# setup.sh — Shared test setup/teardown for framework hook tests

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/hooks"

# Tests run against this checkout, never the operator's live install (#12): HOME is a
# throwaway directory whose .claude-dev-framework is a copy of the tree under test, so
# init.sh reads this tree's assets and session-start.sh's `git fetch` there has no
# remote to reach. A copy rather than a link, so nothing a test runs can write to the
# checkout or fetch in its repository.
TEST_LAB_HOME=$(mktemp -d)
mkdir -p "$TEST_LAB_HOME/.claude-dev-framework"
cp -R "$HOOK_DIR/../hooks" "$HOOK_DIR/../rules" "$HOOK_DIR/../gates" "$HOOK_DIR/../profiles" \
      "$HOOK_DIR/../scripts" "$HOOK_DIR/../migrations" "$HOOK_DIR/../FRAMEWORK_VERSION" \
      "$TEST_LAB_HOME/.claude-dev-framework/"
git init --quiet "$TEST_LAB_HOME/.claude-dev-framework"
export HOME="$TEST_LAB_HOME"
# Hermetic: when the suite itself runs under Claude Code, CLAUDECODE=1 is inherited, and
# mark-evaluated.sh refuses under it by design. Tests that need it set it themselves.
unset CLAUDECODE
trap 'rm -rf "$TEST_LAB_HOME"' EXIT

# Create a temporary git repo with a basic manifest for testing
setup_test_project() {
  TEST_DIR=$(mktemp -d)
  mkdir -p "$TEST_DIR/.claude/framework/hooks"

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
  rm -f /tmp/.claude_stop_errors_hash_${TEST_HASH}_*
  rm -f "/tmp/.claude_approval_shown_${TEST_HASH}" "/tmp/.claude_eval_log_${TEST_HASH}"

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

# mark-evaluated.sh, the user's override, asks for a code typed at the controlling
# terminal. These run it the two ways the tests need, whether or not the suite itself
# has a terminal (run from one, a bare call would wait on it).
# run_without_ctty CMD... — in a new session with no controlling terminal, as the agent's
# Bash tool runs: /dev/tty cannot be opened.
run_without_ctty() {
  perl -MPOSIX -e 'POSIX::setsid() >= 0 or die "setsid: $!\n"; exec @ARGV or die "exec: $!\n"' "$@"
}
# mark_evaluated_at_terminal REASON [ANSWER] — as the user at a terminal: under a
# pseudo-terminal (expect), from TEST_DIR, typing back the code it shows, or ANSWER
# instead. Prints the script's output, then rc=N (rc=timeout if it never finished).
mark_evaluated_at_terminal() {
  (cd "$TEST_DIR" && MARK="$HOOK_DIR/mark-evaluated.sh" REASON="$1" ANSWER="${2:-}" expect -c '
    set timeout 20
    spawn -noecho env -u CLAUDECODE bash $env(MARK) $env(REASON)
    expect {
      -re {Type ([0-9]+) } { set code $expect_out(1,string) }
      eof { catch wait r; puts "\nrc=[lindex $r 3]"; exit 0 }
      timeout { puts "\nrc=timeout"; exit 0 }
    }
    if {$env(ANSWER) ne ""} { set code $env(ANSWER) }
    send "$code\r"
    expect { eof {} timeout { puts "\nrc=timeout"; exit 0 } }
    catch wait r
    puts "\nrc=[lindex $r 3]"')
}

run_hook_exit_code() {
  local hook="$1" input="$2"
  (cd "$TEST_DIR" && echo "$input" | bash "$hook" >/dev/null 2>&1; echo $?)
}
