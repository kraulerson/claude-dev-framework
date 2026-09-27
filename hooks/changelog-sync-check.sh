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
  # GNU form first (#10): GNU `stat -f` is file-system status — it prints a block on
  # stdout and fails, so the fallback's epoch was appended to it. BSD `stat -c` fails
  # with nothing on stdout, so this order yields a clean epoch on both.
  MTIME=$(stat -c %Y "$MARKER" 2>/dev/null || stat -f %m "$MARKER" 2>/dev/null || echo 0)
  # Only a plain number reaches the arithmetic; anything else counts as stale.
  case "$MTIME" in ''|*[!0-9]*) MTIME=0 ;; esac
  AGE=$(( $(date +%s) - MTIME ))
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
