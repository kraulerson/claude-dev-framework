#!/usr/bin/env bash
# config-guard.sh — PreToolUse (Bash|Write|Edit) blocks modification of framework config and hooks
# Protects: .claude/settings.json, .claude/manifest.json, .claude/framework/hooks/*
# Also blocks CLAUDE_PROJECT_DIR environment variable overrides.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 1

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")

# --- Write/Edit tool: protect framework config files ---
if [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ]; then
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null || echo "")
  case "$FILE_PATH" in
    */.claude/settings.json|*/.claude/settings.local.json|*/.claude/manifest.json|*/.claude/framework/*)
      printf "BLOCKED — Framework configuration files cannot be modified by Claude. These files control enforcement hooks, protected branches, and verification gates.\n\nIf a configuration change is needed, ask the user to make the edit manually in their editor.\n\nCOMPLIANCE REMINDER: Your obligation is compliance first, speed second.\n" >&2
      exit 2
      ;;
  esac
  exit 0
fi

# --- Bash tool: protect hook files and config from shell modification ---
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
[ -z "$COMMAND" ] && exit 0

# Block CLAUDE_PROJECT_DIR= assignment (not reads like echo $CLAUDE_PROJECT_DIR)
if echo "$COMMAND" | grep -qE 'CLAUDE_PROJECT_DIR='; then
  printf "BLOCKED — CLAUDE_PROJECT_DIR cannot be overridden. This variable controls enforcement hook behavior.\n\nCOMPLIANCE REMINDER: Your obligation is compliance first, speed second.\n" >&2
  exit 2
fi

# Check if command references framework config or hook paths
if echo "$COMMAND" | grep -qE '\.claude/(framework/hooks/|settings\.json|settings\.local\.json|manifest\.json)'; then
  # Allow mark-evaluated.sh (sanctioned script) — check first so it doesn't fall through
  if echo "$COMMAND" | grep -qE 'mark-evaluated\.sh'; then
    exit 0
  fi
  # Allow read-only git inspection (BL-021): diff/log/show/blame/status etc. — mutating subcommands (add, checkout, restore, rm, mv, commit, stash, reset, clean, apply, update-ref) are NOT in this list and stay blocked.
  if echo "$COMMAND" | grep -qE '^\s*git\s+(diff|log|show|blame|status|ls-files|cat-file|rev-parse|reflog|describe|name-rev|grep)\b'; then
    exit 0
  fi
  # Allow read-only commands (cat, head, tail, less, more, wc, file, stat, ls, grep, rg, awk, bat)
  if echo "$COMMAND" | grep -qE '^\s*(cat|head|tail|less|more|wc|file|stat|ls|grep|rg|awk|bat)\s'; then
    exit 0
  fi
  printf "BLOCKED — Modification of framework files via Bash is not permitted. Framework hooks and configuration are managed by the framework, not by Claude.\n\nCOMPLIANCE REMINDER: Your obligation is compliance first, speed second.\n" >&2
  exit 2
fi

exit 0
