# v4.0.0 Enforcement Zones Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade claude-dev-framework from v3.0.0 to v4.0.0, introducing enforcement zones, plan-tracking gate, Context7 enforcement, configurable verification gates, and a rewritten session start.

**Architecture:** Five enforcement zones (Discovery, Design, Planning, Implementation, Verification) organize existing and new hooks into workflow stages. New hooks add plan-tracking (blocks edits until a task is in_progress), Context7 enforcement (blocks edits using unresearched libraries), and verification gates (configurable pre-commit quality checks). Session start is rewritten to be terse and zone-based with multi-phase re-injection.

**Tech Stack:** Bash (hooks), jq (JSON processing), Claude Code hook API (PreToolUse/PostToolUse/SessionStart/Stop), Context7 MCP (npx @upstash/context7-mcp), Playwright (optional visual auditor gate)

---

## File Map

### New Files

| File | Responsibility |
|------|---------------|
| `hooks/enforce-plan-tracking.sh` | PreToolUse (Write\|Edit) — blocks source edits until a plan task is in_progress |
| `hooks/plan-tracker.sh` | PostToolUse — watches TaskUpdate calls, creates/clears plan_active marker |
| `hooks/enforce-context7.sh` | PreToolUse (Write\|Edit) — blocks source edits using unresearched third-party libraries |
| `hooks/context7-tracker.sh` | PostToolUse — watches Context7 MCP calls, creates per-library markers |
| `hooks/verification-gate.sh` | PreToolUse (Bash) — runs configurable verification gates before git commit |
| `hooks/known-stdlib.txt` | Data file — standard library module names per language, one per line as `lang:module` |
| `gates/visual-auditor.sh` | Playwright-based screenshot gate for web-app profile |
| `tests/test-enforce-plan-tracking.sh` | Tests for plan-tracking enforcement |
| `tests/test-plan-tracker.sh` | Tests for plan-tracker marker creation |
| `tests/test-enforce-context7.sh` | Tests for Context7 enforcement |
| `tests/test-context7-tracker.sh` | Tests for Context7 tracker marker creation |
| `tests/test-verification-gate.sh` | Tests for verification gate runner |
| `tests/test-session-start-v4.sh` | Tests for rewritten session start |
| `migrations/v4.sh` | Migration script from v3 to v4 |

### Modified Files

| File | What Changes |
|------|-------------|
| `hooks/session-start.sh` | Full rewrite — zone activation model, Context7 install check, terse output |
| `hooks/skill-tracker.sh` | Also creates `.claude_has_plan_{hash}` on `writing-plans` skill invoke |
| `hooks/sync-tracker.sh` | Also clears `.claude_plan_active_{hash}` after commit |
| `hooks/marker-guard.sh` | Extended regex to include `plan_active\|has_plan\|c7` marker types |
| `hooks/stop-checklist.sh` | Updated advisory messages to reference zones |
| `hooks/_helpers.sh` | Add `check_context7()` helper function |
| `scripts/_shared.sh` | Add new hook mappings to `generate_settings_json()` |
| `profiles/_base.yml` | Add new hooks: enforce-plan-tracking, plan-tracker, enforce-context7, context7-tracker, verification-gate |
| `profiles/web-app.yml` | Add visual-auditor gate suggestion |
| `templates/manifest.json.template` | Add `verificationGates` array to projectConfig |
| `templates/settings.json.template` | Add new hook entries |
| `tests/helpers/setup.sh` | Add cleanup for new marker types |
| `tests/test-integration-workflow.sh` | Add v4 full lifecycle test |
| `tests/test-marker-persistence.sh` | Add new marker types |
| `tests/test-spaces-in-path.sh` | Add new markers with spaces |
| `FRAMEWORK_VERSION` | Bump to 4.0.0 |

---

### Task 1: Update Test Helpers and Framework Version

**Files:**
- Modify: `tests/helpers/setup.sh:43-49` (teardown_test_project)
- Modify: `FRAMEWORK_VERSION:1`

- [ ] **Step 1: Update teardown to clean new marker types**

In `tests/helpers/setup.sh`, update the `teardown_test_project` function:

```bash
teardown_test_project() {
  # Clean up any marker files this test created
  rm -f "/tmp/.claude_evaluated_${TEST_HASH}"
  rm -f "/tmp/.claude_superpowers_${TEST_HASH}"
  rm -f "/tmp/.claude_session_start_${TEST_HASH}"
  rm -f "/tmp/.claude_changelog_synced_${TEST_HASH}"
  rm -f "/tmp/.claude_plan_closed_${TEST_HASH}"
  rm -f "/tmp/.claude_plan_active_${TEST_HASH}"
  rm -f "/tmp/.claude_has_plan_${TEST_HASH}"
  rm -f /tmp/.claude_c7_${TEST_HASH}_*

  # Remove temp directory and remote
  [ -n "$TEST_DIR" ] && rm -rf "$TEST_DIR" "${TEST_DIR}_remote.git"
  unset CLAUDE_PROJECT_DIR TEST_DIR TEST_HASH
}
```

- [ ] **Step 2: Bump framework version**

Change `FRAMEWORK_VERSION` content to:

```
4.0.0
```

- [ ] **Step 3: Run existing tests to confirm no breakage**

Run: `bash tests/run-tests.sh`
Expected: All 71+ existing tests pass (new markers in teardown don't affect existing tests).

- [ ] **Step 4: Commit**

```bash
git add tests/helpers/setup.sh FRAMEWORK_VERSION
git commit -m "chore: bump to v4.0.0 and update test teardown for new marker types"
```

---

### Task 2: Update marker-guard.sh

**Files:**
- Modify: `hooks/marker-guard.sh:14`

- [ ] **Step 1: Write the failing test**

Create `tests/test-marker-guard-v4.sh`:

```bash
#!/usr/bin/env bash
# test-marker-guard-v4.sh — Tests for v4 marker types in marker-guard
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/marker-guard.sh"

# --- Test: blocks manual plan_active marker creation ---
test_blocks_plan_active() {
  setup_test_project
  INPUT='{"tool_input":{"command":"touch /tmp/.claude_plan_active_abc123"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block plan_active marker creation"
  teardown_test_project
}

# --- Test: blocks manual has_plan marker creation ---
test_blocks_has_plan() {
  setup_test_project
  INPUT='{"tool_input":{"command":"touch /tmp/.claude_has_plan_abc123"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block has_plan marker creation"
  teardown_test_project
}

# --- Test: blocks manual c7 marker creation ---
test_blocks_c7() {
  setup_test_project
  INPUT='{"tool_input":{"command":"touch /tmp/.claude_c7_abc123_react"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block c7 marker creation"
  teardown_test_project
}

# --- Test: allows non-marker touch commands ---
test_allows_normal_touch() {
  setup_test_project
  INPUT='{"tool_input":{"command":"touch /tmp/myfile.txt"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "should allow normal touch commands"
  teardown_test_project
}

# --- Run all tests ---
echo "marker-guard.sh (v4 markers)"
test_blocks_plan_active
test_blocks_has_plan
test_blocks_c7
test_allows_normal_touch
run_tests
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-marker-guard-v4.sh`
Expected: FAIL — `plan_active`, `has_plan`, and `c7` markers are not in the current guard pattern.

- [ ] **Step 3: Update marker-guard.sh**

Replace the guard pattern in `hooks/marker-guard.sh` line 14:

```bash
if echo "$COMMAND" | grep -qE 'touch.*/tmp/\.claude_(superpowers|evaluated|plan_closed|plan_active|has_plan|skill_active|c7)_'; then
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-marker-guard-v4.sh`
Expected: All 4 tests pass.

- [ ] **Step 5: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass (existing marker-guard tests unaffected).

- [ ] **Step 6: Commit**

```bash
git add hooks/marker-guard.sh tests/test-marker-guard-v4.sh
git commit -m "feat: extend marker-guard to block v4 marker types (plan_active, has_plan, c7)"
```

---

### Task 3: Add _helpers.sh Context7 Check

**Files:**
- Modify: `hooks/_helpers.sh` (append after line 136)

- [ ] **Step 1: Add check_context7 function**

Append to `hooks/_helpers.sh`:

```bash

check_context7() {
  # Check if Context7 MCP server is registered in Claude Code
  local settings="$HOME/.claude/settings.json"
  [ ! -f "$settings" ] && return 1
  check_jq || return 1
  # Check both mcpServers key and common naming patterns
  jq -e '.mcpServers.context7 // .mcpServers["context7-mcp"] // empty' "$settings" >/dev/null 2>&1
}
```

- [ ] **Step 2: Verify manually**

Run: `source hooks/_helpers.sh && check_context7 && echo "found" || echo "not found"`
Expected: "found" if Context7 is installed, "not found" if not. Either is fine — confirms the function runs without error.

- [ ] **Step 3: Commit**

```bash
git add hooks/_helpers.sh
git commit -m "feat: add check_context7 helper for Context7 MCP detection"
```

---

### Task 4: Create Plan-Tracker Hook (Planning Zone)

**Files:**
- Create: `hooks/plan-tracker.sh`
- Test: `tests/test-plan-tracker.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test-plan-tracker.sh`:

```bash
#!/usr/bin/env bash
# test-plan-tracker.sh — Tests for plan-tracker PostToolUse hook
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/plan-tracker.sh"

# --- Test: creates plan_active marker on TaskUpdate to in_progress ---
test_creates_marker_on_in_progress() {
  setup_test_project
  INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"in_progress"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_plan_active_${TEST_HASH}" "should create plan_active marker"
  teardown_test_project
}

# --- Test: clears plan_active marker on TaskUpdate to completed ---
test_clears_marker_on_completed() {
  setup_test_project
  touch "/tmp/.claude_plan_active_${TEST_HASH}"
  INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_not_exists "/tmp/.claude_plan_active_${TEST_HASH}" "should clear plan_active marker on completed"
  teardown_test_project
}

# --- Test: ignores non-TaskUpdate tools ---
test_ignores_other_tools() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"echo hello"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_not_exists "/tmp/.claude_plan_active_${TEST_HASH}" "should not create marker for non-TaskUpdate"
  teardown_test_project
}

# --- Test: ignores TaskUpdate without status change ---
test_ignores_no_status() {
  setup_test_project
  INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","subject":"New name"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_not_exists "/tmp/.claude_plan_active_${TEST_HASH}" "should not create marker for TaskUpdate without status"
  teardown_test_project
}

# --- Test: does not create marker on TaskUpdate to pending ---
test_ignores_pending() {
  setup_test_project
  INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"pending"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_not_exists "/tmp/.claude_plan_active_${TEST_HASH}" "should not create marker for pending status"
  teardown_test_project
}

# --- Run all tests ---
echo "plan-tracker.sh"
test_creates_marker_on_in_progress
test_clears_marker_on_completed
test_ignores_other_tools
test_ignores_no_status
test_ignores_pending
run_tests
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-plan-tracker.sh`
Expected: FAIL — `hooks/plan-tracker.sh` does not exist yet.

- [ ] **Step 3: Create plan-tracker.sh**

Create `hooks/plan-tracker.sh`:

```bash
#!/usr/bin/env bash
# plan-tracker.sh — PostToolUse hook for Planning Zone
# Watches TaskUpdate calls to manage plan_active marker.
# Creates marker when a task moves to in_progress.
# Clears marker when a task moves to completed (forces re-engagement).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 0

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")

# Only act on TaskUpdate calls
[ "$TOOL" = "TaskUpdate" ] || exit 0

HASH=$(get_project_hash)
STATUS=$(echo "$INPUT" | jq -r '.tool_input.status // empty' 2>/dev/null || echo "")

case "$STATUS" in
  in_progress)
    touch "/tmp/.claude_plan_active_${HASH}"
    ;;
  completed)
    rm -f "/tmp/.claude_plan_active_${HASH}"
    ;;
esac
exit 0
```

- [ ] **Step 4: Make executable and run test**

Run: `chmod +x hooks/plan-tracker.sh && bash tests/test-plan-tracker.sh`
Expected: All 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add hooks/plan-tracker.sh tests/test-plan-tracker.sh
git commit -m "feat: add plan-tracker hook — creates/clears plan_active marker on TaskUpdate"
```

---

### Task 5: Create Enforce-Plan-Tracking Hook (Planning Zone)

**Files:**
- Create: `hooks/enforce-plan-tracking.sh`
- Test: `tests/test-enforce-plan-tracking.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test-enforce-plan-tracking.sh`:

```bash
#!/usr/bin/env bash
# test-enforce-plan-tracking.sh — Tests for enforce-plan-tracking hook
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/enforce-plan-tracking.sh"

# --- Test: doc file passes regardless ---
test_doc_file_passes() {
  setup_test_project
  INPUT='{"tool_input":{"file_path":"README.md"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "doc file should pass"
  teardown_test_project
}

# --- Test: test file passes regardless ---
test_test_file_passes() {
  setup_test_project
  INPUT='{"tool_input":{"file_path":"tests/test_app.py"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "test file should pass"
  teardown_test_project
}

# --- Test: source file passes when no has_plan marker (zone not armed) ---
test_source_passes_without_plan() {
  setup_test_project
  INPUT='{"tool_input":{"file_path":"app.py"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "should pass when Planning Zone not armed"
  teardown_test_project
}

# --- Test: source file blocks when has_plan exists but no plan_active ---
test_blocks_without_plan_active() {
  setup_test_project
  touch "/tmp/.claude_has_plan_${TEST_HASH}"
  INPUT='{"tool_input":{"file_path":"app.py"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  RESULT=$(run_hook "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block when has_plan but no plan_active"
  assert_contains "$RESULT" "BLOCKED" "should say BLOCKED"
  assert_contains "$RESULT" "Planning Zone" "should mention Planning Zone"
  teardown_test_project
}

# --- Test: source file passes when both markers exist ---
test_passes_with_both_markers() {
  setup_test_project
  touch "/tmp/.claude_has_plan_${TEST_HASH}"
  touch "/tmp/.claude_plan_active_${TEST_HASH}"
  INPUT='{"tool_input":{"file_path":"app.py"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "should pass with both plan markers"
  teardown_test_project
}

# --- Test: config file passes regardless ---
test_config_file_passes() {
  setup_test_project
  touch "/tmp/.claude_has_plan_${TEST_HASH}"
  INPUT='{"tool_input":{"file_path":"config.json"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "config file should pass even with has_plan"
  teardown_test_project
}

# --- Run all tests ---
echo "enforce-plan-tracking.sh"
test_doc_file_passes
test_test_file_passes
test_source_passes_without_plan
test_blocks_without_plan_active
test_passes_with_both_markers
test_config_file_passes
run_tests
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-enforce-plan-tracking.sh`
Expected: FAIL — `hooks/enforce-plan-tracking.sh` does not exist yet.

- [ ] **Step 3: Create enforce-plan-tracking.sh**

Create `hooks/enforce-plan-tracking.sh`:

```bash
#!/usr/bin/env bash
# enforce-plan-tracking.sh — PreToolUse (Write|Edit) blocking hook for Planning Zone
# Blocks source file edits until a plan task is marked in_progress.
# Only active when writing-plans skill has been invoked (has_plan marker exists).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 1

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null || echo "")
[ -z "$FILE_PATH" ] && exit 0
is_doc_or_config "$FILE_PATH" && exit 0
is_test_file "$FILE_PATH" && exit 0
is_source_file "$FILE_PATH" || exit 0

HASH=$(get_project_hash)

# Planning Zone only arms when writing-plans has been invoked
[ -f "/tmp/.claude_has_plan_${HASH}" ] || exit 0

# Check for active plan task
[ -f "/tmp/.claude_plan_active_${HASH}" ] && exit 0

cat >&2 << 'MSG'
BLOCKED [Planning Zone] — No plan task is in_progress.

You have a written plan for this session. Before editing source files, mark the task you are working on as in_progress using TaskUpdate.

Do NOT edit source files without an active plan task.
Do NOT skip this because the change seems small.
Do NOT create the marker manually — it is created automatically when you update a task to in_progress.

COMPLIANCE REMINDER: Your obligation is compliance first, speed second. There is no task small enough to skip this requirement.
MSG
exit 2
```

- [ ] **Step 4: Make executable and run test**

Run: `chmod +x hooks/enforce-plan-tracking.sh && bash tests/test-enforce-plan-tracking.sh`
Expected: All 8 assertions pass (6 test functions, 2 extra assertions in test_blocks_without_plan_active).

- [ ] **Step 5: Commit**

```bash
git add hooks/enforce-plan-tracking.sh tests/test-enforce-plan-tracking.sh
git commit -m "feat: add enforce-plan-tracking hook — blocks edits until plan task is in_progress"
```

---

### Task 6: Create Context7 Tracker Hook (Implementation Zone)

**Files:**
- Create: `hooks/context7-tracker.sh`
- Test: `tests/test-context7-tracker.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test-context7-tracker.sh`:

```bash
#!/usr/bin/env bash
# test-context7-tracker.sh — Tests for context7-tracker PostToolUse hook
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/context7-tracker.sh"

# --- Test: creates marker on resolve-library-id call ---
test_creates_marker_on_resolve() {
  setup_test_project
  INPUT='{"tool_name":"mcp__context7__resolve-library-id","tool_input":{"libraryName":"react"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_c7_${TEST_HASH}_react" "should create c7 marker for react"
  teardown_test_project
}

# --- Test: creates marker on get-library-docs call ---
test_creates_marker_on_get_docs() {
  setup_test_project
  INPUT='{"tool_name":"mcp__context7__get-library-docs","tool_input":{"context7CompatibleLibraryID":"/facebook/react","topic":"hooks"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_c7_${TEST_HASH}_facebook-react" "should create c7 marker for facebook/react"
  teardown_test_project
}

# --- Test: normalizes scoped package names ---
test_normalizes_scoped_names() {
  setup_test_project
  INPUT='{"tool_name":"mcp__context7__resolve-library-id","tool_input":{"libraryName":"@anthropic-ai/sdk"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_c7_${TEST_HASH}_anthropic-ai-sdk" "should normalize scoped name"
  teardown_test_project
}

# --- Test: ignores non-Context7 tools ---
test_ignores_other_tools() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"echo hello"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  # No c7 markers should exist
  local count
  count=$(ls /tmp/.claude_c7_${TEST_HASH}_* 2>/dev/null | wc -l | xargs)
  assert_equals "0" "$count" "should not create markers for non-Context7 tools"
  teardown_test_project
}

# --- Test: ignores Skill tool (not Context7 MCP) ---
test_ignores_skill_tool() {
  setup_test_project
  INPUT='{"tool_name":"Skill","tool_input":{"skill":"superpowers:brainstorming"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  local count
  count=$(ls /tmp/.claude_c7_${TEST_HASH}_* 2>/dev/null | wc -l | xargs)
  assert_equals "0" "$count" "should not create markers for Skill tool"
  teardown_test_project
}

# --- Run all tests ---
echo "context7-tracker.sh"
test_creates_marker_on_resolve
test_creates_marker_on_get_docs
test_normalizes_scoped_names
test_ignores_other_tools
test_ignores_skill_tool
run_tests
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-context7-tracker.sh`
Expected: FAIL — `hooks/context7-tracker.sh` does not exist yet.

- [ ] **Step 3: Create context7-tracker.sh**

Create `hooks/context7-tracker.sh`:

```bash
#!/usr/bin/env bash
# context7-tracker.sh — PostToolUse hook for Implementation Zone
# Watches Context7 MCP tool calls and creates per-library markers.
# These markers are checked by enforce-context7.sh before source edits.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 0

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")

# Match Context7 MCP tool names (mcp__context7__resolve-library-id, mcp__context7__get-library-docs)
case "$TOOL" in
  mcp__context7__resolve-library-id|mcp__context7__resolve_library_id)
    LIB=$(echo "$INPUT" | jq -r '.tool_input.libraryName // empty' 2>/dev/null || echo "")
    ;;
  mcp__context7__get-library-docs|mcp__context7__get_library_docs)
    # Extract library name from context7CompatibleLibraryID (e.g., "/facebook/react")
    LIB=$(echo "$INPUT" | jq -r '.tool_input.context7CompatibleLibraryID // empty' 2>/dev/null || echo "")
    ;;
  *) exit 0 ;;
esac

[ -z "$LIB" ] && exit 0

HASH=$(get_project_hash)

# Normalize: lowercase, strip leading @/ characters, replace / with -
NORMALIZED=$(echo "$LIB" | tr '[:upper:]' '[:lower:]' | sed 's|^[@/]*||' | tr '/' '-')

touch "/tmp/.claude_c7_${HASH}_${NORMALIZED}"
exit 0
```

- [ ] **Step 4: Make executable and run test**

Run: `chmod +x hooks/context7-tracker.sh && bash tests/test-context7-tracker.sh`
Expected: All 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add hooks/context7-tracker.sh tests/test-context7-tracker.sh
git commit -m "feat: add context7-tracker hook — creates per-library markers on Context7 MCP calls"
```

---

### Task 7: Create known-stdlib.txt

**Files:**
- Create: `hooks/known-stdlib.txt`

- [ ] **Step 1: Create the standard library list**

Create `hooks/known-stdlib.txt`. Format: `language:module_name` — one per line. This covers the most common standard library modules that should never trigger Context7 enforcement.

```
# Standard library modules — these never trigger Context7 enforcement.
# Format: language:module_name
# Lines starting with # are comments.

# JavaScript/TypeScript built-ins (Node.js core modules)
js:fs
js:path
js:os
js:util
js:http
js:https
js:net
js:url
js:crypto
js:stream
js:events
js:child_process
js:cluster
js:buffer
js:assert
js:readline
js:zlib
js:querystring
js:dns
js:tls
js:vm
js:worker_threads
js:perf_hooks
js:async_hooks
js:timers
js:console
js:process
js:module
js:node:fs
js:node:path
js:node:os
js:node:util
js:node:http
js:node:https
js:node:net
js:node:url
js:node:crypto
js:node:stream
js:node:events
js:node:child_process
js:node:buffer
js:node:assert
js:node:readline
js:node:zlib
js:node:querystring
js:node:dns
js:node:tls
js:node:vm
js:node:worker_threads
js:node:test

# Python standard library
py:os
py:sys
py:json
py:re
py:math
py:datetime
py:collections
py:itertools
py:functools
py:pathlib
py:typing
py:abc
py:io
py:logging
py:unittest
py:subprocess
py:threading
py:multiprocessing
py:socket
py:http
py:urllib
py:hashlib
py:hmac
py:base64
py:copy
py:dataclasses
py:enum
py:contextlib
py:argparse
py:configparser
py:csv
py:sqlite3
py:xml
py:html
py:string
py:textwrap
py:struct
py:time
py:random
py:tempfile
py:shutil
py:glob
py:fnmatch
py:pprint
py:traceback
py:warnings
py:inspect
py:ast
py:dis
py:pickle
py:shelve
py:gzip
py:zipfile
py:tarfile
py:signal
py:select
py:asyncio
py:concurrent
py:queue
py:secrets
py:uuid

# Go standard library
go:fmt
go:os
go:io
go:net
go:http
go:net/http
go:encoding/json
go:encoding/xml
go:strings
go:strconv
go:math
go:time
go:sync
go:context
go:errors
go:log
go:flag
go:path
go:path/filepath
go:sort
go:regexp
go:bytes
go:bufio
go:crypto
go:crypto/sha256
go:crypto/tls
go:database/sql
go:testing
go:reflect
go:runtime
go:os/exec
go:os/signal
go:embed

# Rust standard library
rs:std
rs:core
rs:alloc
rs:collections
rs:env
rs:fs
rs:io
rs:net
rs:path
rs:process
rs:sync
rs:thread
rs:time

# Ruby standard library
rb:json
rb:yaml
rb:csv
rb:net/http
rb:uri
rb:fileutils
rb:pathname
rb:set
rb:date
rb:time
rb:logger
rb:open-uri
rb:optparse
rb:erb
rb:digest
rb:base64
rb:securerandom
rb:socket
rb:stringio
rb:tempfile

# C/C++ standard library
c:stdio
c:stdlib
c:string
c:math
c:time
c:errno
c:assert
c:ctype
c:signal
c:stdarg
c:stddef
c:limits
c:float
c:stdbool
c:stdint
c:pthread
c:unistd
c:fcntl
c:sys/types
c:sys/stat
c:sys/socket
cpp:iostream
cpp:string
cpp:vector
cpp:map
cpp:set
cpp:algorithm
cpp:memory
cpp:thread
cpp:mutex
cpp:chrono
cpp:filesystem
cpp:fstream
cpp:sstream
cpp:functional
cpp:optional
cpp:variant
cpp:tuple
cpp:array
cpp:regex
cpp:numeric
cpp:cmath
```

- [ ] **Step 2: Verify file is well-formed**

Run: `grep -v '^#' hooks/known-stdlib.txt | grep -v '^$' | head -5`
Expected: First 5 non-comment lines like `js:fs`, `js:path`, etc.

- [ ] **Step 3: Commit**

```bash
git add hooks/known-stdlib.txt
git commit -m "feat: add known-stdlib.txt for Context7 standard library exclusions"
```

---

### Task 8: Create Enforce-Context7 Hook (Implementation Zone)

**Files:**
- Create: `hooks/enforce-context7.sh`
- Test: `tests/test-enforce-context7.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test-enforce-context7.sh`:

```bash
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
test_edit_reads_new_string
test_degraded_skips
test_test_file_with_imports_passes
run_tests
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-enforce-context7.sh`
Expected: FAIL — `hooks/enforce-context7.sh` does not exist yet.

- [ ] **Step 3: Create enforce-context7.sh**

Create `hooks/enforce-context7.sh`:

```bash
#!/usr/bin/env bash
# enforce-context7.sh — PreToolUse (Write|Edit) blocking hook for Implementation Zone
# Blocks source file edits that import unresearched third-party libraries.
# Libraries are marked as researched by context7-tracker.sh when Context7 MCP is queried.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 1

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null || echo "")
[ -z "$FILE_PATH" ] && exit 0
is_doc_or_config "$FILE_PATH" && exit 0
is_test_file "$FILE_PATH" && exit 0
is_source_file "$FILE_PATH" || exit 0

HASH=$(get_project_hash)

# Skip if Context7 enforcement is degraded (user declined install)
[ -f "/tmp/.claude_c7_degraded_${HASH}" ] && exit 0

# Extract content to scan for imports
if [ "$TOOL_NAME" = "Edit" ]; then
  CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null || echo "")
else
  CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null || echo "")
fi
[ -z "$CONTENT" ] && exit 0

# Load known stdlib modules
STDLIB_FILE="$SCRIPT_DIR/known-stdlib.txt"

# Determine language from file extension
EXT=".${FILE_PATH##*.}"
LANG_PREFIX=""
case "$EXT" in
  .js|.mjs|.cjs|.jsx|.ts|.tsx) LANG_PREFIX="js" ;;
  .py|.ipynb) LANG_PREFIX="py" ;;
  .go) LANG_PREFIX="go" ;;
  .rs) LANG_PREFIX="rs" ;;
  .rb|.erb) LANG_PREFIX="rb" ;;
  .c|.h) LANG_PREFIX="c" ;;
  .cpp|.hpp|.cc) LANG_PREFIX="cpp" ;;
  *) LANG_PREFIX="" ;;
esac

# Extract library names from import statements
LIBS=""

# JavaScript/TypeScript: import ... from 'lib'; require('lib')
if [ "$LANG_PREFIX" = "js" ]; then
  JS_IMPORTS=$(echo "$CONTENT" | grep -oE "(import .+ from ['\"]([^'\"./][^'\"]*)['\"]|require\(['\"]([^'\"./][^'\"]*)['\"])" 2>/dev/null || true)
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    LIB=$(echo "$line" | grep -oE "['\"][^'\"./][^'\"]*['\"]" | head -1 | tr -d "'" | tr -d '"')
    [ -n "$LIB" ] && LIBS="${LIBS}${LIB}\n"
  done <<< "$JS_IMPORTS"
fi

# Python: from lib import ...; import lib
if [ "$LANG_PREFIX" = "py" ]; then
  PY_IMPORTS=$(echo "$CONTENT" | grep -oE "(from [a-zA-Z_][a-zA-Z0-9_]* import|^import [a-zA-Z_][a-zA-Z0-9_.]*)" 2>/dev/null || true)
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    LIB=$(echo "$line" | sed -E 's/^from ([a-zA-Z_][a-zA-Z0-9_]*).*/\1/' | sed -E 's/^import ([a-zA-Z_][a-zA-Z0-9_]*).*/\1/')
    [ -n "$LIB" ] && LIBS="${LIBS}${LIB}\n"
  done <<< "$PY_IMPORTS"
fi

# Go: import "lib" or import ( "lib" )
if [ "$LANG_PREFIX" = "go" ]; then
  GO_IMPORTS=$(echo "$CONTENT" | grep -oE '"[a-zA-Z][^"]*"' 2>/dev/null || true)
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    LIB=$(echo "$line" | tr -d '"')
    [ -n "$LIB" ] && LIBS="${LIBS}${LIB}\n"
  done <<< "$GO_IMPORTS"
fi

# Rust: use lib::...; extern crate lib;
if [ "$LANG_PREFIX" = "rs" ]; then
  RS_IMPORTS=$(echo "$CONTENT" | grep -oE "(use [a-zA-Z_][a-zA-Z0-9_]*|extern crate [a-zA-Z_][a-zA-Z0-9_]*)" 2>/dev/null || true)
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    LIB=$(echo "$line" | sed -E 's/^(use|extern crate) ([a-zA-Z_][a-zA-Z0-9_]*).*/\2/')
    [ -n "$LIB" ] && LIBS="${LIBS}${LIB}\n"
  done <<< "$RS_IMPORTS"
fi

# Ruby: require 'lib'
if [ "$LANG_PREFIX" = "rb" ]; then
  RB_IMPORTS=$(echo "$CONTENT" | grep -oE "require ['\"][a-zA-Z][^'\"]*['\"]" 2>/dev/null || true)
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    LIB=$(echo "$line" | grep -oE "['\"][^'\"]*['\"]" | tr -d "'" | tr -d '"')
    [ -n "$LIB" ] && LIBS="${LIBS}${LIB}\n"
  done <<< "$RB_IMPORTS"
fi

# C/C++: #include <lib.h> (non-relative only)
if [ "$LANG_PREFIX" = "c" ] || [ "$LANG_PREFIX" = "cpp" ]; then
  C_INCLUDES=$(echo "$CONTENT" | grep -oE '#include <[^>]+>' 2>/dev/null || true)
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    LIB=$(echo "$line" | sed -E 's/#include <([^>]+)>/\1/' | sed 's/\.h$//')
    [ -n "$LIB" ] && LIBS="${LIBS}${LIB}\n"
  done <<< "$C_INCLUDES"
fi

# Deduplicate and check each library
MISSING=""
CHECKED=""
while IFS= read -r lib; do
  [ -z "$lib" ] && continue
  # Skip if already checked
  echo "$CHECKED" | grep -qx "$lib" && continue
  CHECKED="${CHECKED}${lib}\n"

  # Normalize for marker lookup: lowercase, strip @, replace / with -
  NORMALIZED=$(echo "$lib" | tr '[:upper:]' '[:lower:]' | sed 's|^[@/]*||' | tr '/' '-')

  # Check stdlib
  if [ -n "$LANG_PREFIX" ] && [ -f "$STDLIB_FILE" ]; then
    # Check both exact match and top-level module match
    TOP_MODULE=$(echo "$lib" | cut -d'/' -f1 | cut -d'.' -f1)
    if grep -qx "${LANG_PREFIX}:${lib}" "$STDLIB_FILE" 2>/dev/null || \
       grep -qx "${LANG_PREFIX}:${TOP_MODULE}" "$STDLIB_FILE" 2>/dev/null; then
      continue
    fi
  fi

  # Skip relative imports
  case "$lib" in
    ./*|../*|..*) continue ;;
  esac

  # Check for Context7 marker
  if [ ! -f "/tmp/.claude_c7_${HASH}_${NORMALIZED}" ]; then
    MISSING="${MISSING}  - ${lib}\n"
  fi
done <<< "$(printf "%b" "$LIBS" | sort -u)"

if [ -n "$MISSING" ]; then
  printf "BLOCKED [Implementation Zone] — Unresearched libraries detected:\n%b\nBefore editing, query Context7 for each library:\n  1. Use resolve-library-id to find the Context7 ID\n  2. Use get-library-docs to fetch current documentation\n\nIf Context7 has no results, consider using Tavily web search for bleeding-edge libraries.\n\nDo NOT write code using libraries you haven't researched.\nDo NOT skip this because you are confident in your training data.\nDo NOT create markers manually.\n\nCOMPLIANCE REMINDER: Your obligation is compliance first, speed second.\n" "$MISSING" >&2
  exit 2
fi
exit 0
```

- [ ] **Step 4: Make executable and run test**

Run: `chmod +x hooks/enforce-context7.sh && bash tests/test-enforce-context7.sh`
Expected: All 10 tests pass (12 total assertions).

- [ ] **Step 5: Commit**

```bash
git add hooks/enforce-context7.sh tests/test-enforce-context7.sh
git commit -m "feat: add enforce-context7 hook — blocks edits using unresearched third-party libraries"
```

---

### Task 9: Create Verification Gate Hook (Verification Zone)

**Files:**
- Create: `hooks/verification-gate.sh`
- Test: `tests/test-verification-gate.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test-verification-gate.sh`:

```bash
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
  # Add a gate that always passes
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-verification-gate.sh`
Expected: FAIL — `hooks/verification-gate.sh` does not exist yet.

- [ ] **Step 3: Create verification-gate.sh**

Create `hooks/verification-gate.sh`:

```bash
#!/usr/bin/env bash
# verification-gate.sh — PreToolUse (Bash) blocking hook for Verification Zone
# Runs configurable verification gates before git commit.
# Gates are defined in manifest.json → projectConfig._base.verificationGates[]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 1

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
echo "$COMMAND" | grep -qE '^\s*git\s+commit' || exit 0

# Read gates from manifest
MANIFEST=$(get_manifest_path)
[ ! -f "$MANIFEST" ] || ! check_jq && exit 0

GATES=$(jq -c '.projectConfig._base.verificationGates[]? // empty' "$MANIFEST" 2>/dev/null || true)
[ -z "$GATES" ] && exit 0

while IFS= read -r gate; do
  [ -z "$gate" ] && continue

  NAME=$(echo "$gate" | jq -r '.name // "unnamed"')
  ENABLED=$(echo "$gate" | jq -r '.enabled // true')
  CMD=$(echo "$gate" | jq -r '.command // empty')
  FAIL_ON=$(echo "$gate" | jq -r '.failOn // "exit_code"')
  FAIL_PATTERN=$(echo "$gate" | jq -r '.failPattern // empty')

  # Skip disabled gates
  [ "$ENABLED" = "false" ] && continue
  [ -z "$CMD" ] && continue

  # Check if command exists (first word)
  FIRST_WORD=$(echo "$CMD" | awk '{print $1}')
  if ! command -v "$FIRST_WORD" >/dev/null 2>&1 && [ ! -f "$FIRST_WORD" ]; then
    # Command not found — skip with advisory (don't block for missing tools)
    continue
  fi

  # Run the gate
  GATE_STDOUT=""
  GATE_STDERR=""
  GATE_EXIT=0
  GATE_STDERR_FILE=$(mktemp)
  GATE_STDOUT=$(eval "$CMD" 2>"$GATE_STDERR_FILE") || GATE_EXIT=$?
  GATE_STDERR=$(cat "$GATE_STDERR_FILE")
  rm -f "$GATE_STDERR_FILE"

  FAILED=false

  case "$FAIL_ON" in
    exit_code)
      [ "$GATE_EXIT" -ne 0 ] && FAILED=true
      ;;
    stderr)
      if [ -n "$FAIL_PATTERN" ] && [ -n "$GATE_STDERR" ]; then
        echo "$GATE_STDERR" | grep -qE "$FAIL_PATTERN" && FAILED=true
      fi
      ;;
    stdout)
      if [ -n "$FAIL_PATTERN" ] && [ -n "$GATE_STDOUT" ]; then
        echo "$GATE_STDOUT" | grep -qE "$FAIL_PATTERN" && FAILED=true
      fi
      ;;
  esac

  if [ "$FAILED" = true ]; then
    OUTPUT=""
    [ -n "$GATE_STDOUT" ] && OUTPUT="$GATE_STDOUT"
    [ -n "$GATE_STDERR" ] && OUTPUT="${OUTPUT:+$OUTPUT\n}$GATE_STDERR"
    printf "BLOCKED [Verification Zone] — %s FAILED\nOutput: %b\nFix the issues above before committing.\nDo NOT skip verification gates. Do NOT use --no-verify.\n\nCOMPLIANCE REMINDER: Your obligation is compliance first, speed second.\n" "$NAME" "$OUTPUT" >&2
    exit 2
  fi
done <<< "$GATES"

exit 0
```

- [ ] **Step 4: Make executable and run test**

Run: `chmod +x hooks/verification-gate.sh && bash tests/test-verification-gate.sh`
Expected: All 10 assertions pass (7 test functions).

- [ ] **Step 5: Commit**

```bash
git add hooks/verification-gate.sh tests/test-verification-gate.sh
git commit -m "feat: add verification-gate hook — configurable pre-commit quality gates"
```

---

### Task 10: Create Visual Auditor Gate Script

**Files:**
- Create: `gates/visual-auditor.sh`

- [ ] **Step 1: Create gates directory and script**

Create `gates/visual-auditor.sh`:

```bash
#!/usr/bin/env bash
# visual-auditor.sh — Playwright-based visual audit gate for web-app profile
# Takes a screenshot of the running app and outputs the path for Claude to self-reflect.
# Exits 0 always — Claude self-reflects on the screenshot, the gate itself doesn't judge.
# If Playwright or dev server is not available, exits 0 with advisory.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_DIR="$(cd "$SCRIPT_DIR/../hooks" && pwd)"
source "$HOOK_DIR/_helpers.sh" 2>/dev/null || exit 0

# Read visual auditor config from manifest
DEV_CMD=$(get_manifest_value '.projectConfig._base.visualAuditor.devServerCommand')
DEV_URL=$(get_manifest_value '.projectConfig._base.visualAuditor.devServerUrl')

if [ -z "$DEV_CMD" ] || [ -z "$DEV_URL" ]; then
  echo "Visual Auditor: No devServerCommand or devServerUrl configured in manifest. Skipping." >&2
  exit 0
fi

# Check Playwright is available
if ! npx playwright --version >/dev/null 2>&1; then
  echo "Visual Auditor: Playwright not installed. Run 'npx playwright install' to enable. Skipping." >&2
  exit 0
fi

# Start dev server in background
eval "$DEV_CMD" &
DEV_PID=$!
trap "kill $DEV_PID 2>/dev/null; wait $DEV_PID 2>/dev/null" EXIT

# Wait for server to be ready (up to 30 seconds)
READY=false
for i in $(seq 1 30); do
  if curl -s -o /dev/null -w "%{http_code}" "$DEV_URL" 2>/dev/null | grep -qE '^(200|301|302)'; then
    READY=true
    break
  fi
  sleep 1
done

if [ "$READY" = false ]; then
  echo "Visual Auditor: Dev server at $DEV_URL did not become ready in 30s. Skipping." >&2
  exit 0
fi

# Take screenshot
SCREENSHOT="/tmp/.claude_visual_audit_$(date +%s).png"
npx playwright screenshot --browser chromium "$DEV_URL" "$SCREENSHOT" 2>/dev/null

if [ -f "$SCREENSHOT" ]; then
  echo "Visual Auditor: Screenshot saved to $SCREENSHOT"
  echo "Review the screenshot and confirm the UI matches the spec before proceeding."
  exit 0
else
  echo "Visual Auditor: Screenshot failed. Skipping." >&2
  exit 0
fi
```

- [ ] **Step 2: Make executable**

Run: `chmod +x gates/visual-auditor.sh`

- [ ] **Step 3: Commit**

```bash
git add gates/visual-auditor.sh
git commit -m "feat: add visual-auditor gate — Playwright screenshot for web-app pre-commit"
```

---

### Task 11: Update skill-tracker.sh for Planning Zone

**Files:**
- Modify: `hooks/skill-tracker.sh:19-23`

- [ ] **Step 1: Write the failing test**

Add a test to a new file `tests/test-skill-tracker-v4.sh`:

```bash
#!/usr/bin/env bash
# test-skill-tracker-v4.sh — Tests for v4 additions to skill-tracker
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/skill-tracker.sh"

# --- Test: writing-plans creates has_plan marker ---
test_writing_plans_creates_has_plan() {
  setup_test_project
  INPUT='{"tool_name":"Skill","tool_input":{"skill":"superpowers:writing-plans"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_has_plan_${TEST_HASH}" "writing-plans should create has_plan marker"
  assert_file_exists "/tmp/.claude_superpowers_${TEST_HASH}" "writing-plans should also create superpowers marker"
  teardown_test_project
}

# --- Test: writing-plans (non-namespaced) creates has_plan marker ---
test_writing_plans_short_creates_has_plan() {
  setup_test_project
  INPUT='{"tool_name":"Skill","tool_input":{"skill":"writing-plans"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_has_plan_${TEST_HASH}" "writing-plans (short) should create has_plan marker"
  teardown_test_project
}

# --- Test: brainstorming does NOT create has_plan marker ---
test_brainstorming_no_has_plan() {
  setup_test_project
  INPUT='{"tool_name":"Skill","tool_input":{"skill":"superpowers:brainstorming"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_not_exists "/tmp/.claude_has_plan_${TEST_HASH}" "brainstorming should NOT create has_plan marker"
  assert_file_exists "/tmp/.claude_superpowers_${TEST_HASH}" "brainstorming should create superpowers marker"
  teardown_test_project
}

# --- Run all tests ---
echo "skill-tracker.sh (v4 plan markers)"
test_writing_plans_creates_has_plan
test_writing_plans_short_creates_has_plan
test_brainstorming_no_has_plan
run_tests
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-skill-tracker-v4.sh`
Expected: FAIL — `has_plan` marker is not created by current skill-tracker.

- [ ] **Step 3: Update skill-tracker.sh**

Replace the case block in `hooks/skill-tracker.sh` (lines 19-23):

```bash
# Create superpowers marker when any superpowers skill is invoked
case "$SKILL_NAME" in
  superpowers:*|brainstorm*|writing-plans|executing-plans|test-driven*|systematic-debugging|requesting-code-review|receiving-code-review|dispatching*|finishing-a-development*|subagent-driven*|verification-before*)
    touch "/tmp/.claude_superpowers_${HASH}"
    ;;
esac

# Create has_plan marker when writing-plans is invoked (arms Planning Zone)
case "$SKILL_NAME" in
  writing-plans|superpowers:writing-plans)
    touch "/tmp/.claude_has_plan_${HASH}"
    ;;
esac
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-skill-tracker-v4.sh`
Expected: All 5 assertions pass.

- [ ] **Step 5: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All existing tests still pass.

- [ ] **Step 6: Commit**

```bash
git add hooks/skill-tracker.sh tests/test-skill-tracker-v4.sh
git commit -m "feat: skill-tracker creates has_plan marker on writing-plans invoke"
```

---

### Task 12: Update sync-tracker.sh for Planning Zone

**Files:**
- Modify: `hooks/sync-tracker.sh:19-22`

- [ ] **Step 1: Write the failing test**

Add to `tests/test-sync-tracker-v4.sh`:

```bash
#!/usr/bin/env bash
# test-sync-tracker-v4.sh — Tests for v4 additions to sync-tracker
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/sync-tracker.sh"

# --- Test: successful commit clears plan_active marker ---
test_commit_clears_plan_active() {
  setup_test_project
  touch "/tmp/.claude_plan_active_${TEST_HASH}"

  # Make a real commit in the test repo so exit_code is 0
  echo "// code" > "$TEST_DIR/app.js"
  git -C "$TEST_DIR" add app.js
  git -C "$TEST_DIR" commit -m "test commit" --quiet

  INPUT='{"tool_input":{"command":"git commit -m \"test\""},"tool_response":{"exit_code":"0"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_not_exists "/tmp/.claude_plan_active_${TEST_HASH}" "commit should clear plan_active marker"
  teardown_test_project
}

# --- Test: failed commit does NOT clear plan_active marker ---
test_failed_commit_keeps_plan_active() {
  setup_test_project
  touch "/tmp/.claude_plan_active_${TEST_HASH}"
  INPUT='{"tool_input":{"command":"git commit -m \"test\""},"tool_response":{"exit_code":"1"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_plan_active_${TEST_HASH}" "failed commit should keep plan_active marker"
  teardown_test_project
}

# --- Run all tests ---
echo "sync-tracker.sh (v4 plan_active clearing)"
test_commit_clears_plan_active
test_failed_commit_keeps_plan_active
run_tests
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-sync-tracker-v4.sh`
Expected: FAIL on first test — `plan_active` not cleared by current sync-tracker.

- [ ] **Step 3: Update sync-tracker.sh**

In `hooks/sync-tracker.sh`, add to the commit-clearing block (after line 21):

```bash
  rm -f "/tmp/.claude_plan_active_${HASH}"
```

The full block becomes:

```bash
if echo "$COMMAND" | grep -qE '^\s*git\s+commit' && [ "$EXIT_CODE" = "0" ]; then
  rm -f "/tmp/.claude_evaluated_${HASH}"
  rm -f "/tmp/.claude_superpowers_${HASH}"
  rm -f "/tmp/.claude_plan_active_${HASH}"
fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-sync-tracker-v4.sh`
Expected: Both tests pass.

- [ ] **Step 5: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add hooks/sync-tracker.sh tests/test-sync-tracker-v4.sh
git commit -m "feat: sync-tracker clears plan_active marker after successful commit"
```

---

### Task 13: Rewrite session-start.sh

**Files:**
- Modify: `hooks/session-start.sh` (full rewrite)
- Test: `tests/test-session-start-v4.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test-session-start-v4.sh`:

```bash
#!/usr/bin/env bash
# test-session-start-v4.sh — Tests for rewritten session-start hook
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/session-start.sh"

# --- Test: output contains compliance directive ---
test_has_directive() {
  setup_test_project
  RESULT=$(run_hook "$HOOK" "")
  assert_contains "$RESULT" "FRAMEWORK COMPLIANCE DIRECTIVE" "should contain directive"
  teardown_test_project
}

# --- Test: output contains ZONES ARMED section ---
test_has_zones() {
  setup_test_project
  RESULT=$(run_hook "$HOOK" "")
  assert_contains "$RESULT" "ZONES ARMED" "should contain zones section"
  assert_contains "$RESULT" "Discovery" "should list Discovery zone"
  assert_contains "$RESULT" "Design" "should list Design zone"
  assert_contains "$RESULT" "Planning" "should list Planning zone"
  assert_contains "$RESULT" "Implementation" "should list Implementation zone"
  assert_contains "$RESULT" "Verification" "should list Verification zone"
  teardown_test_project
}

# --- Test: output does NOT contain old ACTIVE RULES section ---
test_no_rules_listing() {
  setup_test_project
  RESULT=$(run_hook "$HOOK" "")
  assert_not_contains "$RESULT" "ACTIVE RULES" "should not list individual rules"
  teardown_test_project
}

# --- Test: output contains profile/branch/rules summary line ---
test_summary_line() {
  setup_test_project
  RESULT=$(run_hook "$HOOK" "")
  assert_contains "$RESULT" "Profile:" "should contain Profile"
  assert_contains "$RESULT" "Branch:" "should contain Branch"
  assert_contains "$RESULT" "Rules:" "should contain Rules count"
  teardown_test_project
}

# --- Test: output does NOT contain old banner format ---
test_no_old_banner() {
  setup_test_project
  RESULT=$(run_hook "$HOOK" "")
  assert_not_contains "$RESULT" "=== CLAUDE DEV FRAMEWORK" "should not have old banner"
  assert_not_contains "$RESULT" "WORKFLOW ENFORCEMENT" "should not have old workflow section"
  teardown_test_project
}

# --- Test: exit code is always 0 ---
test_exit_zero() {
  setup_test_project
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "")
  assert_exit_code "0" "$EXIT_CODE" "should always exit 0"
  teardown_test_project
}

# --- Run all tests ---
echo "session-start.sh (v4 rewrite)"
test_has_directive
test_has_zones
test_no_rules_listing
test_summary_line
test_no_old_banner
test_exit_zero
run_tests
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-session-start-v4.sh`
Expected: FAIL — old session-start.sh still has `ACTIVE RULES`, `=== CLAUDE DEV FRAMEWORK`, `WORKFLOW ENFORCEMENT`.

- [ ] **Step 3: Rewrite session-start.sh**

Replace the entire contents of `hooks/session-start.sh`:

```bash
#!/usr/bin/env bash
# session-start.sh — SessionStart hook (v4.0.0). stdout = Claude context.
# Activates enforcement zones, checks dependencies, outputs terse zone report.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh"

HASH=$(get_project_hash)
BRANCH=$(get_branch)

# Record session start commit for stop-checklist multi-commit detection
git rev-parse HEAD > "/tmp/.claude_session_start_${HASH}" 2>/dev/null || true
PROFILE=$(get_manifest_value '.profile')
FRAMEWORK_DIR="$(get_framework_dir)"
FRAMEWORK_CLONE="$HOME/.claude-dev-framework"
WARNINGS=""

# --- Dependency checks ---

# jq
if ! check_jq; then
  WARNINGS="${WARNINGS}\n  ! jq not installed. Hooks degraded. Install: brew install jq (macOS) / apt install jq (Linux)"
fi

# Superpowers
SP_STATUS="verified"
if [ -f "$HOME/.claude/settings.json" ] && check_jq; then
  SP=$(jq -r '.enabledPlugins["superpowers@claude-plugins-official"] // false' "$HOME/.claude/settings.json" 2>/dev/null || echo "false")
  if [ "$SP" != "true" ]; then
    SP_STATUS="MISSING"
    WARNINGS="${WARNINGS}\n  ! Superpowers plugin NOT installed. Run: claude > /plugins > search superpowers > install"
  fi
fi

# Context7
C7_STATUS="ready"
if check_context7; then
  C7_STATUS="ready"
else
  C7_STATUS="not installed"
  WARNINGS="${WARNINGS}\n  ! Context7 MCP not installed. Implementation Zone degraded."
  WARNINGS="${WARNINGS}\n    To install: claude mcp add context7 -- npx -y @upstash/context7-mcp@latest"
  # Set degraded flag so enforce-context7.sh passes through
  touch "/tmp/.claude_c7_degraded_${HASH}"
fi

# --- Framework freshness ---
SYNC_STATUS="unknown"
if [ -d "$FRAMEWORK_CLONE/.git" ]; then
  pushd "$FRAMEWORK_CLONE" > /dev/null
  git fetch origin main --quiet 2>/dev/null || true
  LOCAL=$(git rev-parse HEAD 2>/dev/null || echo "?")
  REMOTE=$(git rev-parse origin/main 2>/dev/null || echo "?")
  if [ "$LOCAL" = "$REMOTE" ]; then SYNC_STATUS="up-to-date"
  elif [ "$LOCAL" != "?" ] && [ "$REMOTE" != "?" ]; then
    BEHIND=$(git rev-list --count HEAD..origin/main 2>/dev/null || echo "?")
    SYNC_STATUS="$BEHIND behind"
    WARNINGS="${WARNINGS}\n  ! Framework $BEHIND commits behind. Run: cd ~/.claude-dev-framework && git pull && cd - && bash ~/.claude-dev-framework/scripts/sync.sh"
  fi
  popd > /dev/null
fi

# --- Discovery review (>90 days) ---
LR=$(get_manifest_value '.discovery.lastReviewDate')
if [ -n "$LR" ]; then
  NOW=$(date +%s)
  THEN=$(date -j -f "%Y-%m-%d" "$LR" +%s 2>/dev/null || date -d "$LR" +%s 2>/dev/null || echo "$NOW")
  DAYS=$(( (NOW - THEN) / 86400 ))
  [ "$DAYS" -gt 90 ] && WARNINGS="${WARNINGS}\n  ! Discovery review overdue (last: $LR, $DAYS days ago). Run: init.sh --reconfigure"
fi

# --- Count active rules ---
RULE_COUNT=0
if check_jq; then
  RULE_COUNT=$(jq -r '.activeRules | length // 0' "$(get_manifest_path)" 2>/dev/null || echo "0")
fi

# --- Count verification gates ---
GATE_NAMES=""
if check_jq; then
  GATE_NAMES=$(jq -r '.projectConfig._base.verificationGates[]? | select(.enabled == true) | .name' "$(get_manifest_path)" 2>/dev/null || true)
fi
GATE_LIST=""
if [ -n "$GATE_NAMES" ]; then
  GATE_LIST=$(echo "$GATE_NAMES" | tr '\n' ', ' | sed 's/, $//')
fi

# --- Context history ---
CTX_FILE=$(get_branch_config_value '.contextHistoryFile')
CTX=""
[ -n "$CTX_FILE" ] && [ -f "$CTX_FILE" ] && CTX=$(tail -30 "$CTX_FILE" 2>/dev/null || true)

# --- Output ---
FW_VER=$(cat "$FRAMEWORK_CLONE/FRAMEWORK_VERSION" 2>/dev/null || echo "?")
cat << CTXEOF
FRAMEWORK COMPLIANCE DIRECTIVE: Your primary obligation is to follow all framework hooks and rules exactly. Never skip, circumvent, rationalize past, or fake compliance -- even if a change seems simple. When a hook blocks, follow its instructions. Markers are created automatically. Violation is session failure.

ZONES ARMED:
  # Discovery    -- Context7 ${C7_STATUS}, Superpowers ${SP_STATUS}
  # Design       -- Write|Edit blocked until Superpowers skill invoked
  # Planning     -- Write|Edit blocked until plan task is in_progress
  # Implementation -- New library imports require Context7 lookup first
  # Verification -- Pre-commit: ${GATE_LIST:-no gates configured}
CTXEOF

if [ -n "$WARNINGS" ]; then
  printf "\nWARNINGS:%b\n" "$WARNINGS"
fi

echo ""
echo "Profile: ${PROFILE:-unknown} | Branch: $BRANCH | Rules: $RULE_COUNT active | Sync: $SYNC_STATUS | v$FW_VER"

[ -n "$CTX" ] && printf "\n=== RECENT CONTEXT ===\n%s\n=== END CONTEXT ===" "$CTX"
exit 0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-session-start-v4.sh`
Expected: All 14 assertions pass (6 test functions).

- [ ] **Step 5: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass. Note: existing session-start tests may need updating if they check for old output format.

- [ ] **Step 6: Commit**

```bash
git add hooks/session-start.sh tests/test-session-start-v4.sh
git commit -m "feat: rewrite session-start.sh — zone activation model, terse output, Context7 check"
```

---

### Task 14: Update stop-checklist.sh Zone References

**Files:**
- Modify: `hooks/stop-checklist.sh:71-97`

- [ ] **Step 1: Update advisory messages to reference zones**

In `hooks/stop-checklist.sh`, update the advisory section (starting at line 71). Replace lines 73-86:

```bash
    # Superpowers audit: commits were made but no superpowers marker
    if [ ! -f "/tmp/.claude_superpowers_${HASH}" ]; then
      ADVISORIES="${ADVISORIES}[Design Zone] This session produced commits but the Superpowers workflow may not have been followed. Review commit quality.\n\n"
    fi

    # Plan closure: if Superpowers was used (commits exist) and no closure marker
    if [ ! -f "/tmp/.claude_plan_closed_${HASH}" ]; then
      ADVISORIES="${ADVISORIES}[Planning Zone] If this session involved planned work, document plan closure: planned vs. actual, decisions made, issues deferred.\n\n"
    fi

    # Session handoff
    if [ -n "$CTX_HISTORY" ]; then
      ADVISORIES="${ADVISORIES}[Discovery Zone] Consider saving a handoff note to ${CTX_HISTORY} for the next session."
    fi
```

- [ ] **Step 2: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass (stop-checklist tests check for content presence — zone prefixes shouldn't break existing assertions unless they check for exact strings).

- [ ] **Step 3: Commit**

```bash
git add hooks/stop-checklist.sh
git commit -m "feat: update stop-checklist advisory messages with zone references"
```

---

### Task 15: Update _shared.sh and Profile Files

**Files:**
- Modify: `scripts/_shared.sh:14-29` (generate_settings_json case block)
- Modify: `profiles/_base.yml:34-41` (hooks list)
- Modify: `profiles/web-app.yml` (add visual-auditor suggestion)
- Modify: `templates/manifest.json.template` (add verificationGates)
- Modify: `templates/settings.json.template` (add new hooks)

- [ ] **Step 1: Update generate_settings_json in _shared.sh**

Add new hook mappings to the case block in `scripts/_shared.sh` after line 28 (before `*) continue ;;`):

```bash
      enforce-plan-tracking) event="PreToolUse";  matcher="Write|Edit" ;;
      plan-tracker)          event="PostToolUse";  matcher="" ;;
      enforce-context7)      event="PreToolUse";   matcher="Write|Edit" ;;
      context7-tracker)      event="PostToolUse";  matcher="" ;;
      verification-gate)     event="PreToolUse";   matcher="Bash" ;;
```

- [ ] **Step 2: Update _base.yml hooks**

Add to the hooks list in `profiles/_base.yml` (after `marker-guard`):

```yaml
  - enforce-plan-tracking
  - plan-tracker
  - enforce-context7
  - context7-tracker
  - verification-gate
```

- [ ] **Step 3: Update web-app.yml suggests**

Add to `profiles/web-app.yml` at the end:

```yaml
  verificationGates:
    - name: visual-auditor
      command: ".claude/framework/gates/visual-auditor.sh"
      failOn: exit_code
      enabled: true
```

- [ ] **Step 4: Update manifest.json template**

Add `verificationGates` to the projectConfig._base section in `templates/manifest.json.template`:

```json
{
  "frameworkVersion": "FRAMEWORK_VERSION_PLACEHOLDER",
  "frameworkCommit": "COMMIT_PLACEHOLDER",
  "frameworkRepo": "kraulerson/claude-dev-framework",
  "localClonePath": "~/.claude-dev-framework",
  "lastSyncDate": "DATE_PLACEHOLDER",
  "profile": "PROFILE_PLACEHOLDER",
  "profileInherits": ["_base"],
  "files": {},
  "activeRules": [],
  "activeHooks": [],
  "projectConfig": {
    "_base": {
      "sourceExtensions": [".py", ".js", ".ts", ".go", ".rs", ".java", ".kt", ".swift"],
      "protectedBranches": ["main"],
      "verificationGates": []
    },
    "branches": []
  },
  "discovery": {
    "futurePlatforms": null,
    "discoveryDate": null,
    "lastReviewDate": null
  }
}
```

- [ ] **Step 5: Update settings.json template**

Add new hooks to `templates/settings.json.template`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/framework/hooks/session-start.sh"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/framework/hooks/enforce-evaluate.sh" },
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/framework/hooks/pre-commit-checks.sh" },
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/framework/hooks/branch-safety.sh" },
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/framework/hooks/marker-guard.sh" },
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/framework/hooks/verification-gate.sh" }
        ]
      },
      {
        "matcher": "Write|Edit",
        "hooks": [
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/framework/hooks/enforce-superpowers.sh" },
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/framework/hooks/enforce-plan-tracking.sh" },
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/framework/hooks/enforce-context7.sh" },
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/framework/hooks/changelog-sync-check.sh" },
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/framework/hooks/scalability-check.sh" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/framework/hooks/sync-tracker.sh" }
        ]
      },
      {
        "hooks": [
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/framework/hooks/skill-tracker.sh" },
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/framework/hooks/plan-tracker.sh" },
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/framework/hooks/context7-tracker.sh" }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/framework/hooks/stop-checklist.sh" }
        ]
      }
    ],
    "PreCompact": [
      {
        "hooks": [
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/framework/hooks/pre-compact-reminder.sh" }
        ]
      }
    ]
  }
}
```

- [ ] **Step 6: Commit**

```bash
git add scripts/_shared.sh profiles/_base.yml profiles/web-app.yml templates/manifest.json.template templates/settings.json.template
git commit -m "feat: register v4 hooks in profiles, templates, and settings generator"
```

---

### Task 16: Create Migration Script

**Files:**
- Create: `migrations/v4.sh`

- [ ] **Step 1: Create migrations directory if needed**

Run: `ls migrations/ 2>/dev/null || echo "need to create"`

- [ ] **Step 2: Create v4.sh migration script**

Create `migrations/v4.sh`:

```bash
#!/usr/bin/env bash
# v4.sh — Migration script from v3.x to v4.0.0
# Run from project root: bash ~/.claude-dev-framework/migrations/v4.sh
set -euo pipefail

FRAMEWORK_CLONE="$HOME/.claude-dev-framework"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
FRAMEWORK_DIR="$PROJECT_DIR/.claude/framework"
MANIFEST="$PROJECT_DIR/.claude/manifest.json"

echo "=== Migrating to v4.0.0 ==="
echo "Project: $PROJECT_DIR"
echo ""

# 1. Verify v3 framework exists
if [ ! -f "$MANIFEST" ]; then
  echo "ERROR: No manifest.json found at $MANIFEST" >&2
  echo "Run init.sh first for new projects." >&2
  exit 1
fi

CURRENT_VER=$(jq -r '.frameworkVersion // "unknown"' "$MANIFEST" 2>/dev/null || echo "unknown")
echo "Current version: $CURRENT_VER"

# 2. Copy new hook files
echo "Copying new hooks..."
for hook in enforce-plan-tracking.sh plan-tracker.sh enforce-context7.sh context7-tracker.sh verification-gate.sh known-stdlib.txt; do
  cp "$FRAMEWORK_CLONE/hooks/$hook" "$FRAMEWORK_DIR/hooks/$hook"
  [ "${hook##*.}" = "sh" ] && chmod +x "$FRAMEWORK_DIR/hooks/$hook"
  echo "  + hooks/$hook"
done

# 3. Copy updated hooks
echo "Updating existing hooks..."
for hook in session-start.sh skill-tracker.sh sync-tracker.sh marker-guard.sh stop-checklist.sh _helpers.sh; do
  cp "$FRAMEWORK_CLONE/hooks/$hook" "$FRAMEWORK_DIR/hooks/$hook"
  echo "  ~ hooks/$hook"
done

# 4. Copy gates directory
echo "Copying gates..."
mkdir -p "$FRAMEWORK_DIR/gates"
cp "$FRAMEWORK_CLONE/gates/visual-auditor.sh" "$FRAMEWORK_DIR/gates/visual-auditor.sh"
chmod +x "$FRAMEWORK_DIR/gates/visual-auditor.sh"
echo "  + gates/visual-auditor.sh"

# 5. Update manifest
echo "Updating manifest.json..."
TMPFILE=$(mktemp)
jq '.frameworkVersion = "4.0.0" |
    .projectConfig._base.verificationGates = (.projectConfig._base.verificationGates // [])' \
    "$MANIFEST" > "$TMPFILE" && mv "$TMPFILE" "$MANIFEST"

# 6. Add new hooks to activeHooks
CURRENT_HOOKS=$(jq -r '.activeHooks[]' "$MANIFEST" 2>/dev/null || true)
NEW_HOOKS="enforce-plan-tracking plan-tracker enforce-context7 context7-tracker verification-gate"
for h in $NEW_HOOKS; do
  if ! echo "$CURRENT_HOOKS" | grep -qx "$h"; then
    jq --arg h "$h" '.activeHooks += [$h]' "$MANIFEST" > "$TMPFILE" && mv "$TMPFILE" "$MANIFEST"
    echo "  + activeHooks: $h"
  fi
done

# 7. Regenerate settings.json
echo "Regenerating settings.json..."
source "$FRAMEWORK_CLONE/scripts/_shared.sh"
ALL_HOOKS=$(jq -r '.activeHooks[]' "$MANIFEST" 2>/dev/null)
SETTINGS_JSON=$(generate_settings_json $ALL_HOOKS)
merge_hooks_into_settings "$SETTINGS_JSON" "$PROJECT_DIR/.claude/settings.json"
echo "  ~ .claude/settings.json"

# 8. Context7 check
echo ""
echo "Checking Context7 MCP server..."
source "$FRAMEWORK_CLONE/hooks/_helpers.sh"
if check_context7; then
  echo "  Context7: installed"
else
  echo "  Context7: NOT installed"
  echo ""
  read -rp "Context7 MCP is required for v4.0.0. Install now? (requires Node.js) [y/N] " REPLY
  if [[ "$REPLY" =~ ^[Yy]$ ]]; then
    echo "Installing Context7..."
    claude mcp add context7 -- npx -y @upstash/context7-mcp@latest
    echo "  Context7: installed"
  else
    echo "  Context7: skipped (Implementation Zone will be degraded)"
  fi
fi

echo ""
echo "=== Migration to v4.0.0 complete ==="
echo ""
echo "Next steps:"
echo "  1. Run 'bash ~/.claude-dev-framework/scripts/init.sh --reconfigure' to configure verification gates"
echo "  2. Review .claude/settings.json to confirm new hooks are registered"
echo "  3. Start a new Claude session to verify zone activation"
```

- [ ] **Step 3: Make executable**

Run: `chmod +x migrations/v4.sh`

- [ ] **Step 4: Commit**

```bash
git add migrations/v4.sh
git commit -m "feat: add v4 migration script — copies hooks, updates manifest, installs Context7"
```

---

### Task 17: Integration Test

**Files:**
- Modify: `tests/test-integration-workflow.sh`

- [ ] **Step 1: Read current integration test**

Read `tests/test-integration-workflow.sh` to understand the existing test structure.

- [ ] **Step 2: Add v4 lifecycle integration test**

Add new test functions to `tests/test-integration-workflow.sh` that test the full v4 flow:

```bash
# --- Test: v4 full lifecycle ---
# Design (superpowers) -> Plan (writing-plans + TaskUpdate) -> Edit -> Commit
test_v4_full_lifecycle() {
  setup_test_project

  # 1. Source edit should be blocked (no superpowers marker)
  INPUT_EDIT='{"tool_input":{"file_path":"app.py"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK_DIR/enforce-superpowers.sh" "$INPUT_EDIT")
  assert_exit_code "2" "$EXIT_CODE" "v4: should block without superpowers"

  # 2. Simulate brainstorming skill -> superpowers marker
  INPUT_SKILL='{"tool_name":"Skill","tool_input":{"skill":"superpowers:brainstorming"}}'
  run_hook "$HOOK_DIR/skill-tracker.sh" "$INPUT_SKILL" >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_superpowers_${TEST_HASH}" "v4: brainstorming should create superpowers marker"

  # 3. Simulate writing-plans skill -> has_plan marker
  INPUT_PLAN='{"tool_name":"Skill","tool_input":{"skill":"superpowers:writing-plans"}}'
  run_hook "$HOOK_DIR/skill-tracker.sh" "$INPUT_PLAN" >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_has_plan_${TEST_HASH}" "v4: writing-plans should create has_plan marker"

  # 4. Source edit should be blocked by Planning Zone (has_plan but no plan_active)
  EXIT_CODE=$(run_hook_exit_code "$HOOK_DIR/enforce-plan-tracking.sh" "$INPUT_EDIT")
  assert_exit_code "2" "$EXIT_CODE" "v4: should block without plan_active"

  # 5. Simulate TaskUpdate to in_progress -> plan_active marker
  INPUT_TASK='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"in_progress"}}'
  run_hook "$HOOK_DIR/plan-tracker.sh" "$INPUT_TASK" >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_plan_active_${TEST_HASH}" "v4: TaskUpdate should create plan_active marker"

  # 6. Source edit should now pass both gates
  EXIT_CODE=$(run_hook_exit_code "$HOOK_DIR/enforce-superpowers.sh" "$INPUT_EDIT")
  assert_exit_code "0" "$EXIT_CODE" "v4: should pass superpowers with marker"
  EXIT_CODE=$(run_hook_exit_code "$HOOK_DIR/enforce-plan-tracking.sh" "$INPUT_EDIT")
  assert_exit_code "0" "$EXIT_CODE" "v4: should pass plan-tracking with marker"

  # 7. Simulate commit -> markers cleared
  INPUT_COMMIT='{"tool_input":{"command":"git commit -m \"feat: test\""},"tool_response":{"exit_code":"0"}}'
  echo "// code" > "$TEST_DIR/app.py"
  git -C "$TEST_DIR" add app.py
  git -C "$TEST_DIR" commit -m "feat: test" --quiet
  run_hook "$HOOK_DIR/sync-tracker.sh" "$INPUT_COMMIT" >/dev/null 2>&1
  assert_file_not_exists "/tmp/.claude_superpowers_${TEST_HASH}" "v4: commit should clear superpowers marker"
  assert_file_not_exists "/tmp/.claude_plan_active_${TEST_HASH}" "v4: commit should clear plan_active marker"
  assert_file_exists "/tmp/.claude_has_plan_${TEST_HASH}" "v4: commit should NOT clear has_plan marker"

  teardown_test_project
}
```

Add call to `test_v4_full_lifecycle` before the existing `run_tests` call in the file.

- [ ] **Step 3: Run the integration test**

Run: `bash tests/test-integration-workflow.sh`
Expected: All tests pass including the new v4 lifecycle test.

- [ ] **Step 4: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add tests/test-integration-workflow.sh
git commit -m "test: add v4 full lifecycle integration test"
```

---

### Task 18: Update Documentation

**Files:**
- Modify: `docs/HOOK_REFERENCE.md`
- Modify: `docs/COMPLIANCE_ENGINEERING.md`
- Modify: `docs/GLOSSARY.md`

- [ ] **Step 1: Read current docs to understand format**

Read the first 30 lines of each file to understand the heading structure and style.

- [ ] **Step 2: Update HOOK_REFERENCE.md**

Add entries for the 5 new hooks (enforce-plan-tracking, plan-tracker, enforce-context7, context7-tracker, verification-gate) and the visual-auditor gate, following the existing format. Add a "Zones" section at the top mapping hooks to zones.

- [ ] **Step 3: Update COMPLIANCE_ENGINEERING.md**

Update the layer table to reflect v4.0.0 enforcement zones. The 8-layer model becomes a 5-zone + 8-layer model. Add a section describing how zones organize the layers.

- [ ] **Step 4: Update GLOSSARY.md**

Add definitions for: Zone, Enforcement Zone, Verification Gate, Context7, Plan-Tracking, Visual Auditor, Tavily (advisory).

- [ ] **Step 5: Commit**

```bash
git add docs/HOOK_REFERENCE.md docs/COMPLIANCE_ENGINEERING.md docs/GLOSSARY.md
git commit -m "docs: update hook reference, compliance engineering, and glossary for v4.0.0"
```

---

### Task 19: Final Validation

- [ ] **Step 1: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass (100+ assertions).

- [ ] **Step 2: Verify hook count**

Run: `ls -1 hooks/*.sh | wc -l`
Expected: 18 (13 existing + 5 new: enforce-plan-tracking, plan-tracker, enforce-context7, context7-tracker, verification-gate).

- [ ] **Step 3: Verify framework version**

Run: `cat FRAMEWORK_VERSION`
Expected: `4.0.0`

- [ ] **Step 4: Verify generate_settings_json includes all hooks**

Run: `source scripts/_shared.sh && generate_settings_json session-start enforce-evaluate enforce-superpowers pre-commit-checks branch-safety stop-checklist pre-compact-reminder changelog-sync-check sync-tracker skill-tracker scalability-check pre-deploy-check marker-guard enforce-plan-tracking plan-tracker enforce-context7 context7-tracker verification-gate | jq .`
Expected: Valid JSON with all 18 hooks registered under correct events/matchers.

- [ ] **Step 5: Dry-run session start**

Run: `CLAUDE_PROJECT_DIR="$PWD" bash hooks/session-start.sh`
Expected: Terse zone output with compliance directive, ZONES ARMED section, summary line. No old-style banner or rule listing.

- [ ] **Step 6: Commit version tag**

```bash
git tag -a v4.0.0 -m "v4.0.0 — Enforcement Zones with Superpowers and Context7 integration"
```
