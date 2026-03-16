# Hook Reference

## session-start.sh
- **Event:** SessionStart
- **Blocking:** No
- **Purpose:** Load active rules as context, inject marker instructions, check framework sync, verify plugins, load context history
- **Customize:** Edit `manifest.json → activeRules` to change which rules are loaded
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
- **Marker:** `/tmp/.claude_changelog_synced_{hash}` — created by sync-tracker
- **Disable:** Remove `changelog-sync-check` from `manifest.json → activeHooks`

## scalability-check.sh
- **Event:** PreToolUse (Write|Edit)
- **Blocking:** Advisory (JSON additionalContext)
- **Purpose:** Reminds about future platform plans when editing architecture-relevant files
- **Configured by:** `manifest.json → discovery → futurePlatforms`
- **Disable:** Remove `scalability-check` from `manifest.json → activeHooks`

## sync-tracker.sh
- **Event:** PostToolUse (Bash)
- **Blocking:** No
- **Purpose:** Creates changelog sync marker when sync scripts succeed
- **Disable:** Remove `sync-tracker` from `manifest.json → activeHooks`
