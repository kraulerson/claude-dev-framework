#!/usr/bin/env bash
# marker-tracker.sh — PostToolUse (all tools) unified marker management.
# Replaces: skill-tracker.sh, plan-tracker.sh, context7-tracker.sh, sync-tracker.sh
#
# Single entry point for all PostToolUse marker operations:
#   Skill        → superpowers + has_plan markers
#   TaskUpdate   → plan_active marker
#   Context7 MCP → per-library c7 markers
#   Bash         → changelog sync + post-commit marker clearing
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 0

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
[ -z "$TOOL" ] && exit 0

HASH=$(get_project_hash)

case "$TOOL" in

  # --- Skill tracking (was skill-tracker.sh) ---
  Skill)
    SKILL_NAME=$(echo "$INPUT" | jq -r '.tool_input.skill // empty' 2>/dev/null || echo "")
    # Create superpowers marker when any superpowers skill is invoked
    case "$SKILL_NAME" in
      superpowers:*|brainstorm*|writing-plans|executing-plans|test-driven*|systematic-debugging|requesting-code-review|receiving-code-review|dispatching*|finishing-a-development*|subagent-driven*|verification-before*)
        touch "/tmp/.claude_superpowers_${HASH}"
        ;;
    esac
    # Create has_plan marker when writing-plans is invoked (arms Planning Zone)
    case "$SKILL_NAME" in
      writing-plans|superpowers:writing-plans)
        touch "/tmp/.claude_has_plan_${HASH}"
        ;;
    esac
    ;;

  # --- Plan tracking (was plan-tracker.sh) ---
  TaskUpdate)
    STATUS=$(echo "$INPUT" | jq -r '.tool_input.status // empty' 2>/dev/null || echo "")
    case "$STATUS" in
      in_progress) touch "/tmp/.claude_plan_active_${HASH}" ;;
      completed)   rm -f "/tmp/.claude_plan_active_${HASH}" ;;
    esac
    ;;

  # --- Context7 tracking (was context7-tracker.sh) ---
  mcp__context7__resolve-library-id|mcp__context7__resolve_library_id|mcp__plugin_context7_context7__resolve-library-id|mcp__plugin_context7_context7__resolve_library_id)
    LIB=$(echo "$INPUT" | jq -r '.tool_input.libraryName // empty' 2>/dev/null || echo "")
    [ -z "$LIB" ] && exit 0
    NORMALIZED=$(echo "$LIB" | tr '[:upper:]' '[:lower:]' | sed 's|^[@/]*||' | tr '/' '-')
    touch "/tmp/.claude_c7_${HASH}_${NORMALIZED}"
    ;;
  mcp__context7__get-library-docs|mcp__context7__get_library_docs|mcp__plugin_context7_context7__get-library-docs|mcp__plugin_context7_context7__get_library_docs|mcp__context7__query-docs|mcp__plugin_context7_context7__query-docs)
    LIB=$(echo "$INPUT" | jq -r '.tool_input.context7CompatibleLibraryID // empty' 2>/dev/null || echo "")
    [ -z "$LIB" ] && exit 0
    NORMALIZED=$(echo "$LIB" | tr '[:upper:]' '[:lower:]' | sed 's|^[@/]*||' | tr '/' '-')
    touch "/tmp/.claude_c7_${HASH}_${NORMALIZED}"
    ;;

  # --- Sync tracking (was sync-tracker.sh) ---
  Bash)
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
    EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_response.exit_code // "1"' 2>/dev/null || echo "1")
    # Track successful sync script executions
    if echo "$COMMAND" | grep -qE 'sync-(changelog|shared|ios)\.sh' && [ "$EXIT_CODE" = "0" ]; then
      touch "/tmp/.claude_changelog_synced_${HASH}"
    fi
    # Clear evaluation/superpowers/plan_active markers after successful commit
    if echo "$COMMAND" | grep -qE '\bgit\b.*\bcommit\b' && [ "$EXIT_CODE" = "0" ]; then
      rm -f "/tmp/.claude_evaluated_${HASH}"
      rm -f "/tmp/.claude_superpowers_${HASH}"
      rm -f "/tmp/.claude_plan_active_${HASH}"
    fi
    ;;

esac
exit 0
