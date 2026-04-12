#!/usr/bin/env bash
# marker-guard.sh — PreToolUse (Bash) blocks manual marker creation
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 1

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")

# Allow the sanctioned mark-evaluated.sh script
echo "$COMMAND" | grep -qE 'mark-evaluated\.sh' && exit 0

# Block any command that references workflow marker paths (any creation method)
if echo "$COMMAND" | grep -qE '/tmp/\.claude_(superpowers|evaluated|plan_closed|plan_active|has_plan|skill_active|c7|c7_degraded)_'; then
  echo "BLOCKED — Manual marker creation is not permitted. Markers are created automatically by the framework when you complete the required workflow. Invoke the appropriate Superpowers skill or present an evaluation to proceed." >&2
  exit 2
fi
exit 0
