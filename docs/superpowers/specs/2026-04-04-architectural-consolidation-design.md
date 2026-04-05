# Architectural Consolidation (Sub-project B)

**Date:** 2026-04-04
**Status:** Approved
**Breaking:** No (internal optimizations, no behavior changes)
**Scope:** hooks/session-start.sh, hooks/marker-tracker.sh (new), templates/settings.json.template, profiles/, scripts/_shared.sh, tests/, docs/

---

## Problem Statement

The Sub-project A performance audit identified two architectural improvements deferred as non-goals:

1. **Sequential session-start checks** — `session-start.sh` runs 5 dependency checks sequentially. The `git fetch` call (~200-500ms network latency) blocks the entire startup even though 4 local checks could run concurrently.
2. **Redundant PostToolUse processes** — 4 tracker hooks (`skill-tracker.sh`, `plan-tracker.sh`, `context7-tracker.sh`, `sync-tracker.sh`) each spawn a separate process, read stdin, and parse JSON with jq on every tool call. They share identical boilerplate (read input, extract tool_name, get project hash) and could be a single process with one jq parse.

Two other audit items were evaluated and rejected during brainstorming:
- **Parallelize verification gates** — rejected. Common case is 1-2 gates; sequential with early exit is optimal.
- **Consolidate pre-commit Bash hook chain** — rejected. Claude Code controls hook sequencing; a dispatcher would add complexity without confirmed benefit.

## Solution

### 1. Background git fetch in session-start.sh

Move the `git fetch origin main --quiet` call to a background job started early in the script. The 4 local checks (jq, Superpowers, Context7, discovery review) run while the fetch completes in the background. A `wait` call before the freshness comparison block ensures the fetch has finished before comparing local vs remote HEADs.

**Current flow (sequential):**
```
jq check → Superpowers check → Context7 check → git fetch (blocking) → compare → discovery review → output
```

**New flow (fetch overlapped):**
```
git fetch (background) → jq check → Superpowers check → Context7 check → discovery review → wait(fetch) → compare → output
```

**Implementation:**

After setting `FRAMEWORK_CLONE` (line 15), start the background fetch:

```bash
# Start git fetch in background — overlaps with local checks below
FETCH_PID=""
if [ -d "$FRAMEWORK_CLONE/.git" ]; then
  git -C "$FRAMEWORK_CLONE" fetch origin main --quiet 2>/dev/null &
  FETCH_PID=$!
fi
```

Move the freshness comparison block (lines 49-61) to after the discovery review. Replace the `pushd`/`git fetch`/compare/`popd` block with:

```bash
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
```

Also replaces `pushd`/`popd` with `git -C` for cleaner subprocess handling.

**Impact:** ~200-500ms savings on session start (network latency hidden behind local checks). Zero behavior change — same output, same warnings.

### 2. Merge tracker hooks into marker-tracker.sh

Replace 4 separate PostToolUse hooks with a single `marker-tracker.sh` that reads input once, parses with jq once, and routes to the appropriate marker logic via a `case` statement.

**Hooks being merged:**

| Old Hook | Tool Filter | Logic |
|----------|------------|-------|
| `skill-tracker.sh` | `Skill` | Touch superpowers marker on Superpowers skill invoke; touch has_plan marker on writing-plans invoke |
| `plan-tracker.sh` | `TaskUpdate` | Touch plan_active on in_progress; remove plan_active on completed |
| `context7-tracker.sh` | `mcp__context7__*` | Normalize library name, touch c7 marker |
| `sync-tracker.sh` | `Bash` | Touch changelog_synced on sync script; clear evaluated/superpowers/plan_active on commit |

**New file: `hooks/marker-tracker.sh`**

```bash
#!/usr/bin/env bash
# marker-tracker.sh — PostToolUse (all tools) unified marker management.
# Replaces: skill-tracker.sh, plan-tracker.sh, context7-tracker.sh, sync-tracker.sh
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
    case "$SKILL_NAME" in
      superpowers:*|brainstorm*|writing-plans|executing-plans|test-driven*|systematic-debugging|requesting-code-review|receiving-code-review|dispatching*|finishing-a-development*|subagent-driven*|verification-before*)
        touch "/tmp/.claude_superpowers_${HASH}"
        ;;
    esac
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
    if echo "$COMMAND" | grep -qE 'sync-(changelog|shared|ios)\.sh' && [ "$EXIT_CODE" = "0" ]; then
      touch "/tmp/.claude_changelog_synced_${HASH}"
    fi
    if echo "$COMMAND" | grep -qE '^\s*git\s+commit' && [ "$EXIT_CODE" = "0" ]; then
      rm -f "/tmp/.claude_evaluated_${HASH}"
      rm -f "/tmp/.claude_superpowers_${HASH}"
      rm -f "/tmp/.claude_plan_active_${HASH}"
    fi
    ;;

esac
exit 0
```

**Files to delete:** `hooks/skill-tracker.sh`, `hooks/plan-tracker.sh`, `hooks/context7-tracker.sh`, `hooks/sync-tracker.sh`

**settings.json.template change:** Replace the two PostToolUse entries:

```json
"PostToolUse": [
  {
    "hooks": [
      { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/framework/hooks/marker-tracker.sh" }
    ]
  }
]
```

**Profile changes:**
- `profiles/_base.yml`: Replace `skill-tracker`, `plan-tracker`, `context7-tracker` with `marker-tracker`
- `profiles/web-app.yml`: Replace `sync-tracker` with `marker-tracker` (if not already in _base)
- `profiles/mobile-app.yml`: Replace `sync-tracker` with `marker-tracker` (if not already in _base)

Since marker-tracker subsumes all 4, it belongs in `_base.yml` and should be removed from type-specific profiles.

**scripts/_shared.sh change:** Replace the 4 tracker case entries with one:

```bash
marker-tracker)        event="PostToolUse";  matcher="" ;;
```

**Test changes:**
- Create `tests/test-marker-tracker.sh` — consolidate all assertions from the 4 existing test files (`test-context7-tracker.sh`, `test-plan-tracker.sh`, `test-skill-tracker-v4.sh`, `test-sync-tracker-v4.sh`, `test-marker-persistence.sh`)
- Update `tests/test-integration-workflow.sh` — change hook paths from individual trackers to `marker-tracker.sh`
- Delete old test files: `test-context7-tracker.sh`, `test-plan-tracker.sh`, `test-skill-tracker-v4.sh`, `test-sync-tracker-v4.sh`, `test-marker-persistence.sh`
- Update `tests/helpers/setup.sh` — change `sync-tracker` to `marker-tracker` in activeHooks

**Doc changes (reference updates only, not rewrites):**
- `README.md` — replace 4 tracker entries in hook table with 1 marker-tracker entry
- `docs/HOOK_REFERENCE.md` — replace 4 tracker sections with 1 marker-tracker section
- `docs/CLAUDE-GUIDE.md` — update references from sync-tracker to marker-tracker
- `docs/CREATING_PROFILES.md` — update hook list
- `docs/COMPLIANCE_ENGINEERING.md` — update Layer 5 reference and zone table
Historical docs (`docs/superpowers/specs/2026-03-31-*`, `docs/superpowers/plans/2026-03-31-*`, `migrations/v4.sh`) are left unchanged — they document v4.0.0 as-built.

**Impact:** 3 fewer processes spawned per tool call. One jq parse instead of 4. ~15-30ms savings per tool invocation.

## Files to Modify

| File | Change |
|------|--------|
| `hooks/session-start.sh` | Background git fetch, use git -C, reorder blocks |
| `hooks/marker-tracker.sh` (new) | Unified PostToolUse marker management |
| `hooks/skill-tracker.sh` (delete) | Replaced by marker-tracker |
| `hooks/plan-tracker.sh` (delete) | Replaced by marker-tracker |
| `hooks/context7-tracker.sh` (delete) | Replaced by marker-tracker |
| `hooks/sync-tracker.sh` (delete) | Replaced by marker-tracker |
| `templates/settings.json.template` | Consolidate PostToolUse entries |
| `profiles/_base.yml` | Replace 3 trackers with marker-tracker |
| `profiles/web-app.yml` | Remove sync-tracker (now in _base via marker-tracker) |
| `profiles/mobile-app.yml` | Remove sync-tracker (now in _base via marker-tracker) |
| `scripts/_shared.sh` | Replace 4 tracker cases with 1 marker-tracker case |
| `tests/test-marker-tracker.sh` (new) | Consolidated tracker tests |
| `tests/test-context7-tracker.sh` (delete) | Replaced |
| `tests/test-plan-tracker.sh` (delete) | Replaced |
| `tests/test-skill-tracker-v4.sh` (delete) | Replaced |
| `tests/test-sync-tracker-v4.sh` (delete) | Replaced |
| `tests/test-marker-persistence.sh` (delete) | Replaced |
| `tests/test-integration-workflow.sh` | Update hook paths |
| `tests/helpers/setup.sh` | Update activeHooks |
| `README.md` | Update hook table |
| `docs/HOOK_REFERENCE.md` | Replace 4 tracker sections with 1 |
| `docs/CLAUDE-GUIDE.md` | Update sync-tracker references |
| `docs/CREATING_PROFILES.md` | Update hook list |
| `docs/COMPLIANCE_ENGINEERING.md` | Update Layer 5 + zone table |

## Testing

All existing test assertions are preserved in the consolidated test file. Total assertion count should remain the same or increase slightly. Run full suite after each change.

## Non-Goals

- Verification gate parallelization (rejected — sequential with early exit is optimal)
- Pre-commit hook chain consolidation (rejected — Claude Code controls sequencing)
- Changes to historical docs or migration scripts
