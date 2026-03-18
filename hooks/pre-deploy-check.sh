#!/usr/bin/env bash
# pre-deploy-check.sh — PreToolUse (Bash) advisory hook
# Warns if deployment-related commands are run with unpushed commits.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 0

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
[[ -z "$COMMAND" ]] && exit 0

# Built-in deployment command patterns
DEPLOY_PATTERNS='git\s+pull|docker\s+compose|docker-compose|kubectl\s+(apply|rollout)|ssh\s+.*(deploy|restart|pull)|rsync'

# Add project-specific deploy commands from discovery
CUSTOM_CMDS=$(get_manifest_value '.discovery.deployCommands')
if [[ -n "$CUSTOM_CMDS" && "$CUSTOM_CMDS" != "N/A" && "$CUSTOM_CMDS" != "n/a" ]]; then
  ESCAPED=$(echo "$CUSTOM_CMDS" | sed 's/[.[\*^$()+?{}|]/\\&/g')
  DEPLOY_PATTERNS="${DEPLOY_PATTERNS}|${ESCAPED}"
fi

# Only proceed if command matches a deployment pattern
echo "$COMMAND" | grep -qE "$DEPLOY_PATTERNS" || exit 0

# Check for upstream tracking branch
UPSTREAM=$(git rev-parse --abbrev-ref '@{u}' 2>/dev/null || echo "")
if [[ -z "$UPSTREAM" ]]; then
  jq -n '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "additionalContext": "WARNING: This branch has no upstream tracking branch set. If deploying remotely, push first: git push -u origin <branch>\n\nThis advisory is not optional guidance. Acknowledge and act on it before proceeding."
    }
  }'
  exit 0
fi

# Check for unpushed commits
UNPUSHED=$(git log '@{u}'..HEAD --oneline 2>/dev/null || echo "")
if [[ -n "$UNPUSHED" ]]; then
  COUNT=$(echo "$UNPUSHED" | wc -l | xargs)
  jq -n --arg c "$COUNT" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "additionalContext": ("HOLD — You have " + $c + " unpushed commit(s) on this branch. Push to remote before deploying or pulling on another machine. Run: git push\n\nThis advisory is not optional guidance. Acknowledge and act on it before proceeding.")
    }
  }'
fi
exit 0
