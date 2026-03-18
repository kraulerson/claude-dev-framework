#!/usr/bin/env bash
# pre-compact-reminder.sh — PreCompact advisory hook
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 0

CTX_FILE=$(get_branch_config_value '.contextHistoryFile')
[ -z "$CTX_FILE" ] && exit 0

CTX_DIRTY=$(git diff --name-only -- "$CTX_FILE" 2>/dev/null || true)
CTX_STAGED=$(git diff --cached --name-only -- "$CTX_FILE" 2>/dev/null || true)

if [ -z "$CTX_DIRTY" ] && [ -z "$CTX_STAGED" ]; then
  jq -n --arg f "$CTX_FILE" '{
    "hookSpecificOutput": {
      "hookEventName": "PreCompact",
      "additionalContext": ("CONTEXT COMPACTION WARNING: Append a session summary to " + $f + " NOW before compaction. After compaction, re-read: " + $f + " and any active source files.\n\nThis advisory is not optional guidance. Acknowledge and act on it before proceeding.")
    }
  }'
fi
exit 0
