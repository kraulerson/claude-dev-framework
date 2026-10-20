#!/usr/bin/env bash
# _preflight.sh — Shared input parsing and file classification for Write|Edit hooks.
# Sourced by hooks via: source "$SCRIPT_DIR/_preflight.sh"
# Usage:
#   preflight_init              # reads stdin, extracts file_path (or a Bash command) and tool_name
#   preflight_bash_as_writes    # a Bash call: checks each file it writes as a Write, then exits
#   preflight_skip_non_source   # returns 0 if file should be skipped (doc/config/test/non-source)
#
# After preflight_init, these variables are available:
#   _PF_INPUT      — raw JSON input
#   _PF_FILE_PATH  — extracted file path
#   _PF_TOOL_NAME  — tool name (Write, Edit, NotebookEdit or Bash)
#   _PF_COMMAND    — the command, for Bash

_PF_INPUT=""
_PF_FILE_PATH=""
_PF_TOOL_NAME=""
_PF_COMMAND=""

preflight_init() {
  local tc
  _PF_INPUT=$(cat)
  # One jq for the tool name and, for Bash, the command: these hooks run on every Bash call.
  tc=$(echo "$_PF_INPUT" | jq -r '(.tool_name // ""), (if .tool_name == "Bash" then (.tool_input.command // "") else empty end)' 2>/dev/null || echo "")
  _PF_TOOL_NAME="${tc%%$'\n'*}"
  if [ "$_PF_TOOL_NAME" = "Bash" ]; then
    _PF_COMMAND=""; case "$tc" in *$'\n'*) _PF_COMMAND="${tc#*$'\n'}" ;; esac
  else
    _PF_FILE_PATH=$(echo "$_PF_INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // empty' 2>/dev/null || echo "")
  fi
}

preflight_skip_non_source() {
  [ -z "$_PF_FILE_PATH" ] && return 0
  is_doc_or_config "$_PF_FILE_PATH" && return 0
  is_test_file "$_PF_FILE_PATH" && return 0
  is_source_file "$_PF_FILE_PATH" || return 0
  return 1
}

# A Bash call (#39): run this hook once per file the command writes (bash_write_targets,
# each file once), as a Write of that path whose content is the command's here-document
# bodies, and exit with the first refusal, or else the first advisory. Only source files
# inside the project are checked; with `all`, every file inside the project
# (changelog-sync-check reads the changelog); with `ext`, one file per extension, for a
# gate whose verdict on a source file inside the project depends only on its language
# (enforce-superpowers, enforce-plan-tracking, enforce-context7). Any other tool
# returns at once.
preflight_bash_as_writes() {
  local mode="${1:-source}" cwd targets t d e seen="|" ins=$'\n' outs=$'\n' keep="" content json out rc advice=""
  [ "$_PF_TOOL_NAME" = "Bash" ] || return 0
  bash_may_write "$_PF_COMMAND" || exit 0
  cwd=$(echo "$_PF_INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")
  targets=$(bash_write_targets "$_PF_COMMAND" "${cwd:-${CLAUDE_PROJECT_DIR:-$PWD}}" | awk '!seen[$0]++') || {
    echo "$(basename "$0"): reading the files this Bash command writes failed; it was not checked." >&2
    exit 1
  }
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    # Inside or outside is decided by the folder (resolve_path_physical resolves the
    # nearest existing directory), so it is worked out once per folder.
    d="${t%/*}/"
    case "$outs" in *$'\n'"$d"$'\n'*) continue ;; esac
    case "$ins" in
      *$'\n'"$d"$'\n'*) ;;
      *) if path_outside_project "$d"; then outs="$outs$d"$'\n'; continue; fi; ins="$ins$d"$'\n' ;;
    esac
    if [ "$mode" != all ]; then _PF_FILE_PATH="$t"; preflight_skip_non_source && continue; fi
    if [ "$mode" = ext ]; then
      e="${t##*/}"; case "$e" in *.*) e=".${e##*.}" ;; *) e="" ;; esac
      case "$seen" in *"|$e|"*) continue ;; esac
      seen="$seen$e|"
    fi
    keep="$keep$t"$'\n'
  done <<< "$targets"
  [ -n "$keep" ] || exit 0
  content=$(bash_heredoc_text "$_PF_COMMAND")
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    json=$(jq -nc --arg p "$t" --arg c "$content" '{tool_name:"Write",tool_input:{file_path:$p,content:$c}}')
    out=$(echo "$json" | "$BASH" "$0" 2>&1) && rc=0 || rc=$?
    case "$rc" in
      0) [ -n "$advice" ] || advice="$out" ;;
      2) printf 'This Bash command writes %s. A file written through Bash gets the same check as a Write or Edit of it:\n\n%s\n' "$t" "$out" >&2
         exit 2 ;;
      *) printf '%s\n' "$out" >&2; exit "$rc" ;;
    esac
  done <<< "$keep"
  [ -z "$advice" ] || printf '%s\n' "$advice"
  exit 0
}
