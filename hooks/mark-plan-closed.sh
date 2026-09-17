#!/usr/bin/env bash
# mark-plan-closed.sh — Sanctioned path for creating the plan-closed marker
# Called by Claude after documenting plan closure (rules/plan-closure.md).
# Usage: bash .claude/framework/hooks/mark-plan-closed.sh "one-line closure summary"
#        bash .claude/framework/hooks/mark-plan-closed.sh --note path/to/closure-note.md
# The summary is plain text, no shell punctuation. Run it as a lone command from the
# project root; the guards refuse chained forms.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || { echo "ERROR: Could not load helpers" >&2; exit 1; }

USAGE="Usage: bash .claude/framework/hooks/mark-plan-closed.sh \"one-line closure summary\" (plain text, no shell punctuation) | --note path/to/closure-note.md"
fail() { echo "ERROR: $1 $USAGE" >&2; exit 1; }

if [[ "${1:-}" = "--note" ]]; then
  # Closure note: a regular file with real content
  [ "$#" -eq 2 ] || fail "--note takes exactly one path."
  NOTE="$2"
  [[ "$NOTE" != *$'\n'* ]] || fail "The closure note path must be one line."
  [ -f "$NOTE" ] || fail "Closure note not found: ${NOTE}."
  grep -q -- '[^[:space:]]' "$NOTE" || fail "Closure note is empty: ${NOTE}."
  RECORD="note: ${NOTE}"
else
  # Closure summary: exactly one non-blank, single-line argument
  [ "$#" -eq 1 ] || fail "A single quoted closure summary is required."
  SUMMARY="$1"
  [[ -n "${SUMMARY//[[:space:]]/}" ]] || fail "The closure summary is empty."
  [[ "$SUMMARY" != *$'\n'* ]] || fail "The closure summary must be one line."
  RECORD="$SUMMARY"
fi

HASH=$(get_project_hash)
TIMESTAMP=$(date +%Y-%m-%dT%H:%M:%S)

# Create the marker; its content is the closure record
printf '%s | %s\n' "$TIMESTAMP" "$RECORD" > "/tmp/.claude_plan_closed_${HASH}"

echo "Plan closure marker created. Closure: ${RECORD}"
