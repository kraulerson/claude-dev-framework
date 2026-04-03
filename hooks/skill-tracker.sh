#!/usr/bin/env bash
# skill-tracker.sh — PostToolUse (all tools) automatic marker creation
# Detects Superpowers skill invocations and creates markers automatically.
# Claude should never create markers manually — this hook does it.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 0

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")

# Only act on Skill tool invocations
[ "$TOOL" = "Skill" ] || exit 0

HASH=$(get_project_hash)
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
exit 0
