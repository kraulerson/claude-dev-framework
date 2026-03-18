#!/usr/bin/env bash
# mark-evaluated.sh — Sanctioned path for creating the evaluate marker
# Called by Claude after presenting an evaluation and receiving user approval.
# Usage: bash .claude/framework/hooks/mark-evaluated.sh "brief description of what was approved"
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || { echo "ERROR: Could not load helpers" >&2; exit 1; }

REASON="${1:-}"
if [ -z "$REASON" ]; then
  echo "ERROR: A reason is required. Usage: bash .claude/framework/hooks/mark-evaluated.sh \"description of what was approved\"" >&2
  exit 1
fi

HASH=$(get_project_hash)
TIMESTAMP=$(date +%Y-%m-%dT%H:%M:%S)

# Create the marker
touch "/tmp/.claude_evaluated_${HASH}"

# Audit log
echo "${TIMESTAMP} | ${REASON}" >> "/tmp/.claude_eval_log_${HASH}"

echo "Evaluation marker created. Reason: ${REASON}"
