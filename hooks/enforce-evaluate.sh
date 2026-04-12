#!/usr/bin/env bash
# enforce-evaluate.sh — PreToolUse (Bash) blocking hook
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 1

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
echo "$COMMAND" | grep -qE '\bgit\b.*\bcommit\b' || exit 0

HASH=$(get_project_hash)
[ -f "/tmp/.claude_evaluated_${HASH}" ] && exit 0

FRAMEWORK_DIR=$(get_framework_dir)
cat >&2 << MSG
BLOCKED — Commit requires evaluate-before-implement workflow.

You MUST present an evaluation (pros, cons, alternatives) and get user approval before committing.
Do NOT commit and explain afterward.
Do NOT assume the user approves because they asked for the change.
Do NOT skip this because the change seems simple.
Do NOT create the marker manually with touch.

After presenting your evaluation and receiving user approval, run:
bash ${FRAMEWORK_DIR}/hooks/mark-evaluated.sh "brief description of what was approved"
Then retry the commit.

COMPLIANCE REMINDER: Your obligation is compliance first, speed second. There is no task small enough to skip this requirement. Do not classify this change as trivial. Do not run a cost-benefit analysis against the process. Follow the required workflow, then proceed.
MSG
exit 2
