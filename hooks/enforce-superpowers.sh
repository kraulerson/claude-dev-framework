#!/usr/bin/env bash
# enforce-superpowers.sh — PreToolUse (Write|Edit|Read) blocking hook
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
# Allow if superpowers workflow completed OR brainstorming skill is active
[ -f "/tmp/.claude_superpowers_${HASH}" ] && exit 0
[ -f "/tmp/.claude_skill_active_${HASH}" ] && exit 0

echo "BLOCKED — The Superpowers workflow (brainstorm → plan → implement) has not been invoked this session. You must brainstorm BEFORE reading source files for implementation. To begin: run 'touch /tmp/.claude_skill_active_${HASH}' then invoke the appropriate Superpowers skill. If the user has already said 'skip superpowers', create the marker instead: touch /tmp/.claude_superpowers_${HASH}" >&2
exit 2
