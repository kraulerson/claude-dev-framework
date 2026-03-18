#!/usr/bin/env bash
# marker-guard.sh — PreToolUse (Bash) blocks manual marker creation
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 1

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")

# Block any attempt to manually create workflow markers
if echo "$COMMAND" | grep -qE 'touch.*/tmp/\.claude_(superpowers|evaluated|plan_closed|skill_active)_'; then
  echo "BLOCKED — Manual marker creation is not permitted. Markers are created automatically by the framework when you complete the required workflow. Invoke the appropriate Superpowers skill or present an evaluation to proceed." >&2
  exit 2
fi
exit 0
