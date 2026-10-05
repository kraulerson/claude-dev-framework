#!/usr/bin/env bash
# record-approval.sh — UserPromptSubmit. Turns the user's own answer to a question the
# agent recorded in .claude/pending-approval.json (schema 2) into the evaluation marker,
# bound to the staged change the user was shown (approval design B, spec
# docs/superpowers/specs/2026-10-05-approval-via-pending-question-design.md).
#
# Two exchanges: the first reply that names an option id is blocked and the question,
# each option's effect, the staged change and the hooks that will run are rendered to
# the user (the block reason reaches the user, not Claude); the next prompt in the same
# session, if it names an option id and nothing changed since, is the pick. Turns that
# start with `<` (task notifications, cross-session messages, marked pastes) and slash
# commands neither pick nor void the render. Free text never approves.
#
# Fail direction: an internal error grants nothing and never blocks the user's prompt
# (blocking would refuse every prompt while a question is pending). No `set -e` and no
# exit 2 here; failures are reported to the user and to Claude.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

report_failure() {
  local m="record-approval.sh: $1 — no approval was recorded."
  if jq --version >/dev/null 2>&1; then
    jq -nc --arg m "$m" '{systemMessage: $m, hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $m}}'
  else
    printf '{"systemMessage":"record-approval.sh: jq is not installed or not working — no approval was recorded.","hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"record-approval.sh: jq is not installed or not working — no approval was recorded."}}\n'
  fi
  exit 0
}
context() { jq -nc --arg c "$1" '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $c}}'; }

source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || report_failure "could not load _helpers.sh"
INPUT=$(cat)
PROJ="${CLAUDE_PROJECT_DIR:-$PWD}"
SENTINEL="$PROJ/.claude/pending-approval.json"
[ -f "$SENTINEL" ] || exit 0
jq --version >/dev/null 2>&1 || report_failure "jq is not installed or not working"
type git_stage_state >/dev/null 2>&1 || report_failure "the framework's _helpers.sh is older than this hook; run the framework sync"

PROMPT=$(jq -r '.prompt // empty' <<< "$INPUT" 2>/dev/null) || report_failure "could not read the hook input"
SESSION=$(jq -r '.session_id // empty' <<< "$INPUT" 2>/dev/null)
PROMPT_ID=$(jq -r '.prompt_id // empty' <<< "$INPUT" 2>/dev/null)
CWD=$(jq -r '.cwd // empty' <<< "$INPUT" 2>/dev/null); [ -n "$CWD" ] || CWD="$PWD"
HASH=$(get_project_hash)
SHOWN="/tmp/.claude_approval_shown_${HASH}"
MARKER="/tmp/.claude_evaluated_${HASH}"

# --- Which prompts count -------------------------------------------------------------
TRIMMED="${PROMPT#"${PROMPT%%[![:space:]]*}"}"
case "$TRIMMED" in '<'*|'/'*) exit 0 ;; esac
# A reply that only quotes a harness tag is the user's, but it is not read as an answer
# (the tag rule must also hold if a later Claude Code moves the wrapper). Claude is told,
# so it can ask for a plain reply; the render stays.
case "$PROMPT" in *'<task-notification'*|*'<cross-session-message'*)
  context "A question is pending in .claude/pending-approval.json. The user's message contains a <task-notification> or <cross-session-message> tag, so it was not read as an answer and nothing was approved. If the user meant to answer, ask them to reply with just the option id (for example: A1)."
  exit 0 ;;
esac
LINE="${TRIMMED%%$'\n'*}"
TOKEN="${LINE%%[[:space:]]*}"
while :; do
  case "$TOKEN" in
    *[.,:\;!\)-]) TOKEN="${TOKEN%?}" ;;
    *—) TOKEN="${TOKEN%—}" ;;
    *–) TOKEN="${TOKEN%–}" ;;
    *) break ;;
  esac
done

# --- The recorded question ------------------------------------------------------------
INFO=$(pending_approval_info "$SENTINEL")
PROBLEMS=$(jq -r '.problems | join("; ")' <<< "$INFO" 2>/dev/null) || report_failure "could not read the pending question"
if [ -n "$PROBLEMS" ]; then
  rm -f "$SHOWN"
  MSG="A question is pending in .claude/pending-approval.json, but it cannot be answered: ${PROBLEMS}. Nothing was approved. Rewrite the file as schema 2 with the Write tool (stage the change first), present the question to the user and stop: ${PENDING_APPROVAL_SHAPE}"
  jq -nc --arg c "$MSG" --arg u "The pending question cannot be answered (${PROBLEMS}); nothing was approved. The agent must rewrite it in the current format and re-ask." \
    '{systemMessage: $u, hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $c}}'
  exit 0
fi
IDS=$(jq -r '[.opts[].id] | join(", ")' <<< "$INFO")
OPTION=$(jq -c --arg t "$TOKEN" 'first(.opts[] | select((.id | ascii_upcase) == ($t | ascii_upcase))) // empty' <<< "$INFO")
if [ -z "$OPTION" ]; then
  rm -f "$SHOWN"
  context "A question is pending in .claude/pending-approval.json (options: ${IDS}). The user's message did not start with an option id, so nothing was approved and the question stays open. If the user meant to answer it, ask them to reply with the option id first (for example: $(jq -r '.opts[0].id' <<< "$INFO"))."
  exit 0
fi
PICK=$(jq -r .id <<< "$OPTION")
APPROVES=$(jq -r .approves <<< "$OPTION")
SENTINEL_SHA=$(shasum -a 256 < "$SENTINEL" | cut -c1-64)

if ! STATE=$(git_stage_state "$CWD"); then
  rm -f "$SHOWN"
  jq -nc --arg r "The pending question cannot be shown for approval: the git index has unresolved conflicts (git write-tree failed), or ${CWD} is not a git repository. Resolve the conflicts, stage the change, and answer again. Nothing was approved." \
    '{decision: "block", reason: $r}'
  exit 0
fi

# --- Step 2: the pick (the render was shown in this session and nothing changed) -----
if [ -f "$SHOWN" ] && jq -e --arg s "$SESSION" --arg h "$SENTINEL_SHA" --argjson st "$STATE" \
     '.session_id == $s and .sentinel_sha256 == $h and .head == $st.head and .tree == $st.tree
      and .hooks_digest == $st.hooks_digest and .config_digest == $st.config_digest' "$SHOWN" >/dev/null 2>&1; then
  rm -f "$SHOWN"
  if [ "$APPROVES" = commit ] && git_nothing_staged "$CWD"; then
    context "The user picked ${PICK}, which approves a commit, but nothing is staged, so nothing was approved. Stage the change, then ask again (the question is still recorded)."
    exit 0
  fi
  NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  RECORD=$(jq -nc --argjson st "$STATE" --argjson o "$OPTION" --argjson i "$INFO" --arg s "$SESSION" \
    --arg p "$PROMPT_ID" --arg h "$SENTINEL_SHA" --arg now "$NOW" --arg att "${CLAUDE_CODE_SESSION_ATTENDED:-}" \
    '{event: "approval", source: "pick", session_id: $s, prompt_id: $p, pick: $o.id, approves: $o.approves,
      question: $i.question, option_text: $o.text, sentinel_sha256: $h, picked_at: $now, attended: $att} + $st') \
    || report_failure "could not build the approval record"
  if [ "$APPROVES" = commit ]; then
    TMP=$(mktemp "/tmp/.claude_evaluated_${HASH}.XXXXXX") || report_failure "could not write the marker"
    printf '%s\n' "$RECORD" > "$TMP" && mv -f "$TMP" "$MARKER" || { rm -f "$TMP"; report_failure "could not write the marker"; }
  fi
  mkdir -p "$PROJ/.claude"
  printf '%s\n' "$RECORD" >> "$PROJ/.claude/approvals.jsonl"
  printf '%s | pick %s (%s) | %s\n' "$NOW" "$PICK" "$APPROVES" "$(jq -r .question <<< "$INFO" | tr '\n' ' ')" >> "/tmp/.claude_eval_log_${HASH}"
  rm -f "$SENTINEL"
  if [ "$APPROVES" = commit ]; then
    context "The user picked ${PICK} and approved committing the staged change (tree $(jq -r .tree <<< "$STATE" | cut -c1-12)): $(jq -r .text <<< "$OPTION"). Commit it now with a lone \`git commit -m \"…\"\` and nothing else on the line. Any change to the stage, HEAD, git hooks or git config voids the approval."
  else
    context "The user picked ${PICK}: $(jq -r .text <<< "$OPTION"). That approves nothing; do not commit. The question is resolved."
  fi
  exit 0
fi

# --- Step 1: render the question and block; the next reply confirms --------------------
jq -nc --arg s "$SESSION" --arg p "$PROMPT_ID" --arg h "$SENTINEL_SHA" --argjson st "$STATE" \
  --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{session_id: $s, prompt_id: $p, sentinel_sha256: $h, shown_at: $now} + $st' > "$SHOWN" \
  || report_failure "could not write the render record"
OPTIONS=$(jq -r '.opts[] | "  \(.id) — \(.text) [\(if .approves == "commit" then "approves committing the staged change below" else "approves nothing" end)]"' <<< "$INFO")
REC=$(jq -r '.rec' <<< "$INFO")
if git_nothing_staged "$CWD"; then
  STAGED="  Nothing is staged: an option that approves a commit cannot be picked until the change is staged and the question asked again."
else
  STAGED=$(git -C "$CWD" diff --cached --stat 2>/dev/null | sed 's/^/  /')
fi
REASON="Pending question (.claude/pending-approval.json):
$(jq -r .question <<< "$INFO")
${OPTIONS}${REC:+
Recommended: ${REC}}
Staged change:
${STAGED}
Hooks that will run at commit: $(git_hook_names "$CWD")
Reply with the option id again (for example: ${PICK}) to confirm. Any other reply leaves the question open."
jq -nc --arg r "$REASON" '{decision: "block", reason: $r}'
exit 0
