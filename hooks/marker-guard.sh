#!/usr/bin/env bash
# marker-guard.sh — PreToolUse (Bash|Write|Edit|NotebookEdit) blocks manual marker creation
set -euo pipefail
# Fail closed (#11 review): Claude Code treats any exit code other than 2 as
# non-blocking, so a crash under set -e/-u must not let the call through. The EXIT
# trap blocks; the deliberate decisions below leave through guard_allow/guard_block,
# which clear it first. (bash 3.2 reports $? as 0 in an EXIT trap after an unbound
# variable, so the trap does not consult it.)
trap 'echo "BLOCKED — marker-guard.sh failed internally; refusing the call rather than allowing it." >&2; exit 2' EXIT
guard_allow() { trap - EXIT; exit 0; }
guard_block() { trap - EXIT; exit 2; }
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 1

INPUT=$(cat)

# Without a working jq the input cannot be parsed, so refuse rather than let the call
# through unread (#11 review). A narrower test would not help: every real call names
# its transcript under ~/.claude. `jq --version` also catches a jq that is present
# but broken.
jq --version >/dev/null 2>&1 || {
  echo "BLOCKED — jq is not installed or not working, so marker-guard.sh cannot read this call. Install jq (brew install jq / apt install jq)." >&2
  guard_block
}
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")

BLOCK_MSG="BLOCKED — Manual marker manipulation is not permitted. Workflow markers are created by the framework when you complete the required workflow: the evaluation marker when the user picks an approving option of a question you recorded in .claude/pending-approval.json, the plan-closed marker by the sanctioned script mark-plan-closed.sh (after documenting plan closure, as a lone command). Invoke the appropriate Superpowers skill, record the question and stop, or run mark-plan-closed.sh, to proceed."

# --- File tools: block any write to a framework marker path (R-07) ---
if [[ "$TOOL_NAME" = "Write" || "$TOOL_NAME" = "Edit" || "$TOOL_NAME" = "NotebookEdit" ]]; then
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // empty' 2>/dev/null || echo "")
  # Compared in lower case: a case-insensitive disk treats /TMP/.Claude_x as /tmp/.claude_x.
  NORM_PATH=$(_normalize_path "$FILE_PATH" | tr '[:upper:]' '[:lower:]')
  if [[ "$NORM_PATH" == /tmp/.claude_* || "$NORM_PATH" == /private/tmp/.claude_* ]]; then
    echo "$BLOCK_MSG" >&2
    guard_block
  fi
  guard_allow
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")

# Allow the sanctioned mark-plan-closed.sh script (mark-evaluated.sh is the user's own
# override since approval design B, and is not sanctioned for the agent) — but only
# as a lone, unchained invocation (R-11) of the project's own copy: the script path,
# taken from the agent's cwd, must resolve to <project>/.claude/framework/hooks/, so
# a script of the same name elsewhere unlocks nothing (#11). See
# is_sanctioned_mark_command in _helpers.sh.
if [[ "$COMMAND" == *mark-plan-closed.sh* ]] \
   && is_sanctioned_mark_command "$COMMAND" "$CWD"; then
  guard_allow
fi

# Block any command that references a workflow marker or framework state name (any
# creation, deletion, or tampering method). The marker basename is matched with or
# without the `/tmp/` prefix so obfuscated forms — `cd /tmp && touch .claude_evaluated_X`,
# `touch "/tmp/$(printf .claude_evaluated_X)"` — are still caught. NOTE: a command that
# never spells a full marker name (e.g. `p=/tmp/.claude_; touch ${p}evaluated_$H`,
# assembled at runtime) is inherently beyond static command-string inspection; that
# residual is covered by the file-tool guard above and the OS-sandbox layer (R-23).
# A here-string, not `echo | grep -q`: under pipefail, grep exiting on its first match
# killed echo with SIGPIPE on a command longer than the pipe buffer, and the failed
# pipeline read as "no match" (#11). Case-insensitive, as the disk usually is.
if grep -qiE '\.claude_(superpowers|evaluated|plan_closed|plan_active|has_plan|skill_active|c7|c7_degraded|changelog_synced|session_start|last_head|stop_errors_hash|eval_log|approval_shown)' <<< "$COMMAND"; then
  echo "$BLOCK_MSG" >&2
  guard_block
fi
guard_allow
