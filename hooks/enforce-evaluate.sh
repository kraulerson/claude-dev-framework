#!/usr/bin/env bash
# enforce-evaluate.sh — PreToolUse (Bash) blocking hook
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 1

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
echo "$COMMAND" | grep -qE '^\s*git\s+commit' || exit 0

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
MSG
exit 2
