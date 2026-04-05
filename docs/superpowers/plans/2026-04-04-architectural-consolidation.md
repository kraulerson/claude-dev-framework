# Architectural Consolidation (Sub-project B) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Background the git fetch in session-start.sh and merge 4 PostToolUse tracker hooks into a single marker-tracker.sh to reduce per-tool-call overhead.

**Architecture:** Two independent changes. (1) session-start.sh starts git fetch as a background job, runs local checks concurrently, waits before comparing. (2) skill-tracker, plan-tracker, context7-tracker, and sync-tracker merge into marker-tracker.sh with one jq parse and a case-based router. Settings template, profiles, scripts, tests, and docs updated to match.

**Tech Stack:** Bash, jq

---

## File Map

### New Files

| File | Responsibility |
|------|---------------|
| `hooks/marker-tracker.sh` | Unified PostToolUse marker management (replaces 4 tracker hooks) |
| `tests/test-marker-tracker.sh` | Consolidated tracker tests (replaces 5 test files) |

### Modified Files

| File | What Changes |
|------|-------------|
| `hooks/session-start.sh` | Background git fetch, use `git -C`, reorder blocks |
| `templates/settings.json.template` | Consolidate PostToolUse entries into single marker-tracker |
| `profiles/_base.yml` | Replace skill-tracker, plan-tracker, context7-tracker with marker-tracker |
| `profiles/web-app.yml` | Remove sync-tracker (subsumed by marker-tracker in _base) |
| `profiles/mobile-app.yml` | Remove sync-tracker (subsumed by marker-tracker in _base) |
| `scripts/_shared.sh` | Replace 4 tracker case entries with 1 marker-tracker entry |
| `tests/test-integration-workflow.sh` | Update hook paths from individual trackers to marker-tracker.sh |
| `tests/helpers/setup.sh` | Change sync-tracker to marker-tracker in activeHooks |
| `README.md` | Update hook table (4 tracker rows → 1 marker-tracker row, count 18→15) |
| `docs/HOOK_REFERENCE.md` | Replace 4 tracker sections with 1, update zone table |
| `docs/CLAUDE-GUIDE.md` | Update sync-tracker references to marker-tracker |
| `docs/CREATING_PROFILES.md` | Update hook list in inheritance section |
| `docs/COMPLIANCE_ENGINEERING.md` | Update Layer 5 reference and zone table |

### Deleted Files

| File | Reason |
|------|--------|
| `hooks/skill-tracker.sh` | Merged into marker-tracker.sh |
| `hooks/plan-tracker.sh` | Merged into marker-tracker.sh |
| `hooks/context7-tracker.sh` | Merged into marker-tracker.sh |
| `hooks/sync-tracker.sh` | Merged into marker-tracker.sh |
| `tests/test-context7-tracker.sh` | Merged into test-marker-tracker.sh |
| `tests/test-plan-tracker.sh` | Merged into test-marker-tracker.sh |
| `tests/test-skill-tracker-v4.sh` | Merged into test-marker-tracker.sh |
| `tests/test-sync-tracker-v4.sh` | Merged into test-marker-tracker.sh |
| `tests/test-marker-persistence.sh` | Merged into test-marker-tracker.sh |

---

### Task 1: Background git fetch in session-start.sh

**Files:**
- Modify: `hooks/session-start.sh`

- [ ] **Step 1: Replace session-start.sh**

Replace the entire content of `hooks/session-start.sh`:

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

# --- Start git fetch in background (overlaps with local checks below) ---
FETCH_PID=""
if [ -d "$FRAMEWORK_CLONE/.git" ]; then
  git -C "$FRAMEWORK_CLONE" fetch origin main --quiet 2>/dev/null &
  FETCH_PID=$!
fi

# --- Dependency checks (local, fast) ---

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

# --- Discovery review (>90 days) ---
LR=$(get_manifest_value '.discovery.lastReviewDate')
if [ -n "$LR" ]; then
  NOW=$(date +%s)
  THEN=$(date -j -f "%Y-%m-%d" "$LR" +%s 2>/dev/null || date -d "$LR" +%s 2>/dev/null || echo "$NOW")
  DAYS=$(( (NOW - THEN) / 86400 ))
  [ "$DAYS" -gt 90 ] && WARNINGS="${WARNINGS}\n  ! Discovery review overdue (last: $LR, $DAYS days ago). Run: init.sh --reconfigure"
fi

# --- Framework freshness (wait for background fetch) ---
SYNC_STATUS="unknown"
if [ -n "$FETCH_PID" ]; then
  wait "$FETCH_PID" 2>/dev/null || true
  LOCAL=$(git -C "$FRAMEWORK_CLONE" rev-parse HEAD 2>/dev/null || echo "?")
  REMOTE=$(git -C "$FRAMEWORK_CLONE" rev-parse origin/main 2>/dev/null || echo "?")
  if [ "$LOCAL" = "$REMOTE" ]; then SYNC_STATUS="up-to-date"
  elif [ "$LOCAL" != "?" ] && [ "$REMOTE" != "?" ]; then
    BEHIND=$(git -C "$FRAMEWORK_CLONE" rev-list --count HEAD..origin/main 2>/dev/null || echo "?")
    SYNC_STATUS="$BEHIND behind"
    WARNINGS="${WARNINGS}\n  ! Framework $BEHIND commits behind. Run: cd ~/.claude-dev-framework && git pull && cd - && bash ~/.claude-dev-framework/scripts/sync.sh"
  fi
fi

# --- Count active rules ---
RULE_COUNT=0
if check_jq; then
  RULE_COUNT=$(jq -r '.activeRules | length // 0' "$(get_manifest_path)" 2>/dev/null || echo "0")
fi

# --- Count verification gates ---
GATE_LIST=""
if check_jq; then
  GATE_NAMES=$(jq -r '.projectConfig._base.verificationGates[]? | select(.enabled == true) | .name' "$(get_manifest_path)" 2>/dev/null || true)
  if [ -n "$GATE_NAMES" ]; then
    GATE_LIST=$(echo "$GATE_NAMES" | tr '\n' ', ' | sed 's/, $//')
  fi
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
  # Discovery      -- Context7 ${C7_STATUS}, Superpowers ${SP_STATUS}
  # Design         -- Write|Edit blocked until Superpowers skill invoked
  # Planning       -- Write|Edit blocked until plan task is in_progress
  # Implementation -- New library imports require Context7 lookup first
  # Verification   -- Pre-commit: ${GATE_LIST:-no gates configured}
CTXEOF

if [ -n "$WARNINGS" ]; then
  printf "\nWARNINGS:%b\n" "$WARNINGS"
fi

echo ""
echo "Profile: ${PROFILE:-unknown} | Branch: $BRANCH | Rules: $RULE_COUNT active | Sync: $SYNC_STATUS | v$FW_VER"

[ -n "$CTX" ] && printf "\n=== RECENT CONTEXT ===\n%s\n=== END CONTEXT ===" "$CTX"
exit 0
```

- [ ] **Step 2: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All 23 test files pass. Session-start tests verify output format and exit code, which are unchanged.

- [ ] **Step 3: Commit**

```bash
git add hooks/session-start.sh
git commit -m "perf: background git fetch in session-start — overlaps with local dependency checks"
```

---

### Task 2: Create marker-tracker.sh

**Files:**
- Create: `hooks/marker-tracker.sh`

- [ ] **Step 1: Create the unified tracker hook**

Create `hooks/marker-tracker.sh`:

```bash
#!/usr/bin/env bash
# marker-tracker.sh — PostToolUse (all tools) unified marker management.
# Replaces: skill-tracker.sh, plan-tracker.sh, context7-tracker.sh, sync-tracker.sh
#
# Single entry point for all PostToolUse marker operations:
#   Skill        → superpowers + has_plan markers
#   TaskUpdate   → plan_active marker
#   Context7 MCP → per-library c7 markers
#   Bash         → changelog sync + post-commit marker clearing
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 0

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
[ -z "$TOOL" ] && exit 0

HASH=$(get_project_hash)

case "$TOOL" in

  # --- Skill tracking (was skill-tracker.sh) ---
  Skill)
    SKILL_NAME=$(echo "$INPUT" | jq -r '.tool_input.skill // empty' 2>/dev/null || echo "")
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
    ;;

  # --- Plan tracking (was plan-tracker.sh) ---
  TaskUpdate)
    STATUS=$(echo "$INPUT" | jq -r '.tool_input.status // empty' 2>/dev/null || echo "")
    case "$STATUS" in
      in_progress) touch "/tmp/.claude_plan_active_${HASH}" ;;
      completed)   rm -f "/tmp/.claude_plan_active_${HASH}" ;;
    esac
    ;;

  # --- Context7 tracking (was context7-tracker.sh) ---
  mcp__context7__resolve-library-id|mcp__context7__resolve_library_id)
    LIB=$(echo "$INPUT" | jq -r '.tool_input.libraryName // empty' 2>/dev/null || echo "")
    [ -z "$LIB" ] && exit 0
    NORMALIZED=$(echo "$LIB" | tr '[:upper:]' '[:lower:]' | sed 's|^[@/]*||' | tr '/' '-')
    touch "/tmp/.claude_c7_${HASH}_${NORMALIZED}"
    ;;
  mcp__context7__get-library-docs|mcp__context7__get_library_docs)
    LIB=$(echo "$INPUT" | jq -r '.tool_input.context7CompatibleLibraryID // empty' 2>/dev/null || echo "")
    [ -z "$LIB" ] && exit 0
    NORMALIZED=$(echo "$LIB" | tr '[:upper:]' '[:lower:]' | sed 's|^[@/]*||' | tr '/' '-')
    touch "/tmp/.claude_c7_${HASH}_${NORMALIZED}"
    ;;

  # --- Sync tracking (was sync-tracker.sh) ---
  Bash)
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
    EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_response.exit_code // "1"' 2>/dev/null || echo "1")
    # Track successful sync script executions
    if echo "$COMMAND" | grep -qE 'sync-(changelog|shared|ios)\.sh' && [ "$EXIT_CODE" = "0" ]; then
      touch "/tmp/.claude_changelog_synced_${HASH}"
    fi
    # Clear evaluation/superpowers/plan_active markers after successful commit
    if echo "$COMMAND" | grep -qE '^\s*git\s+commit' && [ "$EXIT_CODE" = "0" ]; then
      rm -f "/tmp/.claude_evaluated_${HASH}"
      rm -f "/tmp/.claude_superpowers_${HASH}"
      rm -f "/tmp/.claude_plan_active_${HASH}"
    fi
    ;;

esac
exit 0
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x hooks/marker-tracker.sh`

- [ ] **Step 3: Commit**

```bash
git add hooks/marker-tracker.sh
git commit -m "feat: add marker-tracker.sh — unified PostToolUse marker management"
```

---

### Task 3: Create consolidated test file

**Files:**
- Create: `tests/test-marker-tracker.sh`

- [ ] **Step 1: Create the consolidated test file**

Create `tests/test-marker-tracker.sh` with all assertions from the 5 old test files:

```bash
#!/usr/bin/env bash
# test-marker-tracker.sh — Tests for unified marker-tracker PostToolUse hook
# Consolidates: test-skill-tracker-v4, test-plan-tracker, test-context7-tracker,
#               test-sync-tracker-v4, test-marker-persistence
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/marker-tracker.sh"

# =============================================
# Skill tracking (was skill-tracker.sh)
# =============================================

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

# =============================================
# Plan tracking (was plan-tracker.sh)
# =============================================

# --- Test: TaskUpdate in_progress creates plan_active marker ---
test_task_in_progress_creates_marker() {
  setup_test_project
  INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"in_progress"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_plan_active_${TEST_HASH}" "in_progress should create plan_active marker"
  teardown_test_project
}

# --- Test: TaskUpdate completed clears plan_active marker ---
test_task_completed_clears_marker() {
  setup_test_project
  touch "/tmp/.claude_plan_active_${TEST_HASH}"
  INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_not_exists "/tmp/.claude_plan_active_${TEST_HASH}" "completed should clear plan_active marker"
  teardown_test_project
}

# --- Test: TaskUpdate pending does nothing ---
test_task_pending_no_change() {
  setup_test_project
  INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"pending"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_not_exists "/tmp/.claude_plan_active_${TEST_HASH}" "pending should not create plan_active marker"
  teardown_test_project
}

# --- Test: non-TaskUpdate does not affect plan_active ---
test_non_task_update_no_plan_marker() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"echo hello"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_not_exists "/tmp/.claude_plan_active_${TEST_HASH}" "non-TaskUpdate should not create plan_active marker"
  teardown_test_project
}

# --- Test: TaskUpdate without status does nothing ---
test_task_update_no_status() {
  setup_test_project
  INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","subject":"New name"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_not_exists "/tmp/.claude_plan_active_${TEST_HASH}" "TaskUpdate without status should not create marker"
  teardown_test_project
}

# =============================================
# Context7 tracking (was context7-tracker.sh)
# =============================================

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

# --- Test: ignores non-Context7 tools for c7 markers ---
test_ignores_other_tools_for_c7() {
  setup_test_project
  INPUT='{"tool_name":"Bash","tool_input":{"command":"echo hello"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  local count
  count=$(ls /tmp/.claude_c7_${TEST_HASH}_* 2>/dev/null | wc -l | xargs)
  assert_equals "0" "$count" "should not create c7 markers for non-Context7 tools"
  teardown_test_project
}

# --- Test: ignores Skill tool for c7 markers ---
test_ignores_skill_tool_for_c7() {
  setup_test_project
  INPUT='{"tool_name":"Skill","tool_input":{"skill":"superpowers:brainstorming"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  local count
  count=$(ls /tmp/.claude_c7_${TEST_HASH}_* 2>/dev/null | wc -l | xargs)
  assert_equals "0" "$count" "should not create c7 markers for Skill tool"
  teardown_test_project
}

# =============================================
# Sync tracking (was sync-tracker.sh)
# =============================================

# --- Test: successful commit clears plan_active marker ---
test_commit_clears_plan_active() {
  setup_test_project
  touch "/tmp/.claude_plan_active_${TEST_HASH}"
  INPUT='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"test\""},"tool_response":{"exit_code":"0"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_not_exists "/tmp/.claude_plan_active_${TEST_HASH}" "commit should clear plan_active marker"
  teardown_test_project
}

# --- Test: failed commit does NOT clear plan_active marker ---
test_failed_commit_keeps_plan_active() {
  setup_test_project
  touch "/tmp/.claude_plan_active_${TEST_HASH}"
  INPUT='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"test\""},"tool_response":{"exit_code":"1"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_plan_active_${TEST_HASH}" "failed commit should keep plan_active marker"
  teardown_test_project
}

# =============================================
# Marker persistence (was test-marker-persistence.sh)
# =============================================

# --- Test: markers cleared after successful git commit ---
test_markers_cleared_after_commit() {
  setup_test_project
  touch "/tmp/.claude_evaluated_${TEST_HASH}"
  touch "/tmp/.claude_superpowers_${TEST_HASH}"
  COMMIT_INPUT='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"Add feature\""},"tool_response":{"exit_code":"0"}}'
  run_hook "$HOOK" "$COMMIT_INPUT" >/dev/null
  assert_file_not_exists "/tmp/.claude_evaluated_${TEST_HASH}" "evaluated marker should be cleared after commit"
  assert_file_not_exists "/tmp/.claude_superpowers_${TEST_HASH}" "superpowers marker should be cleared after commit"
  teardown_test_project
}

# --- Test: markers survive non-commit commands ---
test_markers_survive_non_commit() {
  setup_test_project
  touch "/tmp/.claude_evaluated_${TEST_HASH}"
  touch "/tmp/.claude_superpowers_${TEST_HASH}"
  STATUS_INPUT='{"tool_name":"Bash","tool_input":{"command":"git status"},"tool_response":{"exit_code":"0"}}'
  run_hook "$HOOK" "$STATUS_INPUT" >/dev/null
  assert_file_exists "/tmp/.claude_evaluated_${TEST_HASH}" "evaluated marker should survive non-commit"
  assert_file_exists "/tmp/.claude_superpowers_${TEST_HASH}" "superpowers marker should survive non-commit"
  teardown_test_project
}

# --- Test: markers survive failed commit ---
test_markers_survive_failed_commit() {
  setup_test_project
  touch "/tmp/.claude_evaluated_${TEST_HASH}"
  touch "/tmp/.claude_superpowers_${TEST_HASH}"
  FAIL_INPUT='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"fail\""},"tool_response":{"exit_code":"1"}}'
  run_hook "$HOOK" "$FAIL_INPUT" >/dev/null
  assert_file_exists "/tmp/.claude_evaluated_${TEST_HASH}" "evaluated marker should survive failed commit"
  assert_file_exists "/tmp/.claude_superpowers_${TEST_HASH}" "superpowers marker should survive failed commit"
  teardown_test_project
}

# =============================================
# Run all tests
# =============================================
echo "marker-tracker.sh (unified)"

# Skill tracking
test_writing_plans_creates_has_plan
test_writing_plans_short_creates_has_plan
test_brainstorming_no_has_plan

# Plan tracking
test_task_in_progress_creates_marker
test_task_completed_clears_marker
test_task_pending_no_change
test_non_task_update_no_plan_marker
test_task_update_no_status

# Context7 tracking
test_creates_marker_on_resolve
test_creates_marker_on_get_docs
test_normalizes_scoped_names
test_ignores_other_tools_for_c7
test_ignores_skill_tool_for_c7

# Sync tracking + marker persistence
test_commit_clears_plan_active
test_failed_commit_keeps_plan_active
test_markers_cleared_after_commit
test_markers_survive_non_commit
test_markers_survive_failed_commit

run_tests
```

- [ ] **Step 2: Run the new test file against marker-tracker.sh**

Run: `bash tests/test-marker-tracker.sh`
Expected: All 23 assertions pass (marker-tracker.sh was created in Task 2).

- [ ] **Step 3: Commit**

```bash
git add tests/test-marker-tracker.sh
git commit -m "test: add consolidated test-marker-tracker.sh — 23 assertions from 5 old test files"
```

---

### Task 4: Delete old tracker hooks and tests

**Files:**
- Delete: `hooks/skill-tracker.sh`, `hooks/plan-tracker.sh`, `hooks/context7-tracker.sh`, `hooks/sync-tracker.sh`
- Delete: `tests/test-skill-tracker-v4.sh`, `tests/test-plan-tracker.sh`, `tests/test-context7-tracker.sh`, `tests/test-sync-tracker-v4.sh`, `tests/test-marker-persistence.sh`

- [ ] **Step 1: Delete old hook files**

Run:
```bash
git rm hooks/skill-tracker.sh hooks/plan-tracker.sh hooks/context7-tracker.sh hooks/sync-tracker.sh
```

- [ ] **Step 2: Delete old test files**

Run:
```bash
git rm tests/test-skill-tracker-v4.sh tests/test-plan-tracker.sh tests/test-context7-tracker.sh tests/test-sync-tracker-v4.sh tests/test-marker-persistence.sh
```

- [ ] **Step 3: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: 19 test files (was 23, minus 5 deleted, plus 1 new). All pass. The test runner auto-discovers `test-*.sh` files so deleted files are automatically excluded.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor: remove 4 individual tracker hooks and 5 test files — replaced by marker-tracker"
```

---

### Task 5: Update settings.json.template

**Files:**
- Modify: `templates/settings.json.template:35-48`

- [ ] **Step 1: Replace PostToolUse entries**

Replace the entire PostToolUse section (lines 35-48):

```json
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
```

With:

```json
      {
        "hooks": [
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/framework/hooks/marker-tracker.sh" }
        ]
      }
```

- [ ] **Step 2: Commit**

```bash
git add templates/settings.json.template
git commit -m "refactor: settings template uses single marker-tracker for all PostToolUse events"
```

---

### Task 6: Update profiles

**Files:**
- Modify: `profiles/_base.yml:40-45`
- Modify: `profiles/web-app.yml:17`
- Modify: `profiles/mobile-app.yml:15`

- [ ] **Step 1: Update _base.yml**

Replace lines 40-45 in `profiles/_base.yml`:

```yaml
  - skill-tracker
  - marker-guard
  - enforce-plan-tracking
  - plan-tracker
  - enforce-context7
  - context7-tracker
```

With:

```yaml
  - marker-tracker
  - marker-guard
  - enforce-plan-tracking
  - enforce-context7
```

- [ ] **Step 2: Update web-app.yml**

Remove line 17 (`  - sync-tracker`) from `profiles/web-app.yml`.

- [ ] **Step 3: Update mobile-app.yml**

Remove line 15 (`  - sync-tracker`) from `profiles/mobile-app.yml`.

- [ ] **Step 4: Commit**

```bash
git add profiles/_base.yml profiles/web-app.yml profiles/mobile-app.yml
git commit -m "refactor: profiles use marker-tracker instead of 4 individual trackers"
```

---

### Task 7: Update scripts/_shared.sh

**Files:**
- Modify: `scripts/_shared.sh:24-32`

- [ ] **Step 1: Replace tracker case entries**

Replace lines 24-32 in `scripts/_shared.sh`:

```bash
      sync-tracker)         event="PostToolUse";  matcher="Bash" ;;
      skill-tracker)        event="PostToolUse";  matcher="" ;;
      scalability-check)    event="PreToolUse";   matcher="Write|Edit" ;;
      pre-deploy-check)     event="PreToolUse";   matcher="Bash" ;;
      marker-guard)         event="PreToolUse";   matcher="Bash" ;;
      enforce-plan-tracking) event="PreToolUse";  matcher="Write|Edit" ;;
      plan-tracker)          event="PostToolUse";  matcher="" ;;
      enforce-context7)      event="PreToolUse";   matcher="Write|Edit" ;;
      context7-tracker)      event="PostToolUse";  matcher="" ;;
```

With:

```bash
      marker-tracker)       event="PostToolUse";  matcher="" ;;
      scalability-check)    event="PreToolUse";   matcher="Write|Edit" ;;
      pre-deploy-check)     event="PreToolUse";   matcher="Bash" ;;
      marker-guard)         event="PreToolUse";   matcher="Bash" ;;
      enforce-plan-tracking) event="PreToolUse";  matcher="Write|Edit" ;;
      enforce-context7)      event="PreToolUse";   matcher="Write|Edit" ;;
```

- [ ] **Step 2: Commit**

```bash
git add scripts/_shared.sh
git commit -m "refactor: _shared.sh maps marker-tracker instead of 4 individual trackers"
```

---

### Task 8: Update test-integration-workflow.sh and helpers/setup.sh

**Files:**
- Modify: `tests/test-integration-workflow.sh:60,86,91,100,114`
- Modify: `tests/helpers/setup.sh:25`

- [ ] **Step 1: Update integration test hook paths**

In `tests/test-integration-workflow.sh`, replace all references to individual tracker hooks with `marker-tracker.sh`:

Line 60 — replace:
```bash
  run_hook "$HOOK_DIR/sync-tracker.sh" "$POST_COMMIT" >/dev/null
```
With:
```bash
  run_hook "$HOOK_DIR/marker-tracker.sh" "$POST_COMMIT" >/dev/null
```

Line 86 — replace:
```bash
  run_hook "$HOOK_DIR/skill-tracker.sh" "$INPUT_SKILL" >/dev/null 2>&1
```
With:
```bash
  run_hook "$HOOK_DIR/marker-tracker.sh" "$INPUT_SKILL" >/dev/null 2>&1
```

Line 91 — replace:
```bash
  run_hook "$HOOK_DIR/skill-tracker.sh" "$INPUT_PLAN" >/dev/null 2>&1
```
With:
```bash
  run_hook "$HOOK_DIR/marker-tracker.sh" "$INPUT_PLAN" >/dev/null 2>&1
```

Line 100 — replace:
```bash
  run_hook "$HOOK_DIR/plan-tracker.sh" "$INPUT_TASK" >/dev/null 2>&1
```
With:
```bash
  run_hook "$HOOK_DIR/marker-tracker.sh" "$INPUT_TASK" >/dev/null 2>&1
```

Line 114 — replace:
```bash
  run_hook "$HOOK_DIR/sync-tracker.sh" "$INPUT_COMMIT" >/dev/null 2>&1
```
With:
```bash
  run_hook "$HOOK_DIR/marker-tracker.sh" "$INPUT_COMMIT" >/dev/null 2>&1
```

Note: The integration test inputs for sync-tracker (lines 59, 110) need `tool_name` added since marker-tracker routes on it. Update the JSON inputs:

Line 59 (`POST_COMMIT`) — replace:
```bash
  POST_COMMIT='{"tool_input":{"command":"git commit -m \"Add feature\""},"tool_response":{"exit_code":"0"}}'
```
With:
```bash
  POST_COMMIT='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"Add feature\""},"tool_response":{"exit_code":"0"}}'
```

Line 110 (`INPUT_COMMIT`) — replace:
```bash
  INPUT_COMMIT='{"tool_input":{"command":"git commit -m \"feat: test\""},"tool_response":{"exit_code":"0"}}'
```
With:
```bash
  INPUT_COMMIT='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"feat: test\""},"tool_response":{"exit_code":"0"}}'
```

- [ ] **Step 2: Update helpers/setup.sh activeHooks**

In `tests/helpers/setup.sh`, line 25, replace:
```bash
  "activeHooks": ["enforce-evaluate", "stop-checklist", "sync-tracker"],
```
With:
```bash
  "activeHooks": ["enforce-evaluate", "stop-checklist", "marker-tracker"],
```

- [ ] **Step 3: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All 19 test files pass. Integration workflow tests exercise marker-tracker through the full lifecycle.

- [ ] **Step 4: Commit**

```bash
git add tests/test-integration-workflow.sh tests/helpers/setup.sh
git commit -m "test: update integration tests and setup to use marker-tracker"
```

---

### Task 9: Update documentation

**Files:**
- Modify: `README.md:98-119`
- Modify: `docs/HOOK_REFERENCE.md:1-147`
- Modify: `docs/CLAUDE-GUIDE.md:31,59`
- Modify: `docs/CREATING_PROFILES.md:37`
- Modify: `docs/COMPLIANCE_ENGINEERING.md:53,103-108,146-148`

- [ ] **Step 1: Update README.md hook table**

Replace lines 98-119 in `README.md`:

```markdown
## Hooks

**18 hooks** enforce rules mechanically via Claude Code's hook API:

| Hook | Zone | Type | What it does |
|------|------|------|-------------|
| **session-start** | Discovery | Context | Activates enforcement zones, checks dependencies, outputs terse zone report |
| **enforce-superpowers** | Design | Blocking | Blocks source file edits without invoking the Superpowers workflow |
| **skill-tracker** | Design | Passive | Creates superpowers/has_plan markers when Superpowers skills are invoked |
| **enforce-plan-tracking** | Planning | Blocking | Blocks source edits until a plan task is marked in_progress |
| **plan-tracker** | Planning | Passive | Creates/clears plan_active marker on TaskUpdate calls |
| **enforce-context7** | Implementation | Blocking | Blocks edits using unresearched third-party libraries (Context7 MCP) |
| **context7-tracker** | Implementation | Passive | Creates per-library markers when Context7 MCP is queried |
| **enforce-evaluate** | Verification | Blocking | Blocks commits without presenting evaluation and getting user approval |
| **pre-commit-checks** | Verification | Blocking | Blocks commits missing version bumps or changelog updates |
| **verification-gate** | Verification | Blocking | Runs configurable pre-commit quality gates (linter, type-check, visual auditor) |
| **branch-safety** | Verification | Blocking | Blocks pushes to protected branches |
| **stop-checklist** | — | Blocking | Blocks session end with uncommitted work, untested bug fixes, or missing plan closure |
| **marker-guard** | — | Blocking | Prevents manual creation of workflow markers via touch commands |
| **sync-tracker** | — | Passive | Clears markers after commits, tracks sync operations |
| **pre-compact-reminder** | — | Advisory | Warns to save context history before compression |
| **changelog-sync-check** | — | Advisory | Warns before editing stale changelogs |
| **scalability-check** | — | Advisory | Reminds about future platform plans when editing architecture |
| **pre-deploy-check** | — | Advisory | Warns before deployment commands if commits are unpushed |
```

With:

```markdown
## Hooks

**15 hooks** enforce rules mechanically via Claude Code's hook API:

| Hook | Zone | Type | What it does |
|------|------|------|-------------|
| **session-start** | Discovery | Context | Activates enforcement zones, checks dependencies, outputs terse zone report |
| **enforce-superpowers** | Design | Blocking | Blocks source file edits without invoking the Superpowers workflow |
| **enforce-plan-tracking** | Planning | Blocking | Blocks source edits until a plan task is marked in_progress |
| **enforce-context7** | Implementation | Blocking | Blocks edits using unresearched third-party libraries (Context7 MCP) |
| **enforce-evaluate** | Verification | Blocking | Blocks commits without presenting evaluation and getting user approval |
| **pre-commit-checks** | Verification | Blocking | Blocks commits missing version bumps or changelog updates |
| **verification-gate** | Verification | Blocking | Runs configurable pre-commit quality gates (linter, type-check, visual auditor) |
| **branch-safety** | Verification | Blocking | Blocks pushes to protected branches |
| **stop-checklist** | — | Blocking | Blocks session end with uncommitted work, untested bug fixes, or missing plan closure |
| **marker-guard** | — | Blocking | Prevents manual creation of workflow markers via touch commands |
| **marker-tracker** | — | Passive | Unified PostToolUse marker management: skill/plan/context7/sync tracking |
| **pre-compact-reminder** | — | Advisory | Warns to save context history before compression |
| **changelog-sync-check** | — | Advisory | Warns before editing stale changelogs |
| **scalability-check** | — | Advisory | Reminds about future platform plans when editing architecture |
| **pre-deploy-check** | — | Advisory | Warns before deployment commands if commits are unpushed |
```

- [ ] **Step 2: Update HOOK_REFERENCE.md**

Replace the zone table (lines 5-11):

```markdown
| Zone | Hooks | Purpose |
|------|-------|---------|
| Discovery | session-start.sh | Dependency checks, zone activation, Context7 install |
| Design | enforce-superpowers.sh, skill-tracker.sh | Blocks edits until Superpowers skill invoked |
| Planning | enforce-plan-tracking.sh, plan-tracker.sh | Blocks edits until plan task is in_progress |
| Implementation | enforce-context7.sh, context7-tracker.sh | Blocks edits using unresearched libraries |
| Verification | enforce-evaluate.sh, pre-commit-checks.sh, verification-gate.sh | Pre-commit quality gates |
```

With:

```markdown
| Zone | Hooks | Purpose |
|------|-------|---------|
| Discovery | session-start.sh | Dependency checks, zone activation, Context7 install |
| Design | enforce-superpowers.sh, marker-tracker.sh | Blocks edits until Superpowers skill invoked |
| Planning | enforce-plan-tracking.sh, marker-tracker.sh | Blocks edits until plan task is in_progress |
| Implementation | enforce-context7.sh, marker-tracker.sh | Blocks edits using unresearched libraries |
| Verification | enforce-evaluate.sh, pre-commit-checks.sh, verification-gate.sh | Pre-commit quality gates |
```

Replace the changelog-sync-check marker line (line 69):

```markdown
- **Marker:** `/tmp/.claude_changelog_synced_{hash}` — created by sync-tracker
```

With:

```markdown
- **Marker:** `/tmp/.claude_changelog_synced_{hash}` — created by marker-tracker
```

Replace the 4 individual tracker sections (lines 86-137) with a single section. Delete lines 86-137 (sync-tracker, skill-tracker, enforce-plan-tracking marker reference, plan-tracker, enforce-context7 marker reference, context7-tracker) and replace with:

Replace lines 86-91 (sync-tracker section):
```markdown
## sync-tracker.sh
- **Event:** PostToolUse (Bash)
- **Blocking:** No
- **Purpose:** Creates changelog sync marker when sync scripts succeed; clears evaluation/superpowers/plan_active markers after successful commit
- **Disable:** Remove `sync-tracker` from `manifest.json → activeHooks`

## skill-tracker.sh
- **Event:** PostToolUse (all tools)
- **Zone:** Design + Planning
- **Blocking:** No
- **Purpose:** Automatically creates superpowers marker when Superpowers skill is invoked; creates has_plan marker when writing-plans is invoked
- **Markers:** `.claude_superpowers_{hash}`, `.claude_has_plan_{hash}`
- **Disable:** Remove `skill-tracker` from `manifest.json → activeHooks`
```

With:

```markdown
## marker-tracker.sh
- **Event:** PostToolUse (all tools)
- **Zone:** Design + Planning + Implementation
- **Blocking:** No
- **Purpose:** Unified PostToolUse marker management. Creates superpowers/has_plan markers on Superpowers skill invoke; creates/clears plan_active marker on TaskUpdate; creates per-library c7 markers on Context7 MCP queries; creates changelog_synced marker on sync scripts; clears evaluation/superpowers/plan_active markers after successful commit
- **Markers:** `.claude_superpowers_{hash}`, `.claude_has_plan_{hash}`, `.claude_plan_active_{hash}`, `.claude_c7_{hash}_{library}`, `.claude_changelog_synced_{hash}`
- **Disable:** Remove `marker-tracker` from `manifest.json → activeHooks`
```

Update the enforce-plan-tracking marker line (line 113):
```markdown
- **Marker:** `/tmp/.claude_plan_active_{hash}` — created by plan-tracker.sh when TaskUpdate sets status to in_progress
```
With:
```markdown
- **Marker:** `/tmp/.claude_plan_active_{hash}` — created by marker-tracker.sh when TaskUpdate sets status to in_progress
```

Delete the plan-tracker section (lines 116-121):
```markdown
## plan-tracker.sh
- **Event:** PostToolUse (all tools)
- **Zone:** Planning
- **Blocking:** No
- **Purpose:** Creates plan_active marker when TaskUpdate sets a task to in_progress; clears it when a task is set to completed
- **Disable:** Remove `plan-tracker` from `manifest.json → activeHooks`
```

Update the enforce-context7 marker line (line 129):
```markdown
- **Marker:** `/tmp/.claude_c7_{hash}_{library}` — one per researched library, created by context7-tracker.sh
```
With:
```markdown
- **Marker:** `/tmp/.claude_c7_{hash}_{library}` — one per researched library, created by marker-tracker.sh
```

Delete the context7-tracker section (lines 132-137):
```markdown
## context7-tracker.sh
- **Event:** PostToolUse (all tools)
- **Zone:** Implementation
- **Blocking:** No
- **Purpose:** Watches for Context7 MCP tool calls (resolve-library-id, get-library-docs) and creates per-library markers
- **Disable:** Remove `context7-tracker` from `manifest.json → activeHooks`
```

- [ ] **Step 3: Update CLAUDE-GUIDE.md**

Replace line 31:
```markdown
- `sync-tracker.sh` silently creates markers when sync scripts succeed and clears evaluation/superpowers markers after a successful `git commit` (so you go through the workflow again for the next change).
```
With:
```markdown
- `marker-tracker.sh` silently creates markers when sync scripts succeed and clears evaluation/superpowers markers after a successful `git commit` (so you go through the workflow again for the next change).
```

Replace line 59:
```markdown
**Important**: The evaluation and Superpowers markers clear after each commit (via `sync-tracker.sh`). This means for each new piece of work in a session, you must go through those workflows again. This is intentional — it prevents a single approval from covering unrelated changes. Other markers have different lifecycles (see the "Cleared when" column above).
```
With:
```markdown
**Important**: The evaluation and Superpowers markers clear after each commit (via `marker-tracker.sh`). This means for each new piece of work in a session, you must go through those workflows again. This is intentional — it prevents a single approval from covering unrelated changes. Other markers have different lifecycles (see the "Cleared when" column above).
```

- [ ] **Step 4: Update CREATING_PROFILES.md**

Replace line 37:
```markdown
- 7 universal hooks (session-start, enforce-evaluate, enforce-superpowers, stop-checklist, pre-compact-reminder, skill-tracker, marker-guard)
```
With:
```markdown
- 10 universal hooks (session-start, enforce-evaluate, enforce-superpowers, enforce-plan-tracking, enforce-context7, stop-checklist, pre-compact-reminder, marker-tracker, marker-guard, verification-gate)
```

- [ ] **Step 5: Update COMPLIANCE_ENGINEERING.md**

Replace line 53:
```markdown
Layer 5: Automatic Marker Creation (skill-tracker.sh)
```
With:
```markdown
Layer 5: Automatic Marker Creation (marker-tracker.sh)
```

Replace lines 103-108:
```markdown
### Layer 5 — Automatic Marker Creation
**File:** `hooks/skill-tracker.sh`

A `PostToolUse` hook (no matcher — fires on all tool uses) that detects when the Skill tool invokes a Superpowers skill. When detected, it creates the superpowers marker automatically.
```
With:
```markdown
### Layer 5 — Automatic Marker Creation
**File:** `hooks/marker-tracker.sh`

A `PostToolUse` hook (no matcher — fires on all tool uses) that manages all workflow markers. Detects Superpowers skill invocations, TaskUpdate status changes, Context7 MCP queries, and post-commit cleanup. Creates markers automatically so Claude never needs to (or can) create them manually.
```

Replace lines 146-148:
```markdown
| **Design** | Before any source edit | enforce-superpowers.sh, skill-tracker.sh | Write/Edit blocked until Superpowers skill invoked |
| **Planning** | After design, before implementation | enforce-plan-tracking.sh, plan-tracker.sh | Write/Edit blocked until plan task is in_progress |
| **Implementation** | During edits | enforce-context7.sh, context7-tracker.sh | Blocks edits using unresearched third-party libraries |
```
With:
```markdown
| **Design** | Before any source edit | enforce-superpowers.sh, marker-tracker.sh | Write/Edit blocked until Superpowers skill invoked |
| **Planning** | After design, before implementation | enforce-plan-tracking.sh, marker-tracker.sh | Write/Edit blocked until plan task is in_progress |
| **Implementation** | During edits | enforce-context7.sh, marker-tracker.sh | Blocks edits using unresearched third-party libraries |
```

- [ ] **Step 6: Commit**

```bash
git add README.md docs/HOOK_REFERENCE.md docs/CLAUDE-GUIDE.md docs/CREATING_PROFILES.md docs/COMPLIANCE_ENGINEERING.md
git commit -m "docs: update all references from individual trackers to marker-tracker"
```

---

### Task 10: Final Validation

- [ ] **Step 1: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: 19 test files, all pass.

- [ ] **Step 2: Verify no dangling references to old tracker hooks**

Run: `grep -rn 'skill-tracker\|sync-tracker\|plan-tracker\|context7-tracker' hooks/ templates/ profiles/ scripts/ tests/ --include='*.sh' --include='*.yml' --include='*.template' --include='*.json'`
Expected: No matches. (Historical docs in `docs/superpowers/specs/2026-03-31-*` and `docs/superpowers/plans/2026-03-31-*` and `migrations/v4.sh` will still have references — that's correct, they document v4.0.0 as-built.)

- [ ] **Step 3: Verify marker-tracker.sh is executable**

Run: `ls -la hooks/marker-tracker.sh`
Expected: `-rwxr-xr-x` permissions.

- [ ] **Step 4: Verify hook count matches README**

Run: `ls hooks/*.sh | grep -v '/_' | wc -l`
Expected: 16 (15 hooks + mark-evaluated.sh utility). Was 19 (18 hooks + mark-evaluated.sh). Underscore-prefixed helpers (_helpers.sh, _preflight.sh) are excluded by the grep.

- [ ] **Step 5: Push**

```bash
git push origin main
```
