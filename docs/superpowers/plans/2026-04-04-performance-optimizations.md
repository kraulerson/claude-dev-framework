# Performance Optimizations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce per-operation latency across all hooks by caching manifest reads, deduplicating file classification, optimizing import parsing, and removing dead code.

**Architecture:** Add manifest read cache and extension cache to `_helpers.sh` (process-level variables). Create `_preflight.sh` shared helper for Write|Edit hooks. Optimize `enforce-context7.sh` subshell chains. Fix `stop-checklist.sh` git loop. Clean up `verification-gate.sh` tmpfile pattern. Remove dead code.

**Tech Stack:** Bash, jq

---

## File Map

### New Files

| File | Responsibility |
|------|---------------|
| `hooks/_preflight.sh` | Shared Write|Edit input parsing and file classification |

### Modified Files

| File | What Changes |
|------|-------------|
| `hooks/_helpers.sh` | Add manifest cache, extension cache, remove dead code |
| `hooks/enforce-superpowers.sh` | Use preflight |
| `hooks/enforce-plan-tracking.sh` | Use preflight |
| `hooks/enforce-context7.sh` | Use preflight + optimize import parsing + single stdlib grep |
| `hooks/changelog-sync-check.sh` | Use preflight for input parsing |
| `hooks/scalability-check.sh` | Use preflight |
| `hooks/stop-checklist.sh` | Optimize git loop for bug-fix detection |
| `hooks/verification-gate.sh` | Replace tmpfile with fd redirection |

---

### Task 1: Add Manifest Cache to _helpers.sh

**Files:**
- Modify: `hooks/_helpers.sh:5-22`

- [ ] **Step 1: Add the cache function and variable**

In `hooks/_helpers.sh`, after line 5 (`check_jq() { ... }`), before line 6 (`check_git`), add:

```bash
_MANIFEST_CACHE=""
_get_manifest_json() {
  if [ -z "$_MANIFEST_CACHE" ]; then
    local manifest; manifest="$(get_manifest_path)"
    [ -f "$manifest" ] && _MANIFEST_CACHE=$(cat "$manifest") || _MANIFEST_CACHE="{}"
  fi
  echo "$_MANIFEST_CACHE"
}
```

- [ ] **Step 2: Update get_manifest_value to use cache**

Replace lines 12-16:

```bash
get_manifest_value() {
  local manifest; manifest="$(get_manifest_path)"
  [ ! -f "$manifest" ] || ! check_jq && { echo ""; return 0; }
  jq -r "$1 // empty" "$manifest" 2>/dev/null || echo ""
}
```

With:

```bash
get_manifest_value() {
  ! check_jq && { echo ""; return 0; }
  local json; json=$(_get_manifest_json)
  [ "$json" = "{}" ] && { echo ""; return 0; }
  echo "$json" | jq -r "$1 // empty" 2>/dev/null || echo ""
}
```

- [ ] **Step 3: Update get_manifest_array to use cache**

Replace lines 18-22:

```bash
get_manifest_array() {
  local manifest; manifest="$(get_manifest_path)"
  [ ! -f "$manifest" ] || ! check_jq && return 0
  jq -r "$1 // empty" "$manifest" 2>/dev/null || true
}
```

With:

```bash
get_manifest_array() {
  ! check_jq && return 0
  local json; json=$(_get_manifest_json)
  [ "$json" = "{}" ] && return 0
  echo "$json" | jq -r "$1 // empty" 2>/dev/null || true
}
```

- [ ] **Step 4: Update get_branch_config_value to use cache**

Replace lines 26-46. The key change: read manifest once via cache, pipe to all jq calls:

```bash
get_branch_config_value() {
  local jq_path="$1" branch base_val branch_val
  branch="$(get_branch)"
  ! check_jq && { echo ""; return 0; }
  local json; json=$(_get_manifest_json)
  [ "$json" = "{}" ] && { echo ""; return 0; }
  base_val=$(echo "$json" | jq -r ".projectConfig._base${jq_path} // empty" 2>/dev/null || echo "")
  branch_val=$(echo "$json" | jq -r --arg b "$branch" '.projectConfig.branches[] | select(.match == $b) | .config'"${jq_path}"' // empty' 2>/dev/null || echo "")
  if [ -z "$branch_val" ]; then
    local patterns; patterns=$(echo "$json" | jq -r '.projectConfig.branches[].match // empty' 2>/dev/null || true)
    while IFS= read -r pattern; do
      [ -z "$pattern" ] && continue
      if [[ "$branch" == $pattern ]]; then
        local inherits; inherits=$(echo "$json" | jq -r --arg p "$pattern" '.projectConfig.branches[] | select(.match == $p) | .inherits // empty' 2>/dev/null || echo "")
        [ -n "$inherits" ] && branch_val=$(echo "$json" | jq -r --arg b "$inherits" '.projectConfig.branches[] | select(.match == $b) | .config'"${jq_path}"' // empty' 2>/dev/null || echo "")
        local overlay; overlay=$(echo "$json" | jq -r --arg p "$pattern" '.projectConfig.branches[] | select(.match == $p) | .config'"${jq_path}"' // empty' 2>/dev/null || echo "")
        [ -n "$overlay" ] && branch_val="$overlay"
        break
      fi
    done <<< "$patterns"
  fi
  if [ -n "$branch_val" ]; then echo "$branch_val"; elif [ -n "$base_val" ]; then echo "$base_val"; else echo ""; fi
}
```

- [ ] **Step 5: Update get_branch_config_array to use cache**

Replace lines 48-55:

```bash
get_branch_config_array() {
  local jq_path="$1" branch result
  branch="$(get_branch)"
  ! check_jq && return 0
  local json; json=$(_get_manifest_json)
  [ "$json" = "{}" ] && return 0
  result=$(echo "$json" | jq -r --arg b "$branch" '(.projectConfig.branches[] | select(.match == $b) | .config'"${jq_path}"'[]?) // empty' 2>/dev/null || true)
  [ -z "$result" ] && result=$(echo "$json" | jq -r ".projectConfig._base${jq_path}[]? // empty" 2>/dev/null || true)
  echo "$result"
}
```

- [ ] **Step 6: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All 23 test files pass. Manifest cache is transparent — behavior unchanged.

- [ ] **Step 7: Commit**

```bash
git add hooks/_helpers.sh
git commit -m "perf: add manifest read cache to _helpers.sh — read file once per hook invocation"
```

---

### Task 2: Add Extension Cache to is_source_file()

**Files:**
- Modify: `hooks/_helpers.sh:57-90` (is_source_file function)

- [ ] **Step 1: Add cache variable and update is_source_file**

Add before the `is_source_file()` function:

```bash
_SOURCE_EXTS_CACHE=""
```

Inside `is_source_file()`, replace lines 66-89 (the extension loading and matching block):

```bash
  # 2. Explicit allowlist from manifest (or fallback) — user override
  if [ -z "$_SOURCE_EXTS_CACHE" ]; then
    _SOURCE_EXTS_CACHE=$(get_branch_config_array '.sourceExtensions')
    if [ -z "$_SOURCE_EXTS_CACHE" ]; then
      _SOURCE_EXTS_CACHE=".html .css .scss .less .sass .jsx .tsx .vue .svelte"
      _SOURCE_EXTS_CACHE="$_SOURCE_EXTS_CACHE .js .ts .mjs .cjs"
      _SOURCE_EXTS_CACHE="$_SOURCE_EXTS_CACHE .py .ipynb"
      _SOURCE_EXTS_CACHE="$_SOURCE_EXTS_CACHE .java .kt .kts .scala .groovy"
      _SOURCE_EXTS_CACHE="$_SOURCE_EXTS_CACHE .cs .fs .vb"
      _SOURCE_EXTS_CACHE="$_SOURCE_EXTS_CACHE .swift .m .mm"
      _SOURCE_EXTS_CACHE="$_SOURCE_EXTS_CACHE .c .cpp .h .hpp .rs .go .zig .asm .s"
      _SOURCE_EXTS_CACHE="$_SOURCE_EXTS_CACHE .rb .erb"
      _SOURCE_EXTS_CACHE="$_SOURCE_EXTS_CACHE .php"
      _SOURCE_EXTS_CACHE="$_SOURCE_EXTS_CACHE .sh .bash .zsh"
      _SOURCE_EXTS_CACHE="$_SOURCE_EXTS_CACHE .bat .cmd .ps1 .psm1 .vbs"
      _SOURCE_EXTS_CACHE="$_SOURCE_EXTS_CACHE .dart"
      _SOURCE_EXTS_CACHE="$_SOURCE_EXTS_CACHE .ex .exs .erl"
      _SOURCE_EXTS_CACHE="$_SOURCE_EXTS_CACHE .hs"
      _SOURCE_EXTS_CACHE="$_SOURCE_EXTS_CACHE .clj .cljs"
      _SOURCE_EXTS_CACHE="$_SOURCE_EXTS_CACHE .lua"
      _SOURCE_EXTS_CACHE="$_SOURCE_EXTS_CACHE .r .R"
      _SOURCE_EXTS_CACHE="$_SOURCE_EXTS_CACHE .pl .pm"
      _SOURCE_EXTS_CACHE="$_SOURCE_EXTS_CACHE .sql .graphql .proto"
      _SOURCE_EXTS_CACHE="$_SOURCE_EXTS_CACHE .tf .hcl"
    fi
  fi
  for e in $_SOURCE_EXTS_CACHE; do [ "$ext" = "$e" ] && return 0; done
```

- [ ] **Step 2: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All 23 test files pass.

- [ ] **Step 3: Commit**

```bash
git add hooks/_helpers.sh
git commit -m "perf: cache source extensions in is_source_file() — avoid repeated manifest reads"
```

---

### Task 3: Remove Dead Code

**Files:**
- Modify: `hooks/_helpers.sh`

- [ ] **Step 1: Remove check_git()**

Delete the `check_git` line (currently `check_git() { command -v git &>/dev/null; }`).

- [ ] **Step 2: Remove validate_file_path()**

Delete the `validate_file_path()` function (5 lines).

- [ ] **Step 3: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All 23 test files pass. Neither function is called anywhere.

- [ ] **Step 4: Commit**

```bash
git add hooks/_helpers.sh
git commit -m "chore: remove unused check_git() and validate_file_path() from _helpers.sh"
```

---

### Task 4: Create _preflight.sh

**Files:**
- Create: `hooks/_preflight.sh`

- [ ] **Step 1: Create the preflight helper**

Create `hooks/_preflight.sh`:

```bash
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
```

- [ ] **Step 2: Commit**

```bash
git add hooks/_preflight.sh
git commit -m "feat: add _preflight.sh shared helper for Write|Edit hooks"
```

---

### Task 5: Update enforce-superpowers.sh to Use Preflight

**Files:**
- Modify: `hooks/enforce-superpowers.sh`

- [ ] **Step 1: Replace input parsing with preflight**

Replace the entire file content:

```bash
#!/usr/bin/env bash
# enforce-superpowers.sh — PreToolUse (Write|Edit) blocking hook
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 1
source "$SCRIPT_DIR/_preflight.sh"

preflight_init
preflight_skip_non_source && exit 0

HASH=$(get_project_hash)
[ -f "/tmp/.claude_superpowers_${HASH}" ] && exit 0

cat >&2 << 'MSG'
BLOCKED — Source file edit requires Superpowers workflow.

You MUST invoke superpowers:brainstorming before editing source files.
Do NOT present a text evaluation as a substitute.
Do NOT ask the user if you should proceed without brainstorming.
Do NOT skip this because the change seems simple.
Do NOT create the marker manually — it is created automatically when you invoke a Superpowers skill.

Invoke the skill now, then retry the edit.

COMPLIANCE REMINDER: Your obligation is compliance first, speed second. There is no task small enough to skip this requirement. Do not classify this change as trivial. Do not run a cost-benefit analysis against the process. Follow the required workflow, then proceed.
MSG
exit 2
```

- [ ] **Step 2: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All 23 test files pass.

- [ ] **Step 3: Commit**

```bash
git add hooks/enforce-superpowers.sh
git commit -m "refactor: enforce-superpowers uses shared preflight helper"
```

---

### Task 6: Update enforce-plan-tracking.sh to Use Preflight

**Files:**
- Modify: `hooks/enforce-plan-tracking.sh`

- [ ] **Step 1: Replace input parsing with preflight**

Replace the entire file content:

```bash
#!/usr/bin/env bash
# enforce-plan-tracking.sh — PreToolUse (Write|Edit) blocking hook for Planning Zone
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 1
source "$SCRIPT_DIR/_preflight.sh"

preflight_init
preflight_skip_non_source && exit 0

HASH=$(get_project_hash)

# Planning Zone only arms when writing-plans has been invoked
[ -f "/tmp/.claude_has_plan_${HASH}" ] || exit 0

# Check for active plan task
[ -f "/tmp/.claude_plan_active_${HASH}" ] && exit 0

cat >&2 << 'MSG'
BLOCKED [Planning Zone] — No plan task is in_progress.

You have a written plan for this session. Before editing source files, mark the task you are working on as in_progress using TaskUpdate.

Do NOT edit source files without an active plan task.
Do NOT skip this because the change seems small.
Do NOT create the marker manually — it is created automatically when you update a task to in_progress.

COMPLIANCE REMINDER: Your obligation is compliance first, speed second. There is no task small enough to skip this requirement.
MSG
exit 2
```

- [ ] **Step 2: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All 23 test files pass.

- [ ] **Step 3: Commit**

```bash
git add hooks/enforce-plan-tracking.sh
git commit -m "refactor: enforce-plan-tracking uses shared preflight helper"
```

---

### Task 7: Update scalability-check.sh to Use Preflight

**Files:**
- Modify: `hooks/scalability-check.sh`

- [ ] **Step 1: Replace input parsing with preflight**

Replace the entire file content:

```bash
#!/usr/bin/env bash
# scalability-check.sh — PreToolUse (Write|Edit) advisory hook
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 1
source "$SCRIPT_DIR/_preflight.sh"

preflight_init
preflight_skip_non_source && exit 0

FUTURE=$(get_manifest_value '.discovery.futurePlatforms')
[ -z "$FUTURE" ] && exit 0

BASENAME=$(basename "$_PF_FILE_PATH")
case "$BASENAME" in
  *Repository*|*Service*|*API*|*Router*|*Middleware*|*Schema*|*Migration*|*build.gradle*|*Package.swift*|*Cargo.toml*|*package.json*|*Dockerfile*) ;;
  *) exit 0 ;;
esac

jq -n --arg fp "$FUTURE" '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": ("REMINDER: This project may expand to: " + $fp + ". Consider whether this architectural choice keeps that option open or closes it off. If it restricts future options, flag it in your evaluation.\n\nThis advisory is not optional guidance. Acknowledge and act on it before proceeding.")
  }
}'
exit 0
```

- [ ] **Step 2: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All 23 test files pass.

- [ ] **Step 3: Commit**

```bash
git add hooks/scalability-check.sh
git commit -m "refactor: scalability-check uses shared preflight helper"
```

---

### Task 8: Update changelog-sync-check.sh to Use Preflight Input Parsing

**Files:**
- Modify: `hooks/changelog-sync-check.sh`

- [ ] **Step 1: Replace input parsing with preflight**

Replace the entire file content:

```bash
#!/usr/bin/env bash
# changelog-sync-check.sh — PreToolUse (Write|Edit) advisory hook
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 1
source "$SCRIPT_DIR/_preflight.sh"

preflight_init
[ -z "$_PF_FILE_PATH" ] && exit 0

CHANGELOG=$(get_branch_config_value '.changelogFile')
[ -z "$CHANGELOG" ] && exit 0
echo "$_PF_FILE_PATH" | grep -q "$CHANGELOG" || exit 0

HASH=$(get_project_hash)
MARKER="/tmp/.claude_changelog_synced_${HASH}"
if [ -f "$MARKER" ]; then
  AGE=$(( $(date +%s) - $(stat -f %m "$MARKER" 2>/dev/null || stat -c %Y "$MARKER" 2>/dev/null || echo 0) ))
  [ "$AGE" -lt 3600 ] && exit 0
fi

SYNC_CMD=$(get_branch_config_value '.syncCommand')
[ -z "$SYNC_CMD" ] && exit 0

jq -n --arg cmd "$SYNC_CMD" '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": ("IMPORTANT: Before editing the changelog, run the sync command first to merge upstream changes: " + $cmd + "\n\nThis advisory is not optional guidance. Acknowledge and act on it before proceeding.")
  }
}'
exit 0
```

- [ ] **Step 2: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All 23 test files pass.

- [ ] **Step 3: Commit**

```bash
git add hooks/changelog-sync-check.sh
git commit -m "refactor: changelog-sync-check uses shared preflight helper"
```

---

### Task 9: Optimize enforce-context7.sh

**Files:**
- Modify: `hooks/enforce-context7.sh`

- [ ] **Step 1: Use preflight and optimize import extraction**

Replace the entire file content:

```bash
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
```

- [ ] **Step 2: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All 23 test files pass (including test-enforce-context7.sh with all 15 assertions).

- [ ] **Step 3: Commit**

```bash
git add hooks/enforce-context7.sh
git commit -m "perf: optimize enforce-context7 — preflight, single-sed import extraction, single stdlib grep"
```

---

### Task 10: Optimize stop-checklist.sh Git Loop

**Files:**
- Modify: `hooks/stop-checklist.sh:34-47`

- [ ] **Step 1: Replace per-commit git diff with batch query**

Replace lines 34-47:

```bash
if [ "$HAS_SOURCE" = false ] && [ -z "$STAGED" ] && [ -n "$SESSION_START" ]; then
  UNTESTED_FIXES=""
  while IFS=' ' read -r sha msg; do
    [ -z "$sha" ] && continue
    if echo "$msg" | grep -qiE '\b(fix|bug|patch|hotfix|repair|resolve)\b'; then
      COMMIT_FILES=$(git diff --name-only "${sha}~1" "$sha" 2>/dev/null || true)
      HAS_TEST=false
      for f in $COMMIT_FILES; do is_test_file "$f" && { HAS_TEST=true; break; }; done
      [ "$HAS_TEST" = false ] && UNTESTED_FIXES="${UNTESTED_FIXES}${sha:0:8}\n"
    fi
  done <<< "$(git log --format='%H %s' "${SESSION_START}..HEAD" 2>/dev/null || true)"
  if [ -n "$UNTESTED_FIXES" ]; then
    ERRORS="${ERRORS}- One or more commits look like a bug fix but have NO regression test.\n"
  fi
fi
```

With:

```bash
if [ "$HAS_SOURCE" = false ] && [ -z "$STAGED" ] && [ -n "$SESSION_START" ]; then
  UNTESTED_FIXES=""
  # Get all commits with files in one git call
  COMMIT_LOG=$(git log --format="COMMIT %H %s" --name-only "${SESSION_START}..HEAD" 2>/dev/null || true)
  CURRENT_SHA="" CURRENT_MSG="" CURRENT_HAS_TEST=false
  while IFS= read -r line; do
    if [[ "$line" == COMMIT\ * ]]; then
      # Process previous commit
      if [ -n "$CURRENT_SHA" ] && echo "$CURRENT_MSG" | grep -qiE '\b(fix|bug|patch|hotfix|repair|resolve)\b'; then
        [ "$CURRENT_HAS_TEST" = false ] && UNTESTED_FIXES="${UNTESTED_FIXES}${CURRENT_SHA:0:8}\n"
      fi
      CURRENT_SHA="${line#COMMIT }" CURRENT_SHA="${CURRENT_SHA%% *}"
      CURRENT_MSG="${line#COMMIT * }"
      CURRENT_HAS_TEST=false
    elif [ -n "$line" ] && [ -n "$CURRENT_SHA" ]; then
      is_test_file "$line" && CURRENT_HAS_TEST=true
    fi
  done <<< "$COMMIT_LOG"
  # Process last commit
  if [ -n "$CURRENT_SHA" ] && echo "$CURRENT_MSG" | grep -qiE '\b(fix|bug|patch|hotfix|repair|resolve)\b'; then
    [ "$CURRENT_HAS_TEST" = false ] && UNTESTED_FIXES="${UNTESTED_FIXES}${CURRENT_SHA:0:8}\n"
  fi
  if [ -n "$UNTESTED_FIXES" ]; then
    ERRORS="${ERRORS}- One or more commits look like a bug fix but have NO regression test.\n"
  fi
fi
```

- [ ] **Step 2: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All 23 test files pass (stop-checklist tests verify bug-fix detection).

- [ ] **Step 3: Commit**

```bash
git add hooks/stop-checklist.sh
git commit -m "perf: stop-checklist uses single git log --name-only instead of per-commit git diff"
```

---

### Task 11: Optimize verification-gate.sh Tmpfile

**Files:**
- Modify: `hooks/verification-gate.sh:39-46`

- [ ] **Step 1: Replace tmpfile pattern with fd redirection**

Replace lines 39-46:

```bash
  # Run the gate
  GATE_STDOUT=""
  GATE_STDERR=""
  GATE_EXIT=0
  GATE_STDERR_FILE=$(mktemp)
  GATE_STDOUT=$(eval "$CMD" 2>"$GATE_STDERR_FILE") || GATE_EXIT=$?
  GATE_STDERR=$(cat "$GATE_STDERR_FILE")
  rm -f "$GATE_STDERR_FILE"
```

With:

```bash
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
```

- [ ] **Step 2: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All 23 test files pass (verification-gate tests cover exit_code, stderr, and disabled gates).

- [ ] **Step 3: Commit**

```bash
git add hooks/verification-gate.sh
git commit -m "perf: verification-gate uses fd redirection instead of tmpfile for stderr capture"
```

---

### Task 12: Final Validation

- [ ] **Step 1: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All 23 test files pass.

- [ ] **Step 2: Verify _preflight.sh is sourced correctly**

Run: `grep -r '_preflight.sh' hooks/`
Expected: 5 hooks source it (enforce-superpowers, enforce-plan-tracking, enforce-context7, changelog-sync-check, scalability-check).

- [ ] **Step 3: Verify no dead code remains**

Run: `grep -n 'check_git\|validate_file_path' hooks/_helpers.sh`
Expected: No matches.

- [ ] **Step 4: Verify manifest cache is used**

Run: `grep -n '_get_manifest_json\|_MANIFEST_CACHE' hooks/_helpers.sh`
Expected: Cache variable declaration + function definition + usage in all 4 manifest functions.

- [ ] **Step 5: Push**

```bash
git push origin main
```
