#!/usr/bin/env bash
# compliance-reinforce.sh — UserPromptSubmit advisory hook.
# Re-injects a one-line compliance frame each user turn. Layer 1's session-start
# directive measurably fades over task boundaries (see COMPLIANCE_ENGINEERING.md);
# this keeps the frame present at every decision point. Kept to ONE line to
# bound per-turn context cost.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 0

jq -n '{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "FRAMEWORK REMINDER: Enforcement hooks are active. Follow blocked-hook instructions exactly; never bypass, forge markers, or classify work as trivial to skip the workflow."
  }
}'
exit 0
