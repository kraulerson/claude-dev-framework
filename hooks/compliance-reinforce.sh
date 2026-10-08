#!/usr/bin/env bash
# compliance-reinforce.sh — UserPromptSubmit advisory hook.
# Re-injects a one-line compliance frame each user turn. Layer 1's session-start
# directive measurably fades over task boundaries (see COMPLIANCE_ENGINEERING.md);
# this keeps the frame present at every decision point. Kept to ONE line to
# bound per-turn context cost.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 0

# The time leads the line (#30): nothing else tells the agent today's date. A _helpers.sh
# older than this hook (a sync left half done) has no cdf_now_line: remind without it.
NOW_LINE=""
type cdf_now_line >/dev/null 2>&1 && NOW_LINE=$(cdf_now_line)
jq -n --arg ctx "${NOW_LINE:+$NOW_LINE }FRAMEWORK REMINDER: Enforcement hooks are active. Follow blocked-hook instructions exactly; never bypass, forge markers, or classify work as trivial to skip the workflow." '{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": $ctx
  }
}'
exit 0
