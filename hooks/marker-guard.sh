#!/usr/bin/env bash
# marker-guard.sh — PreToolUse (Bash|Write|Edit|NotebookEdit) blocks manual marker creation
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 1

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")

BLOCK_MSG="BLOCKED — Manual marker manipulation is not permitted. Markers are created automatically by the framework when you complete the required workflow. Invoke the appropriate Superpowers skill or present an evaluation to proceed."

# Normalize a path lexically (no disk access): collapse `//`, drop `/.` segments,
# and resolve `/..` so non-canonical forms like `/tmp/./.claude_x`, `/tmp//.claude_x`,
# and `/tmp/foo/../.claude_x` cannot slip past the marker-path glob (R-07).
_normalize_path() {
  local input="$1" lead="" seg oldIFS out
  case "$input" in /*) lead="/";; esac
  oldIFS="$IFS"; IFS='/'
  # shellcheck disable=SC2086
  set -- $input
  IFS="$oldIFS"
  local stack
  stack=()
  for seg in "$@"; do
    case "$seg" in
      ''|.) : ;;
      ..)
        if [ "${#stack[@]}" -gt 0 ]; then
          unset "stack[$(( ${#stack[@]} - 1 ))]"
          stack=( "${stack[@]}" )
        fi
        ;;
      *) stack[${#stack[@]}]="$seg" ;;
    esac
  done
  oldIFS="$IFS"; IFS='/'
  out="${stack[*]}"
  IFS="$oldIFS"
  printf '%s%s\n' "$lead" "$out"
}

# --- File tools: block any write to a framework marker path (R-07) ---
if [[ "$TOOL_NAME" = "Write" || "$TOOL_NAME" = "Edit" || "$TOOL_NAME" = "NotebookEdit" ]]; then
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // empty' 2>/dev/null || echo "")
  NORM_PATH=$(_normalize_path "$FILE_PATH")
  if [[ "$NORM_PATH" == /tmp/.claude_* || "$NORM_PATH" == /private/tmp/.claude_* ]]; then
    echo "$BLOCK_MSG" >&2
    exit 2
  fi
  exit 0
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")

# Allow the sanctioned mark-evaluated.sh script — but only as a lone, unchained
# invocation. A command that merely CONTAINS the string (e.g. appended after
# `&&`) must not unlock the guard (R-11).
if [[ "$COMMAND" == *mark-evaluated.sh* ]]; then
  # Redirections (`>`, `>>`, `2>`, `<`) can create/truncate a marker or the settings
  # file, so treat `>`/`<` as chaining and fall through to the blocking checks (R-11).
  if [[ "$COMMAND" =~ [\;\&\|\`\>\<] || "$COMMAND" == *'$('* || "$COMMAND" == *$'\n'* ]]; then
    : # chained/substituted/redirected — fall through to the blocking checks
  elif [[ "$COMMAND" =~ ^[[:space:]]*(bash[[:space:]]+)?[^[:space:]]*mark-evaluated\.sh([[:space:]]|$) ]]; then
    exit 0
  fi
fi

# Block any command that references a workflow marker or framework state name (any
# creation, deletion, or tampering method). The marker basename is matched with or
# without the `/tmp/` prefix so obfuscated forms — `cd /tmp && touch .claude_evaluated_X`,
# `touch "/tmp/$(printf .claude_evaluated_X)"` — are still caught. NOTE: a command that
# never spells a full marker name (e.g. `p=/tmp/.claude_; touch ${p}evaluated_$H`,
# assembled at runtime) is inherently beyond static command-string inspection; that
# residual is covered by the file-tool guard above and the OS-sandbox layer (R-23).
if echo "$COMMAND" | grep -qE '\.claude_(superpowers|evaluated|plan_closed|plan_active|has_plan|skill_active|c7|c7_degraded|changelog_synced|session_start|last_head|stop_errors_hash|eval_log)'; then
  echo "$BLOCK_MSG" >&2
  exit 2
fi
exit 0
