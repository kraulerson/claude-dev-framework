#!/usr/bin/env bash
# sync-tracker.sh — PostToolUse (Bash) marker tracker
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 0

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_response.exit_code // "1"' 2>/dev/null || echo "1")

if echo "$COMMAND" | grep -qE 'sync-(changelog|shared|ios)\.sh' && [ "$EXIT_CODE" = "0" ]; then
  HASH=$(get_project_hash)
  touch "/tmp/.claude_changelog_synced_${HASH}"
fi
exit 0
