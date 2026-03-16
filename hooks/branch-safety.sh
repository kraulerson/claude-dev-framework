#!/usr/bin/env bash
# branch-safety.sh — PreToolUse (Bash) BLOCKING hook
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 1

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
echo "$COMMAND" | grep -qE '^\s*git\s+push' || exit 0

BRANCH=$(get_branch)

PROTECTED=$(get_manifest_array '.projectConfig._base.protectedBranches[]')
for pb in $PROTECTED; do
  if [ "$BRANCH" = "$pb" ]; then
    echo "PUSH BLOCKED — You are on protected branch '$BRANCH'. Direct pushes are not allowed." >&2
    exit 2
  fi
done

DEV_BRANCHES=$(get_branch_config_array '.devBranches')
if [ -n "$DEV_BRANCHES" ]; then
  ALLOWED=false
  for db in $DEV_BRANCHES; do
    [[ "$BRANCH" == $db ]] && { ALLOWED=true; break; }
  done
  if [ "$ALLOWED" = false ]; then
    echo "PUSH BLOCKED — Branch '$BRANCH' is not in the allowed dev branches for this config. Allowed: $DEV_BRANCHES" >&2
    exit 2
  fi
fi
exit 0
