#!/usr/bin/env bash
# stop-checklist.sh — Stop hook. Blocks if work is incomplete.
#
# Pending-approval sentinel: if ${CLAUDE_PROJECT_DIR:-.}/.claude/pending-approval.json
# exists, the agent is holding on a user decision — exit 0 silently (no block
# JSON, no stderr advisory). Agent deletes the file when the user picks.
# Staleness (orphaned file after a crash) is not handled here; `rm` manually.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 0

INPUT=$(cat)
STOP_REASON=$(echo "$INPUT" | jq -r '.stop_reason // empty' 2>/dev/null || echo "")
[ "$STOP_REASON" = "user" ] || [ "$STOP_REASON" = "tool_error" ] && exit 0

# Pending-approval sentinel: existence alone means "in flight" — malformed/empty content still counts, per spec.
PENDING_APPROVAL="${CLAUDE_PROJECT_DIR:-.}/.claude/pending-approval.json"
[ -f "$PENDING_APPROVAL" ] && exit 0

HASH=$(get_project_hash)
CHANGELOG=$(get_branch_config_value '.changelogFile')
CTX_HISTORY=$(get_branch_config_value '.contextHistoryFile')
SESSION_START=$(cat "/tmp/.claude_session_start_${HASH}" 2>/dev/null || echo "")

DIRTY=$(git diff --name-only 2>/dev/null || true)
STAGED=$(git diff --cached --name-only 2>/dev/null || true)
ALL=$(printf "%s\n%s" "$DIRTY" "$STAGED" | sort -u | grep -v '^$' || true)

HAS_SOURCE=false
if [ -n "$ALL" ]; then
  for f in $ALL; do
    is_source_file "$f" 2>/dev/null && { HAS_SOURCE=true; break; }
  done
fi

# Exposed as a function so session-scope dedup can hash the final ERRORS string without duplicating the accumulation logic.
compute_errors() {
  local errors=""

  if [ "$HAS_SOURCE" = true ]; then
    [ -n "$CHANGELOG" ] && ! echo "$ALL" | grep -q "$CHANGELOG" && errors="${errors}- Source files modified but $CHANGELOG not updated.\n"
    errors="${errors}- Uncommitted source changes. Commit before finishing.\n"
  fi

  if [ "$HAS_SOURCE" = false ] && [ -z "$STAGED" ] && [ -n "$SESSION_START" ]; then
    local untested_fixes="" commit_log current_sha="" current_msg="" current_has_test=false current_has_source=false line
    # --no-merges: git log --name-only emits no files for merge commits, so a merge subject containing "fix" would falsely register as an untested fix.
    commit_log=$(git log --no-merges --format="COMMIT %H %s" --name-only "${SESSION_START}..HEAD" 2>/dev/null || true)
    while IFS= read -r line; do
      if [[ "$line" == COMMIT\ * ]]; then
        # Only flag if source was actually touched — config/doc-only fixes can't have a code regression test.
        if [ -n "$current_sha" ] && echo "$current_msg" | grep -qiE '\b(fix|bug|patch|hotfix|repair|resolve)\b'; then
          [ "$current_has_source" = true ] && [ "$current_has_test" = false ] && untested_fixes="${untested_fixes}${current_sha:0:8}\n"
        fi
        current_sha="${line#COMMIT }" current_sha="${current_sha%% *}"
        current_msg="${line#COMMIT * }"
        current_has_test=false
        current_has_source=false
      elif [ -n "$line" ] && [ -n "$current_sha" ]; then
        is_test_file "$line" && current_has_test=true
        is_source_file "$line" 2>/dev/null && current_has_source=true
      fi
    done <<< "$commit_log"
    if [ -n "$current_sha" ] && echo "$current_msg" | grep -qiE '\b(fix|bug|patch|hotfix|repair|resolve)\b'; then
      [ "$current_has_source" = true ] && [ "$current_has_test" = false ] && untested_fixes="${untested_fixes}${current_sha:0:8}\n"
    fi
    if [ -n "$untested_fixes" ]; then
      errors="${errors}- One or more commits look like a bug fix but have NO regression test.\n"
    fi
  fi

  local transcript_path size ctx_dirty ctx_staged recent
  transcript_path=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || echo "")
  if [ -n "$transcript_path" ] && [ -f "$transcript_path" ] && [ -n "$CTX_HISTORY" ]; then
    size=$(wc -c < "$transcript_path" 2>/dev/null || echo 0)
    if [ "$size" -gt 150000 ]; then
      ctx_dirty=$(git diff --name-only -- "$CTX_HISTORY" 2>/dev/null || true)
      ctx_staged=$(git diff --cached --name-only -- "$CTX_HISTORY" 2>/dev/null || true)
      recent=$(git log --oneline -5 --diff-filter=M -- "$CTX_HISTORY" 2>/dev/null || true)
      [ -z "$ctx_dirty" ] && [ -z "$ctx_staged" ] && [ -z "$recent" ] && errors="${errors}- Substantial session but $CTX_HISTORY not updated.\n"
    fi
  fi

  printf "%s" "$errors"
}

ERRORS=$(compute_errors)

# Session-scope error dedup: suffix with session-start SHA so prior sessions are naturally orphaned (different suffix, no cross-session leakage).
ERRORS_MARKER="/tmp/.claude_stop_errors_hash_${HASH}_${SESSION_START:-no-session}"

if [ -n "$ERRORS" ]; then
  ERRORS_HASH=$(printf '%s' "$ERRORS" | shasum -a 256 | cut -c1-16)
  # Same error set already surfaced this session — staying silent avoids amplifying imperative pressure on the agent ("Complete these, then finish") on retries.
  if [ -f "$ERRORS_MARKER" ] && [ "$(cat "$ERRORS_MARKER" 2>/dev/null)" = "$ERRORS_HASH" ]; then
    exit 0
  fi
  printf '%s' "$ERRORS_HASH" > "$ERRORS_MARKER"
  REASON=$(printf "Unfinished steps:\n\n%b\nComplete these, then finish." "$ERRORS")
  jq -n --arg r "$REASON" '{"decision": "block", "reason": $r}'
  exit 0
fi

# Errors cleared — drop any stale marker so the next fresh error set is seen.
[ -f "$ERRORS_MARKER" ] && rm -f "$ERRORS_MARKER"

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
      # SOLO_ORCHESTRATOR_STOP_HOOK_PATCH — advisory via stderr, not invalid JSON
      echo "$MSG" >&2
    fi
  fi
fi
exit 0
