#!/usr/bin/env bash
# context7-tracker.sh — PostToolUse hook for Implementation Zone
# Watches Context7 MCP tool calls and creates per-library markers.
# These markers are checked by enforce-context7.sh before source edits.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 0

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")

# Match Context7 MCP tool names
case "$TOOL" in
  mcp__context7__resolve-library-id|mcp__context7__resolve_library_id)
    LIB=$(echo "$INPUT" | jq -r '.tool_input.libraryName // empty' 2>/dev/null || echo "")
    ;;
  mcp__context7__get-library-docs|mcp__context7__get_library_docs)
    LIB=$(echo "$INPUT" | jq -r '.tool_input.context7CompatibleLibraryID // empty' 2>/dev/null || echo "")
    ;;
  *) exit 0 ;;
esac

[ -z "$LIB" ] && exit 0

HASH=$(get_project_hash)

# Normalize: lowercase, strip leading @/ characters, replace / with -
NORMALIZED=$(echo "$LIB" | tr '[:upper:]' '[:lower:]' | sed 's|^[@/]*||' | tr '/' '-')

touch "/tmp/.claude_c7_${HASH}_${NORMALIZED}"
exit 0
