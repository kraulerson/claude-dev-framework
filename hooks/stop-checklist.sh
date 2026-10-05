#!/usr/bin/env bash
# stop-checklist.sh — Stop hook. Blocks if work is incomplete.
#
# Pending-approval sentinel: if ${CLAUDE_PROJECT_DIR:-.}/.claude/pending-approval.json
# exists, the agent is holding on a user decision — the stop is allowed and the user is
# shown the question (systemMessage); only a commit that does not match the tree the
# user approved is still reported (once). record-approval.sh resolves the file when the
# user picks. Staleness (orphaned file after a crash) is not handled here; `rm` manually.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 0

INPUT=$(cat)
# stop_hook_active=true means Claude is already continuing because this hook
# blocked a previous stop this turn — exit 0 to prevent an infinite block loop.
# (Real Stop input carries no reason/kind field; this flag is the only loop signal.)
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")
[[ "$STOP_HOOK_ACTIVE" = "true" ]] && exit 0

HASH=$(get_project_hash)
SESSION_START=$(cat "/tmp/.claude_session_start_${HASH}" 2>/dev/null || echo "")
# Session-scope error dedup: suffix with session-start SHA so prior sessions are naturally orphaned (different suffix, no cross-session leakage).
ERRORS_MARKER="/tmp/.claude_stop_errors_hash_${HASH}_${SESSION_START:-no-session}"

# Approval design B: a commit made in this session whose tree is not the one the user
# approved (marker-tracker's matched=false record). Checked before the pending-question
# exit too, so recording a new question cannot hide it.
approval_mismatch_errors() {
  local approvals="${CLAUDE_PROJECT_DIR:-.}/.claude/approvals.jsonl" sha errors=""
  if [ -n "$SESSION_START" ] && [ -f "$approvals" ] && check_jq; then
    while IFS= read -r sha; do
      [ -n "$sha" ] && [ "$sha" != "$SESSION_START" ] || continue
      git merge-base --is-ancestor "$SESSION_START" "$sha" 2>/dev/null || continue
      errors="${errors}- Commit ${sha:0:8} does not match the tree the user approved (a git hook or another process changed what was committed). Tell the user.\n"
    done <<< "$(jq -r 'select(.event == "commit" and .matched == false) | .commit' "$approvals" 2>/dev/null)"
  fi
  printf "%s" "$errors"
}

# Pending-approval sentinel: existence alone means "in flight" — malformed/empty content still counts, per spec.
# The agent may stop. The user is told what is pending (approval design B; a Stop
# systemMessage is shown interactively and in stream-json): for a schema-2 question how
# to answer it, for a v1 or invalid one that it cannot be answered and the shape the
# agent must rewrite it in. The render the user confirms comes from record-approval.sh.
PENDING_APPROVAL="${CLAUDE_PROJECT_DIR:-.}/.claude/pending-approval.json"
if [ -f "$PENDING_APPROVAL" ]; then
  if type pending_approval_info >/dev/null 2>&1 && check_jq; then
    PA_INFO=$(pending_approval_info "$PENDING_APPROVAL")
    PA_PROBLEMS=$(jq -r '.problems | join("; ")' <<< "$PA_INFO" 2>/dev/null || echo "it cannot be read")
    if [ -n "$PA_PROBLEMS" ]; then
      PA_MSG="The pending question in .claude/pending-approval.json cannot be answered: ${PA_PROBLEMS}. The agent must rewrite it as schema 2 (stage the change first) and ask again: ${PENDING_APPROVAL_SHAPE}"
    else
      PA_MSG="Pending question: $(jq -r .question <<< "$PA_INFO") — reply with the option id ($(jq -r '[.opts[].id] | join(" / ")' <<< "$PA_INFO")); you will then be shown the staged change and asked to confirm."
    fi
    MISMATCH=$(approval_mismatch_errors)
    if [ -n "$MISMATCH" ]; then
      MISMATCH_HASH=$(printf '%s' "$MISMATCH" | shasum -a 256 | cut -c1-16)
      if [ "$(cat "$ERRORS_MARKER" 2>/dev/null)" != "$MISMATCH_HASH" ]; then
        printf '%s' "$MISMATCH_HASH" > "$ERRORS_MARKER"
        jq -nc --arg r "$(printf "Unfinished steps:\n\n%b\nComplete these, then finish." "$MISMATCH")" --arg m "$PA_MSG" \
          '{decision: "block", reason: $r, systemMessage: $m}'
        exit 0
      fi
    fi
    jq -nc --arg m "$PA_MSG" '{systemMessage: $m}'
  fi
  exit 0
fi

CHANGELOG=$(get_branch_config_value '.changelogFile')
CTX_HISTORY=$(get_branch_config_value '.contextHistoryFile')

STAGED=$(git diff --cached --name-only 2>/dev/null || true)
# git status --porcelain covers modified + staged + untracked (??). Strip the
# 3-char status prefix, rename arrows, and quoting around paths with spaces.
ALL=$(git status --porcelain 2>/dev/null \
  | sed -e 's/^...//' -e 's/.* -> //' -e 's/^"//' -e 's/"$//' \
  | sort -u | grep -v '^$' || true)

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
    # The commit itself may be waiting on the user (enforce-evaluate needs their
    # approval first), so name the sentinel that lets the agent stop and ask.
    errors="${errors}- Uncommitted source changes. Commit before finishing. If the commit is waiting on the user's approval, ask them and record the open question in .claude/pending-approval.json (schema 2, the shape the enforce-evaluate block message gives); this check then lets you stop. The framework resolves it when the user picks an option.\n"
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

  errors="${errors}$(approval_mismatch_errors)"

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
      ADVISORIES="${ADVISORIES}[Planning Zone] If this session involved planned work, document plan closure: planned vs. actual, decisions made, issues deferred; then run: bash .claude/framework/hooks/mark-plan-closed.sh \"one-line summary\" (plain text, no shell punctuation), from the project root\n\n"
    fi

    # [Discovery Zone] Session handoff
    if [ -n "$CTX_HISTORY" ]; then
      ADVISORIES="${ADVISORIES}[Discovery Zone] Consider saving a handoff note to ${CTX_HISTORY} for the next session."
    fi

    if [ -n "$ADVISORIES" ]; then
      MSG=$(printf "Session produced %s commit(s).\n\n%b" "$SESSION_COMMITS" "$ADVISORIES")
      # Stop hooks support hookSpecificOutput.additionalContext as of Claude Code >= 2.x (2026),
      # so the advisory is delivered as structured context rather than stderr.
      jq -n --arg ctx "$MSG" '{
        "hookSpecificOutput": {
          "hookEventName": "Stop",
          "additionalContext": $ctx
        }
      }'
    fi
  fi
fi
exit 0
