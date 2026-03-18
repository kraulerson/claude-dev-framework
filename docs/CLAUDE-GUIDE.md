# How This Framework Works — For Claude

This document explains the Claude Dev Framework from your perspective as the AI agent operating within it. The framework enforces development discipline through hooks that fire at specific points in your workflow.

## Session Lifecycle

### 1. Session Start

When a session begins, `session-start.sh` fires and injects context into your conversation. You will see:

- **Framework banner** with version, profile, branch, and sync status
- **Active rules** — one-line summaries of all rules you must follow
- **Warnings** — missing dependencies, outdated framework, stale discovery config
- **Marker instructions** — commands you MUST run at specific workflow points

### 2. During the Session

As you work, hooks fire at two points:

**Before writing source files** (`PreToolUse: Write|Edit`):
- `enforce-superpowers.sh` **blocks** you from writing source files if you haven't completed the Superpowers workflow (brainstorm/plan/implement). Create the marker after invoking a Superpowers skill, or after the user confirms skipping.
- `scalability-check.sh` **advises** you to consider future platform plans when editing architectural files.
- `changelog-sync-check.sh` **advises** you to run the sync command before editing the changelog.

**Before running bash commands** (`PreToolUse: Bash`):
- `enforce-evaluate.sh` **blocks** `git commit` if you haven't completed the evaluate-before-implement workflow. Present an evaluation and get user approval first, then create the marker.
- `pre-commit-checks.sh` **blocks** `git commit` if source files are staged but the changelog or version files are not.
- `branch-safety.sh` **blocks** `git push` to protected branches.

**After running bash commands** (`PostToolUse: Bash`):
- `sync-tracker.sh` silently creates markers when sync scripts succeed and clears evaluation/superpowers markers after a successful `git commit` (so you go through the workflow again for the next change).

### 3. Session End

When a session ends (not initiated by the user), `stop-checklist.sh` checks:
- Are there uncommitted source file changes? → **blocks**
- Were source files changed but changelog not updated? → **blocks**
- Did any commit in this session look like a bug fix without a test? → **blocks**
- Was context history updated in long sessions? → **blocks**

If all checks pass and the session produced commits, it also **advises**:
- **Plan closure** — if no plan closure marker exists, reminds you to document planned vs. actual outcomes
- **Session handoff** — reminds you to save a handoff note to the context history file

If the session ends due to `stop_reason: "user"` or `stop_reason: "tool_error"`, the checklist is skipped entirely.

## The Marker System

Markers are temporary files in `/tmp/` that track workflow completion. They are keyed by a hash of your project directory, so different projects don't interfere.

| Marker | Created when | Cleared when | Checked by |
|--------|-------------|--------------|------------|
| `.claude_evaluated_{hash}` | You present an evaluation and get user approval, then run `touch` | After successful `git commit` | `enforce-evaluate.sh` |
| `.claude_superpowers_{hash}` | You invoke a Superpowers skill, then run `touch` | After successful `git commit` | `enforce-superpowers.sh` |
| `.claude_session_start_{hash}` | Session starts (automatic) | Session ends | `stop-checklist.sh` |
| `.claude_changelog_synced_{hash}` | Sync script succeeds (automatic) | Not auto-cleared | `changelog-sync-check.sh` |
| `.claude_plan_closed_{hash}` | You document plan closure, then run `touch` | Session ends | `stop-checklist.sh` |

**Important**: The evaluation and Superpowers markers clear after each commit (via `sync-tracker.sh`). This means for each new piece of work in a session, you must go through those workflows again. This is intentional — it prevents a single approval from covering unrelated changes. Other markers have different lifecycles (see the "Cleared when" column above).

## Responding to Advisories

When you receive an advisory (additionalContext), you should:

1. **Acknowledge it** — don't ignore the reminder
2. **Follow the workflow** — present an evaluation, invoke Superpowers, etc.
3. **Get user approval** — the user confirms or says "skip"
4. **Create the marker** — run the `touch` command to record completion
5. **Proceed** — you can now write source files or commit

If the user says "skip evaluation" or "skip superpowers", create the marker anyway — the user has made a deliberate choice.

## Responding to Hard Blocks

When a hook blocks with exit 2 or `decision: "block"`:

- **Read the error message** — it tells you exactly what's missing
- **Fix the issue** — stage the changelog, bump the version, commit your work
- **Retry** — the hook will pass once the requirements are met
- **Do NOT work around blocks** — they exist to prevent real mistakes

## Terminology

See [GLOSSARY.md](GLOSSARY.md) for canonical terms. Key distinctions:
- **"blocks"** = hard stop, action cannot proceed
- **"advises"** = guidance injected, action proceeds
- **"source files"** = files with code extensions (matches `is_source_file()`)
- **"trivial"** = formatting, typos, config values, version numbers — no design decisions needed
- **"user approval"** = user explicitly agrees to proceed
