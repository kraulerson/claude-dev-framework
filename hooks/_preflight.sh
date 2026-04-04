#!/usr/bin/env bash
# _preflight.sh — Shared input parsing and file classification for Write|Edit hooks.
# Sourced by hooks via: source "$SCRIPT_DIR/_preflight.sh"
# Usage:
#   preflight_init              # reads stdin, extracts file_path and tool_name
#   preflight_skip_non_source   # returns 0 if file should be skipped (doc/config/test/non-source)
#
# After preflight_init, these variables are available:
#   _PF_INPUT      — raw JSON input
#   _PF_FILE_PATH  — extracted file path
#   _PF_TOOL_NAME  — tool name (Write or Edit)

_PF_INPUT=""
_PF_FILE_PATH=""
_PF_TOOL_NAME=""

preflight_init() {
  _PF_INPUT=$(cat)
  _PF_FILE_PATH=$(echo "$_PF_INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null || echo "")
  _PF_TOOL_NAME=$(echo "$_PF_INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
}

preflight_skip_non_source() {
  [ -z "$_PF_FILE_PATH" ] && return 0
  is_doc_or_config "$_PF_FILE_PATH" && return 0
  is_test_file "$_PF_FILE_PATH" && return 0
  is_source_file "$_PF_FILE_PATH" || return 0
  return 1
}
