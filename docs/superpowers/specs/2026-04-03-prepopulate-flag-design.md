# --prepopulate Flag for init.sh

**Date:** 2026-04-03
**Status:** Approved
**Breaking:** No (additive flag, no existing behavior changes)
**Scope:** scripts/init.sh, tests, README

---

## Problem Statement

The Solo Orchestrator (and any application installing claude-dev-framework as a dependency) already knows the project's platform, language, dev OS, and branch when it calls `scripts/init.sh`. Currently it pipes empty lines to skip the interactive discovery interview, which means the framework falls back to defaults and misses useful context.

Additionally, init.sh does not check for or offer to install required dependencies (Superpowers plugin, Context7 MCP), leaving that to session-start.sh at runtime. Callers that manage their own dependencies need a way to skip these checks.

## Solution

### 1. `--prepopulate <path>` Flag

A new flag for `scripts/init.sh` that reads a JSON file containing pre-answered discovery data, skipping the interactive interview entirely.

**JSON format** (same structure as `run_discovery()` output):

```json
{
  "branch:main": {
    "purpose": "main development branch",
    "devOS": "Darwin",
    "targetPlatform": "web",
    "buildTools": "typescript"
  },
  "futurePlatforms": null,
  "discoveryDate": "2026-04-03",
  "lastReviewDate": "2026-04-03"
}
```

**Behavior when provided:**
- Skip `run_discovery()` interactive interview entirely
- Read the JSON file contents as `DISCOVERY_JSON`
- Log to stderr: `"Using pre-populated discovery from <path>"`
- Continue with profile detection, hook installation, manifest generation as normal

**Validation (3 checks, all must pass):**
1. File exists at the given path
2. File is valid JSON (`jq '.' file`)
3. JSON contains at least one key matching `branch:*`

If any validation fails: warn to stderr with specific failure reason, fall back to interactive `run_discovery()`.

**Priority:** `--prepopulate` takes precedence over both clean-install and `--reconfigure` discovery. Providing the file is an explicit "I already have answers" signal.

### 2. Dependency Install Section

Init.sh gains a dependency check/install section that runs after the existing Phase 5 plugin check area. This mirrors what `migrations/v4.sh` already does.

**Checks:**
1. **Superpowers plugin** — reads `~/.claude/settings.json` for `enabledPlugins["superpowers@claude-plugins-official"]`
   - If missing: prints install instructions (cannot be auto-installed — requires Claude CLI interactive flow)
2. **Context7 MCP** — uses `check_context7()` from `_helpers.sh`
   - If missing: offers auto-install with consent: `"Context7 MCP is required for v4.0.0. Install now? (requires Node.js) [y/N]"`
   - If confirmed: runs `claude mcp add context7 -- npx -y @upstash/context7-mcp@latest`
   - If declined: warns that Implementation Zone will be degraded

**`--skip-plugin-check` behavior:** When this flag is set (already exists), skip ALL dependency checks — Superpowers, Context7. Solo Orchestrator passes this flag because it handles dependency installation itself.

### 3. Flag Parsing Update

Current flag parsing uses a simple `for arg` loop. Since `--prepopulate` takes a value argument, the loop needs positional tracking. When `--prepopulate` is seen, the next argument is consumed as the path.

```bash
PREPOPULATE_FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --migrate) MIGRATE=true ;;
    --reconfigure) RECONFIGURE=true ;;
    --archive) ARCHIVE=true ;;
    --skip-plugin-check) SKIP_PLUGINS=true ;;
    --prepopulate) shift; PREPOPULATE_FILE="${1:-}" ;;
  esac
  shift
done
```

### 4. Integration Point

Lines 268-272 of current init.sh change from:

```bash
DISCOVERY_JSON="{}"
if [ "$HAS_EXISTING" = false ] || [ "$RECONFIGURE" = true ]; then
  DISCOVERY_JSON=$(run_discovery)
fi
```

To:

```bash
DISCOVERY_JSON="{}"
if [ -n "$PREPOPULATE_FILE" ]; then
  # Validate prepopulated JSON
  if [ ! -f "$PREPOPULATE_FILE" ]; then
    echo "WARNING: Prepopulate file not found: $PREPOPULATE_FILE. Falling back to interview." >&2
  elif ! jq '.' "$PREPOPULATE_FILE" >/dev/null 2>&1; then
    echo "WARNING: Prepopulate file is not valid JSON: $PREPOPULATE_FILE. Falling back to interview." >&2
  elif ! jq -e 'keys[] | select(startswith("branch:"))' "$PREPOPULATE_FILE" >/dev/null 2>&1; then
    echo "WARNING: Prepopulate file has no branch:* keys: $PREPOPULATE_FILE. Falling back to interview." >&2
  else
    DISCOVERY_JSON=$(cat "$PREPOPULATE_FILE")
    echo "Using pre-populated discovery from $PREPOPULATE_FILE" >&2
  fi
  # If DISCOVERY_JSON still empty after validation failure, run interview
  if [ "$DISCOVERY_JSON" = "{}" ]; then
    DISCOVERY_JSON=$(run_discovery)
  fi
elif [ "$HAS_EXISTING" = false ] || [ "$RECONFIGURE" = true ]; then
  DISCOVERY_JSON=$(run_discovery)
fi
```

## Solo Orchestrator Usage

After this change, Solo Orchestrator's init call changes from:

```bash
# Before: piping empty lines
echo "" | echo "" | echo "" | bash "$FRAMEWORK_CLONE/scripts/init.sh" --skip-plugin-check
```

To:

```bash
# After: prepopulated discovery
bash "$FRAMEWORK_CLONE/scripts/init.sh" --skip-plugin-check --prepopulate .claude/discovery-prepopulated.json
```

## Files to Modify

| File | Change |
|------|--------|
| `scripts/init.sh` | Add `--prepopulate` flag parsing, validation, conditional skip of `run_discovery()`, dependency install section |
| `tests/test-prepopulate.sh` | New test file — valid JSON passes, invalid JSON falls back, missing file falls back, no branch key falls back |
| `README.md` | Document `--prepopulate` flag |

## Testing

| Test | Expected |
|------|----------|
| Valid JSON with `branch:*` key | Discovery skipped, JSON used as-is, log message printed |
| Valid JSON without `branch:*` key | Warning printed, falls back to interview |
| Invalid JSON file | Warning printed, falls back to interview |
| Missing file path | Warning printed, falls back to interview |
| `--skip-plugin-check` | Superpowers and Context7 checks both skipped |
| No `--prepopulate` flag (clean install) | Interactive interview runs as before |
| `--prepopulate` with `--reconfigure` | Prepopulate takes priority |

## Non-Goals

- Profile override flag — `detect-profile.sh` always runs
- Validating individual field values within the prepopulated JSON — structure check only
- Making `run_discovery()` accept partial prepopulation (all or nothing)
