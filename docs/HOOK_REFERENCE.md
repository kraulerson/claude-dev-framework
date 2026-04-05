# Hook Reference

## Enforcement Zones (v4.0.0)

| Zone | Hooks | Purpose |
|------|-------|---------|
| Discovery | session-start.sh | Dependency checks, zone activation, Context7 install |
| Design | enforce-superpowers.sh, marker-tracker.sh | Blocks edits until Superpowers skill invoked |
| Planning | enforce-plan-tracking.sh, marker-tracker.sh | Blocks edits until plan task is in_progress |
| Implementation | enforce-context7.sh, marker-tracker.sh | Blocks edits using unresearched libraries |
| Verification | enforce-evaluate.sh, pre-commit-checks.sh, verification-gate.sh | Pre-commit quality gates |

---

## session-start.sh
- **Event:** SessionStart
- **Zone:** Discovery
- **Blocking:** No
- **Purpose:** Activates enforcement zones, checks dependencies (jq, Superpowers, Context7), outputs terse zone report, loads context history
- **Customize:** Edit `manifest.json → activeRules` to change rule count; `verificationGates` to change gate listing
- **Disable:** Remove `session-start` from `manifest.json → activeHooks`

## enforce-evaluate.sh
- **Event:** PreToolUse (Bash)
- **Blocking:** Advisory (JSON additionalContext)
- **Purpose:** Injects reminder if `git commit` runs without an evaluation marker
- **Marker:** `/tmp/.claude_evaluated_{hash}` — created when evaluation is approved
- **Disable:** Remove `enforce-evaluate` from `manifest.json → activeHooks`

## enforce-superpowers.sh
- **Event:** PreToolUse (Write|Edit)
- **Blocking:** Advisory (JSON additionalContext)
- **Purpose:** Injects reminder if source files are written without Superpowers workflow
- **Skips:** Docs, config, test files
- **Marker:** `/tmp/.claude_superpowers_{hash}` — created when Superpowers skill is invoked
- **Disable:** Remove `enforce-superpowers` from `manifest.json → activeHooks`

## pre-commit-checks.sh
- **Event:** PreToolUse (Bash)
- **Blocking:** Yes (exit 2)
- **Purpose:** Blocks `git commit` if version files or changelog not staged alongside source changes
- **Configured by:** `manifest.json → projectConfig → versionFiles`, `changelogFile`, `sourceExtensions`
- **Disable:** Remove `pre-commit-checks` from `manifest.json → activeHooks`

## branch-safety.sh
- **Event:** PreToolUse (Bash)
- **Blocking:** Yes (exit 2)
- **Purpose:** Blocks `git push` to protected branches or outside allowed dev branches
- **Configured by:** `manifest.json → projectConfig → protectedBranches`, `devBranches`
- **Disable:** Remove `branch-safety` from `manifest.json → activeHooks`

## stop-checklist.sh
- **Event:** Stop
- **Blocking:** Yes (JSON `decision: "block"`)
- **Purpose:** Blocks session end if uncommitted work, missing changelog, bug fix without test, or long session without context history
- **Never blocks:** User-initiated stops or tool errors
- **Disable:** Remove `stop-checklist` from `manifest.json → activeHooks`

## pre-compact-reminder.sh
- **Event:** PreCompact
- **Blocking:** Advisory (JSON additionalContext)
- **Purpose:** Warns to save context history before compression
- **Disable:** Remove `pre-compact-reminder` from `manifest.json → activeHooks`

## changelog-sync-check.sh
- **Event:** PreToolUse (Write|Edit)
- **Blocking:** Advisory (JSON additionalContext)
- **Purpose:** Warns before editing changelog if upstream changes exist
- **Marker:** `/tmp/.claude_changelog_synced_{hash}` — created by marker-tracker
- **Disable:** Remove `changelog-sync-check` from `manifest.json → activeHooks`

## scalability-check.sh
- **Event:** PreToolUse (Write|Edit)
- **Blocking:** Advisory (JSON additionalContext)
- **Purpose:** Reminds about future platform plans when editing architecture-relevant files
- **Configured by:** `manifest.json → discovery → futurePlatforms`
- **Disable:** Remove `scalability-check` from `manifest.json → activeHooks`

## pre-deploy-check.sh
- **Event:** PreToolUse (Bash)
- **Blocking:** Advisory (JSON additionalContext)
- **Purpose:** Warns before deployment commands (docker compose, kubectl, git pull, ssh, rsync) if there are unpushed commits
- **Configured by:** `manifest.json → discovery → deployCommands` (custom deploy commands)
- **Disable:** Remove `pre-deploy-check` from `manifest.json → activeHooks`

## marker-tracker.sh
- **Event:** PostToolUse (all tools)
- **Zone:** Design + Planning + Implementation
- **Blocking:** No
- **Purpose:** Unified PostToolUse marker management. Creates superpowers/has_plan markers on Superpowers skill invoke; creates/clears plan_active marker on TaskUpdate; creates per-library c7 markers on Context7 MCP queries; creates changelog_synced marker on sync scripts; clears evaluation/superpowers/plan_active markers after successful commit
- **Markers:** `.claude_superpowers_{hash}`, `.claude_has_plan_{hash}`, `.claude_plan_active_{hash}`, `.claude_c7_{hash}_{library}`, `.claude_changelog_synced_{hash}`
- **Disable:** Remove `marker-tracker` from `manifest.json → activeHooks`

## marker-guard.sh
- **Event:** PreToolUse (Bash)
- **Blocking:** Yes (exit 2)
- **Purpose:** Blocks manual creation of workflow markers via `touch` command. Prevents Claude from forging markers to bypass enforcement.
- **Allowed:** `mark-evaluated.sh` script path
- **Disable:** Remove `marker-guard` from `manifest.json → activeHooks`

## enforce-plan-tracking.sh
- **Event:** PreToolUse (Write|Edit)
- **Zone:** Planning
- **Blocking:** Yes (exit 2)
- **Purpose:** Blocks source file edits until a plan task is marked in_progress via TaskUpdate
- **Skips:** Docs, config, test files; also skips if no `has_plan` marker exists (zone not armed)
- **Marker:** `/tmp/.claude_plan_active_{hash}` — created by marker-tracker.sh when TaskUpdate sets status to in_progress
- **Disable:** Remove `enforce-plan-tracking` from `manifest.json → activeHooks`

## enforce-context7.sh
- **Event:** PreToolUse (Write|Edit)
- **Zone:** Implementation
- **Blocking:** Yes (exit 2)
- **Purpose:** Scans code being written for import/require statements. Blocks if any third-party library hasn't been researched via Context7 MCP.
- **Skips:** Docs, config, test files; standard library imports (known-stdlib.txt); relative imports; degraded mode
- **Marker:** `/tmp/.claude_c7_{hash}_{library}` — one per researched library, created by marker-tracker.sh
- **Disable:** Remove `enforce-context7` from `manifest.json → activeHooks`

## verification-gate.sh
- **Event:** PreToolUse (Bash)
- **Zone:** Verification
- **Blocking:** Yes (exit 2)
- **Purpose:** Runs configurable verification gates before git commit. Gates are defined in `manifest.json → projectConfig._base.verificationGates[]`
- **Gate types:** `failOn: "exit_code"` (non-zero fails), `failOn: "stderr"` (pattern match), `failOn: "stdout"` (pattern match)
- **Built-in gates:** Linter-Gate, Visual Auditor (web-app), Type-Check Gate
- **Disable:** Remove `verification-gate` from `manifest.json → activeHooks` or set individual gates to `enabled: false`
