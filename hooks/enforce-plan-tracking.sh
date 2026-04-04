#!/usr/bin/env bash
# enforce-plan-tracking.sh — PreToolUse (Write|Edit) blocking hook for Planning Zone
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 1
source "$SCRIPT_DIR/_preflight.sh"

preflight_init
preflight_skip_non_source && exit 0

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
