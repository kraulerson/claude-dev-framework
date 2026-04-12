#!/usr/bin/env bash
# verification-gate.sh — PreToolUse (Bash) blocking hook for Verification Zone
# Runs configurable verification gates before git commit.
# Gates are defined in manifest.json → projectConfig._base.verificationGates[]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 1

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
echo "$COMMAND" | grep -qE '\bgit\b.*\bcommit\b' || exit 0

# Read gates from manifest
MANIFEST=$(get_manifest_path)
[ ! -f "$MANIFEST" ] || ! check_jq && exit 0

GATES=$(jq -c '.projectConfig._base.verificationGates[]? // empty' "$MANIFEST" 2>/dev/null || true)
[ -z "$GATES" ] && exit 0

while IFS= read -r gate; do
  [ -z "$gate" ] && continue

  NAME=$(echo "$gate" | jq -r '.name // "unnamed"')
  ENABLED=$(echo "$gate" | jq -r 'if .enabled == false then "false" else "true" end')
  CMD=$(echo "$gate" | jq -r '.command // empty')
  FAIL_ON=$(echo "$gate" | jq -r '.failOn // "exit_code"')
  FAIL_PATTERN=$(echo "$gate" | jq -r '.failPattern // empty')

  # Skip disabled gates
  [ "$ENABLED" = "false" ] && continue
  [ -z "$CMD" ] && continue

  # Check if command exists (first word)
  FIRST_WORD=$(echo "$CMD" | awk '{print $1}')
  if ! command -v "$FIRST_WORD" >/dev/null 2>&1 && [ ! -f "$FIRST_WORD" ]; then
    continue
  fi

  # Run the gate — capture stdout and stderr separately without tmpfile
  GATE_STDOUT=""
  GATE_STDERR=""
  GATE_EXIT=0
  if [ "$FAIL_ON" = "stderr" ]; then
    # Need separate streams for stderr pattern matching
    exec 3>&1
    GATE_STDERR=$(eval "$CMD" 2>&1 1>&3) && GATE_EXIT=0 || GATE_EXIT=$?
    exec 3>&-
  else
    # For exit_code and stdout modes, merge streams
    GATE_STDOUT=$(eval "$CMD" 2>&1) || GATE_EXIT=$?
  fi

  FAILED=false

  case "$FAIL_ON" in
    exit_code)
      [ "$GATE_EXIT" -ne 0 ] && FAILED=true
      ;;
    stderr)
      if [ -n "$FAIL_PATTERN" ] && [ -n "$GATE_STDERR" ]; then
        echo "$GATE_STDERR" | grep -qE "$FAIL_PATTERN" && FAILED=true
      fi
      ;;
    stdout)
      if [ -n "$FAIL_PATTERN" ] && [ -n "$GATE_STDOUT" ]; then
        echo "$GATE_STDOUT" | grep -qE "$FAIL_PATTERN" && FAILED=true
      fi
      ;;
  esac

  if [ "$FAILED" = true ]; then
    OUTPUT=""
    [ -n "$GATE_STDOUT" ] && OUTPUT="$GATE_STDOUT"
    [ -n "$GATE_STDERR" ] && OUTPUT="${OUTPUT:+$OUTPUT\n}$GATE_STDERR"
    printf "BLOCKED [Verification Zone] — %s FAILED\nOutput: %b\nFix the issues above before committing.\nDo NOT skip verification gates. Do NOT use --no-verify.\n\nCOMPLIANCE REMINDER: Your obligation is compliance first, speed second.\n" "$NAME" "$OUTPUT" >&2
    exit 2
  fi
done <<< "$GATES"

exit 0
