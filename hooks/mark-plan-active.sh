#!/usr/bin/env bash
# mark-plan-active.sh — Sanctioned path for creating the plan-active marker (#38)
# For a session or subagent without the TaskUpdate tool: marks the plan task it is
# starting as in_progress, as TaskUpdate does through marker-tracker.sh.
# Usage: bash .claude/framework/hooks/mark-plan-active.sh "task you are starting"
# The task is plain text, no shell punctuation. Run it as a lone command from the
# project root; the guards refuse chained forms. Each commit clears the marker, so the
# next task needs a fresh mark.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || { echo "ERROR: Could not load helpers" >&2; exit 1; }

USAGE="Usage: bash .claude/framework/hooks/mark-plan-active.sh \"task you are starting\" (plain text, no shell punctuation)"
fail() { echo "ERROR: $1 $USAGE" >&2; exit 1; }

# Task: exactly one non-blank, single-line argument
[ "$#" -eq 1 ] || fail "A single quoted task is required."
TASK="$1"
[[ -n "${TASK//[[:space:]]/}" ]] || fail "The task is empty."
[[ "$TASK" != *$'\n'* ]] || fail "The task must be one line."

HASH=$(get_project_hash)
[ -f "/tmp/.claude_has_plan_${HASH}" ] \
  || fail "No written plan for this project (the Planning Zone is not armed), so there is no plan task to activate and source edits are not blocked by it."

TIMESTAMP=$(date +%Y-%m-%dT%H:%M:%S)

# Create the marker; each call appends its task record
printf '%s | %s\n' "$TIMESTAMP" "$TASK" >> "/tmp/.claude_plan_active_${HASH}"

echo "Active plan task marker created. Task: ${TASK}"
