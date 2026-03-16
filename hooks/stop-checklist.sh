#!/usr/bin/env bash
# stop-checklist.sh — Stop hook. Blocks if work is incomplete.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 0

INPUT=$(cat)
STOP_REASON=$(echo "$INPUT" | jq -r '.stop_reason // empty' 2>/dev/null || echo "")
[ "$STOP_REASON" = "user" ] || [ "$STOP_REASON" = "tool_error" ] && exit 0

ERRORS=""
CHANGELOG=$(get_branch_config_value '.changelogFile')
CTX_HISTORY=$(get_branch_config_value '.contextHistoryFile')

DIRTY=$(git diff --name-only 2>/dev/null || true)
STAGED=$(git diff --cached --name-only 2>/dev/null || true)
ALL=$(printf "%s\n%s" "$DIRTY" "$STAGED" | sort -u | grep -v '^$' || true)

HAS_SOURCE=false
if [ -n "$ALL" ]; then
  for f in $ALL; do
    is_source_file "$f" 2>/dev/null && { HAS_SOURCE=true; break; }
  done
fi

if [ "$HAS_SOURCE" = true ]; then
  [ -n "$CHANGELOG" ] && ! echo "$ALL" | grep -q "$CHANGELOG" && ERRORS="${ERRORS}- Source files modified but $CHANGELOG not updated.\n"
  ERRORS="${ERRORS}- Uncommitted source changes. Commit before finishing.\n"
fi

if [ "$HAS_SOURCE" = false ] && [ -z "$STAGED" ]; then
  LAST_MSG=$(git log -1 --pretty=%B 2>/dev/null || true)
  if echo "$LAST_MSG" | grep -qiE '\b(fix|bug|patch|hotfix|repair|resolve)\b'; then
    LAST_FILES=$(git diff --name-only HEAD~1 HEAD 2>/dev/null || true)
    HAS_TEST=false
    for f in $LAST_FILES; do is_test_file "$f" && { HAS_TEST=true; break; }; done
    [ "$HAS_TEST" = false ] && ERRORS="${ERRORS}- Last commit looks like a bug fix but has NO regression test.\n"
  fi
fi

TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || echo "")
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ] && [ -n "$CTX_HISTORY" ]; then
  SIZE=$(wc -c < "$TRANSCRIPT_PATH" 2>/dev/null || echo 0)
  if [ "$SIZE" -gt 150000 ]; then
    CTX_DIRTY=$(git diff --name-only -- "$CTX_HISTORY" 2>/dev/null || true)
    CTX_STAGED=$(git diff --cached --name-only -- "$CTX_HISTORY" 2>/dev/null || true)
    RECENT=$(git log --oneline -5 --diff-filter=M -- "$CTX_HISTORY" 2>/dev/null || true)
    [ -z "$CTX_DIRTY" ] && [ -z "$CTX_STAGED" ] && [ -z "$RECENT" ] && ERRORS="${ERRORS}- Substantial session but $CTX_HISTORY not updated.\n"
  fi
fi

if [ -n "$ERRORS" ]; then
  REASON=$(printf "Unfinished steps:\n\n%b\nComplete these, then finish." "$ERRORS")
  jq -n --arg r "$REASON" '{"decision": "block", "reason": $r}'
fi
exit 0
