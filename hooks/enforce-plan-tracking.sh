#!/usr/bin/env bash
# enforce-plan-tracking.sh — PreToolUse (Bash|Write|Edit) blocking hook for Planning Zone
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 1
source "$SCRIPT_DIR/_preflight.sh"

preflight_init
preflight_bash_as_writes ext
preflight_skip_non_source && exit 0

HASH=$(get_project_hash)

# Planning Zone only arms when writing-plans has been invoked
[ -f "/tmp/.claude_has_plan_${HASH}" ] || exit 0

# Check for active plan task
[ -f "/tmp/.claude_plan_active_${HASH}" ] && exit 0

cat >&2 << 'MSG'
BLOCKED [Planning Zone] — No plan task is in_progress.

You have a written plan for this session. Before editing source files, mark the task you are working on as in_progress, one of two ways:
  1. TaskUpdate with status in_progress. If TaskUpdate is a deferred tool, load it first with ToolSearch.
  2. Without TaskUpdate, run this as its own Bash call from the project root (no cd, chaining, pipes or redirection; the task in plain text, no shell punctuation):
     bash .claude/framework/hooks/mark-plan-active.sh "<task>"

Each commit clears the mark, so mark the next task the same way before editing for it.

Do NOT edit source files without an active plan task.
Do NOT skip this because the change seems small.
Do NOT create the marker any other way — only TaskUpdate and mark-plan-active.sh create it.

COMPLIANCE REMINDER: Your obligation is compliance first, speed second. There is no task small enough to skip this requirement.
MSG
exit 2
