#!/usr/bin/env bash
# test-enforce-evaluate.sh — Tests for enforce-evaluate hook
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/enforce-evaluate.sh"

# --- Test: non-commit command passes silently ---
test_non_commit_passthrough() {
  setup_test_project
  INPUT='{"tool_input":{"command":"git status"}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  assert_equals "" "$RESULT" "non-commit should produce no output"
  teardown_test_project
}

# --- Test: commit without marker blocks with exit 2 ---
test_commit_without_marker() {
  setup_test_project
  INPUT='{"tool_input":{"command":"git commit -m \"Add feature\""}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "should block with exit 2"
  assert_contains "$RESULT" "BLOCKED" "should say BLOCKED"
  assert_contains "$RESULT" "evaluate-before-implement" "should mention the rule"
  # The relative form from the project root: an absolute path breaks on a space (#11 review).
  assert_contains "$RESULT" 'bash .claude/framework/hooks/mark-evaluated.sh "' "should print the relative mark-evaluated.sh command"
  teardown_test_project
}

# --- Test: commit with marker passes ---
test_commit_with_marker() {
  setup_test_project
  touch "/tmp/.claude_evaluated_${TEST_HASH}"
  INPUT='{"tool_input":{"command":"git commit -m \"Add feature\""}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  assert_equals "" "$RESULT" "commit with marker should produce no output"
  teardown_test_project
}

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

# --- Test: chained git commit still blocks ---
test_chained_commit_blocks() {
  setup_test_project
  INPUT='{"tool_input":{"command":"cd . && git commit -m \"bypass\""}}'
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "chained git commit should still block"
  teardown_test_project
}

# --- Test: -n short flag blocked even with evaluated marker ---
test_short_n_flag_blocked() {
  setup_test_project
  touch "/tmp/.claude_evaluated_${TEST_HASH}"
  INPUT='{"tool_input":{"command":"git commit -n -m \"bypass hooks\""}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "-n should block even with evaluate marker"
  assert_contains "$RESULT" "shorthand for --no-verify" "should mention the -n flag is shorthand"
  teardown_test_project
}

# --- Test: core.hooksPath override blocked ---
test_hookspath_override_blocked() {
  setup_test_project
  touch "/tmp/.claude_evaluated_${TEST_HASH}"
  INPUT='{"tool_input":{"command":"git -c core.hooksPath=/dev/null commit -m \"x\""}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "core.hooksPath override should block"
  assert_contains "$RESULT" "core.hooksPath" "should mention core.hooksPath"
  teardown_test_project
}

# --- Test: --no-verif (git long-option abbreviation) is blocked (R-12) ---
test_no_verify_abbreviation_blocked() {
  setup_test_project
  touch "/tmp/.claude_evaluated_${TEST_HASH}"
  INPUT='{"tool_input":{"command":"git commit --no-verif -m \"x\""}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "--no-verif abbreviation should block even with marker"
  assert_contains "$RESULT" "no-verify" "should mention --no-verify"
  teardown_test_project
}

# --- Test: core.hooksPath set in a SEPARATE non-commit command is blocked (R-12) ---
test_hookspath_separate_command_blocked() {
  setup_test_project
  touch "/tmp/.claude_evaluated_${TEST_HASH}"
  INPUT='{"tool_input":{"command":"git config core.hooksPath /dev/null"}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "2" "$EXIT_CODE" "git config core.hooksPath (non-commit) should block"
  assert_contains "$RESULT" "core.hooksPath" "should mention core.hooksPath"
  teardown_test_project
}

# --- Test: -m message flag does NOT trip the -n detector ---
test_message_flag_not_flagged() {
  setup_test_project
  touch "/tmp/.claude_evaluated_${TEST_HASH}"
  INPUT='{"tool_input":{"command":"git commit -m \"Add feature\""}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  assert_exit_code "0" "$EXIT_CODE" "-m must not trip the -n detector"
  assert_equals "" "$RESULT" "-m commit with marker should produce no output"
  teardown_test_project
}

# Hook input in the shape Claude Code sends (session keys, transcript under ~/.claude).
ee_input() {
  jq -nc --arg c "$1" --arg d "$TEST_DIR" --arg t "$HOME/.claude/projects/x/s.jsonl" \
    '{session_id:"s",transcript_path:$t,cwd:$d,permission_mode:"auto",hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c,description:"x"}}'
}

# --- Test (dogfood-2 row 15, run-1 sibling): a command that only mentions a commit in
# its text, or runs read-only git beside the word, is not a commit ---
test_commit_word_in_text_passes() {
  local cmd
  setup_test_project
  while IFS= read -r cmd; do
    cmd=$(printf '%b' "$cmd")
    RESULT=$(run_hook "$HOOK" "$(ee_input "$cmd")")
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(ee_input "$cmd")")
    assert_exit_code "0" "$EXIT_CODE" "not a commit: $cmd"
    assert_equals "" "$RESULT" "no output for: $cmd"
  done << 'CMDS'
printf '%s\\n' "- [Stage 2] Pass check: git status -sb = main ahead 2, untracked .claude/last-checked-commit.txt and .claude/tool-usage.json." >> ~/dogfood-2026-10/k-pdf-dogfood-2-FINDINGS.md
cd "$HOME/Documents/Claude Projects/k-pdf-dogfood-2" && bash scripts/escalate-to-user.sh --question "Karl must run the mark-evaluated, git add and git commit steps himself (config-guard blocks the agent from both). Waiting for done." --option "A1: Karl runs the block" --recommendation "A1" 2>&1 | tail -3
git status --short && git log --oneline -5 | grep -i commit
git log -1 --format="last commit %h"
echo "remember: git commit after review" >> notes.md
CMDS
  teardown_test_project
}

# --- Test: every way of running git commit is still a commit, including the forms
# whose text hides it from a word split (substitution, a variable command, a shell or
# interpreter given code, xargs) ---
test_commit_forms_still_block() {
  local cmd
  setup_test_project
  while IFS= read -r cmd; do
    cmd=$(printf '%b' "$cmd")
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(ee_input "$cmd")")
    assert_exit_code "2" "$EXIT_CODE" "a commit must block: $cmd"
  done << 'CMDS'
cd "$HOME/Documents/Claude Projects/k-pdf-dogfood-2" && git commit -m "fix(preferences): fall back"
env GIT_AUTHOR_NAME=x git commit -m x
git -C . commit -m x
/usr/bin/git commit -m x
"git" commit -m x
g\\it commit -m x
git config alias.ci "commit"
git -c alias.ci=commit ci -m x
x=git; $x commit -m x
echo $(git commit -m x)
echo `git commit -m x`
echo "$(git commit -m x)"
bash -c "git commit -m x"
sh -c 'cd . && git commit -m x'
printf 'git commit -m x' | bash
printf 'git commit -m x' | sh -s
python3 - <<'EOF'\nimport os; os.system("git commit -m x")\nEOF
python3 -c "import os; os.system('git commit -m x')"
eval "git commit -m x"
echo -m x | xargs git commit
git -c alias.ci='commit -am x' ci
git -c alias.ci='!git commit -m x' ci
git --config-env=alias.ci=CI ci
CI='commit -m x' git --config-env=alias.ci=CI ci
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=alias.ci GIT_CONFIG_VALUE_0='commit -m x' git ci
GIT_CONFIG_PARAMETERS="'alias.ci=commit -m x'" git ci
export GIT_CONFIG_PARAMETERS="'alias.ci=commit -m x'"; git ci
git --config-env alias.ci=CI ci
GIT_CONFIG_GLOBAL=/tmp/aliases git ci
git config alias.ci 'commit -m x'
git config --global alias.ci '!git commit -m x'
V='commit -am x'; git -c alias.ci="$V" ci
V="'alias.ci=commit -am x'"; GIT_CONFIG_PARAMETERS="$V" git ci
git -c alias.ci=$'com\\\\x6dit -am x' ci
git -c alias.zz-not-a-cmd='commit -am x' zz-not-a-cmd
KV='alias.ci=commit -am x'; git -c "$KV" ci
CE='alias.ci=V'; git --config-env=$CE ci
GIT commit -m x
Git commit -m x
/usr/bin/GIT commit -m x
GIT -c alias.ci='commit -am x' ci
CMDS
  teardown_test_project
}

# --- Test (review round 2): a read-only command that mentions alias. or carries
# config that cannot define the subcommand it runs is not a commit ---
test_config_mentions_not_commits() {
  local cmd
  setup_test_project
  while IFS= read -r cmd; do
    RESULT=$(run_hook "$HOOK" "$(ee_input "$cmd")")
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(ee_input "$cmd")")
    assert_exit_code "0" "$EXIT_CODE" "not a commit: $cmd"
    assert_equals "" "$RESULT" "no output for: $cmd"
  done << 'CMDS'
git config --get alias.lg
git config --list | grep alias.
git status; echo alias.foo
GIT_CONFIG_NOSYSTEM=1 git status
git --config-env=user.name=NAME status
git -c alias.st=status st
GIT_CONFIG_GLOBAL=/tmp/aliases git log --oneline -3
git -c alias.ci='commit -am x' status
git config alias.lg 'log --oneline'
CMDS
  teardown_test_project
}

# --- Test (review rounds 3-4): a subcommand counts as not aliasable only when it is
# both a builtin of the hook's git and in the long-standing baseline list. An
# installed git-NAME does not count: PATH, GIT_EXEC_PATH and --exec-path at run
# time decide whether it shadows an alias, and the command controls those. When git
# cannot list its builtins, every subcommand counts as aliasable ---
test_alias_check_reads_live_git() {
  local bin real cmd
  setup_test_project
  bin=$(mktemp -d)
  # Externals and an exec path the command points elsewhere: still commits.
  while IFS= read -r cmd; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(ee_input "$cmd")")
    assert_exit_code "2" "$EXIT_CODE" "a commit must block: $cmd"
  done << 'CMDS'
git --exec-path=/tmp/none -c alias.send-email='commit -am x' send-email
GIT_EXEC_PATH=/tmp/none git -c alias.send-email='commit -am x' send-email
git --exec-path=/tmp/none -c alias.submodule='commit -am x' submodule
git --exec-path=/tmp/none -c alias.filter-branch='commit -am x' filter-branch
git --exec-path=/tmp/none -c alias.request-pull='commit -am x' request-pull
git --exec-path=/tmp/none -c alias.mergetool='commit -am x' mergetool
GIT_CONFIG_GLOBAL=/dev/null git lfs status
GIT_CONFIG_GLOBAL=/dev/null git subtree pull
GIT_CONFIG_COUNT=0 git flow init
GIT_CONFIG_GLOBAL=/tmp/aliases git maintenance run
CMDS
  # A decoy git-ci on the hook's PATH must not make `ci` read as an external.
  printf '#!/bin/sh\nexit 0\n' > "$bin/git-ci"; chmod +x "$bin/git-ci"
  export PATH="$bin:$PATH"
  while IFS= read -r cmd; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(ee_input "$cmd")")
    assert_exit_code "2" "$EXIT_CODE" "a decoy git-ci on PATH must not unblock: $cmd"
  done << 'CMDS'
git -c alias.ci='commit -am toctou' ci
PATH=/usr/bin:/bin git -c alias.ci='commit -am decoy' ci
env -i /usr/bin/git -c alias.ci='commit -am x' ci
env PATH=/usr/bin git -c alias.ci='commit -am x' ci
export PATH=/usr/bin; git -c alias.ci='commit -am x' ci
GIT_CONFIG_COUNT=0 git ci
CMDS
  export PATH="${PATH#"$bin:"}"
  rm -f "$bin/git-ci"
  # A git whose builtin list lacks log: log is aliasable for it, though in the baseline.
  real=$(command -v git)
  printf '#!/bin/sh\ncase "$1" in --list-cmds*) echo status; exit 0 ;; esac\nexec "%s" "$@"\n' "$real" > "$bin/git"; chmod +x "$bin/git"
  export PATH="$bin:$PATH"
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(ee_input 'GIT_CONFIG_GLOBAL=/tmp/aliases git log --oneline -3')")
  export PATH="${PATH#"$bin:"}"
  assert_exit_code "2" "$EXIT_CODE" "a baseline name the hook's git does not list counts as aliasable"
  # A git that cannot list its builtins: fail strict.
  printf '#!/bin/sh\ncase "$1" in --list-cmds*) exit 1 ;; esac\nexec "%s" "$@"\n' "$real" > "$bin/git"; chmod +x "$bin/git"
  export PATH="$bin:$PATH"
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(ee_input 'GIT_CONFIG_GLOBAL=/tmp/aliases git log --oneline -3')")
  export PATH="${PATH#"$bin:"}"
  assert_exit_code "2" "$EXIT_CODE" "when the builtin list cannot be read, the subcommand counts as aliasable"
  # The same git named by absolute path is asked, not the PATH git.
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(ee_input "GIT_CONFIG_GLOBAL=/tmp/aliases $bin/git log --oneline -3")")
  assert_exit_code "2" "$EXIT_CODE" "a git named by absolute path is the one whose builtins count"
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(ee_input 'GIT_CONFIG_GLOBAL=/tmp/aliases git log --oneline -3')")
  assert_exit_code "0" "$EXIT_CODE" "the host git lists log, a baseline builtin: not a commit"
  rm -rf "$bin"
  teardown_test_project
}

# --- Test (review round 5): a git named by a relative path (./git, sub/git, ~/bin/git)
# is not the hook's git, so with inline alias config every subcommand counts as
# aliasable; with no such config it is an ordinary command ---
test_relative_git_is_strict() {
  local real d cmd
  setup_test_project
  real=$(command -v git)
  for d in "$TEST_DIR" "$TEST_DIR/sub" "$HOME/bin"; do
    mkdir -p "$d"
    printf '#!/bin/sh\ncase "$1" in --list-cmds*) echo status; echo commit; exit 0 ;; esac\nexec "%s" "$@"\n' "$real" > "$d/git"
    chmod +x "$d/git"
  done
  while IFS= read -r cmd; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(ee_input "$cmd")")
    assert_exit_code "2" "$EXIT_CODE" "a relative-path git with an inline alias must block: $cmd"
  done << 'CMDS'
./git -c alias.stash='commit -am x' stash
sub/git -c alias.stash='commit -am x' stash
~/bin/git -c alias.stash='commit -am x' stash
CMDS
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(ee_input './git status')")
  assert_exit_code "0" "$EXIT_CODE" "a relative-path git with no inline config is not a commit"
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(ee_input "git -c alias.stash='commit -am x' stash")")
  assert_exit_code "0" "$EXIT_CODE" "the hook's own git lists stash: an alias cannot shadow it"
  rm -rf "$HOME/bin"
  teardown_test_project
}

# --- Test (review): --no-verify, -n and --amend are read from the commit as the shell
# runs it, so a quoted or escaped spelling of commit does not slip past them ---
test_commit_flags_read_after_quote_removal() {
  local cmd
  setup_test_project
  touch "/tmp/.claude_evaluated_${TEST_HASH}"
  while IFS= read -r cmd; do
    cmd=$(printf '%b' "$cmd")
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(ee_input "$cmd")")
    assert_exit_code "2" "$EXIT_CODE" "skips the git hooks, must block even with the marker: $cmd"
  done << 'CMDS'
git "comm""it" --no-verify -m x
git "comm""it" -n -m x
git co\\mmit --no-veri -m x
git 'commit' -an -m x
GIT commit --no-verify -m x
Git commit -n -m x
GIT -c core.hookspath=/dev/null commit -m x
CMDS
  RESULT=$(run_hook "$HOOK" "$(ee_input 'git "comm""it" --amend -m x')")
  assert_contains "$RESULT" "WARNING" "a quoted spelling of commit --amend still warns"
  teardown_test_project
}

# --- Test (review): a hook newer than its _helpers.sh (an interrupted or partly
# kept framework sync) judges commits by the text rule; it never lets a commit
# through unchecked ---
test_old_helpers_still_gate_commits() {
  local skew h
  setup_test_project
  skew=$(mktemp -d)
  cp "$HOOK_DIR"/*.sh "$skew/"
  # The helpers as an older framework shipped them: without the commit detector.
  printf '\nunset -f command_runs_git_commit git_commit_text\n' >> "$skew/_helpers.sh"
  for h in enforce-evaluate pre-commit-checks verification-gate; do
    jq '.projectConfig._base.changelogFile = "CHANGELOG.md" | .projectConfig._base.verificationGates = [{"name":"always-fail","command":"exit 1","failOn":"exit_code","enabled":true}]' \
      "$TEST_DIR/.claude/manifest.json" > "$TEST_DIR/m.json" && mv "$TEST_DIR/m.json" "$TEST_DIR/.claude/manifest.json"
    echo "// code" > "$TEST_DIR/app.kt"; git -C "$TEST_DIR" add app.kt
    EXIT_CODE=$(run_hook_exit_code "$skew/$h.sh" "$(ee_input 'git commit -m x')")
    assert_exit_code "2" "$EXIT_CODE" "$h with an old _helpers.sh must still block a commit"
    EXIT_CODE=$(run_hook_exit_code "$skew/$h.sh" "$(ee_input 'GIT commit -m x')")
    assert_exit_code "2" "$EXIT_CODE" "$h with an old _helpers.sh must still block GIT commit"
    EXIT_CODE=$(run_hook_exit_code "$skew/$h.sh" "$(ee_input 'git status')")
    assert_exit_code "0" "$EXIT_CODE" "$h with an old _helpers.sh still lets other commands run"
    # It says so on stderr, and only there: stdout stays empty.
    ERR=$(cd "$TEST_DIR" && echo "$(ee_input 'git status')" | bash "$skew/$h.sh" 2>&1 >/dev/null)
    OUT=$(cd "$TEST_DIR" && echo "$(ee_input 'git status')" | bash "$skew/$h.sh" 2>/dev/null)
    assert_contains "$ERR" "_helpers.sh is older than $h.sh; run the framework sync" "$h names the out-of-step helpers on stderr"
    assert_equals "" "$OUT" "$h prints nothing on stdout for the skew notice"
  done
  rm -rf "$skew"
  teardown_test_project
}

# --- Run all tests ---
echo "enforce-evaluate.sh"
test_non_commit_passthrough
test_commit_without_marker
test_commit_with_marker
test_chained_commit_blocks
test_no_verify_blocked
test_amend_warns
test_short_n_flag_blocked
test_hookspath_override_blocked
test_no_verify_abbreviation_blocked
test_hookspath_separate_command_blocked
test_message_flag_not_flagged
test_commit_word_in_text_passes
test_commit_forms_still_block
test_config_mentions_not_commits
test_alias_check_reads_live_git
test_relative_git_is_strict
test_commit_flags_read_after_quote_removal
test_old_helpers_still_gate_commits
run_tests
