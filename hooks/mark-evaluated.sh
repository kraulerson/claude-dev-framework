#!/usr/bin/env bash
# mark-evaluated.sh — the USER's manual override for the evaluation marker.
# Run it yourself, in a separate terminal (not through Claude Code and not as a `!`
# command), from the project root, after staging the change you approve:
#   bash .claude/framework/hooks/mark-evaluated.sh "brief description of what was approved"
# It then shows a code on your terminal; type it back to approve.
# The agent cannot run it: the guards refuse it (any copy, any folder, by name), it
# refuses under Claude Code (CLAUDECODE is set there), and it needs a terminal, which
# the agent's Bash tool does not have. Inside Claude Code, approval comes from
# answering the agent's recorded question with the option id (record-approval.sh;
# approval design B).
# Like a pick, the marker is bound to HEAD, the staged tree, the git hooks and the git
# config at this moment; any change before the commit voids it.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || { echo "ERROR: Could not load helpers" >&2; exit 1; }

if [ -n "${CLAUDECODE:-}" ]; then
  echo "ERROR: mark-evaluated.sh is the user's own override. Run it in a separate terminal, not through Claude Code or a ! command (CLAUDECODE is set here). Inside Claude Code, approve by answering the agent's recorded question with the option id." >&2
  exit 1
fi
REASON="${1:-}"
if [ -z "$REASON" ]; then
  echo "ERROR: A reason is required. Usage: bash .claude/framework/hooks/mark-evaluated.sh \"description of what was approved\"" >&2
  exit 1
fi
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required." >&2; exit 1; }
STATE=$(git_stage_state .) || { echo "ERROR: could not read the staged state (unresolved conflicts, or not a git repository)." >&2; exit 1; }

# The user, at a terminal: a code shown on the controlling terminal must be typed back
# there. CLAUDECODE alone is one variable the agent can clear (`CLAUDECODE= bash …`);
# the agent's Bash tool has no controlling terminal, so a plain run cannot open
# /dev/tty, and stdin is not read, so a pipe answers nothing. This is not the barrier
# against a determined agent: a pseudo-terminal driver (expect) can read the code and
# type it back. The barrier is config-guard refusing the script by name; a renamed copy
# is R-23.
if ! { exec 3<>/dev/tty; } 2>/dev/null; then
  echo "ERROR: mark-evaluated.sh must be run by you at a terminal (it asks you to type a code there); this process has none. Run it in your own separate terminal window." >&2
  exit 1
fi
CODE=$(( $(od -An -N4 -tu4 /dev/urandom | tr -d ' ') % 900000 + 100000 ))
printf 'Approve committing the staged change (tree %s): %s\nType %s and press Enter to approve (anything else cancels): ' \
  "$(jq -r .tree <<< "$STATE" | cut -c1-12)" "$REASON" "$CODE" >&3
IFS= read -r ANSWER <&3 || ANSWER=""
exec 3>&-
if [ "$ANSWER" != "$CODE" ]; then
  echo "Cancelled: the code was not typed back. Nothing was approved." >&2
  exit 1
fi

HASH=$(get_project_hash)
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
RECORD=$(jq -nc --arg r "$REASON" --arg now "$NOW" --argjson st "$STATE" \
  '{event: "approval", source: "override", reason: $r, picked_at: $now} + $st')
TMP=$(mktemp "/tmp/.claude_evaluated_${HASH}.XXXXXX")
printf '%s\n' "$RECORD" > "$TMP" && mv -f "$TMP" "/tmp/.claude_evaluated_${HASH}"
mkdir -p "${CLAUDE_PROJECT_DIR:-.}/.claude"
printf '%s\n' "$RECORD" >> "${CLAUDE_PROJECT_DIR:-.}/.claude/approvals.jsonl"
echo "${NOW} | override | ${REASON}" >> "/tmp/.claude_eval_log_${HASH}"

echo "Evaluation marker created for the staged change (tree $(jq -r .tree <<< "$STATE" | cut -c1-12)). Reason: ${REASON}"
