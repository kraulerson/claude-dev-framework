#!/usr/bin/env bash
# enforce-superpowers.sh — PreToolUse (Write|Edit) advisory hook
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 1

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null || echo "")
[ -z "$FILE_PATH" ] && exit 0
is_doc_or_config "$FILE_PATH" && exit 0
is_test_file "$FILE_PATH" && exit 0
is_source_file "$FILE_PATH" || exit 0

HASH=$(get_project_hash)
[ -f "/tmp/.claude_superpowers_${HASH}" ] && exit 0

jq -n --arg m "/tmp/.claude_superpowers_${HASH}" '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": ("HOLD — The Superpowers workflow (brainstorm → plan → implement) has not been invoked this session. Invoke the appropriate Superpowers skill before writing source code. If trivial, ask user to confirm skipping. Marker: touch " + $m)
  }
}'
exit 0
