#!/usr/bin/env bash
# sync-tracker.sh — PostToolUse (Bash) marker tracker
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 0

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_response.exit_code // "1"' 2>/dev/null || echo "1")
HASH=$(get_project_hash)

# Track successful sync script executions
if echo "$COMMAND" | grep -qE 'sync-(changelog|shared|ios)\.sh' && [ "$EXIT_CODE" = "0" ]; then
  touch "/tmp/.claude_changelog_synced_${HASH}"
fi

# Clear evaluation/superpowers/skill_active markers after successful commit
# so the next change in this session goes through the workflow again
if echo "$COMMAND" | grep -qE '^\s*git\s+commit' && [ "$EXIT_CODE" = "0" ]; then
  rm -f "/tmp/.claude_evaluated_${HASH}"
  rm -f "/tmp/.claude_superpowers_${HASH}"
  rm -f "/tmp/.claude_skill_active_${HASH}"
fi
exit 0
