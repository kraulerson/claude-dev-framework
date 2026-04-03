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
