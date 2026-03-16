#!/usr/bin/env bash
# enforce-evaluate.sh — PreToolUse (Bash) advisory hook
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 1

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
echo "$COMMAND" | grep -qE '^\s*git\s+commit' || exit 0

HASH=$(get_project_hash)
[ -f "/tmp/.claude_evaluated_${HASH}" ] && exit 0

jq -n --arg m "/tmp/.claude_evaluated_${HASH}" '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": ("HOLD — The evaluate-before-implement rule requires you to present an evaluation (pros, cons, alternatives) and get user approval before committing. If this is a trivial change, ask the user to confirm skipping evaluation. To create the marker: touch " + $m)
  }
}'
exit 0
