#!/usr/bin/env bash
# enforce-context7.sh — PreToolUse (Write|Edit) blocking hook for Implementation Zone
# Blocks source file edits that import unresearched third-party libraries.
# Libraries are marked as researched by context7-tracker.sh when Context7 MCP is queried.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 1

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null || echo "")
[ -z "$FILE_PATH" ] && exit 0
is_doc_or_config "$FILE_PATH" && exit 0
is_test_file "$FILE_PATH" && exit 0
is_source_file "$FILE_PATH" || exit 0

HASH=$(get_project_hash)

# Skip if Context7 enforcement is degraded (user declined install)
[ -f "/tmp/.claude_c7_degraded_${HASH}" ] && exit 0

# Extract content to scan for imports
if [ "$TOOL_NAME" = "Edit" ]; then
  CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null || echo "")
else
  CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null || echo "")
fi
[ -z "$CONTENT" ] && exit 0

# Load known stdlib modules
STDLIB_FILE="$SCRIPT_DIR/known-stdlib.txt"

# Determine language from file extension
EXT=".${FILE_PATH##*.}"
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
  JS_IMPORTS=$(echo "$CONTENT" | grep -oE "(import .+ from ['\"]([^'\"./][^'\"]*)['\"]|require\(['\"]([^'\"./][^'\"]*)['\"])" 2>/dev/null || true)
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    LIB=$(echo "$line" | grep -oE "['\"][^'\"./][^'\"]*['\"]" | head -1 | tr -d "'" | tr -d '"')
    [ -n "$LIB" ] && LIBS="${LIBS}${LIB}\n"
  done <<< "$JS_IMPORTS"
fi

# Python: from lib import ...; import lib
if [ "$LANG_PREFIX" = "py" ]; then
  PY_IMPORTS=$(echo "$CONTENT" | grep -oE "(from [a-zA-Z_][a-zA-Z0-9_]* import|^import [a-zA-Z_][a-zA-Z0-9_.]*)" 2>/dev/null || true)
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    LIB=$(echo "$line" | sed -E 's/^from ([a-zA-Z_][a-zA-Z0-9_]*).*/\1/' | sed -E 's/^import ([a-zA-Z_][a-zA-Z0-9_]*).*/\1/')
    [ -n "$LIB" ] && LIBS="${LIBS}${LIB}\n"
  done <<< "$PY_IMPORTS"
fi

# Go: import "lib" or import ( "lib" )
if [ "$LANG_PREFIX" = "go" ]; then
  GO_IMPORTS=$(echo "$CONTENT" | grep -oE '"[a-zA-Z][^"]*"' 2>/dev/null || true)
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    LIB=$(echo "$line" | tr -d '"')
    [ -n "$LIB" ] && LIBS="${LIBS}${LIB}\n"
  done <<< "$GO_IMPORTS"
fi

# Rust: use lib::...; extern crate lib;
if [ "$LANG_PREFIX" = "rs" ]; then
  RS_IMPORTS=$(echo "$CONTENT" | grep -oE "(use [a-zA-Z_][a-zA-Z0-9_]*|extern crate [a-zA-Z_][a-zA-Z0-9_]*)" 2>/dev/null || true)
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    LIB=$(echo "$line" | sed -E 's/^(use|extern crate) ([a-zA-Z_][a-zA-Z0-9_]*).*/\2/')
    [ -n "$LIB" ] && LIBS="${LIBS}${LIB}\n"
  done <<< "$RS_IMPORTS"
fi

# Ruby: require 'lib'
if [ "$LANG_PREFIX" = "rb" ]; then
  RB_IMPORTS=$(echo "$CONTENT" | grep -oE "require ['\"][a-zA-Z][^'\"]*['\"]" 2>/dev/null || true)
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    LIB=$(echo "$line" | grep -oE "['\"][^'\"]*['\"]" | tr -d "'" | tr -d '"')
    [ -n "$LIB" ] && LIBS="${LIBS}${LIB}\n"
  done <<< "$RB_IMPORTS"
fi

# C/C++: #include <lib.h> (non-relative only)
if [ "$LANG_PREFIX" = "c" ] || [ "$LANG_PREFIX" = "cpp" ]; then
  C_INCLUDES=$(echo "$CONTENT" | grep -oE '#include <[^>]+>' 2>/dev/null || true)
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    LIB=$(echo "$line" | sed -E 's/#include <([^>]+)>/\1/' | sed 's/\.h$//')
    [ -n "$LIB" ] && LIBS="${LIBS}${LIB}\n"
  done <<< "$C_INCLUDES"
fi

# Deduplicate and check each library
MISSING=""
CHECKED=""
while IFS= read -r lib; do
  [ -z "$lib" ] && continue
  # Skip if already checked
  echo "$CHECKED" | grep -qx "$lib" && continue
  CHECKED="${CHECKED}${lib}\n"

  # Normalize for marker lookup: lowercase, strip @, replace / with -
  NORMALIZED=$(echo "$lib" | tr '[:upper:]' '[:lower:]' | sed 's|^[@/]*||' | tr '/' '-')

  # Check stdlib
  if [ -n "$LANG_PREFIX" ] && [ -f "$STDLIB_FILE" ]; then
    TOP_MODULE=$(echo "$lib" | cut -d'/' -f1 | cut -d'.' -f1)
    if grep -qx "${LANG_PREFIX}:${lib}" "$STDLIB_FILE" 2>/dev/null || \
       grep -qx "${LANG_PREFIX}:${TOP_MODULE}" "$STDLIB_FILE" 2>/dev/null; then
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
