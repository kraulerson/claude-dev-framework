#!/usr/bin/env bash
# test-verification-gate.sh — Tests for verification-gate pre-commit hook
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/verification-gate.sh"

# --- Test: non-commit commands pass ---
test_non_commit_passes() {
  setup_test_project
  INPUT='{"tool_input":{"command":"git status"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "non-commit should pass"
  teardown_test_project
}

# --- Test: commit passes when no gates configured ---
test_no_gates_passes() {
  setup_test_project
  INPUT='{"tool_input":{"command":"git commit -m \"test\""}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "should pass with no gates configured"
  teardown_test_project
}

# --- Test: commit passes when gate command succeeds ---
test_passing_gate() {
  setup_test_project
  local manifest="$TEST_DIR/.claude/manifest.json"
  cat > "$manifest" << 'MANIFEST'
{
  "frameworkVersion": "4.0.0",
  "profile": "web-app",
  "activeRules": [],
  "activeHooks": [],
  "projectConfig": {
    "_base": {
      "sourceExtensions": [".js"],
      "verificationGates": [
        {
          "name": "always-pass",
          "description": "Test gate that always passes",
          "command": "echo ok",
          "failOn": "exit_code",
          "enabled": true,
          "profile": "_base"
        }
      ]
    },
    "branches": []
  },
  "discovery": {}
}
MANIFEST
  INPUT='{"tool_input":{"command":"git commit -m \"test\""}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "should pass when gate succeeds"
  teardown_test_project
}

# --- Test: commit blocks when gate exit code fails ---
test_failing_gate_exit_code() {
  setup_test_project
  local manifest="$TEST_DIR/.claude/manifest.json"
  cat > "$manifest" << 'MANIFEST'
{
  "frameworkVersion": "4.0.0",
  "profile": "web-app",
  "activeRules": [],
  "activeHooks": [],
  "projectConfig": {
    "_base": {
      "verificationGates": [
        {
          "name": "always-fail",
          "description": "Test gate that always fails",
          "command": "exit 1",
          "failOn": "exit_code",
          "enabled": true,
          "profile": "_base"
        }
      ]
    },
    "branches": []
  },
  "discovery": {}
}
MANIFEST
  INPUT='{"tool_input":{"command":"git commit -m \"test\""}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  RESULT=$(run_hook "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block when gate fails"
  assert_contains "$RESULT" "BLOCKED" "should say BLOCKED"
  assert_contains "$RESULT" "Verification Zone" "should mention Verification Zone"
  assert_contains "$RESULT" "always-fail" "should name failing gate"
  teardown_test_project
}

# --- Test: commit blocks when gate stderr matches pattern ---
test_failing_gate_stderr() {
  setup_test_project
  local manifest="$TEST_DIR/.claude/manifest.json"
  cat > "$manifest" << 'MANIFEST'
{
  "frameworkVersion": "4.0.0",
  "profile": "web-app",
  "activeRules": [],
  "activeHooks": [],
  "projectConfig": {
    "_base": {
      "verificationGates": [
        {
          "name": "lint-check",
          "description": "Check for warnings",
          "command": "echo 'warning: unused var' >&2; exit 0",
          "failOn": "stderr",
          "failPattern": "warning|error",
          "enabled": true,
          "profile": "_base"
        }
      ]
    },
    "branches": []
  },
  "discovery": {}
}
MANIFEST
  INPUT='{"tool_input":{"command":"git commit -m \"test\""}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  RESULT=$(run_hook "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block when stderr matches pattern"
  assert_contains "$RESULT" "lint-check" "should name the failing gate"
  teardown_test_project
}

# --- Test: disabled gate is skipped ---
test_disabled_gate_skipped() {
  setup_test_project
  local manifest="$TEST_DIR/.claude/manifest.json"
  cat > "$manifest" << 'MANIFEST'
{
  "frameworkVersion": "4.0.0",
  "profile": "web-app",
  "activeRules": [],
  "activeHooks": [],
  "projectConfig": {
    "_base": {
      "verificationGates": [
        {
          "name": "disabled-gate",
          "description": "This gate is disabled",
          "command": "exit 1",
          "failOn": "exit_code",
          "enabled": false,
          "profile": "_base"
        }
      ]
    },
    "branches": []
  },
  "discovery": {}
}
MANIFEST
  INPUT='{"tool_input":{"command":"git commit -m \"test\""}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "disabled gate should be skipped"
  teardown_test_project
}

# --- Test: missing command skips with warning ---
test_missing_command_skips() {
  setup_test_project
  local manifest="$TEST_DIR/.claude/manifest.json"
  cat > "$manifest" << 'MANIFEST'
{
  "frameworkVersion": "4.0.0",
  "profile": "web-app",
  "activeRules": [],
  "activeHooks": [],
  "projectConfig": {
    "_base": {
      "verificationGates": [
        {
          "name": "missing-tool",
          "description": "Uses a tool that does not exist",
          "command": "nonexistent_tool_xyz123 --check",
          "failOn": "exit_code",
          "enabled": true,
          "profile": "_base"
        }
      ]
    },
    "branches": []
  },
  "discovery": {}
}
MANIFEST
  INPUT='{"tool_input":{"command":"git commit -m \"test\""}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "missing command should skip, not block"
  teardown_test_project
}

# --- Run all tests ---
echo "verification-gate.sh"
test_non_commit_passes
test_no_gates_passes
test_passing_gate
test_failing_gate_exit_code
test_failing_gate_stderr
test_disabled_gate_skipped
test_missing_command_skips
run_tests
