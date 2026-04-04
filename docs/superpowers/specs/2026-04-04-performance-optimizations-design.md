# Performance Optimizations (Sub-project A)

**Date:** 2026-04-04
**Status:** Approved
**Breaking:** No (internal optimizations, no behavior changes)
**Scope:** _helpers.sh, _preflight.sh (new), enforce-context7.sh, stop-checklist.sh, verification-gate.sh, all Write|Edit hooks

---

## Problem Statement

The audit identified repeated work across hooks that fires on every tool invocation:

1. **Manifest read redundancy** — `get_branch_config_value()` makes up to 6 separate jq calls per invocation. `is_source_file()` reads the manifest on every file check. `.changelogFile` is looked up 3 times across different hooks.
2. **Write|Edit boilerplate duplication** — 5 hooks each independently parse JSON input and classify the file (doc/config/test/source) with identical 4-line blocks.
3. **Import extraction subshell overhead** — `enforce-context7.sh` spawns 3+ subshells per library (grep | head | tr). Double grep for stdlib checks.
4. **Stop-checklist git loop** — spawns `git diff --name-only` per fix commit instead of batch query.
5. **Verification gate tmpfile** — `mktemp` + `cat` + `rm` pattern for stderr capture.
6. **Dead code** — `check_git()` and `validate_file_path()` defined but never called.

**Estimated total savings:** 700-1500ms per interactive session.

## Solution

### 1. Manifest Read Cache in `_helpers.sh`

Add a process-level cache variable. First call to any manifest-reading function loads the file once; subsequent calls within the same hook process reuse the cached content.

**New function:**
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

**Modified functions:** `get_manifest_value`, `get_manifest_array`, `get_branch_config_value`, `get_branch_config_array` all change from reading the manifest file directly to piping from `_get_manifest_json`.

**Impact:** Within a single hook invocation, manifest is read once instead of 3-6 times. Saves ~15-20ms per hook invocation.

### 2. `is_source_file()` Extension Cache

Cache the extensions list on first call within a process:

```bash
_SOURCE_EXTS_CACHE=""
```

On first call to `is_source_file()`, populate `_SOURCE_EXTS_CACHE` from `get_branch_config_array`. Subsequent calls reuse the cache. For commits with 20+ staged files, this avoids 19 redundant manifest reads.

**Impact:** ~50-100ms per commit with many staged files.

### 3. Shared Pre-flight Helper (`_preflight.sh`)

New file `hooks/_preflight.sh` that deduplicates the Write|Edit classification boilerplate. Each hook still runs as its own process (Claude Code limitation), but the code is written once:

```bash
# Usage in each Write|Edit hook:
# source "$SCRIPT_DIR/_preflight.sh"
# preflight_init    # reads stdin, extracts file_path, classifies
# preflight_skip_non_source && exit 0   # exits if doc/config/test/non-source

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

**Modified hooks (5):**
- `enforce-superpowers.sh` — replace lines 7-12 with preflight calls
- `enforce-plan-tracking.sh` — replace lines 9-14 with preflight calls
- `enforce-context7.sh` — replace lines 9-15 with preflight calls
- `changelog-sync-check.sh` — replace lines 7-13 with preflight calls (uses `_PF_FILE_PATH`)
- `scalability-check.sh` — replace lines 7-11 with preflight calls

**Impact:** Code deduplication (remove ~20 duplicated lines). No performance gain across hooks (separate processes), but makes each hook shorter and maintenance easier. Also, within each hook, `is_source_file()` now benefits from the extension cache (item 2).

### 4. `enforce-context7.sh` Import Parsing Optimization

**4a. Replace multi-pipe subshell chains with single operations:**

Current (3 subshells per library):
```bash
LIB=$(echo "$line" | grep -oE "['\"][^'\"./][^'\"]*['\"]" | head -1 | tr -d "'" | tr -d '"')
```

Optimized (1 sed call):
```bash
LIB=$(echo "$line" | sed -n "s/.*['\"]\\([^'\"./][^'\"]*\\)['\"].*/\\1/p" | head -1)
```

**4b. Combine double stdlib grep into single alternation:**

Current (2 grep calls):
```bash
grep -qx "${LANG_PREFIX}:${lib}" "$STDLIB_FILE" || grep -qx "${LANG_PREFIX}:${TOP_MODULE}" "$STDLIB_FILE"
```

Optimized (1 grep call):
```bash
grep -qE "^${LANG_PREFIX}:(${lib}|${TOP_MODULE})$" "$STDLIB_FILE"
```

**Impact:** 2-5ms per library extraction, 1-2ms per stdlib check. For files with 10+ imports: 30-70ms savings.

### 5. `stop-checklist.sh` Git Loop Optimization

Current: spawns `git diff --name-only` per fix commit in a loop.

Optimized: single `git log --name-only` call with fix-pattern filter, then parse output:

```bash
# Get all fix commits with their files in one call
FIX_DATA=$(git log --format="%H %s" --name-only "${SESSION_START}..HEAD" 2>/dev/null || true)
```

Then iterate the output to pair commits with their files, checking for test files.

**Impact:** ~50-200ms for sessions with 5+ commits.

### 6. `verification-gate.sh` Tmpfile Cleanup

Replace:
```bash
GATE_STDERR_FILE=$(mktemp)
GATE_STDOUT=$(eval "$CMD" 2>"$GATE_STDERR_FILE") || GATE_EXIT=$?
GATE_STDERR=$(cat "$GATE_STDERR_FILE")
rm -f "$GATE_STDERR_FILE"
```

With:
```bash
GATE_OUTPUT=$(eval "$CMD" 2>&1) || GATE_EXIT=$?
```

For `failOn: "stderr"` mode, capture stderr separately using file descriptor redirection without mktemp:
```bash
exec 3>&1
GATE_STDERR=$( { GATE_STDOUT=$(eval "$CMD" 2>&1 1>&3); } 2>&1 )
GATE_EXIT=$?
exec 3>&-
```

**Impact:** ~5-10ms per gate execution. Eliminates temp file creation/cleanup.

### 7. Dead Code Removal

Remove from `_helpers.sh`:
- `check_git()` (line 6) — defined, never called
- `validate_file_path()` (lines 131-136) — defined, never called

**Impact:** 7 lines removed. Zero behavior change.

## Files to Modify

| File | Change |
|------|--------|
| `hooks/_helpers.sh` | Add manifest cache, extension cache, remove dead code |
| `hooks/_preflight.sh` (new) | Shared Write|Edit classification helper |
| `hooks/enforce-superpowers.sh` | Use preflight |
| `hooks/enforce-plan-tracking.sh` | Use preflight |
| `hooks/enforce-context7.sh` | Use preflight + optimize import parsing + single stdlib grep |
| `hooks/changelog-sync-check.sh` | Use preflight |
| `hooks/scalability-check.sh` | Use preflight |
| `hooks/stop-checklist.sh` | Optimize git loop |
| `hooks/verification-gate.sh` | Replace tmpfile pattern |

## Testing

All existing 23 test files must continue to pass. No new tests needed — these are internal optimizations with identical behavior. Run full suite after each change to catch regressions.

## Non-Goals

- Hook consolidation (Sub-project B, separate spec)
- Test runner parallelization (deferred — suite already fast enough)
- Session-start parallelization (Sub-project B)
- Marker tracker merging (Sub-project B)
