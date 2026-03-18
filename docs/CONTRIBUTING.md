# Contributing — Bash Coding Conventions

These conventions apply to **new code** (new hooks, new helpers, bug fixes). Do NOT bulk-rewrite existing code for style. Update existing code opportunistically when touching it for other reasons.

## Hook Boilerplate

Every hook script should start with this structure:

```bash
#!/usr/bin/env bash
# hook-name.sh — Event (Matcher) description
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 0

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
```

- `set -euo pipefail` is mandatory
- Source `_helpers.sh` with fallback (`|| exit 0` for advisory, `|| exit 1` for blocking)
- Read all stdin into `INPUT` once, then extract fields with jq

## Regex Matching

Prefer bash builtins for simple pattern matches (no subprocess):

```bash
# Preferred — pure bash
[[ "$COMMAND" =~ ^[[:space:]]*git[[:space:]]+commit ]]

# Acceptable — when piping or matching multi-line input
echo "$COMMAND" | grep -qE '^\s*git\s+commit'
```

Use `grep` when the input comes from a pipe or spans multiple lines. Use `[[ =~ ]]` when matching a single variable.

## Error Accumulation

Prefer arrays over string concatenation with `\n`:

```bash
# Preferred
ERRORS=()
ERRORS+=("- Missing changelog.")
ERRORS+=("- Missing version bump.")
(( ${#ERRORS[@]} > 0 )) && printf '%s\n' "${ERRORS[@]}"

# Acceptable (existing code uses this pattern)
ERRORS=""
ERRORS="${ERRORS}- Missing changelog.\n"
printf "%b" "$ERRORS"
```

## Variable Defaults

Use parameter expansion:

```bash
# Preferred
echo "${VAR:-default}"
RESULT="${OUTPUT:-unknown}"

# Instead of
if [ -z "$VAR" ]; then echo "default"; else echo "$VAR"; fi
```

## Bracket Style

Use `[[ ]]` for string and pattern tests. `[ ]` is acceptable for file tests.

```bash
# String tests — use [[ ]]
[[ -z "$VAR" ]] && exit 0
[[ "$STATUS" = "ok" ]] && continue

# File tests — either is fine
[ -f "$path" ] && source "$path"
[[ -f "$path" ]] && source "$path"

# Pattern matching — must use [[ ]]
[[ "$branch" == feature/* ]] && echo "feature branch"
```

## Subprocess Avoidance

Prefer bash builtins when an equivalent exists:

```bash
# Preferred — bash string manipulation
ext=".${filename##*.}"
base="${filename%.*}"

# Instead of
ext=$(echo "$filename" | sed 's/.*\./\./')
base=$(echo "$filename" | sed 's/\..*//')
```

## JSON Output

Use `jq -n` with `--arg` for safe JSON construction. Never build JSON with string concatenation when values may contain special characters:

```bash
# Preferred — safe
jq -n --arg msg "$MESSAGE" '{"reason": $msg}'

# Dangerous — breaks on quotes/newlines in $MESSAGE
echo "{\"reason\": \"$MESSAGE\"}"
```

## Exit Codes

- `exit 0` — hook passes (action proceeds)
- `exit 2` — hook blocks the action (hard block)
- Advisory hooks always `exit 0` but output `additionalContext` JSON

## Testing

When adding or modifying hooks, add or update tests in `tests/`. Follow the existing pattern:

1. Source `helpers/assert.sh` and `helpers/setup.sh`
2. Use `setup_test_project` / `teardown_test_project` for temp git repos
3. Use `run_hook "$HOOK" "$JSON_INPUT"` to execute hooks from the test project directory
4. Use `assert_contains`, `assert_not_contains`, `assert_exit_code` for verification
