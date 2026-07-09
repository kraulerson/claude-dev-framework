# 2026-07-09 Review Remediation Plan (R-01 … R-22)

**Target version:** 4.3.0 (from 4.2.5)
**Branch:** `fix/2026-07-09-review-remediation`
**Out of scope:** R-23 (OS sandbox) and R-24 (plugin packaging) — design discussions, not code tasks.

This plan remediates findings from the 2026-07-09 full framework review. It is written to be executed
by a junior engineer (or one agent per work package) without additional context. Follow it literally.
When a step conflicts with reality (line moved, file renamed), the **Acceptance criteria** win — satisfy
those and note the deviation.

---

## 0. Global rules (read first)

1. **Conventions:** follow `docs/CONTRIBUTING.md` (hook boilerplate, `set -euo pipefail`, `jq -n --arg`
   for JSON, `[[ ]]` for string tests, prefer builtins). Match surrounding style; don't bulk-rewrite.
2. **Bash 3.2 compatibility is mandatory** (macOS default shell). No associative arrays, no `${var,,}`,
   no `readarray`. `shasum`, `stat -f`/`stat -c` dual forms follow existing patterns in `_helpers.sh`.
3. **File ownership is exclusive.** Each work package (WP) lists the only files it may create, modify,
   or delete. If your change seems to need another WP's file, DO NOT touch it — record it in your
   summary as a deviation/handoff note instead.
4. **Tests:** every behavioral change gets test coverage in your WP's own test files. Test pattern:
   source `tests/helpers/assert.sh` + `tests/helpers/setup.sh`, use `setup_test_project`,
   `run_hook "$HOOK" "$JSON"`, `assert_contains` / `assert_exit_code`. Run a single file with
   `bash tests/test-<name>.sh`; the full suite with `bash tests/run-tests.sh`.
   `run-tests.sh` auto-discovers `tests/test-*.sh` — new test files need no registration.
5. **Do not commit.** Leave all changes in the working tree; commits happen after integration review.
6. **Do not push, and do not touch `.git` config.**

### 0.1 Ground truth: real Claude Code hook input schemas (captured 2026-07-09)

These were captured from a live Claude Code session. **They are authoritative.** The old test fixtures
that include `tool_response.exit_code` or `stop_reason` are fiction — those fields do not exist.

**PostToolUse (Bash):**
```json
{
  "permission_mode": "acceptEdits",
  "hook_event_name": "PostToolUse",
  "tool_name": "Bash",
  "tool_input": { "command": "echo hello world", "description": "Echo hello world" },
  "tool_response": { "stdout": "hello world", "stderr": "", "interrupted": false, "isImage": false, "noOutputExpected": false },
  "duration_ms": 35
}
```
(Real inputs also include `session_id`, `transcript_path`, `cwd`, `prompt_id`, `tool_use_id` — scrubbed here.)

**Stop:**
```json
{
  "permission_mode": "acceptEdits",
  "hook_event_name": "Stop",
  "stop_hook_active": false,
  "last_assistant_message": "done",
  "background_tasks": [],
  "session_crons": []
}
```

**SessionStart** additionally carries `source`: one of `startup`, `resume`, `clear`, `compact`.

Key facts:
- Bash `tool_response` has **no `exit_code`** field.
- Stop input has **no `stop_reason`** field; the loop-guard flag is `stop_hook_active`.
- `PreCompact` hooks do **not** support `hookSpecificOutput.additionalContext` (it is silently discarded).
- `Stop`, `PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `SessionStart` **do** support
  `hookSpecificOutput.additionalContext`.
- `SessionEnd` and `UserPromptSubmit` are valid hook events available for registration.

### 0.2 Marker path inventory (for reference)

All markers live in `/tmp` and embed `HASH` = first 12 chars of `shasum -a 256` of the project dir:
`superpowers`, `evaluated`, `has_plan`, `plan_active`, `plan_closed`, `c7_<lib>`, `c7_degraded`,
`changelog_synced`, `session_start`, `stop_errors_hash_<sha>`, `eval_log`, and (new in this plan)
`last_head`.

### 0.3 Work-package → finding map

| WP | Findings | Files owned |
|----|----------|-------------|
| WP1 | R-01, R-03 | `hooks/marker-tracker.sh`, `tests/test-marker-tracker.sh`, `tests/fixtures/posttooluse-bash.json` |
| WP2 | R-02, R-16 | `hooks/enforce-context7.sh`, `tests/test-enforce-context7.sh`, `docs/GLOSSARY.md` |
| WP3 | R-04, R-10, R-14 | `hooks/stop-checklist.sh`, `tests/test-stop-checklist.sh`, `tests/test-stop-checklist-dedup.sh`, `tests/test-stop-checklist-pending-approval.sh`, `tests/fixtures/stop.json` |
| WP4 | R-05, R-06, R-15 (partial), R-20 | `hooks/session-start.sh`, `hooks/session-end.sh` (new), `hooks/pre-compact-reminder.sh` (delete), `tests/test-session-start-v4.sh`, `tests/test-session-end.sh` (new), `tests/test-pre-compact-reminder.sh` (delete) |
| WP5 | R-07 (hook side), R-11, R-12 | `hooks/marker-guard.sh`, `hooks/config-guard.sh`, `hooks/enforce-evaluate.sh`, `hooks/branch-safety.sh`, `tests/test-marker-guard-v4.sh`, `tests/test-config-guard.sh`, `tests/test-enforce-evaluate.sh`, `tests/test-branch-safety.sh` |
| WP6 | R-07 (registration), R-08, R-09, R-13, R-05/R-06 (registration) | `scripts/_shared.sh`, `hooks/_preflight.sh`, `hooks/compliance-reinforce.sh` (new), `profiles/_base.yml`, `tests/test-install-matrix.sh`, `tests/test-compliance-reinforce.sh` (new) |
| WP7 | R-15 (scripts), R-18, R-21, R-19 (v4.sh header) | `scripts/init.sh`, `scripts/push-up.sh`, `migrations/v4.sh`, `hooks/_helpers.sh` |
| WP8 | R-17, R-19, R-15 (README), R-22, version bump | `README.md`, `docs/HOOK_REFERENCE.md`, `docs/COMPLIANCE_ENGINEERING.md`, `templates/settings.json.template` (delete), `templates/manifest.json.template` (delete), `FRAMEWORK_VERSION`, `tests/tools/capture-hook-schemas.sh` (new), `tests/fixtures/README.md` (new) |

---

## WP1 — marker-tracker: real commit detection + Context7 param fix

**Files owned:** `hooks/marker-tracker.sh`, `tests/test-marker-tracker.sh`, `tests/fixtures/posttooluse-bash.json`

### Task 1.1 (R-01): replace `exit_code` logic with HEAD-movement detection

In `hooks/marker-tracker.sh`, the `Bash)` case currently reads
`.tool_response.exit_code // "1"` — that field does not exist (see §0.1), so `EXIT_CODE` is always
`"1"` and the body never runs. Replace the whole `Bash)` case with:

```bash
  # --- Sync tracking + post-commit marker reset (was sync-tracker.sh) ---
  Bash)
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
    INTERRUPTED=$(echo "$INPUT" | jq -r '.tool_response.interrupted // false' 2>/dev/null || echo "false")

    # Track sync script executions. Real tool_response has no exit_code field
    # (only stdout/stderr/interrupted), so "ran to completion" is the best
    # available success signal. This marker only suppresses an advisory.
    if echo "$COMMAND" | grep -qE 'sync-(changelog|shared|ios)\.sh' && [[ "$INTERRUPTED" != "true" ]]; then
      touch "/tmp/.claude_changelog_synced_${HASH}"
    fi

    # Clear evaluation/superpowers/plan_active markers after a successful commit.
    # Success = HEAD moved since the last recorded position. A failed commit
    # leaves HEAD unchanged, so markers survive. If last_head is missing
    # (first commit this session), fail toward clearing — stricter, not looser.
    if echo "$COMMAND" | grep -qE '\bgit\b.*\bcommit\b'; then
      LAST_HEAD_FILE="/tmp/.claude_last_head_${HASH}"
      CURRENT_HEAD=$(git rev-parse HEAD 2>/dev/null || echo "")
      LAST_HEAD=$(cat "$LAST_HEAD_FILE" 2>/dev/null || echo "")
      if [[ -n "$CURRENT_HEAD" && "$CURRENT_HEAD" != "$LAST_HEAD" ]]; then
        rm -f "/tmp/.claude_evaluated_${HASH}"
        rm -f "/tmp/.claude_superpowers_${HASH}"
        rm -f "/tmp/.claude_plan_active_${HASH}"
        echo "$CURRENT_HEAD" > "$LAST_HEAD_FILE"
      fi
    fi
    ;;
```

Note: `hooks/session-start.sh` initializes `/tmp/.claude_last_head_${HASH}` (WP4's job — do not edit
that file).

### Task 1.2 (R-03): accept the current query-docs parameter

In the Context7 docs case (the arm matching `*query-docs` / `*get-library-docs` tool names), change

```bash
LIB=$(echo "$INPUT" | jq -r '.tool_input.context7CompatibleLibraryID // empty' 2>/dev/null || echo "")
```
to
```bash
LIB=$(echo "$INPUT" | jq -r '.tool_input.context7CompatibleLibraryID // .tool_input.libraryId // empty' 2>/dev/null || echo "")
```

Then, after computing `NORMALIZED`, also drop a marker for the ID's final path segment so a
direct-ID call (`/vercel/next.js`) credits the plain library name (`next.js`):

```bash
    touch "/tmp/.claude_c7_${HASH}_${NORMALIZED}"
    LAST_SEGMENT="${LIB##*/}"
    if [[ -n "$LAST_SEGMENT" && "$LAST_SEGMENT" != "$LIB" ]]; then
      LAST_NORMALIZED=$(echo "$LAST_SEGMENT" | tr '[:upper:]' '[:lower:]' | sed 's|^[@/]*||' | tr '/' '-')
      touch "/tmp/.claude_c7_${HASH}_${LAST_NORMALIZED}"
    fi
```

### Task 1.3: fixture + test updates

1. Create `tests/fixtures/posttooluse-bash.json` containing exactly the PostToolUse JSON from §0.1
   (the scrubbed version, pretty-printed).
2. In `tests/test-marker-tracker.sh`, **remove every `"exit_code"` from test inputs** and rebuild the
   commit-clearing tests around HEAD movement. Required cases:
   - **Successful commit clears markers:** in the test repo, seed
     `/tmp/.claude_last_head_${HASH}` with `git rev-parse HEAD`, create the `evaluated` +
     `superpowers` + `plan_active` markers, make a real commit
     (`echo x >> file && git add . && git commit -m "x" --quiet`) so HEAD moves, then pipe the
     real-schema JSON (command `git commit -m "x"`, no exit_code) through the hook and assert all
     three markers are gone and `last_head` now equals the new HEAD.
   - **Failed commit keeps markers:** seed `last_head` with current HEAD, create markers, do NOT
     commit (HEAD unchanged), pipe the same JSON, assert markers still exist.
   - **query-docs with `libraryId`:** pipe
     `{"tool_name":"mcp__context7__query-docs","tool_input":{"libraryId":"/vercel/next.js","query":"routing"}}`
     and assert both `c7_${HASH}_vercel-next.js` and `c7_${HASH}_next.js` markers exist.
   - Keep/adapt existing Skill, TaskUpdate, and resolve-library-id tests (they are schema-correct).
   - Build inputs with jq from the fixture where convenient, e.g.
     `INPUT=$(jq -c --arg cmd "git commit -m x" '.tool_input.command=$cmd' tests/fixtures/posttooluse-bash.json)`.

**Acceptance:** `bash tests/test-marker-tracker.sh` passes; no test input anywhere in the file
contains `exit_code`; the two new commit tests and the query-docs test exist and pass.

---

## WP2 — enforce-context7: fix Go extraction + stale message text

**Files owned:** `hooks/enforce-context7.sh`, `tests/test-enforce-context7.sh`, `docs/GLOSSARY.md`

### Task 2.1 (R-02): scope Go extraction to import statements

The current Go branch greps every quoted string in the file, so `fmt.Println("hello world")` is
treated as library `hello world` and blocks. Replace the Go branch body with logic that first
isolates import lines, then extracts quoted strings **only from those lines**:

```bash
# Go: import "lib" or import ( "lib" \n "lib2" ) — scan import statements only,
# not every quoted string in the file.
if [[ "$LANG_PREFIX" = "go" ]]; then
  GO_IMPORT_LINES=$(echo "$CONTENT" | awk '
    /^[[:space:]]*import[[:space:]]*\(/ { inblock=1; next }
    inblock && /^[[:space:]]*\)/        { inblock=0; next }
    inblock                              { print }
    /^[[:space:]]*import[[:space:]]+"/   { print }
  ')
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    LIB=${line//\"/}
    [ -n "$LIB" ] && LIBS="${LIBS}${LIB}\n"
  done <<< "$(echo "$GO_IMPORT_LINES" | grep -oE '"[a-zA-Z][^"]*"' 2>/dev/null || true)"
fi
```

Note the awk import-block lines may carry alias prefixes (`f "fmt"`) or comments — the
`grep -oE '"..."'` step already isolates just the quoted path, which is what we want.

### Task 2.2 (R-16): update the block message

In the final `printf` block message:
- `get-library-docs` → `query-docs` (step 2 should read: “Use query-docs to fetch current documentation”).
- `consider using Tavily web search for bleeding-edge libraries` →
  `consider using web search (the built-in WebSearch tool) for bleeding-edge libraries`.

In `docs/GLOSSARY.md`, update the “Bleeding-edge doc fallback” row: replace **Tavily** with
**web search (WebSearch)** and adjust the sentence accordingly.

### Task 2.3: tests

Add to `tests/test-enforce-context7.sh`:
- **Go string literals don't block:** Write-tool JSON for `main.go` whose content imports only `fmt`
  but calls `fmt.Println("hello world")` → hook exits 0.
- **Go third-party import still blocks:** content importing `github.com/gin-gonic/gin` (no marker)
  → exit 2, message mentions the import path.
- **Go import block form:** `import (\n\t"fmt"\n\t"os"\n)` with a string literal elsewhere → exit 0.
- Update any existing assertion that greps for `get-library-docs` or `Tavily` in the block message.

**Acceptance:** `bash tests/test-enforce-context7.sh` passes, including the three new Go cases;
`grep -rn "Tavily" hooks/ docs/GLOSSARY.md` returns nothing.

---

## WP3 — stop-checklist: real Stop schema, untracked files, JSON advisory

**Files owned:** `hooks/stop-checklist.sh`, `tests/test-stop-checklist.sh`,
`tests/test-stop-checklist-dedup.sh`, `tests/test-stop-checklist-pending-approval.sh`,
`tests/fixtures/stop.json`

### Task 3.1 (R-04): replace dead `stop_reason` guard with `stop_hook_active`

Replace:
```bash
STOP_REASON=$(echo "$INPUT" | jq -r '.stop_reason // empty' 2>/dev/null || echo "")
[ "$STOP_REASON" = "user" ] || [ "$STOP_REASON" = "tool_error" ] && exit 0
```
with:
```bash
# stop_hook_active=true means Claude is already continuing because this hook
# blocked a previous stop this turn — exit 0 to prevent an infinite block loop.
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")
[[ "$STOP_HOOK_ACTIVE" = "true" ]] && exit 0
```
Also update the header comment (the hook can no longer claim to skip user-initiated stops — that
input signal does not exist).

### Task 3.2 (R-10): include untracked files in the uncommitted-work check

Replace the `DIRTY`/`STAGED`/`ALL` construction with:
```bash
STAGED=$(git diff --cached --name-only 2>/dev/null || true)
# git status --porcelain covers modified + staged + untracked (??). Strip the
# 3-char status prefix, rename arrows, and quoting around paths with spaces.
ALL=$(git status --porcelain 2>/dev/null \
  | sed -e 's/^...//' -e 's/.* -> //' -e 's/^"//' -e 's/"$//' \
  | sort -u | grep -v '^$' || true)
```
Keep `STAGED` — it is still used by the untested-fix gate condition. Delete the now-unused `DIRTY`.

### Task 3.3 (R-14): emit the end-of-session advisory as Stop `additionalContext`

The advisory branch currently does `echo "$MSG" >&2` (marked `SOLO_ORCHESTRATOR_STOP_HOOK_PATCH`).
Stop hooks now support `hookSpecificOutput.additionalContext`. Replace the echo with:
```bash
      jq -n --arg ctx "$MSG" '{
        "hookSpecificOutput": {
          "hookEventName": "Stop",
          "additionalContext": $ctx
        }
      }'
```
Remove the `SOLO_ORCHESTRATOR_STOP_HOOK_PATCH` comment; add a one-liner noting additionalContext is
supported for Stop as of Claude Code ≥ 2.x (2026).

### Task 3.4: fixture + tests

1. Create `tests/fixtures/stop.json` with exactly the Stop JSON from §0.1 (pretty-printed).
2. Update the three stop-checklist test files:
   - Remove any `stop_reason` inputs. Build inputs from the fixture
     (`jq -c '.transcript_path="..."' tests/fixtures/stop.json` etc.).
   - **New:** `stop_hook_active: true` → exit 0, empty stdout.
   - **New:** untracked source file (`echo x > new.py`, never `git add`) → block JSON with
     “Uncommitted source changes”.
   - **New:** untracked path containing a space (`"my file.py"`) → still detected (quote stripping).
   - **Update:** advisory-path tests must now assert stdout contains
     `"hookEventName": "Stop"` and `additionalContext` instead of stderr text.

**Acceptance:** all three `bash tests/test-stop-checklist*.sh` files pass; no `stop_reason` remains
anywhere in `hooks/` or `tests/`; untracked-file and stop_hook_active tests exist and pass.

---

## WP4 — session lifecycle: SessionStart sources, marker hygiene, SessionEnd, PreCompact removal

**Files owned:** `hooks/session-start.sh`, `hooks/session-end.sh` (new),
`hooks/pre-compact-reminder.sh` (**delete**), `tests/test-session-start-v4.sh`,
`tests/test-session-end.sh` (new), `tests/test-pre-compact-reminder.sh` (**delete**)

### Task 4.1 (R-06 + R-20): source-aware SessionStart with marker hygiene

`session-start.sh` currently ignores stdin. Add input parsing right after the helpers are sourced:

```bash
# SessionStart input carries source: startup | resume | clear | compact.
# Manual runs (no stdin) get source="" and are treated as startup.
INPUT=""
if [ ! -t 0 ]; then INPUT=$(cat 2>/dev/null || true); fi
SOURCE=$(echo "$INPUT" | jq -r '.source // empty' 2>/dev/null || echo "")
```

Then replace the unconditional session-start recording (`git rev-parse HEAD > /tmp/.claude_session_start_…`)
with source-dependent behavior:

```bash
case "$SOURCE" in
  resume|compact)
    # Mid-session continuation: keep workflow markers and the session window.
    [ -f "/tmp/.claude_session_start_${HASH}" ] || git rev-parse HEAD > "/tmp/.claude_session_start_${HASH}" 2>/dev/null || true
    [ -f "/tmp/.claude_last_head_${HASH}" ]     || git rev-parse HEAD > "/tmp/.claude_last_head_${HASH}" 2>/dev/null || true
    ;;
  *)
    # startup / clear / unknown: fresh session. Stale markers from prior
    # sessions must not pre-unlock enforcement zones (R-06).
    rm -f "/tmp/.claude_superpowers_${HASH}" \
          "/tmp/.claude_evaluated_${HASH}" \
          "/tmp/.claude_has_plan_${HASH}" \
          "/tmp/.claude_plan_active_${HASH}" \
          "/tmp/.claude_plan_closed_${HASH}" \
          "/tmp/.claude_changelog_synced_${HASH}" \
          "/tmp/.claude_c7_degraded_${HASH}"
    rm -f "/tmp/.claude_c7_${HASH}_"* 2>/dev/null || true
    rm -f "/tmp/.claude_stop_errors_hash_${HASH}"* 2>/dev/null || true
    git rev-parse HEAD > "/tmp/.claude_session_start_${HASH}" 2>/dev/null || true
    git rev-parse HEAD > "/tmp/.claude_last_head_${HASH}"     2>/dev/null || true
    ;;
esac
```

(The existing Context7 dependency check later in the script re-creates `c7_degraded` when Context7
is missing — clearing it here is correct; verify the clear happens BEFORE that check.)

### Task 4.2 (R-05): post-compaction recovery message

At the end of the output section, add:

```bash
if [ "$SOURCE" = "compact" ]; then
  echo ""
  echo "POST-COMPACTION RECOVERY: Context was just compacted. Re-read ${CTX_FILE:-your context history file} and any source files you were actively editing before continuing. Re-check the ZONES ARMED list above — enforcement is still active."
fi
```
(`CTX_FILE` is already computed in the script; keep the fallback text for projects without one.)

Then **delete `hooks/pre-compact-reminder.sh` and `tests/test-pre-compact-reminder.sh`**: the
PreCompact event does not support `additionalContext`, so the hook has been a silent no-op
(review finding R-05). Its registration is removed by WP6/WP8 — do not edit their files.

### Task 4.3 (R-15, session-start portion): current Context7 install command

In the Context7 warning block, replace
`claude mcp add context7 -- npx -y @upstash/context7-mcp@latest` with
`claude mcp add --transport http context7 https://mcp.context7.com/mcp`.

### Task 4.4 (R-06): new SessionEnd cleanup hook

Create `hooks/session-end.sh` (advisory boilerplate, `|| exit 0` on helpers source):

```bash
#!/usr/bin/env bash
# session-end.sh — SessionEnd hook. Clears session-scoped workflow markers so
# a finished session cannot pre-unlock enforcement zones for the next one (R-06).
# The eval audit log (/tmp/.claude_eval_log_*) is intentionally preserved.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 0

HASH=$(get_project_hash)
rm -f "/tmp/.claude_superpowers_${HASH}" \
      "/tmp/.claude_evaluated_${HASH}" \
      "/tmp/.claude_has_plan_${HASH}" \
      "/tmp/.claude_plan_active_${HASH}" \
      "/tmp/.claude_plan_closed_${HASH}" \
      "/tmp/.claude_changelog_synced_${HASH}" \
      "/tmp/.claude_c7_degraded_${HASH}" \
      "/tmp/.claude_session_start_${HASH}" \
      "/tmp/.claude_last_head_${HASH}"
rm -f "/tmp/.claude_c7_${HASH}_"* 2>/dev/null || true
rm -f "/tmp/.claude_stop_errors_hash_${HASH}"* 2>/dev/null || true
exit 0
```

### Task 4.5: tests

- **Update `tests/test-session-start-v4.sh`:** pipe SessionStart JSON (`{"source":"startup"}` etc.)
  into the hook. New cases: (a) startup clears pre-seeded `superpowers`/`evaluated`/c7 markers;
  (b) resume does NOT clear them and does NOT overwrite an existing `session_start` file;
  (c) compact output contains `POST-COMPACTION RECOVERY`; (d) startup writes both `session_start`
  and `last_head` files; (e) existing output assertions (ZONES ARMED etc.) still pass with stdin provided.
- **New `tests/test-session-end.sh`:** seed all markers, run hook with empty JSON `{}`, assert the
  session-scoped ones are gone and `/tmp/.claude_eval_log_${HASH}` survives.

**Acceptance:** `bash tests/test-session-start-v4.sh` and `bash tests/test-session-end.sh` pass;
`hooks/pre-compact-reminder.sh` and its test no longer exist; `git rev-parse HEAD` is only recorded
on startup/clear/unknown sources.

---

## WP5 — guards: forging holes, allowlist injection, bypass variants

**Files owned:** `hooks/marker-guard.sh`, `hooks/config-guard.sh`, `hooks/enforce-evaluate.sh`,
`hooks/branch-safety.sh`, `tests/test-marker-guard-v4.sh`, `tests/test-config-guard.sh`,
`tests/test-enforce-evaluate.sh`, `tests/test-branch-safety.sh`

### Task 5.1 (R-07 hook side + R-11): marker-guard covers file tools; anchored allowlist

Rewrite `hooks/marker-guard.sh` as:

```bash
#!/usr/bin/env bash
# marker-guard.sh — PreToolUse (Bash|Write|Edit|NotebookEdit) blocks manual marker creation
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 1

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")

BLOCK_MSG="BLOCKED — Manual marker manipulation is not permitted. Markers are created automatically by the framework when you complete the required workflow. Invoke the appropriate Superpowers skill or present an evaluation to proceed."

# --- File tools: block any write to a framework marker path (R-07) ---
if [[ "$TOOL_NAME" = "Write" || "$TOOL_NAME" = "Edit" || "$TOOL_NAME" = "NotebookEdit" ]]; then
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // empty' 2>/dev/null || echo "")
  if [[ "$FILE_PATH" == /tmp/.claude_* || "$FILE_PATH" == /private/tmp/.claude_* ]]; then
    echo "$BLOCK_MSG" >&2
    exit 2
  fi
  exit 0
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")

# Allow the sanctioned mark-evaluated.sh script — but only as a lone, unchained
# invocation. A command that merely CONTAINS the string (e.g. appended after
# `&&`) must not unlock the guard (R-11).
if [[ "$COMMAND" == *mark-evaluated.sh* ]]; then
  if [[ "$COMMAND" =~ [\;\&\|\`] || "$COMMAND" == *'$('* || "$COMMAND" == *$'\n'* ]]; then
    : # chained/substituted — fall through to the blocking checks
  elif [[ "$COMMAND" =~ ^[[:space:]]*(bash[[:space:]]+)?[^[:space:]]*mark-evaluated\.sh([[:space:]]|$) ]]; then
    exit 0
  fi
fi

# Block any command that references workflow marker or framework state paths
# (any creation, deletion, or tampering method).
if echo "$COMMAND" | grep -qE '/tmp/\.claude_(superpowers|evaluated|plan_closed|plan_active|has_plan|skill_active|c7|c7_degraded|changelog_synced|session_start|last_head|stop_errors_hash|eval_log)'; then
  echo "$BLOCK_MSG" >&2
  exit 2
fi
exit 0
```

(Note the regex drops the trailing `_` requirement so `last_head`/`session_start` forms match, and
adds the state markers Claude could tamper with to influence enforcement: `last_head` prevents
post-commit resets, `session_start` skews the stop audit, `stop_errors_hash` silences stop blocks.)

### Task 5.2 (R-11 + R-12): config-guard — anchored allowlist, `rm .claude`, relative paths, NotebookEdit

In `hooks/config-guard.sh`:

1. **Tool condition:** `if [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ]` →
   also match `NotebookEdit`; extract the path with
   `.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // empty`.
2. **Relative-path case patterns:** the `case "$FILE_PATH" in` currently only matches `*/.claude/...`.
   Add the leading-anchor variants so relative paths match too:
   ```bash
   case "$FILE_PATH" in
     */.claude/settings.json|*/.claude/settings.local.json|*/.claude/manifest.json|*/.claude/framework/*|\
     .claude/settings.json|.claude/settings.local.json|.claude/manifest.json|.claude/framework/*)
   ```
3. **Anchored mark-evaluated allowlist:** replace
   `if echo "$COMMAND" | grep -qE 'mark-evaluated\.sh'; then exit 0; fi`
   with the same lone-invocation check used in marker-guard (Task 5.1) — copy the block verbatim.
4. **Bare `.claude` destruction (R-12):** before the existing path-reference check, add:
   ```bash
   # Destructive commands aimed at .claude itself (no trailing slash) — e.g. `rm -rf .claude`
   if echo "$COMMAND" | grep -qE '\b(rm|mv|chmod|chown|rmdir)\b[^|;&]*[[:space:]]["'"'"']?(\./)?\.claude["'"'"']?([[:space:]]|$)'; then
     printf "BLOCKED — Modification of the .claude directory is not permitted. Framework hooks and configuration are managed by the framework, not by Claude.\n\nCOMPLIANCE REMINDER: Your obligation is compliance first, speed second.\n" >&2
     exit 2
   fi
   ```
   (This must NOT match `.claude-backup` — the char class after `.claude` excludes `-`; add a test.)

### Task 5.3 (R-12): enforce-evaluate — `-n` and hooksPath bypasses

After the existing `--no-verify` block in `hooks/enforce-evaluate.sh`, add:

```bash
# -n is the short form of --no-verify; catch it in any short-flag cluster (e.g. -an).
if echo "$COMMAND" | grep -qE '\bgit\b.*\bcommit\b' && echo "$COMMAND" | grep -qE '(^|[[:space:]])-[a-zA-Z]*n[a-zA-Z]*([[:space:]]|$)'; then
  printf "BLOCKED — The -n flag is shorthand for --no-verify and bypasses git security hooks. Remove it and commit normally.\n\nCOMPLIANCE REMINDER: Your obligation is compliance first, speed second." >&2
  exit 2
fi

# Overriding core.hooksPath disables git hooks entirely.
if echo "$COMMAND" | grep -qE '\bgit\b.*core\.hooksPath'; then
  printf "BLOCKED — Overriding core.hooksPath disables git security hooks. Run git normally.\n\nCOMPLIANCE REMINDER: Your obligation is compliance first, speed second." >&2
  exit 2
fi
```

Keep these checks BEFORE the evaluated-marker early-exit so they apply even when evaluated.
Known acceptable false positive: `git commit -n` cluster detection also catches a bare `-n` used
for other tools' flags within the same command — acceptable; document with a comment.

### Task 5.4 (R-12): branch-safety — refspec force syntax

After the force-push flag check in `hooks/branch-safety.sh`, add:

```bash
# `git push origin +branch` is force-push via refspec syntax.
if echo "$COMMAND" | grep -qE '\bgit\b.*\bpush\b.*[[:space:]]["'"'"']?\+[^[:space:]]'; then
  printf "PUSH BLOCKED — Refspec force syntax (+branch) is a force push and is not permitted. Use normal push.\n\nCOMPLIANCE REMINDER: Your obligation is compliance first, speed second. There is no task small enough to skip this requirement. Do not classify this change as trivial. Do not run a cost-benefit analysis against the process. Follow the required workflow, then proceed." >&2
  exit 2
fi
```

### Task 5.5: tests (all four test files)

- marker-guard: Write tool to `/tmp/.claude_evaluated_x` → exit 2; Edit and NotebookEdit variants →
  exit 2; Write to a normal path → exit 0; Bash `touch /tmp/.claude_last_head_x` → exit 2;
  Bash `touch /tmp/.claude_superpowers_x && echo mark-evaluated.sh` → exit 2 (injection);
  plain `bash .claude/framework/hooks/mark-evaluated.sh "reason text"` → exit 0.
- config-guard: `rm -rf .claude` → exit 2; `rm -rf .claude-backup` → exit 0; Write with **relative**
  path `.claude/settings.json` → exit 2; NotebookEdit to `.claude/framework/x.ipynb` → exit 2;
  `sed -i '' .claude/manifest.json && echo mark-evaluated.sh` → exit 2 (injection);
  existing read-only git/cat allowlist tests still pass.
- enforce-evaluate: `git commit -n -m x` → exit 2 with `-n` message (even with evaluated marker);
  `git -c core.hooksPath=/dev/null commit -m x` → exit 2; normal `git commit -m x` with evaluated
  marker → exit 0 (message flag `-m` must NOT trip the `-n` detector — assert this).
- branch-safety: `git push origin +main` → exit 2; `git push origin main` (non-protected branch
  config) unchanged behavior.

**Acceptance:** all four `bash tests/test-<name>.sh` files pass with the new cases; the `-m` flag
does not false-positive; `.claude-backup` does not false-positive.

---

## WP6 — settings generation: matchers, deny rules, new hook registrations

**Files owned:** `scripts/_shared.sh`, `hooks/_preflight.sh`, `hooks/compliance-reinforce.sh` (new),
`profiles/_base.yml`, `tests/test-install-matrix.sh`, `tests/test-compliance-reinforce.sh` (new)

### Task 6.1 (R-09 + R-07 + R-05/R-06/R-13 registrations): update the hook→event map

In `generate_settings_json` in `scripts/_shared.sh`, update the case table:

| hook | event | matcher |
|---|---|---|
| `enforce-superpowers` | PreToolUse | `Write\|Edit\|NotebookEdit` |
| `enforce-plan-tracking` | PreToolUse | `Write\|Edit\|NotebookEdit` |
| `enforce-context7` | PreToolUse | `Write\|Edit\|NotebookEdit` |
| `changelog-sync-check` | PreToolUse | `Write\|Edit\|NotebookEdit` |
| `scalability-check` | PreToolUse | `Write\|Edit\|NotebookEdit` |
| `marker-guard` | PreToolUse | `Bash\|Write\|Edit\|NotebookEdit` |
| `config-guard` | PreToolUse | `Bash\|Write\|Edit\|NotebookEdit` |
| `session-end` (new) | SessionEnd | (none) |
| `compliance-reinforce` (new) | UserPromptSubmit | (none) |
| `pre-compact-reminder` | **remove the case entry entirely** | |

All other entries unchanged.

### Task 6.2 (R-08): emit and merge `permissions.deny`

1. In `generate_settings_json`, after building the hooks object, extend the final jq to also emit a
   static permissions block. Final output shape:
   ```json
   { "hooks": { ... }, "permissions": { "deny": [ ... ] } }
   ```
   Deny list (exactly):
   ```
   Edit(/.claude/settings.json)      Write(/.claude/settings.json)
   Edit(/.claude/settings.local.json) Write(/.claude/settings.local.json)
   Edit(/.claude/manifest.json)      Write(/.claude/manifest.json)
   Edit(/.claude/framework/**)       Write(/.claude/framework/**)
   Edit(//tmp/.claude_*)             Write(//tmp/.claude_*)
   Edit(//private/tmp/.claude_*)     Write(//private/tmp/.claude_*)
   ```
   (Leading `/` anchors at the project root; `//` is an absolute filesystem path — this is current
   Claude Code permission-rule syntax. These rules are enforced by the harness itself and also cover
   file commands Claude Code recognizes inside Bash. They are a defense-in-depth layer under
   config-guard/marker-guard, not a replacement.)
2. In `merge_hooks_into_settings`, merge BOTH keys while preserving any user-defined rules:
   ```bash
   local hooks_part perms_part
   hooks_part=$(echo "$settings_json" | jq '.hooks')
   perms_part=$(echo "$settings_json" | jq '.permissions.deny // []')
   ...
   echo "$existing" | jq --argjson h "$hooks_part" --argjson d "$perms_part" '
     . + {hooks: $h}
     | .permissions = ((.permissions // {}) | .deny = (((.deny // []) + $d) | unique | sort))
   ' > "${settings_file}.tmp"
   ```
   The non-existing-file branch writes `$settings_json` as-is (it now already contains both keys).

### Task 6.3 (R-09): _preflight reads notebook paths

In `hooks/_preflight.sh`, change the extraction to:
```bash
_PF_FILE_PATH=$(echo "$_PF_INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // empty' 2>/dev/null || echo "")
```

### Task 6.4 (R-13): new compliance-reinforce hook

Create `hooks/compliance-reinforce.sh`:
```bash
#!/usr/bin/env bash
# compliance-reinforce.sh — UserPromptSubmit advisory hook.
# Re-injects a one-line compliance frame each user turn. Layer 1's session-start
# directive measurably fades over task boundaries (see COMPLIANCE_ENGINEERING.md);
# this keeps the frame present at every decision point. Kept to ONE line to
# bound per-turn context cost.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 0

jq -n '{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "FRAMEWORK REMINDER: Enforcement hooks are active. Follow blocked-hook instructions exactly; never bypass, forge markers, or classify work as trivial to skip the workflow."
  }
}'
exit 0
```

### Task 6.5: profile registration

In `profiles/_base.yml` hooks list: remove `pre-compact-reminder`; add `session-end` and
`compliance-reinforce` (keep list order readable — put `session-end` after `stop-checklist`,
`compliance-reinforce` after `session-start`).

### Task 6.6: tests

- Update `tests/test-install-matrix.sh` for the new matcher strings, the removed pre-compact entry,
  the two new hooks, and assert generated settings contain `"permissions"` with the
  `Edit(//tmp/.claude_*)` deny rule and that `merge_hooks_into_settings` preserves a pre-existing
  user deny rule (seed a settings file containing `"deny": ["WebFetch"]`, merge, assert both present).
- New `tests/test-compliance-reinforce.sh`: hook run with `{}` on stdin → exit 0, stdout parses as
  JSON with `hookEventName == "UserPromptSubmit"` and non-empty `additionalContext`.

**Acceptance:** `bash tests/test-install-matrix.sh` and `bash tests/test-compliance-reinforce.sh`
pass; `generate_settings_json session-start session-end compliance-reinforce marker-guard | jq .`
produces valid JSON with SessionEnd + UserPromptSubmit groups and the permissions block;
`pre-compact-reminder` no longer appears in `scripts/_shared.sh` or `profiles/_base.yml`.

---

## WP7 — scripts polish: install text, push-up dir, dead cache, header

**Files owned:** `scripts/init.sh`, `scripts/push-up.sh`, `migrations/v4.sh`, `hooks/_helpers.sh`

### Task 7.1 (R-15): modern Context7 install in init.sh + migrations/v4.sh

1. `scripts/init.sh` — replace the body of `_install_context7` with the remote-transport form (no
   npx download, so the 30s background/timeout scaffolding is unnecessary):
   ```bash
   _install_context7() {
     if claude mcp add --transport http context7 https://mcp.context7.com/mcp 2>/dev/null; then
       echo "  ✓ Context7 MCP: INSTALLED (remote transport)"
     else
       echo "  ✗ Context7 install failed. Implementation Zone will be degraded."
       return 1
     fi
   }
   ```
2. In both Context7 prompt sites in init.sh, change `(requires Node.js)` to `(remote server — no
   Node.js needed)`.
3. `migrations/v4.sh` — update the install instruction near the end
   (`claude mcp add context7 -- npx -y @upstash/context7-mcp@latest` →
   `claude mcp add --transport http context7 https://mcp.context7.com/mcp`, and drop the
   `requires Node.js` phrasing).

### Task 7.2 (R-19): fix migration header

`migrations/v4.sh` line 2: `# v4-fixed.sh — …` → `# v4.sh — …` (keep the rest of the description).

### Task 7.3 (R-18): push-up destination dir

In `scripts/push-up.sh`, immediately before `cp "$OLDPWD/$FILE_PATH" "$DEST"`, add:
```bash
mkdir -p "$(dirname "$DEST")"
```

### Task 7.4 (R-21): remove the ineffective manifest cache

In `hooks/_helpers.sh`, `_MANIFEST_CACHE` never persists (every caller invokes
`_get_manifest_json` inside `$(…)` subshells), so it re-reads the manifest each call while
implying it doesn't. Simplify:
```bash
_get_manifest_json() {
  local manifest; manifest="$(get_manifest_path)"
  [ -f "$manifest" ] && cat "$manifest" || echo "{}"
}
```
Delete the `_MANIFEST_CACHE=""` global. Do not change the function's name or output shape —
callers depend on it. (`_SOURCE_EXTS_CACHE` in `is_source_file` DOES work — it is used within a
single hook process — leave it alone.)

**Acceptance:** `bash -n` passes on all four files; `bash tests/run-tests.sh` still passes
(this WP has no dedicated test files; existing suites cover `_helpers.sh` indirectly);
`grep -rn "context7-mcp@latest" scripts/ migrations/` returns nothing.

---

## WP8 — docs, templates, version, schema-capture tooling

**Files owned:** `README.md`, `docs/HOOK_REFERENCE.md`, `docs/COMPLIANCE_ENGINEERING.md`,
`templates/settings.json.template` (delete), `templates/manifest.json.template` (delete),
`FRAMEWORK_VERSION`, `tests/tools/capture-hook-schemas.sh` (new), `tests/fixtures/README.md` (new)

### Task 8.1 (R-17): delete dead templates

Delete `templates/settings.json.template` and `templates/manifest.json.template`. They are referenced
by nothing (settings are generated by `scripts/_shared.sh`) and the settings one is stale.
(`push-up.sh --project-template` writes to `templates/project-examples/`, which it now creates
itself — WP7.)

### Task 8.2 (R-19 + R-15): README updates

1. Hook count and table: “**15 hooks**” → “**17 hooks**”. Remove the `pre-compact-reminder` row.
   Add three rows:
   - `config-guard` | — | Blocking | Protects framework config, hooks, and markers from modification
   - `session-end` | — | Passive | Clears session-scoped workflow markers at session end
   - `compliance-reinforce` | — | Advisory | Re-injects a one-line compliance frame on every user prompt
2. “8-layer defense-in-depth model” → “10-layer defense-in-depth model” (line ~7).
3. Context7 install command (Prerequisites section):
   `claude mcp add --transport http context7 https://mcp.context7.com/mcp` and remove the Node.js
   bullet (note: “Node.js — no longer required; Context7 uses the hosted MCP server”).
4. Testing section: update counts to “25+ test files” (integration phase will verify the number
   printed by `bash tests/run-tests.sh` and correct if needed).
5. Add one sentence under Updating: markers are session-scoped as of 4.3.0 (cleared at session
   start/end).

### Task 8.3 (R-19): HOOK_REFERENCE updates

1. `enforce-superpowers.sh` entry: **Blocking:** `Yes (exit 2)`; purpose “Blocks source file edits
   until a Superpowers skill has been invoked this session” (it is not advisory).
2. `stop-checklist.sh` entry: replace the “Never blocks: user-initiated stops or tool errors” line
   with “**Loop guard:** exits silently when `stop_hook_active` is true (a prior block this turn).”
   Add: advisory output is delivered as Stop `additionalContext` JSON.
3. Remove the `pre-compact-reminder.sh` section (hook deleted — PreCompact cannot inject context;
   recovery guidance now ships in session-start's compact-source output).
4. `marker-tracker.sh` entry: describe commit detection as HEAD-movement based; add `last_head` to
   the markers list.
5. `marker-guard.sh` entry: events `PreToolUse (Bash|Write|Edit|NotebookEdit)`; note the expanded
   protected-path list and the lone-invocation rule for `mark-evaluated.sh`.
6. Add new sections (same format as the others):
   - **session-end.sh** — Event: SessionEnd; Blocking: No; Purpose: clears session-scoped markers
     (superpowers, evaluated, has_plan, plan_active, plan_closed, c7_*, changelog_synced, dedup,
     session_start, last_head) so stale markers can't pre-unlock the next session; preserves the
     eval audit log. Disable: remove `session-end` from `manifest.json → activeHooks`.
   - **compliance-reinforce.sh** — Event: UserPromptSubmit; Blocking: No (additionalContext);
     Purpose: one-line compliance frame injected per user prompt (Layer 1 reinforcement).
     Disable: remove `compliance-reinforce` from `manifest.json → activeHooks`.
7. Update the Enforcement Zones table row for Discovery to mention session-end/lifecycle if natural;
   keep terse.

### Task 8.4 (R-19): COMPLIANCE_ENGINEERING updates

1. In the Swiss-cheese diagram, append:
   ```
   Layer 10: Native Permission Rules (permissions.deny in generated settings.json)
     │ Hole: Covers Claude's file tools and recognized Bash file commands only —
     │       arbitrary subprocesses (python -c, node -e) can still write files.
     │       OS-level sandboxing is the future layer for that hole.
   ```
2. Add a short “Layer 10 — Native Permission Rules” subsection mirroring the other layer
   descriptions: deny rules are evaluated by the Claude Code harness before hooks, cannot be
   overridden by allow rules, and protect `.claude/` config plus `/tmp/.claude_*` markers.
3. Under Layer 1, add one sentence: as of v4.3.0 the directive is re-injected every user turn via
   the `compliance-reinforce` UserPromptSubmit hook.
4. Update the “8 defense layers” phrasing in the Enforcement Zones intro to “10 defense layers”.

### Task 8.5 (R-22): fixtures README + schema-capture tool

1. `tests/fixtures/README.md`:
   ```markdown
   # Real hook-input fixtures

   These JSON files were captured from a live Claude Code session (2026-07-09) by registering
   passthrough hooks and recording stdin. They are the authoritative input shapes for hook tests —
   do NOT hand-edit fields into them that Claude Code does not send (the 2026-07 review found the
   suite green against a fictional `tool_response.exit_code` field while production was broken).

   - `posttooluse-bash.json` — PostToolUse input for a Bash call (note: NO exit_code field)
   - `stop.json` — Stop input (note: NO stop_reason field; loop guard is stop_hook_active)

   Refresh after Claude Code updates with: `bash tests/tools/capture-hook-schemas.sh`
   (requires the `claude` CLI and network; not run by run-tests.sh).
   ```
2. `tests/tools/capture-hook-schemas.sh` (executable). Behavior: create a temp dir, `git init`,
   write a settings file registering `cat >> capture-post.jsonl` (PostToolUse, matcher Bash) and
   `cat >> capture-stop.jsonl` (Stop) hooks, run
   `claude -p "Run this exact bash command: echo hello world. Then reply with just: done" --model haiku --settings=<file> --allowedTools="Bash(echo *)" < /dev/null`,
   then for each capture compare `jq -S 'keys'` and `jq -S '.tool_response | keys'` against the
   committed fixtures and exit 1 with a diff on drift, else print OK. Gotchas learned capturing the
   originals: pass the prompt as the FIRST argument after `-p`, use `=` for flag values
   (`--allowedTools` is variadic and will swallow a trailing prompt), and redirect stdin from
   /dev/null. Clean up the temp dir on exit.

### Task 8.6: version bump

`FRAMEWORK_VERSION`: `4.2.5` → `4.3.0`.

**Acceptance:** the two template files are gone; `grep -rn "15 hooks\|8-layer" README.md` returns
nothing; HOOK_REFERENCE has no pre-compact section and has the two new sections;
`bash -n tests/tools/capture-hook-schemas.sh` passes; FRAMEWORK_VERSION reads `4.3.0`.

---

## Integration checklist (run after all WPs)

1. `bash tests/run-tests.sh` — everything green (expect ~25 test files: 24 − 1 deleted + 2 new).
2. `for f in hooks/*.sh scripts/*.sh gates/*.sh migrations/*.sh tests/tools/*.sh; do bash -n "$f" || echo "SYNTAX: $f"; done`
3. `command -v shellcheck >/dev/null && shellcheck -S warning hooks/*.sh scripts/*.sh || true` (advisory).
4. Cross-checks:
   - `grep -rn "exit_code\|stop_reason" hooks/ tests/` → only historical mentions in fixtures README allowed.
   - `grep -rn "pre-compact-reminder" hooks/ scripts/ profiles/ tests/ README.md docs/HOOK_REFERENCE.md` → nothing.
   - `grep -rn "context7-mcp@latest\|Tavily\|get-library-docs" hooks/ scripts/ migrations/ README.md docs/` → nothing.
   - `source scripts/_shared.sh && generate_settings_json session-start compliance-reinforce enforce-superpowers stop-checklist session-end marker-guard config-guard marker-tracker enforce-plan-tracking enforce-context7 verification-gate | jq .` → valid, contains SessionEnd + UserPromptSubmit groups, NotebookEdit matchers, permissions.deny.
   - README hook-table row count = number of `.sh` files in `hooks/` minus 3 (`_helpers`, `_preflight`, `mark-evaluated`) = 17.
   - README test-file count matches the number printed by run-tests.sh.
