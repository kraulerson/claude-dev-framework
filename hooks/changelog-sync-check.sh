#!/usr/bin/env bash
# changelog-sync-check.sh — PreToolUse (Write|Edit) advisory hook
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 1
source "$SCRIPT_DIR/_preflight.sh"

preflight_init
[ -z "$_PF_FILE_PATH" ] && exit 0

CHANGELOG=$(get_branch_config_value '.changelogFile')
[ -z "$CHANGELOG" ] && exit 0
echo "$_PF_FILE_PATH" | grep -q "$CHANGELOG" || exit 0

HASH=$(get_project_hash)
MARKER="/tmp/.claude_changelog_synced_${HASH}"
if [ -f "$MARKER" ]; then
  AGE=$(( $(date +%s) - $(stat -f %m "$MARKER" 2>/dev/null || stat -c %Y "$MARKER" 2>/dev/null || echo 0) ))
  [ "$AGE" -lt 3600 ] && exit 0
fi

SYNC_CMD=$(get_branch_config_value '.syncCommand')
[ -z "$SYNC_CMD" ] && exit 0

jq -n --arg cmd "$SYNC_CMD" '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": ("IMPORTANT: Before editing the changelog, run the sync command first to merge upstream changes: " + $cmd + "\n\nThis advisory is not optional guidance. Acknowledge and act on it before proceeding.")
  }
}'
exit 0
