#!/usr/bin/env bash
# enforce-superpowers.sh — PreToolUse (Write|Edit) blocking hook
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

cat >&2 << MSG
BLOCKED — You MUST invoke a Superpowers skill before writing source files.

DO NOT present an evaluation, propose an approach, or ask to proceed.
DO NOT try to shortcut around this with text. That is not compliance.

YOUR ONLY OPTIONS:
  1. Invoke the Superpowers brainstorming skill now (use the Skill tool)
  2. If the user has already said "skip superpowers", run: touch /tmp/.claude_superpowers_${HASH}

This edit will not proceed until the marker exists.
MSG
exit 2
