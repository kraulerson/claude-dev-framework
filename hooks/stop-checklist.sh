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

# Check ALL session commits for untested bug fixes (not just the last one)
HASH=$(get_project_hash)
SESSION_START=$(cat "/tmp/.claude_session_start_${HASH}" 2>/dev/null || echo "")
if [ "$HAS_SOURCE" = false ] && [ -z "$STAGED" ] && [ -n "$SESSION_START" ]; then
  UNTESTED_FIXES=""
  # Get all commits with files in one git call
  COMMIT_LOG=$(git log --format="COMMIT %H %s" --name-only "${SESSION_START}..HEAD" 2>/dev/null || true)
  CURRENT_SHA="" CURRENT_MSG="" CURRENT_HAS_TEST=false
  while IFS= read -r line; do
    if [[ "$line" == COMMIT\ * ]]; then
      # Process previous commit
      if [ -n "$CURRENT_SHA" ] && echo "$CURRENT_MSG" | grep -qiE '\b(fix|bug|patch|hotfix|repair|resolve)\b'; then
        [ "$CURRENT_HAS_TEST" = false ] && UNTESTED_FIXES="${UNTESTED_FIXES}${CURRENT_SHA:0:8}\n"
      fi
      CURRENT_SHA="${line#COMMIT }" CURRENT_SHA="${CURRENT_SHA%% *}"
      CURRENT_MSG="${line#COMMIT * }"
      CURRENT_HAS_TEST=false
    elif [ -n "$line" ] && [ -n "$CURRENT_SHA" ]; then
      is_test_file "$line" && CURRENT_HAS_TEST=true
    fi
  done <<< "$COMMIT_LOG"
  # Process last commit
  if [ -n "$CURRENT_SHA" ] && echo "$CURRENT_MSG" | grep -qiE '\b(fix|bug|patch|hotfix|repair|resolve)\b'; then
    [ "$CURRENT_HAS_TEST" = false ] && UNTESTED_FIXES="${UNTESTED_FIXES}${CURRENT_SHA:0:8}\n"
  fi
  if [ -n "$UNTESTED_FIXES" ]; then
    ERRORS="${ERRORS}- One or more commits look like a bug fix but have NO regression test.\n"
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
  exit 0
fi

# Advisory: suggest session handoff and plan closure if work was done
if [ -n "$SESSION_START" ]; then
  SESSION_COMMITS=$(git log --oneline "${SESSION_START}..HEAD" 2>/dev/null | wc -l | xargs)
  if [ "$SESSION_COMMITS" -gt 0 ]; then
    ADVISORIES=""

    # [Design Zone] Superpowers audit: commits were made but no superpowers marker
    if [ ! -f "/tmp/.claude_superpowers_${HASH}" ]; then
      ADVISORIES="${ADVISORIES}[Design Zone] This session produced commits but the Superpowers workflow may not have been followed. Review commit quality.\n\n"
    fi

    # [Planning Zone] Plan closure: if Superpowers was used (commits exist) and no closure marker
    if [ ! -f "/tmp/.claude_plan_closed_${HASH}" ]; then
      ADVISORIES="${ADVISORIES}[Planning Zone] If this session involved planned work, document plan closure: planned vs. actual, decisions made, issues deferred.\n\n"
    fi

    # [Discovery Zone] Session handoff
    if [ -n "$CTX_HISTORY" ]; then
      ADVISORIES="${ADVISORIES}[Discovery Zone] Consider saving a handoff note to ${CTX_HISTORY} for the next session."
    fi

    if [ -n "$ADVISORIES" ]; then
      MSG=$(printf "Session produced %s commit(s).\n\n%b" "$SESSION_COMMITS" "$ADVISORIES")
      jq -n --arg m "$MSG" '{
        "hookSpecificOutput": {
          "hookEventName": "Stop",
          "additionalContext": $m
        }
      }'
    fi
  fi
fi
exit 0
