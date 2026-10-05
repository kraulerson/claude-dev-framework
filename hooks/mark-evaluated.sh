#!/usr/bin/env bash
# mark-evaluated.sh — the USER's manual override for the evaluation marker.
# Run it yourself, in a separate terminal (not through Claude Code and not as a `!`
# command), from the project root, after staging the change you approve:
#   bash .claude/framework/hooks/mark-evaluated.sh "brief description of what was approved"
# The agent cannot run it: the guards refuse it, and it refuses under Claude Code
# (CLAUDECODE is set there). Inside Claude Code, approval comes from answering the
# agent's recorded question with the option id (record-approval.sh; approval design B).
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
