# Enforcement Gap Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close 8 enforcement gaps identified in the cross-evaluation against the Solo Orchestrator, hardening all hooks against known bypass vectors.

**Architecture:** Modifications to 7 existing hooks, 1 new hook (`config-guard.sh`), registration of the new hook in `_base.yml` and `_shared.sh`, and corresponding test updates for each change. Each task is a self-contained fix with its own tests and commit.

**Tech Stack:** Bash, jq, Claude Code hook system (PreToolUse/PostToolUse events)

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `hooks/marker-guard.sh` | Modify | R1: Match marker paths regardless of creation command |
| `hooks/branch-safety.sh` | Modify | R2: Block `--force` push |
| `hooks/enforce-evaluate.sh` | Modify | R3: Block `--no-verify`; R5: Remove `^` anchor; R7: Warn on `--amend` |
| `hooks/verification-gate.sh` | Modify | R5: Remove `^` anchor |
| `hooks/pre-commit-checks.sh` | Modify | R5: Remove `^` anchor |
| `hooks/config-guard.sh` | Create | R4+R6: Protect framework config and hook files from modification |
| `hooks/marker-tracker.sh` | Modify | R5: Fix `^` anchor in post-commit clearing; R8: Add plugin-prefixed Context7 names |
| `hooks/enforce-superpowers.sh` | No change | Config guard is separate hook (fires before preflight) |
| `profiles/_base.yml` | Modify | Register `config-guard` hook |
| `scripts/_shared.sh` | Modify | Add `config-guard` to hook→event mapping |
| `tests/test-marker-guard-v4.sh` | Modify | R1: Add bypass-vector tests |
| `tests/test-branch-safety.sh` | Modify | R2: Add force-push tests |
| `tests/test-enforce-evaluate.sh` | Modify | R3+R5+R7: Add `--no-verify`, chaining, amend tests |
| `tests/test-verification-gate.sh` | Modify | R5: Add chaining test |
| `tests/test-pre-commit-checks.sh` | Modify | R5: Add chaining test |
| `tests/test-config-guard.sh` | Create | R4+R6: Full test suite for new hook |
| `tests/test-marker-tracker.sh` | Modify | R5+R8: Chained commit clearing + plugin Context7 names |

---

### Task 1: R5 — Remove `^` anchoring from commit/push regexes

The highest-ROI fix. Four hooks anchor `git commit` or `git push` patterns with `^\s*`, allowing bypass via command chaining (`true && git commit -m test`). The marker-tracker's post-commit clearing has the same anchor bug.

**Files:**
- Modify: `hooks/enforce-evaluate.sh:9`
- Modify: `hooks/branch-safety.sh:9`
- Modify: `hooks/verification-gate.sh:11`
- Modify: `hooks/pre-commit-checks.sh:9`
- Modify: `hooks/marker-tracker.sh:71`
- Modify: `tests/test-enforce-evaluate.sh`
- Modify: `tests/test-branch-safety.sh`
- Modify: `tests/test-verification-gate.sh`
- Modify: `tests/test-pre-commit-checks.sh`
- Modify: `tests/test-marker-tracker.sh`

- [ ] **Step 1: Add chained-command test to test-enforce-evaluate.sh**

Add this test after `test_commit_with_marker`:

```bash
# --- Test: chained git commit still blocks ---
test_chained_commit_blocks() {
  setup_test_project
  INPUT='{"tool_input":{"command":"cd . && git commit -m \"bypass\""}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "chained git commit should still block"
  teardown_test_project
}
```

Add `test_chained_commit_blocks` to the run section before `run_tests`.

- [ ] **Step 2: Add chained-command test to test-branch-safety.sh**

Add after `test_push_dev_branch_passes`:

```bash
# --- Test: chained git push from protected branch blocks ---
test_chained_push_protected_blocks() {
  setup_test_project
  INPUT='{"tool_input":{"command":"echo ok && git push origin main"}}'
  EXIT=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT" "chained push from protected branch should block"
  teardown_test_project
}
```

Add `test_chained_push_protected_blocks` to the run section before `run_tests`.

- [ ] **Step 3: Add chained-command test to test-verification-gate.sh**

Read the existing test file first. Add a test that uses a chained commit with a failing gate configured. The test should confirm the gate still triggers. (Follow the existing test patterns — the file sets up verification gates in manifest.json.)

- [ ] **Step 4: Add chained-command test to test-pre-commit-checks.sh**

Read the existing test file first. Add a test that uses a chained commit. Follow existing patterns.

- [ ] **Step 5: Add chained-commit marker-clearing test to test-marker-tracker.sh**

Add after `test_markers_cleared_after_commit`:

```bash
# --- Test: chained commit still clears markers ---
test_chained_commit_clears_markers() {
  setup_test_project
  touch "/tmp/.claude_evaluated_${TEST_HASH}"
  touch "/tmp/.claude_superpowers_${TEST_HASH}"
  INPUT='{"tool_name":"Bash","tool_input":{"command":"cd . && git commit -m \"test\""},"tool_response":{"exit_code":"0"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_not_exists "/tmp/.claude_evaluated_${TEST_HASH}" "chained commit should clear evaluated marker"
  assert_file_not_exists "/tmp/.claude_superpowers_${TEST_HASH}" "chained commit should clear superpowers marker"
  teardown_test_project
}
```

Add `test_chained_commit_clears_markers` to the run section.

- [ ] **Step 6: Run all new tests — verify they FAIL**

```bash
bash tests/test-enforce-evaluate.sh
bash tests/test-branch-safety.sh
bash tests/test-marker-tracker.sh
```

Expected: The new chained-command tests fail (the current `^`-anchored regexes don't match chained commands).

- [ ] **Step 7: Fix the regexes in all 5 hooks**

In `hooks/enforce-evaluate.sh` line 9, change:
```bash
echo "$COMMAND" | grep -qE '^\s*git\s+commit' || exit 0
```
to:
```bash
echo "$COMMAND" | grep -qE '\bgit\b.*\bcommit\b' || exit 0
```

In `hooks/branch-safety.sh` line 9, change:
```bash
echo "$COMMAND" | grep -qE '^\s*git\s+push' || exit 0
```
to:
```bash
echo "$COMMAND" | grep -qE '\bgit\b.*\bpush\b' || exit 0
```

In `hooks/verification-gate.sh` line 11, change:
```bash
echo "$COMMAND" | grep -qE '^\s*git\s+commit' || exit 0
```
to:
```bash
echo "$COMMAND" | grep -qE '\bgit\b.*\bcommit\b' || exit 0
```

In `hooks/pre-commit-checks.sh` line 9, change:
```bash
echo "$COMMAND" | grep -qE '^\s*git\s+commit' || exit 0
```
to:
```bash
echo "$COMMAND" | grep -qE '\bgit\b.*\bcommit\b' || exit 0
```

In `hooks/marker-tracker.sh` line 71, change:
```bash
if echo "$COMMAND" | grep -qE '^\s*git\s+commit' && [ "$EXIT_CODE" = "0" ]; then
```
to:
```bash
if echo "$COMMAND" | grep -qE '\bgit\b.*\bcommit\b' && [ "$EXIT_CODE" = "0" ]; then
```

- [ ] **Step 8: Run all tests — verify they pass**

```bash
bash tests/run-tests.sh
```

Expected: All tests pass, including the new chained-command tests.

- [ ] **Step 9: Commit**

```bash
git add hooks/enforce-evaluate.sh hooks/branch-safety.sh hooks/verification-gate.sh hooks/pre-commit-checks.sh hooks/marker-tracker.sh tests/test-enforce-evaluate.sh tests/test-branch-safety.sh tests/test-verification-gate.sh tests/test-pre-commit-checks.sh tests/test-marker-tracker.sh
git commit -m "fix: remove ^ anchoring from git command regexes to prevent chaining bypass (R5)"
```

---

### Task 2: R1 — Expand marker-guard to block all file-creation vectors

Currently only catches `touch`. Change to match any command referencing a marker path, regardless of creation method.

**Files:**
- Modify: `hooks/marker-guard.sh:14`
- Modify: `tests/test-marker-guard-v4.sh`

- [ ] **Step 1: Add bypass-vector tests to test-marker-guard-v4.sh**

Add after `test_allows_normal_touch`:

```bash
# --- Test: blocks echo redirect to marker path ---
test_blocks_echo_redirect() {
  setup_test_project
  INPUT='{"tool_input":{"command":"echo \"\" > /tmp/.claude_superpowers_abc123"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block echo redirect to marker"
  teardown_test_project
}

# --- Test: blocks printf redirect to marker path ---
test_blocks_printf_redirect() {
  setup_test_project
  INPUT='{"tool_input":{"command":"printf \"\" > /tmp/.claude_superpowers_abc123"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block printf redirect to marker"
  teardown_test_project
}

# --- Test: blocks cp to marker path ---
test_blocks_cp_to_marker() {
  setup_test_project
  INPUT='{"tool_input":{"command":"cp /dev/null /tmp/.claude_evaluated_abc123"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block cp to marker"
  teardown_test_project
}

# --- Test: blocks python file creation at marker path ---
test_blocks_python_marker() {
  setup_test_project
  INPUT="{\"tool_input\":{\"command\":\"python3 -c \\\"open('/tmp/.claude_superpowers_abc123','w')\\\"\"}}"
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block python marker creation"
  teardown_test_project
}

# --- Test: blocks tee to marker path ---
test_blocks_tee_marker() {
  setup_test_project
  INPUT='{"tool_input":{"command":"tee /tmp/.claude_has_plan_abc123 < /dev/null"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block tee to marker path"
  teardown_test_project
}

# --- Test: still allows mark-evaluated.sh ---
test_allows_mark_evaluated_script() {
  setup_test_project
  INPUT='{"tool_input":{"command":"bash .claude/framework/hooks/mark-evaluated.sh \"user approved\""}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "should allow mark-evaluated.sh"
  teardown_test_project
}

# --- Test: still allows non-marker tmp files ---
test_allows_unrelated_tmp_files() {
  setup_test_project
  INPUT='{"tool_input":{"command":"echo test > /tmp/.claude_other_file"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "should allow non-marker tmp files"
  teardown_test_project
}
```

Add all new test functions to the run section before `run_tests`.

- [ ] **Step 2: Run the new tests — verify they fail**

```bash
bash tests/test-marker-guard-v4.sh
```

Expected: The bypass-vector tests fail (current regex only catches `touch`).

- [ ] **Step 3: Update marker-guard.sh regex**

In `hooks/marker-guard.sh`, replace lines 13-17:

```bash
# Block any attempt to manually create workflow markers via touch
if echo "$COMMAND" | grep -qE 'touch.*/tmp/\.claude_(superpowers|evaluated|plan_closed|plan_active|has_plan|skill_active|c7|c7_degraded)_'; then
  echo "BLOCKED — Manual marker creation is not permitted. Markers are created automatically by the framework when you complete the required workflow. Invoke the appropriate Superpowers skill or present an evaluation to proceed." >&2
  exit 2
fi
```

with:

```bash
# Block any command that references workflow marker paths (any creation method)
if echo "$COMMAND" | grep -qE '/tmp/\.claude_(superpowers|evaluated|plan_closed|plan_active|has_plan|skill_active|c7|c7_degraded)_'; then
  echo "BLOCKED — Manual marker creation is not permitted. Markers are created automatically by the framework when you complete the required workflow. Invoke the appropriate Superpowers skill or present an evaluation to proceed." >&2
  exit 2
fi
```

The change: remove `touch.*` from the regex so it matches the marker path pattern anywhere in the command, regardless of what command precedes it.

- [ ] **Step 4: Run all tests — verify they pass**

```bash
bash tests/run-tests.sh
```

Expected: All tests pass, including the new bypass-vector tests. The `mark-evaluated.sh` allowlist (line 11) still works because it exits 0 before reaching the marker check.

- [ ] **Step 5: Commit**

```bash
git add hooks/marker-guard.sh tests/test-marker-guard-v4.sh
git commit -m "fix: expand marker-guard to block all file-creation vectors, not just touch (R1)"
```

---

### Task 3: R2 — Block force-push

**Files:**
- Modify: `hooks/branch-safety.sh`
- Modify: `tests/test-branch-safety.sh`

- [ ] **Step 1: Add force-push test to test-branch-safety.sh**

Add after the existing tests:

```bash
# --- Test: force push blocked on any branch ---
test_force_push_blocked() {
  setup_test_project
  git -C "$TEST_DIR" checkout -b feature/test --quiet
  INPUT='{"tool_input":{"command":"git push --force origin feature/test"}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  EXIT=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT" "force push should block"
  assert_contains "$RESULT" "BLOCKED" "should say blocked"
  teardown_test_project
}

# --- Test: force push with -f flag blocked ---
test_force_push_short_flag_blocked() {
  setup_test_project
  git -C "$TEST_DIR" checkout -b feature/test --quiet
  INPUT='{"tool_input":{"command":"git push -f origin feature/test"}}'
  EXIT=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT" "force push with -f should block"
  teardown_test_project
}

# --- Test: force-with-lease blocked ---
test_force_with_lease_blocked() {
  setup_test_project
  git -C "$TEST_DIR" checkout -b feature/test --quiet
  INPUT='{"tool_input":{"command":"git push --force-with-lease origin feature/test"}}'
  EXIT=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT" "force-with-lease should block"
  teardown_test_project
}

# --- Test: normal push from dev branch still passes ---
test_normal_push_still_passes() {
  setup_test_project
  git -C "$TEST_DIR" checkout -b feature/test --quiet
  INPUT='{"tool_input":{"command":"git push origin feature/test"}}'
  EXIT=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT" "normal push from dev branch should pass"
  teardown_test_project
}
```

Add all new tests to the run section.

- [ ] **Step 2: Run new tests — verify they fail**

```bash
bash tests/test-branch-safety.sh
```

Expected: Force-push tests fail.

- [ ] **Step 3: Add force-push check to branch-safety.sh**

Insert after line 9 (the push detection line) and before line 11 (`BRANCH=$(get_branch)`):

```bash
# Block force push on any branch
if echo "$COMMAND" | grep -qE '\bgit\b.*\bpush\b.*(-f\b|--force\b|--force-with-lease\b)'; then
  printf "PUSH BLOCKED — Force push is not permitted. Force push overwrites branch history and can destroy audit evidence. Use normal push.\n\nCOMPLIANCE REMINDER: Your obligation is compliance first, speed second. There is no task small enough to skip this requirement. Do not classify this change as trivial. Do not run a cost-benefit analysis against the process. Follow the required workflow, then proceed." >&2
  exit 2
fi
```

- [ ] **Step 4: Run all tests — verify they pass**

```bash
bash tests/run-tests.sh
```

- [ ] **Step 5: Commit**

```bash
git add hooks/branch-safety.sh tests/test-branch-safety.sh
git commit -m "fix: block force-push on all branches (R2)"
```

---

### Task 4: R3 + R7 — Block `--no-verify` and warn on `--amend`

Both are commit-flag checks. Add them to `enforce-evaluate.sh` since it already gates all commits.

**Files:**
- Modify: `hooks/enforce-evaluate.sh`
- Modify: `tests/test-enforce-evaluate.sh`

- [ ] **Step 1: Add `--no-verify` and `--amend` tests**

Add to `tests/test-enforce-evaluate.sh` after the existing tests:

```bash
# --- Test: --no-verify blocked ---
test_no_verify_blocked() {
  setup_test_project
  touch "/tmp/.claude_evaluated_${TEST_HASH}"
  INPUT='{"tool_input":{"command":"git commit --no-verify -m \"bypass hooks\""}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "--no-verify should block even with evaluate marker"
  teardown_test_project
}

# --- Test: --amend warns but allows ---
test_amend_warns() {
  setup_test_project
  touch "/tmp/.claude_evaluated_${TEST_HASH}"
  INPUT='{"tool_input":{"command":"git commit --amend -m \"rewrite\""}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "--amend should allow (advisory only)"
  assert_contains "$RESULT" "WARNING" "--amend should produce a warning"
  teardown_test_project
}
```

Add both to the run section.

- [ ] **Step 2: Run new tests — verify they fail**

```bash
bash tests/test-enforce-evaluate.sh
```

Expected: Both new tests fail.

- [ ] **Step 3: Add `--no-verify` block and `--amend` warning to enforce-evaluate.sh**

Insert after line 9 (`echo "$COMMAND" | grep -qE ...`) and before line 11 (`HASH=$(get_project_hash)`):

```bash
# Block --no-verify (bypasses git security hooks)
if echo "$COMMAND" | grep -qE '\bgit\b.*\bcommit\b.*--no-verify'; then
  printf "BLOCKED — The --no-verify flag bypasses security hooks (gitleaks, Semgrep). Remove --no-verify and commit normally.\n\nCOMPLIANCE REMINDER: Your obligation is compliance first, speed second. There is no task small enough to skip this requirement." >&2
  exit 2
fi

# Warn on --amend (rewrites commit history)
if echo "$COMMAND" | grep -qE '\bgit\b.*\bcommit\b.*--amend'; then
  printf "WARNING — git commit --amend rewrites the previous commit. Ensure the amended content has been through the full workflow. If this amend adds new source code, consider a new commit instead.\n" >&2
fi
```

Note: The `--no-verify` check must come BEFORE the evaluate-marker check (which exits 0 early). The `--amend` warning is advisory (no exit 2), so it falls through to the normal evaluate-marker check.

- [ ] **Step 4: Run all tests — verify they pass**

```bash
bash tests/run-tests.sh
```

- [ ] **Step 5: Commit**

```bash
git add hooks/enforce-evaluate.sh tests/test-enforce-evaluate.sh
git commit -m "fix: block --no-verify, warn on --amend for git commits (R3, R7)"
```

---

### Task 5: R4 + R6 — Create config-guard.sh hook

New PreToolUse hook on Bash, Write, and Edit that protects framework configuration files and hook source code from modification. This addresses Finding 4 (config file protection) and Finding 9 (hook file modification via Bash). Also blocks environment variable overrides targeting framework internals (Finding 6).

**Files:**
- Create: `hooks/config-guard.sh`
- Create: `tests/test-config-guard.sh`
- Modify: `profiles/_base.yml`
- Modify: `scripts/_shared.sh`

- [ ] **Step 1: Write the test file**

Create `tests/test-config-guard.sh`:

```bash
#!/usr/bin/env bash
# test-config-guard.sh — Tests for config-guard hook
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/config-guard.sh"

# =============================================
# Write/Edit tool blocking (.claude/ config files)
# =============================================

# --- Test: blocks Write to .claude/settings.json ---
test_blocks_write_settings() {
  setup_test_project
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"'"$TEST_DIR"'/.claude/settings.json","content":"{}"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block Write to settings.json"
  teardown_test_project
}

# --- Test: blocks Edit to .claude/manifest.json ---
test_blocks_edit_manifest() {
  setup_test_project
  INPUT='{"tool_name":"Edit","tool_input":{"file_path":"'"$TEST_DIR"'/.claude/manifest.json","old_string":"old","new_string":"new"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block Edit to manifest.json"
  teardown_test_project
}

# --- Test: blocks Write to settings.local.json ---
test_blocks_write_settings_local() {
  setup_test_project
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"'"$TEST_DIR"'/.claude/settings.local.json","content":"{}"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block Write to settings.local.json"
  teardown_test_project
}

# --- Test: allows Write to non-framework .claude files ---
test_allows_write_other_claude_files() {
  setup_test_project
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"'"$TEST_DIR"'/.claude/my-notes.md","content":"notes"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "should allow Write to non-framework .claude files"
  teardown_test_project
}

# --- Test: allows Write to normal project files ---
test_allows_write_normal_files() {
  setup_test_project
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"'"$TEST_DIR"'/src/main.py","content":"print()"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "should allow Write to normal project files"
  teardown_test_project
}

# =============================================
# Bash tool blocking (hook file modification)
# =============================================

# --- Test: blocks sed on hook files ---
test_blocks_sed_on_hooks() {
  setup_test_project
  INPUT='{"tool_input":{"command":"sed -i '\'''\'' '\''s/exit 2/exit 0/'\'' .claude/framework/hooks/enforce-superpowers.sh"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block sed on hook files"
  teardown_test_project
}

# --- Test: blocks echo redirect to settings.json ---
test_blocks_echo_redirect_settings() {
  setup_test_project
  INPUT='{"tool_input":{"command":"echo '\''{}'\'' > .claude/settings.json"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block echo redirect to settings.json"
  teardown_test_project
}

# --- Test: blocks rm on hook files ---
test_blocks_rm_on_hooks() {
  setup_test_project
  INPUT='{"tool_input":{"command":"rm .claude/framework/hooks/enforce-superpowers.sh"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block rm on hook files"
  teardown_test_project
}

# --- Test: blocks chmod on hook files ---
test_blocks_chmod_on_hooks() {
  setup_test_project
  INPUT='{"tool_input":{"command":"chmod -x .claude/framework/hooks/enforce-evaluate.sh"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block chmod on hook files"
  teardown_test_project
}

# --- Test: allows reading hook files via cat ---
test_allows_cat_hook_files() {
  setup_test_project
  INPUT='{"tool_input":{"command":"cat .claude/framework/hooks/enforce-superpowers.sh"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "should allow reading hook files"
  teardown_test_project
}

# --- Test: allows non-framework bash commands ---
test_allows_normal_bash() {
  setup_test_project
  INPUT='{"tool_input":{"command":"git status"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "should allow normal bash commands"
  teardown_test_project
}

# =============================================
# Environment variable protection
# =============================================

# --- Test: blocks CLAUDE_PROJECT_DIR override ---
test_blocks_project_dir_override() {
  setup_test_project
  INPUT='{"tool_input":{"command":"CLAUDE_PROJECT_DIR=/tmp git commit -m test"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block CLAUDE_PROJECT_DIR override"
  teardown_test_project
}

# --- Test: allows CLAUDE_PROJECT_DIR in read-only context ---
test_allows_project_dir_read() {
  setup_test_project
  INPUT='{"tool_input":{"command":"echo $CLAUDE_PROJECT_DIR"}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "should allow reading CLAUDE_PROJECT_DIR"
  teardown_test_project
}

# --- Run all tests ---
echo "config-guard.sh"
test_blocks_write_settings
test_blocks_edit_manifest
test_blocks_write_settings_local
test_allows_write_other_claude_files
test_allows_write_normal_files
test_blocks_sed_on_hooks
test_blocks_echo_redirect_settings
test_blocks_rm_on_hooks
test_blocks_chmod_on_hooks
test_allows_cat_hook_files
test_allows_normal_bash
test_blocks_project_dir_override
test_allows_project_dir_read
run_tests
```

- [ ] **Step 2: Run the tests — verify they fail (hook doesn't exist yet)**

```bash
bash tests/test-config-guard.sh
```

Expected: All tests fail because `config-guard.sh` doesn't exist.

- [ ] **Step 3: Create hooks/config-guard.sh**

```bash
#!/usr/bin/env bash
# config-guard.sh — PreToolUse (Bash|Write|Edit) blocks modification of framework config and hooks
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 1

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")

# --- Write/Edit tool: protect framework config files ---
if [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ]; then
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null || echo "")
  case "$FILE_PATH" in
    */.claude/settings.json|*/.claude/settings.local.json|*/.claude/manifest.json|*/.claude/framework/*)
      printf "BLOCKED — Framework configuration files cannot be modified by Claude. These files control enforcement hooks, protected branches, and verification gates.\n\nIf a configuration change is needed, ask the user to make the edit manually in their editor.\n\nCOMPLIANCE REMINDER: Your obligation is compliance first, speed second.\n" >&2
      exit 2
      ;;
  esac
  exit 0
fi

# --- Bash tool: protect hook files and config from shell modification ---
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
[ -z "$COMMAND" ] && exit 0

# Block CLAUDE_PROJECT_DIR= assignment (not reads like echo $CLAUDE_PROJECT_DIR)
if echo "$COMMAND" | grep -qE 'CLAUDE_PROJECT_DIR='; then
  printf "BLOCKED — CLAUDE_PROJECT_DIR cannot be overridden. This variable controls enforcement hook behavior.\n\nCOMPLIANCE REMINDER: Your obligation is compliance first, speed second.\n" >&2
  exit 2
fi

# Check if command references framework config or hook paths
if echo "$COMMAND" | grep -qE '\.claude/(framework/hooks/|settings\.json|settings\.local\.json|manifest\.json)'; then
  # Allow read-only commands
  if echo "$COMMAND" | grep -qE '^\s*(cat|head|tail|less|more|wc|file|stat|ls|grep|rg|awk|bat)\s'; then
    exit 0
  fi
  # Allow mark-evaluated.sh (sanctioned script)
  if echo "$COMMAND" | grep -qE 'mark-evaluated\.sh'; then
    exit 0
  fi
  printf "BLOCKED — Modification of framework files via Bash is not permitted. Framework hooks and configuration are managed by the framework, not by Claude.\n\nCOMPLIANCE REMINDER: Your obligation is compliance first, speed second.\n" >&2
  exit 2
fi

exit 0
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
bash tests/test-config-guard.sh
```

- [ ] **Step 5: Register the hook in _shared.sh**

In `scripts/_shared.sh`, add a new case line inside the `case "$hook" in` block (after the `marker-guard` line):

```bash
      config-guard)        event="PreToolUse";   matcher="Bash|Write|Edit" ;;
```

- [ ] **Step 6: Register the hook in _base.yml**

In `profiles/_base.yml`, add `config-guard` to the hooks list. Insert it as the first hook after `session-start` (it should run before other PreToolUse hooks to protect the infrastructure they depend on):

```yaml
hooks:
  - session-start
  - config-guard
  - enforce-evaluate
  ...
```

- [ ] **Step 7: Run full test suite**

```bash
bash tests/run-tests.sh
```

Expected: All tests pass.

- [ ] **Step 8: Commit**

```bash
git add hooks/config-guard.sh tests/test-config-guard.sh profiles/_base.yml scripts/_shared.sh
git commit -m "feat: add config-guard hook to protect framework config and hook files (R4, R6)"
```

---

### Task 6: R8 — Handle plugin-prefixed Context7 tool names in marker-tracker

**Files:**
- Modify: `hooks/marker-tracker.sh:49-60`
- Modify: `tests/test-marker-tracker.sh`

- [ ] **Step 1: Add plugin-prefixed Context7 test**

Add to `tests/test-marker-tracker.sh` in the Context7 tracking section:

```bash
# --- Test: creates marker on plugin-prefixed resolve-library-id call ---
test_creates_marker_on_plugin_resolve() {
  setup_test_project
  INPUT='{"tool_name":"mcp__plugin_context7_context7__resolve-library-id","tool_input":{"libraryName":"express"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_c7_${TEST_HASH}_express" "plugin-prefixed resolve should create c7 marker"
  teardown_test_project
}

# --- Test: creates marker on plugin-prefixed get-library-docs call ---
test_creates_marker_on_plugin_get_docs() {
  setup_test_project
  INPUT='{"tool_name":"mcp__plugin_context7_context7__get-library-docs","tool_input":{"context7CompatibleLibraryID":"/expressjs/express","topic":"routing"}}'
  run_hook "$HOOK" "$INPUT" >/dev/null 2>&1
  assert_file_exists "/tmp/.claude_c7_${TEST_HASH}_expressjs-express" "plugin-prefixed get-docs should create c7 marker"
  teardown_test_project
}
```

Add both to the run section in the Context7 tracking group.

- [ ] **Step 2: Run test — verify it fails**

```bash
bash tests/test-marker-tracker.sh
```

Expected: The two new plugin-prefixed tests fail.

- [ ] **Step 3: Extend case patterns in marker-tracker.sh**

In `hooks/marker-tracker.sh`, change line 49:
```bash
  mcp__context7__resolve-library-id|mcp__context7__resolve_library_id)
```
to:
```bash
  mcp__context7__resolve-library-id|mcp__context7__resolve_library_id|mcp__plugin_context7_context7__resolve-library-id|mcp__plugin_context7_context7__resolve_library_id)
```

Change line 55:
```bash
  mcp__context7__get-library-docs|mcp__context7__get_library_docs)
```
to:
```bash
  mcp__context7__get-library-docs|mcp__context7__get_library_docs|mcp__plugin_context7_context7__get-library-docs|mcp__plugin_context7_context7__get_library_docs|mcp__context7__query-docs|mcp__plugin_context7_context7__query-docs)
```

Note: Also adding `query-docs` which is the newer Context7 API endpoint.

- [ ] **Step 4: Run all tests — verify they pass**

```bash
bash tests/run-tests.sh
```

- [ ] **Step 5: Commit**

```bash
git add hooks/marker-tracker.sh tests/test-marker-tracker.sh
git commit -m "fix: handle plugin-prefixed and query-docs Context7 tool names (R8)"
```

---

### Task 7: Final verification and changelog

- [ ] **Step 1: Run full test suite**

```bash
bash tests/run-tests.sh
```

Expected: All tests pass — zero failures.

- [ ] **Step 2: Verify no regressions by spot-checking key behaviors**

```bash
# Test: marker-guard still allows mark-evaluated.sh
echo '{"tool_input":{"command":"bash .claude/framework/hooks/mark-evaluated.sh \"test\""}}' | bash hooks/marker-guard.sh && echo "PASS: mark-evaluated allowed"

# Test: non-git commands still pass through enforce-evaluate
echo '{"tool_input":{"command":"npm test"}}' | bash hooks/enforce-evaluate.sh && echo "PASS: non-git passthrough"
```

- [ ] **Step 3: Update CHANGELOG.md**

Add an entry for the enforcement gap remediation under a new version heading. List all 8 remediation items.

- [ ] **Step 4: Commit changelog**

```bash
git add CHANGELOG.md
git commit -m "docs: update changelog for enforcement gap remediation (R1-R8)"
```
