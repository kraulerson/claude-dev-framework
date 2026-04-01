# v4.0.0 Design: Enforcement Zones with Deep Superpowers and Context7 Integration

**Date:** 2026-03-31
**Status:** Approved
**Breaking:** Yes (major version bump from v3.0.0)
**Scope:** Framework-level, sole user, full rollout to all projects

---

## Problem Statement

v3.0.0 enforces compliance through an 8-layer Swiss cheese model with flat hook organization. This works but has gaps:

1. **No plan-tracking enforcement** — After brainstorming, Claude can edit files without engaging with the implementation plan. There is no mechanical link between plan tasks and edit permissions.
2. **No library documentation enforcement** — Claude generates code using outdated training data. Nothing forces it to fetch current docs before writing code that uses a third-party library.
3. **No pluggable verification** — Pre-commit checks are hardcoded (version bump, changelog). Projects can't add custom quality gates (linting, type checking, visual auditing) without modifying framework hooks.
4. **Session start is verbose** — 40 lines of banner, rules, and instructions. Information density is low. The compliance directive fades because it's buried in noise.

## Solution: Enforcement Zones

Reorganize the hook system into five **enforcement zones** representing workflow stages. Zones are an organizational and messaging convention — hooks still fire independently via Claude Code events. Each zone introduces at most 1-2 new hook files.

## Architecture

```
Session Start
    |
    v
+---------------------+
|  DISCOVERY ZONE     |  session-start.sh (rewritten)
|  - Dependency check  |  Checks: Node.js, jq, Superpowers, Context7
|  - Auto-install C7   |  If Context7 missing -> prompt user -> install
|  - Zone activation   |  Terse output: zones armed, warnings only
+----------+----------+
           |
           v
+---------------------+
|  DESIGN ZONE        |  enforce-superpowers.sh (existing, unchanged)
|  - Blocks Write|Edit |  Until Superpowers skill invoked
|  - skill-tracker.sh  |  Auto-creates marker on skill invoke
+----------+----------+
           |
           v
+---------------------+
|  PLANNING ZONE      |  enforce-plan-tracking.sh (NEW)
|  - Blocks Write|Edit |  Until a task is marked in_progress
|  - plan-tracker.sh   |  Detects TaskUpdate -> creates marker
|  - Clears after      |  commit (forces re-engagement)
+----------+----------+
           |
           v
+---------------------+
|  IMPLEMENTATION ZONE |  enforce-context7.sh (NEW)
|  - Detects new lib   |  Watches Write|Edit for import/require
|  - Blocks until C7   |  queried for that library
|  - context7-tracker  |  Tracks which libs have been looked up
+----------+----------+
           |
           v
+---------------------+
|  VERIFICATION ZONE  |  verification-gate.sh (NEW)
|  - Pre-commit gates  |  Runs configured gates before commit
|  - Linter-Gate       |  Rejects if stderr has warnings
|  - Visual Auditor    |  Playwright screenshot + self-reflect
|  - Existing checks   |  version-bump, changelog, evaluate
+---------------------+
```

**Key properties:**
- Zones are sequential in concept but hooks fire based on Claude Code events (PreToolUse, PostToolUse), not zone ordering
- Existing hooks are reorganized under zones but behavior is unchanged
- Marker lifecycle: Design marker + Plan marker must both exist before edits proceed. Both clear after commit.

---

## Section 1: Session Start Rewrite

### Output Structure

```
FRAMEWORK COMPLIANCE DIRECTIVE: Your primary obligation is to follow all
framework hooks and rules exactly. Never skip, circumvent, rationalize past,
or fake compliance -- even if a change seems simple. When a hook blocks, follow
its instructions. Markers are created automatically. Violation is session failure.

ZONES ARMED:
  # Discovery  -- Context7 ready, Superpowers verified
  # Design     -- Write|Edit blocked until Superpowers skill invoked
  # Planning   -- Write|Edit blocked until plan task is in_progress
  # Implementation -- New library imports require Context7 lookup first
  # Verification   -- Pre-commit: linter-gate, visual-auditor, version, changelog

WARNINGS: (only if any)
  ! Framework 3 commits behind origin
  ! Discovery review overdue (last: 2025-12-01)

Profile: web-app | Branch: feat/new-thing | Rules: 14 active
```

### Changes from v3.0.0

- Compliance directive shortened — same teeth, fewer words
- No rule listing — replaced by zone summary. Rules still loaded as context but not enumerated
- No banner/version fluff — profile, branch, rule count on one line
- Warnings only when present — no "all clear" noise

### Multi-Phase Re-Injection

Zone-specific reminders re-inject at transition points via existing hook block messages. Each zone's block message follows the format:

```
BLOCKED [Zone Name] -- What's missing.
What to do.
Do NOT skip this. Do NOT rationalize. Do NOT create markers manually.
```

Claude gets the directive at session start, then targeted reinforcement every time it hits a gate.

### Dependency Checks

Session start verifies in order:
1. `jq` installed
2. Superpowers plugin enabled in `~/.claude/settings.json`
3. Context7 MCP server registered

If Context7 is missing:
- Prompts user: "Context7 MCP is required for v4.0.0. Install now? (requires Node.js)"
- If confirmed: runs `claude mcp add context7 -- npx -y @upstash/context7-mcp@latest`
- If declined: warns "Implementation Zone degraded -- Context7 enforcement disabled", sets flag so `enforce-context7.sh` passes through

---

## Section 2: Plan-Tracking Gate (Planning Zone)

### New Files

**enforce-plan-tracking.sh** (PreToolUse: Write|Edit)
- Fires after enforce-superpowers.sh — both markers must exist
- Checks for `/tmp/.claude_plan_active_{hash}`
- If missing -> exit 2 with block message
- Skips same file types as enforce-superpowers (docs, config, tests)
- Only activates if `.claude_has_plan_{hash}` exists (set when `writing-plans` skill is invoked)

**plan-tracker.sh** (PostToolUse)
- Watches for `TaskUpdate` tool calls where status changes to `in_progress`
- Creates `/tmp/.claude_plan_active_{hash}`
- Watches for `TaskUpdate` to `completed` — clears the marker (forces re-engagement with next task)

### "Has Plan" Guard

Not every session involves a formal plan. The Planning Zone only arms when `writing-plans` is invoked. Quick bug fixes where the user says "skip" are not affected.

`skill-tracker.sh` updated to also create `.claude_has_plan_{hash}` when `writing-plans` skill is detected.

### Marker Lifecycle

```
1. Invoke brainstorming skill     -> .claude_superpowers_{hash} created
2. Invoke writing-plans skill     -> .claude_has_plan_{hash} created
3. TaskUpdate task #1 in_progress -> .claude_plan_active_{hash} created
4. Edit source files              -> both markers checked, pass
5. git commit                     -> superpowers + plan_active cleared
6. TaskUpdate task #2 in_progress -> .claude_plan_active_{hash} re-created
7. Edit source files              -> pass
8. git commit                     -> cleared again
```

### sync-tracker.sh Update

After `git commit`, clears `.claude_plan_active_{hash}` alongside existing superpowers/evaluated markers.

### marker-guard.sh Update

Add `plan_active|has_plan` to the blocked pattern.

---

## Section 3: Context7 Enforcement (Implementation Zone)

### New Files

**enforce-context7.sh** (PreToolUse: Write|Edit)
- Fires on source file edits (same extension filtering)
- For `Write` calls: reads full file content from `$TOOL_INPUT`
- For `Edit` calls: reads the `new_string` field from `$TOOL_INPUT` (only the incoming change, not the full file)
- Scans for import/require patterns across languages:
  - JavaScript/TypeScript: `import ... from '...'`, `require('...')`
  - Python: `from ... import`, `import ...`
  - Go: `import "..."`, `import (...)`
  - Rust: `use ...`, `extern crate ...`
  - Ruby: `require '...'`, `gem '...'`
  - C/C++: `#include <...>` (non-standard-lib only)
- Extracts library names, checks for `/tmp/.claude_c7_{hash}_{library_name}`
- Missing library -> exit 2, names the library, tells Claude to run `resolve-library-id` + `query-docs`
- All libraries have markers or no new libraries -> exit 0

**context7-tracker.sh** (PostToolUse)
- Watches for MCP tool calls to `resolve-library-id` or `query-docs`
- Extracts library name from tool input
- Creates `/tmp/.claude_c7_{hash}_{normalized_name}`
- Normalization: lowercase, slashes to dashes (e.g., `@anthropic-ai/sdk` -> `anthropic-ai-sdk`)

### Standard Library Exclusions

Framework ships `known-stdlib.txt` listing standard library modules per language. These are never gated. Project-local imports (relative paths) are also never gated.

### Marker Persistence

Context7 markers are NOT cleared after commit. Library docs don't need re-fetching per commit. They persist for the session (cleared on machine restart via `/tmp/`).

### Tavily Integration (Advisory)

When `enforce-context7.sh` blocks and Claude's `resolve-library-id` returns no results, the block message on the next edit attempt changes:

```
BLOCKED [Implementation Zone] -- No Context7 docs found for "some-new-lib".
Context7 may not have this library indexed yet. Consider using Tavily
web search to find current documentation before proceeding.
```

Advisory guidance within a blocking message. User decides whether to use Tavily.

### Context7 Installation

`session-start.sh` handles detection and auto-install with consent:
- Checks if Context7 MCP server is registered
- If missing: prompts user with install command
- If user confirms: runs `claude mcp add context7 -- npx -y @upstash/context7-mcp@latest`
- If user declines: Implementation Zone degrades (enforce-context7.sh passes through)

---

## Section 4: Verification Gates (Verification Zone)

### New File

**verification-gate.sh** (PreToolUse: Bash)
- Fires when `git commit` is detected
- Reads gate definitions from `manifest.json -> projectConfig.verificationGates[]`
- Runs each enabled gate's check command sequentially
- Any gate failure -> exit 2 with gate name and output
- All pass -> exit 0

### Gate Configuration (manifest.json)

```json
{
  "projectConfig": {
    "verificationGates": [
      {
        "name": "linter-gate",
        "description": "Rejects commit if linter produces warnings",
        "command": "npm run lint 2>&1",
        "failOn": "stderr",
        "failPattern": "warning|error",
        "enabled": true,
        "profile": "_base"
      },
      {
        "name": "visual-auditor",
        "description": "Screenshots app and reflects on UI spec match",
        "command": ".claude/framework/gates/visual-auditor.sh",
        "failOn": "exit_code",
        "enabled": true,
        "profile": "web-app"
      },
      {
        "name": "type-check-gate",
        "description": "Runs project type checker",
        "command": "npx tsc --noEmit",
        "failOn": "exit_code",
        "enabled": true,
        "profile": "_base"
      }
    ]
  }
}
```

### Gate Fields

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Identifier, used in block messages |
| `description` | string | Human-readable purpose |
| `command` | string | Shell command to execute |
| `failOn` | enum | `"stderr"`, `"exit_code"`, or `"stdout"` |
| `failPattern` | string | Regex for stderr/stdout modes |
| `enabled` | bool | Toggle without removing config |
| `profile` | string | Which profile owns this gate |

### Built-In Gates

**1. Linter-Gate** (`_base` profile)
- Generic — works with any linter that writes to stderr
- Configured per-project via `command`
- Default `failPattern`: `warning|error|warn`

**2. Visual Auditor** (`web-app` profile only)
- Ships as `gates/visual-auditor.sh`
- Requires: Playwright installed, dev server URL in manifest
- Workflow: starts dev server -> waits for ready -> Playwright screenshot -> outputs image path -> exits 0
- Claude receives screenshot path and must self-reflect on UI vs. spec match
- If Playwright not installed or no spec file -> gate skips with advisory
- Configured via `manifest.json -> projectConfig.visualAuditor.devServerCommand` and `devServerUrl`

**3. Type-Check Gate** (`_base` profile)
- Runs project type checker
- `failOn: "exit_code"`
- Configured per-project via `command`

### Dependency Handling

- `init.sh` updated: during discovery, asks which gates to enable and what commands to use
- If a gate's command not found at runtime -> gate warns and skips (doesn't block for missing tool)
- `session-start.sh` reports gate status in Verification zone line

### Block Message Format

```
BLOCKED [Verification Zone] -- linter-gate FAILED
Output: src/utils.ts:14 -- warning: unused variable 'temp'
Fix the issues above before committing.
Do NOT skip verification gates. Do NOT use --no-verify.
```

---

## Section 5: Updated Marker System

### Complete Marker Table (v4.0.0)

| Marker | Zone | Created By | Cleared When | Checked By |
|--------|------|-----------|--------------|-----------|
| `.claude_superpowers_{hash}` | Design | skill-tracker.sh (auto) | After git commit | enforce-superpowers.sh |
| `.claude_has_plan_{hash}` | Planning | skill-tracker.sh (auto, on writing-plans) | Session end | enforce-plan-tracking.sh (arms the zone) |
| `.claude_plan_active_{hash}` | Planning | plan-tracker.sh (auto, on TaskUpdate) | After git commit OR TaskUpdate to completed | enforce-plan-tracking.sh |
| `.claude_evaluated_{hash}` | Verification | mark-evaluated.sh (sanctioned) | After git commit | enforce-evaluate.sh |
| `.claude_c7_{hash}_{lib}` | Implementation | context7-tracker.sh (auto) | Session end (not per-commit) | enforce-context7.sh |
| `.claude_session_start_{hash}` | Discovery | session-start.sh (auto) | Session end | stop-checklist.sh |
| `.claude_changelog_synced_{hash}` | Verification | sync-tracker.sh (auto) | Not auto-cleared | changelog-sync-check.sh |

### marker-guard.sh Updated Pattern

```bash
touch.*/tmp/\.claude_(superpowers|evaluated|plan_closed|plan_active|has_plan|skill_active|c7)_
```

---

## Section 6: Updated Hook Inventory

### New Hooks (4)

| Hook | Event | Blocking | Zone |
|------|-------|----------|------|
| enforce-plan-tracking.sh | PreToolUse (Write\|Edit) | Yes (exit 2) | Planning |
| plan-tracker.sh | PostToolUse | No | Planning |
| enforce-context7.sh | PreToolUse (Write\|Edit) | Yes (exit 2) | Implementation |
| context7-tracker.sh | PostToolUse | No | Implementation |

### Modified Hooks (5)

| Hook | Change |
|------|--------|
| session-start.sh | Full rewrite — zone activation model, Context7 install, terse output |
| skill-tracker.sh | Also creates `.claude_has_plan_{hash}` on writing-plans invoke |
| sync-tracker.sh | Also clears `.claude_plan_active_{hash}` after commit |
| marker-guard.sh | Extended pattern to include new marker types |
| stop-checklist.sh | Updated to reference zones in advisory messages |

### New Gate Scripts (1 directory)

| File | Purpose |
|------|---------|
| gates/visual-auditor.sh | Playwright screenshot + exit code gate |

### New Verification Hook (1)

| Hook | Event | Blocking | Zone |
|------|-------|----------|------|
| verification-gate.sh | PreToolUse (Bash) | Yes (exit 2) | Verification |

### Total Hook Count: 18 (was 13)

---

## Section 7: Profile Updates

### _base.yml Additions

```yaml
hooks:
  # ... existing hooks ...
  - enforce-plan-tracking
  - plan-tracker
  - enforce-context7
  - context7-tracker
  - verification-gate
```

### web-app.yml Additions

```yaml
suggests:
  verificationGates:
    - name: visual-auditor
      command: ".claude/framework/gates/visual-auditor.sh"
      failOn: exit_code
      enabled: true
```

### manifest.json Template Update

New `verificationGates` array in `projectConfig`. New `visualAuditor` config block for web-app projects.

---

## Section 8: Migration (v3.0.0 -> v4.0.0)

### Migration Script

`migrations/v4.sh`:
1. Copy new hook files to project `.claude/framework/hooks/`
2. Copy `gates/` directory
3. Copy `known-stdlib.txt`
4. Update manifest.json:
   - Add `verificationGates: []` to projectConfig (empty — user configures during re-init)
   - Bump frameworkVersion to 4.0.0
5. Regenerate settings.json with new hook registrations
6. Prompt Context7 installation (auto-install with consent)
7. Prompt discovery re-run for gate configuration

### sync.sh Update

Major version detection already exists. v4.0.0 triggers migration prompt.

---

## Section 9: Testing Requirements

### New Test Files

| File | Assertions | What It Tests |
|------|-----------|--------------|
| test-enforce-plan-tracking.sh | ~8 | Blocks without plan_active marker, passes with it, skips without has_plan, skips docs/config/tests |
| test-plan-tracker.sh | ~5 | Creates marker on TaskUpdate in_progress, clears on completed |
| test-enforce-context7.sh | ~10 | Detects import patterns across languages, blocks unknown libs, passes known/stdlib/local, handles no-results Tavily message |
| test-context7-tracker.sh | ~5 | Creates lib markers on resolve-library-id/query-docs calls, normalizes names |
| test-verification-gate.sh | ~8 | Runs gates from manifest, blocks on failure, skips disabled gates, skips missing commands |
| test-session-start-v4.sh | ~6 | Terse output format, zone listing, Context7 detection, warning display |

### Updated Tests

- test-marker-persistence.sh — add new marker types
- test-integration-workflow.sh — full v4 lifecycle (design -> plan -> task -> edit -> verify -> commit)
- test-spaces-in-path.sh — new markers with spaces in project path

### Estimated Total: ~100+ assertions (was 71+)

---

## Dependencies

| Dependency | Required | Checked By | Fallback |
|-----------|----------|-----------|----------|
| jq | Yes | session-start.sh | Hooks degraded |
| Superpowers plugin | Yes | session-start.sh | Warning, some hooks skip |
| Node.js | Yes (for Context7) | session-start.sh | Context7 install fails |
| Context7 MCP | Yes | session-start.sh | Auto-install with consent; if declined, Implementation Zone degraded |
| Playwright | No (web-app gate) | visual-auditor.sh | Gate skips with advisory |
| Tavily | No (advisory) | Not checked | Suggested in block message only |

---

## Non-Goals for v4.0.0

- Plugin architecture — zones provide organization without refactoring
- Tavily as hard dependency — advisory only
- Automated spec comparison for Visual Auditor — Claude self-reflects, no image diffing
- Per-zone enable/disable in manifest — all zones active if profile includes them; individual hooks can be toggled
