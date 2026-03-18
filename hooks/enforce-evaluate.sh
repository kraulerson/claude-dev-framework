#!/usr/bin/env bash
# enforce-evaluate.sh — PreToolUse (Bash) blocking hook
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 1

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
echo "$COMMAND" | grep -qE '^\s*git\s+commit' || exit 0

HASH=$(get_project_hash)
[ -f "/tmp/.claude_evaluated_${HASH}" ] && exit 0

echo "BLOCKED — The evaluate-before-implement rule requires you to present an evaluation (pros, cons, alternatives) and get user approval before committing. If the user has already said 'skip evaluation', create the marker. Otherwise, follow the workflow. Marker: touch /tmp/.claude_evaluated_${HASH}" >&2
exit 2
