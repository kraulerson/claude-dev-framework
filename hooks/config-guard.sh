#!/usr/bin/env bash
# config-guard.sh — PreToolUse (Bash|Write|Edit) blocks modification of framework config and hooks
# Protects: .claude/settings.json, .claude/manifest.json, .claude/framework/hooks/*
# Also blocks CLAUDE_PROJECT_DIR environment variable overrides.
# A literal path into a temp fixture outside the project (a test's own
# .claude/manifest.json under the scratchpad) is not the project's config (#11).
set -euo pipefail
# Fail closed (#11 review): Claude Code treats any exit code other than 2 as
# non-blocking, so a crash under set -e/-u must not let the call through. The EXIT
# trap blocks; the deliberate decisions below leave through guard_allow/guard_block,
# which clear it first. (bash 3.2 reports $? as 0 in an EXIT trap after an unbound
# variable, so the trap does not consult it.)
trap 'echo "BLOCKED — config-guard.sh failed internally; refusing the call rather than allowing it." >&2; exit 2' EXIT
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
  echo "BLOCKED — jq is not installed or not working, so config-guard.sh cannot read this call. Install jq (brew install jq / apt install jq)." >&2
  guard_block
}
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")

# --- Write/Edit/NotebookEdit tool: protect framework config files ---
if [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "NotebookEdit" ]; then
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // empty' 2>/dev/null || echo "")
  # Matched lexically normalized (`.claude//settings.json`, `.claude/x/../settings.json`)
  # and in lower case: a case-insensitive disk treats .Claude/Settings.json as the same file.
  # Assigned first, not inside `case "$(...)"`, where a failure would be swallowed.
  MATCH_PATH=$(_normalize_path "$FILE_PATH" | tr '[:upper:]' '[:lower:]')
  case "$MATCH_PATH" in
    */.claude/settings.json|*/.claude/settings.local.json|*/.claude/manifest.json|*/.claude/framework/*|\
    .claude/settings.json|.claude/settings.local.json|.claude/manifest.json|.claude/framework/*)
      path_is_foreign_temp "$FILE_PATH" && guard_allow
      printf "BLOCKED — Framework configuration files cannot be modified by Claude. These files control enforcement hooks, protected branches, and verification gates.\n\nIf a configuration change is needed, ask the user to make the edit manually in their editor.\n\nCOMPLIANCE REMINDER: Your obligation is compliance first, speed second.\n" >&2
      guard_block
      ;;
  esac
  guard_allow
fi

# --- Bash tool: protect hook files and config from shell modification ---
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
[ -z "$COMMAND" ] && guard_allow
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")

# Every check below reads the command from a here-string, not `echo | grep -q`: under
# pipefail, grep exiting on its first match killed echo with SIGPIPE on a command
# longer than the pipe buffer, and the failed pipeline read as "no match" (#11).
# The path checks also read NORM_COMMAND, the same text with quotes and backslashes
# removed and `//`, `/./` and `x/../` collapsed, so `.claude/framework/./hooks/` or
# `.claude/'framework'/hooks/` cannot slip past them (#11 review).
NORM_SRC=$(tr -d "\"'\\\\" <<< "$COMMAND")
NORM_COMMAND=$(normalize_command_paths "$NORM_SRC")

# Block CLAUDE_PROJECT_DIR= assignment (not reads like echo $CLAUDE_PROJECT_DIR)
if grep -qE 'CLAUDE_PROJECT_DIR=' <<< "$COMMAND"; then
  printf "BLOCKED — CLAUDE_PROJECT_DIR cannot be overridden. This variable controls enforcement hook behavior.\n\nCOMPLIANCE REMINDER: Your obligation is compliance first, speed second.\n" >&2
  guard_block
fi

# Destructive commands aimed at .claude itself — e.g. `rm -rf .claude`, `rm -rf .claude/`,
# `rm -rf .claude/*`, `mv .claude/ /tmp/x`. A trailing `/` is in the terminating char
# class so `.claude` followed by a slash (bare dir, glob, or subpath) is caught, while
# `.claude-backup` (next char `-`) is not.
if grep -qiE '\b(rm|mv|chmod|chown|rmdir)\b[^|;&]*[[:space:]]["'"'"']?(\./)?\.claude["'"'"']?([[:space:]/]|$)' <<< "$COMMAND" \
   || grep -qiE '\b(rm|mv|chmod|chown|rmdir)\b[^|;&]*[[:space:]]["'"'"']?(\./)?\.claude["'"'"']?([[:space:]/]|$)' <<< "$NORM_COMMAND"; then
  printf "BLOCKED — Modification of the .claude directory is not permitted. Framework hooks and configuration are managed by the framework, not by Claude.\n\nCOMPLIANCE REMINDER: Your obligation is compliance first, speed second.\n" >&2
  guard_block
fi

# Check if command references framework config or hook paths (CONFIG_GUARD_PROTECTED_RE
# in _helpers.sh: the config files, framework/hooks/, and the bare .claude/framework
# and .claude/framework/hooks directories, in any letter case)
if grep -qiE "$CONFIG_GUARD_PROTECTED_RE" <<< "$COMMAND" \
   || grep -qiE "$CONFIG_GUARD_PROTECTED_RE" <<< "$NORM_COMMAND"; then
  # Every such path is a literal path into a temp fixture, not the project's (#11).
  all_protected_paths_foreign "$COMMAND" && guard_allow
  # The project's own mark-evaluated.sh / mark-plan-closed.sh, as a lone invocation
  # (R-11) resolved from the agent's cwd (#11). See _helpers.sh.
  if [[ "$COMMAND" == *mark-evaluated.sh* || "$COMMAND" == *mark-plan-closed.sh* ]] \
     && is_sanctioned_mark_command "$COMMAND" "$CWD"; then
    guard_allow
  fi
  # Read-only inspection, as a lone command only: a leading read-only word used to
  # admit whatever was chained after it (#11).
  if is_lone_command "$COMMAND"; then
    # git diff/log/show/blame/status etc. (BL-021) — mutating subcommands (add, checkout,
    # restore, rm, mv, commit, stash, reset, clean, apply, update-ref) are not in this
    # list. --output writes a file; git grep's -O / --open-files-in-pager runs a command.
    if grep -qE '^\s*git\s+(diff|log|show|blame|status|ls-files|cat-file|rev-parse|reflog|describe|name-rev|grep)\b' <<< "$COMMAND" \
       && ! grep -qE '(^|\s)--output' <<< "$COMMAND" \
       && ! { grep -qE '^\s*git\s+grep\b' <<< "$COMMAND" \
              && grep -qE '(^|\s)(--open-files-in-pager|-[[:alnum:]]*O)' <<< "$COMMAND"; }; then
      guard_allow
    fi
    # cat, head, tail, more, wc, file, stat, ls, grep; rg without --pre, which runs a
    # command per file. awk (system()), bat (--pager) and less (-o log file) can
    # write or execute, so they are not read-only here.
    if grep -qE '^\s*(cat|head|tail|more|wc|file|stat|ls|grep)\s' <<< "$COMMAND"; then
      guard_allow
    fi
    if grep -qE '^\s*rg\s' <<< "$COMMAND" && ! grep -qE '(^|\s)--pre(=|\s|$)' <<< "$COMMAND"; then
      guard_allow
    fi
  fi
  printf "BLOCKED — Modification of framework files via Bash is not permitted. Framework hooks and configuration are managed by the framework, not by Claude. Read-only inspection must be a single command with no pipe, chaining or redirection; use the Read tool to view these files.\n\nCOMPLIANCE REMINDER: Your obligation is compliance first, speed second.\n" >&2
  guard_block
fi

guard_allow
