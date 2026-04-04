#!/usr/bin/env bash
# enforce-context7.sh — PreToolUse (Write|Edit) blocking hook for Implementation Zone
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 1
source "$SCRIPT_DIR/_preflight.sh"

preflight_init
preflight_skip_non_source && exit 0

HASH=$(get_project_hash)

# Skip if Context7 enforcement is degraded (user declined install)
[ -f "/tmp/.claude_c7_degraded_${HASH}" ] && exit 0

# Extract content to scan for imports
if [ "$_PF_TOOL_NAME" = "Edit" ]; then
  CONTENT=$(echo "$_PF_INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null || echo "")
else
  CONTENT=$(echo "$_PF_INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null || echo "")
fi
[ -z "$CONTENT" ] && exit 0

# Load known stdlib modules
STDLIB_FILE="$SCRIPT_DIR/known-stdlib.txt"

# Determine language from file extension
EXT=".${_PF_FILE_PATH##*.}"
LANG_PREFIX=""
case "$EXT" in
  .js|.mjs|.cjs|.jsx|.ts|.tsx) LANG_PREFIX="js" ;;
  .py|.ipynb) LANG_PREFIX="py" ;;
  .go) LANG_PREFIX="go" ;;
  .rs) LANG_PREFIX="rs" ;;
  .rb|.erb) LANG_PREFIX="rb" ;;
  .c|.h) LANG_PREFIX="c" ;;
  .cpp|.hpp|.cc) LANG_PREFIX="cpp" ;;
  *) LANG_PREFIX="" ;;
esac

# Extract library names from import statements
LIBS=""

# JavaScript/TypeScript: import ... from 'lib'; require('lib')
if [ "$LANG_PREFIX" = "js" ]; then
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    LIB=$(echo "$line" | sed -n "s/.*['\"]\\([^'\"./][^'\"]*\\)['\"].*/\\1/p" | head -1)
    [ -n "$LIB" ] && LIBS="${LIBS}${LIB}\n"
  done <<< "$(echo "$CONTENT" | grep -oE "(import .+ from ['\"]([^'\"./][^'\"]*)['\"]|require\(['\"]([^'\"./][^'\"]*)['\"])" 2>/dev/null || true)"
fi

# Python: from lib import ...; import lib
if [ "$LANG_PREFIX" = "py" ]; then
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    LIB=$(echo "$line" | sed -E 's/^(from|import) ([a-zA-Z_][a-zA-Z0-9_]*).*/\2/')
    [ -n "$LIB" ] && LIBS="${LIBS}${LIB}\n"
  done <<< "$(echo "$CONTENT" | grep -oE "(from [a-zA-Z_][a-zA-Z0-9_]* import|^import [a-zA-Z_][a-zA-Z0-9_.]*)" 2>/dev/null || true)"
fi

# Go: import "lib" or import ( "lib" )
if [ "$LANG_PREFIX" = "go" ]; then
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    LIB=${line//\"/}
    [ -n "$LIB" ] && LIBS="${LIBS}${LIB}\n"
  done <<< "$(echo "$CONTENT" | grep -oE '"[a-zA-Z][^"]*"' 2>/dev/null || true)"
fi

# Rust: use lib::...; extern crate lib;
if [ "$LANG_PREFIX" = "rs" ]; then
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    LIB=$(echo "$line" | sed -E 's/^(use|extern crate) ([a-zA-Z_][a-zA-Z0-9_]*).*/\2/')
    [ -n "$LIB" ] && LIBS="${LIBS}${LIB}\n"
  done <<< "$(echo "$CONTENT" | grep -oE "(use [a-zA-Z_][a-zA-Z0-9_]*|extern crate [a-zA-Z_][a-zA-Z0-9_]*)" 2>/dev/null || true)"
fi

# Ruby: require 'lib'
if [ "$LANG_PREFIX" = "rb" ]; then
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    LIB=$(echo "$line" | sed -n "s/.*['\"]\\([^'\"]*\\)['\"].*/\\1/p")
    [ -n "$LIB" ] && LIBS="${LIBS}${LIB}\n"
  done <<< "$(echo "$CONTENT" | grep -oE "require ['\"][a-zA-Z][^'\"]*['\"]" 2>/dev/null || true)"
fi

# C/C++: #include <lib.h> (non-relative only)
if [ "$LANG_PREFIX" = "c" ] || [ "$LANG_PREFIX" = "cpp" ]; then
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    LIB=$(echo "$line" | sed -E 's/#include <([^>]+)>/\1/' | sed 's/\.h$//')
    [ -n "$LIB" ] && LIBS="${LIBS}${LIB}\n"
  done <<< "$(echo "$CONTENT" | grep -oE '#include <[^>]+>' 2>/dev/null || true)"
fi

# Deduplicate and check each library
MISSING=""
CHECKED=""
while IFS= read -r lib; do
  [ -z "$lib" ] && continue
  echo "$CHECKED" | grep -qx "$lib" && continue
  CHECKED="${CHECKED}${lib}\n"

  # Normalize for marker lookup: lowercase, strip @, replace / with -
  NORMALIZED=$(echo "$lib" | tr '[:upper:]' '[:lower:]' | sed 's|^[@/]*||' | tr '/' '-')

  # Check stdlib (single grep with alternation)
  if [ -n "$LANG_PREFIX" ] && [ -f "$STDLIB_FILE" ]; then
    TOP_MODULE=$(echo "$lib" | cut -d'/' -f1 | cut -d'.' -f1)
    if grep -qE "^${LANG_PREFIX}:(${lib}|${TOP_MODULE})$" "$STDLIB_FILE" 2>/dev/null; then
      continue
    fi
  fi

  # Skip relative imports
  case "$lib" in
    ./*|../*|..*) continue ;;
  esac

  # Check for Context7 marker
  if [ ! -f "/tmp/.claude_c7_${HASH}_${NORMALIZED}" ]; then
    MISSING="${MISSING}  - ${lib}\n"
  fi
done <<< "$(printf "%b" "$LIBS" | sort -u)"

if [ -n "$MISSING" ]; then
  printf "BLOCKED [Implementation Zone] — Unresearched libraries detected:\n%b\nBefore editing, query Context7 for each library:\n  1. Use resolve-library-id to find the Context7 ID\n  2. Use get-library-docs to fetch current documentation\n\nIf Context7 has no results, consider using Tavily web search for bleeding-edge libraries.\n\nDo NOT write code using libraries you haven't researched.\nDo NOT skip this because you are confident in your training data.\nDo NOT create markers manually.\n\nCOMPLIANCE REMINDER: Your obligation is compliance first, speed second.\n" "$MISSING" >&2
  exit 2
fi
exit 0
