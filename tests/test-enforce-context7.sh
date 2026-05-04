#!/usr/bin/env bash
# test-enforce-context7.sh — Tests for enforce-context7 hook
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/enforce-context7.sh"

# --- Test: doc file passes regardless ---
test_doc_file_passes() {
  setup_test_project
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"README.md","content":"# Hello\nimport react"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "doc file should pass"
  teardown_test_project
}

# --- Test: source file with no imports passes ---
test_no_imports_passes() {
  setup_test_project
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"app.js","content":"const x = 1;\nconsole.log(x);"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "source with no imports should pass"
  teardown_test_project
}

# --- Test: source file with stdlib import passes ---
test_stdlib_import_passes() {
  setup_test_project
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"app.js","content":"import fs from '\''fs'\'';\nfs.readFileSync('\''x'\'');"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "stdlib import should pass"
  teardown_test_project
}

# --- Test: source file with relative import passes ---
test_relative_import_passes() {
  setup_test_project
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"app.js","content":"import { helper } from '\''./utils'\'';"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "relative import should pass"
  teardown_test_project
}

# --- Test: source file with unknown third-party import blocks ---
test_unknown_library_blocks() {
  setup_test_project
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"app.js","content":"import express from '\''express'\'';\nconst app = express();"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  RESULT=$(run_hook "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "unknown library should block"
  assert_contains "$RESULT" "BLOCKED" "should say BLOCKED"
  assert_contains "$RESULT" "Implementation Zone" "should mention Implementation Zone"
  assert_contains "$RESULT" "express" "should name the missing library"
  teardown_test_project
}

# --- Test: source file with researched library passes ---
test_researched_library_passes() {
  setup_test_project
  touch "/tmp/.claude_c7_${TEST_HASH}_express"
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"app.js","content":"import express from '\''express'\'';\nconst app = express();"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "researched library should pass"
  teardown_test_project
}

# --- Test: Python from-import detected ---
test_python_from_import() {
  setup_test_project
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"app.py","content":"from flask import Flask\napp = Flask(__name__)"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  RESULT=$(run_hook "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "Python from-import should block for unknown lib"
  assert_contains "$RESULT" "flask" "should name flask"
  teardown_test_project
}

# --- Test: Python __future__ import passes (stdlib compiler directive) ---
test_python_future_import_passes() {
  setup_test_project
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"app.py","content":"from __future__ import annotations\n\ndef f() -> int:\n    return 1\n"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "from __future__ import should pass as stdlib"
  teardown_test_project
}

# --- Test: Edit tool reads new_string not file_path content ---
test_edit_reads_new_string() {
  setup_test_project
  INPUT='{"tool_name":"Edit","tool_input":{"file_path":"app.js","old_string":"// placeholder","new_string":"import lodash from '\''lodash'\'';\n_.map([1,2],x=>x);"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  RESULT=$(run_hook "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "Edit with new import should block"
  assert_contains "$RESULT" "lodash" "should detect lodash in new_string"
  teardown_test_project
}

# --- Test: Context7 degraded flag skips enforcement ---
test_degraded_skips() {
  setup_test_project
  touch "/tmp/.claude_c7_degraded_${TEST_HASH}"
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"app.js","content":"import express from '\''express'\'';\nconst app = express();"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "should pass when Context7 is degraded"
  teardown_test_project
}

# --- Test: test file passes even with third-party imports ---
test_test_file_with_imports_passes() {
  setup_test_project
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"tests/test_app.js","content":"import { expect } from '\''chai'\'';\nexpect(1).to.equal(1);"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "test file should pass even with third-party imports"
  teardown_test_project
}

# --- Run all tests ---
echo "enforce-context7.sh"
test_doc_file_passes
test_no_imports_passes
test_stdlib_import_passes
test_relative_import_passes
test_unknown_library_blocks
test_researched_library_passes
test_python_from_import
test_python_future_import_passes
test_edit_reads_new_string
test_degraded_skips
test_test_file_with_imports_passes
run_tests
