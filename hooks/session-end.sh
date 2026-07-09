#!/usr/bin/env bash
# session-end.sh — SessionEnd hook. Clears session-scoped workflow markers so
# a finished session cannot pre-unlock enforcement zones for the next one (R-06).
# The eval audit log (/tmp/.claude_eval_log_*) is intentionally preserved.
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
