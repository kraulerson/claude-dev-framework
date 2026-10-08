#!/usr/bin/env bash
# session-end.sh — SessionEnd hook. Clears session-scoped workflow markers so
# a finished session cannot pre-unlock enforcement zones for the next one (R-06).
# The eval audit log (/tmp/.claude_eval_log_*) is intentionally preserved, and so is
# the approval render record (/tmp/.claude_approval_shown_*): it is bound to its
# session_id, so it can only be picked in a resumed run of the same session, which is
# how a headless driver sends each reply (`claude -p --resume <id>`, one process per
# reply). session-start.sh clears it when another session starts.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 0

HASH=$(get_project_hash)
rm -f "/tmp/.claude_superpowers_${HASH}" \
      "/tmp/.claude_evaluated_${HASH}" \
      "/tmp/.claude_has_plan_${HASH}" \
      "/tmp/.claude_plan_active_${HASH}" \
      "/tmp/.claude_plan_closed_${HASH}" \
      "/tmp/.claude_changelog_synced_${HASH}" \
      "/tmp/.claude_c7_degraded_${HASH}" \
      "/tmp/.claude_session_start_${HASH}" \
      "/tmp/.claude_last_head_${HASH}"
rm -f "/tmp/.claude_c7_${HASH}_"* 2>/dev/null || true
rm -f "/tmp/.claude_stop_errors_hash_${HASH}"* 2>/dev/null || true
exit 0
