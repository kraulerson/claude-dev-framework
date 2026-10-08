#!/usr/bin/env bash
# test-enforce-evaluate.sh — Tests for enforce-evaluate hook
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/enforce-evaluate.sh"

# Approve the currently staged change the way the user does (approval design B): a
# schema-2 question, then the user's A1 twice through record-approval.sh.
approve_staged() {
  cat > "$TEST_DIR/.claude/pending-approval.json" << 'JSON'
{"schema": 2, "question": "Commit it?", "options": [{"id": "A1", "text": "Commit the staged change", "approves": "commit"}, {"id": "A2", "text": "Hold", "approves": "none"}], "recommendation": "A1", "offered_at": "2026-10-05T12:00:00Z"}
JSON
  local i in
  in=$(jq -c --arg d "$TEST_DIR" '.prompt = "A1" | .session_id = "s" | .cwd = $d' "$SCRIPT_DIR/fixtures/userpromptsubmit.json")
  for i in 1 2; do run_hook "$HOOK_DIR/record-approval.sh" "$in" >/dev/null; done
}
stage_one() { echo "${2:-x}" > "$TEST_DIR/${1:-feature.py}"; git -C "$TEST_DIR" add "${1:-feature.py}"; }

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
  # Approval design B, interim safety: the agent can record a valid question itself.
  assert_contains "$RESULT" '"schema": 2' "the message gives the schema-2 shape"
  assert_contains "$RESULT" '"approves": "commit"' "the message shows an approving option"
  assert_contains "$RESULT" '"approves": "none"' "the message shows an option that approves nothing"
  assert_contains "$RESULT" ".claude/pending-approval.json" "the message names the path"
  assert_contains "$RESULT" "Stage exactly the change" "the message says to stage first"
  assert_contains "$RESULT" "Stop and ask the user to reply with the option id" "the message says to stop"
  assert_contains "$RESULT" "You cannot create the approval yourself" "the message rules out self-approval"
  assert_not_contains "$RESULT" "run from the project root:" "the agent is no longer told to run mark-evaluated.sh"
  teardown_test_project
}

# --- Test: commit with marker passes ---
test_commit_with_marker() {
  setup_test_project
  stage_one; approve_staged
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
  stage_one; approve_staged
  INPUT='{"tool_input":{"command":"git commit --amend -m \"rewrite\""}}'
  RESULT=$(run_hook "$HOOK" "$INPUT")
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$INPUT")
  # Approval design B: an approval covers one new commit of the staged change, so
  # --amend (which rewrites history) is refused under it.
  assert_exit_code "2" "$EXIT_CODE" "--amend is refused under an approval"
  assert_contains "$RESULT" "WARNING" "--amend should produce a warning"
  assert_contains "$RESULT" "amend" "the refusal names --amend"
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
  stage_one; approve_staged
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

# --- Test (approval design B, spec 9a): config that runs code inside git is refused in
# every config-setting position, with or without a marker, in any letter case ---
test_code_running_config_refused() {
  local cmd
  setup_test_project
  while IFS= read -r cmd; do
    RESULT=$(run_hook "$HOOK" "$(ee_input "$cmd")")
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(ee_input "$cmd")")
    assert_exit_code "2" "$EXIT_CODE" "must be refused: $cmd"
    assert_contains "$RESULT" "runs code" "the refusal explains why: $cmd"
  done << 'CMDS'
GIT_CONFIG_PARAMETERS="'core.hooksPath=/tmp/h'" git commit -m x
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/tmp/h git commit -m x
git -c CORE.HOOKSPATH=x commit -m x
git config hook.x.command y
git config hook.x.event pre-commit
git config core.fsmonitor y
git config include.path f
git config includeIf.gitdir:/x/.path f
git config filter.x.clean c
git config filter.x.process p
git config gpg.program p
git config gpg.ssh.program p
git config core.editor e
git config sequence.editor e
git config core.sshCommand s
git config credential.helper h
git config diff.external d
git config diff.x.command d
git config merge.x.driver d
git config alias.x '!sh -c y'
git -c alias.x='!sh' x
git config --global --add core.hooksPath /tmp/h
git config set core.fsmonitor y
git config --edit
export GIT_CONFIG_PARAMETERS="'core.fsmonitor=x'"; git status
env GIT_CONFIG_KEY_0=hook.x.command GIT_CONFIG_VALUE_0=y git status
git --config-env=core.hooksPath=H status
KV='core.hooksPath=/tmp/h'; git -c "$KV" status
CMDS
  # The review's finding: with a marker present these committed on main (exit 0).
  touch "/tmp/.claude_evaluated_${TEST_HASH}"
  for cmd in "GIT_CONFIG_PARAMETERS=\"'core.hooksPath=/tmp/h'\" git commit -m x" \
             'GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/tmp/h git commit -m x'; do
    RESULT=$(run_hook "$HOOK" "$(ee_input "$cmd")")
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(ee_input "$cmd")")
    assert_exit_code "2" "$EXIT_CODE" "refused even with a marker: $cmd"
    assert_contains "$RESULT" "runs code" "refused for the config, with a marker: $cmd"
  done
  teardown_test_project
}

# --- Test (approval design B, spec 9a): text that only mentions such a key is not a
# config-setting position and passes (the review's false blocks) ---
test_config_mentions_pass() {
  local cmd
  setup_test_project
  while IFS= read -r cmd; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(ee_input "$cmd")")
    assert_exit_code "0" "$EXIT_CODE" "must pass: $cmd"
  done << 'CMDS'
git config --get core.hooksPath
git config core.hooksPath
git config get core.fsmonitor
git log --grep=include.path
git add docs/hook.push.event.md
git grep -n core.fsmonitor
git show HEAD -- src/hook.deploy.command.ts
git config alias.lg 'log --oneline'
git config user.email e@example.invalid
git config --list | grep alias.
git config --get-regexp core.hookspath .
git config --get-all core.editor vim
CMDS
  # A commit message naming a key is not refused for the key (only for the missing approval).
  RESULT=$(run_hook "$HOOK" "$(ee_input 'git commit -m "docs: explain includeIf.gitdir"')")
  assert_not_contains "$RESULT" "runs code" "a commit message naming a key is not a config setting"
  teardown_test_project
}

# --- Test (approval design B, spec 8 and 9c): under an approval the commit must be
# exactly `git commit` with message options, in the approved state ---
test_commit_shape_under_approval() {
  local cmd
  setup_test_project
  stage_one; approve_staged
  echo "msg" > "$TEST_DIR/msg.txt"
  while IFS= read -r cmd; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(ee_input "$cmd")")
    assert_exit_code "0" "$EXIT_CODE" "allowed under the approval: $cmd"
  done << 'CMDS'
git commit -m x
git commit -mx
git commit --message=x
git commit -sq -m x
git commit -m "a b" -s
git commit -F msg.txt
git commit -S -m x
GIT commit -m x
git commit -m x 2>&1
git commit --author="A <a@example.invalid>" --date=now -m x
CMDS
  while IFS= read -r cmd; do
    RESULT=$(run_hook "$HOOK" "$(ee_input "$cmd")")
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(ee_input "$cmd")")
    assert_exit_code "2" "$EXIT_CODE" "refused under the approval: $cmd"
    assert_contains "$RESULT" "approved" "the refusal says why: $cmd"
  done << 'CMDS'
git commit -am x
git commit -a -m x
git commit -m x feature.py
git commit -m x -- feature.py
git commit -i -m x
git commit -o -m x
git commit -p
git commit --amend -m x
git commit --allow-empty -m x
git commit --fixup HEAD
git commit --unknown -m x
git -C . commit -m x
git -c user.name=x commit -m x
git --config-env=user.name=N commit -m x
GIT_INDEX_FILE=/tmp/other-index git commit -m x
GIT_CONFIG_PARAMETERS="'user.name=x'" git commit -m x
HOME=/tmp/h git commit -m x
XDG_CONFIG_HOME=/x git commit -m x
env git commit -m x
env GIT_DIR=.git git commit -m x
exec git commit -m x
command git commit -m x
/usr/bin/git commit -m x
git add feature.py && git commit -m x
git commit -m x | tail -3
git commit -m x > /tmp/out
CMDS
  teardown_test_project
}

# --- Test (approval design B, spec 8): a change after the approval voids it ---
test_state_changes_void_the_approval() {
  local change
  for change in stage hooks config remote head; do
    setup_test_project
    stage_one; approve_staged
    case "$change" in
      stage) stage_one other.py ;;
      hooks) printf '#!/bin/sh\ngit add -A\n' > "$TEST_DIR/.git/hooks/pre-commit"; chmod +x "$TEST_DIR/.git/hooks/pre-commit" ;;
      config) git -C "$TEST_DIR" config user.name "Someone Else" ;;
      remote) git -C "$TEST_DIR" remote add o https://example.invalid/r.git ;;
      head) git -C "$TEST_DIR" commit -q --allow-empty -m other ;;
    esac
    RESULT=$(run_hook "$HOOK" "$(ee_input 'git commit -m x')")
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(ee_input 'git commit -m x')")
    assert_exit_code "2" "$EXIT_CODE" "a $change change voids the approval"
    assert_contains "$RESULT" "changed since the user approved" "the refusal names the change: $change"
    teardown_test_project
  done
}

# --- Test (approval design B, spec 8): the human override's marker gets the same checks;
# a marker without approved state (an old touch marker) approves nothing ---
test_override_and_legacy_markers() {
  setup_test_project
  stage_one
  mark_evaluated_at_terminal "skip evaluation" >/dev/null
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(ee_input 'git commit -m x')")
  assert_exit_code "0" "$EXIT_CODE" "the override approves the staged change"
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(ee_input 'git commit -am x')")
  assert_exit_code "2" "$EXIT_CODE" "the override's marker refuses -a too"
  stage_one other.py
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(ee_input 'git commit -m x')")
  assert_exit_code "2" "$EXIT_CODE" "the override's marker is voided by a stage change"
  teardown_test_project
  setup_test_project
  stage_one
  touch "/tmp/.claude_evaluated_${TEST_HASH}"
  RESULT=$(run_hook "$HOOK" "$(ee_input 'git commit -m x')")
  EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(ee_input 'git commit -m x')")
  assert_exit_code "2" "$EXIT_CODE" "an empty marker approves nothing"
  assert_contains "$RESULT" "no approved state" "the refusal explains the old marker"
  teardown_test_project
}

# --- Test (dogfood-3 rows 3, 10, 12): the commit is git's subcommand, not the word
# "commit" anywhere after git — a file name (pre-commit-checks.sh), a pathspec or a
# here-document's text is not a commit. A here-document is data unless what reads it
# runs code (that case is in the next test) ---
test_dogfood3_not_commits() {
  local cmd
  setup_test_project
  while IFS= read -r cmd; do
    cmd=$(printf '%b' "$cmd")
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(ee_input "$cmd")")
    assert_exit_code "0" "$EXIT_CODE" "not a commit: $cmd"
  done << 'CMDS'
cd "$HOME/Documents/Claude Projects/k-pdf-dogfood-3" && git add .gitignore .claude/manifest.json .claude/framework/hooks/_helpers.sh .claude/framework/hooks/pre-commit-checks.sh .claude/framework/hooks/record-approval.sh && git status --short
git add .claude/framework/hooks/pre-commit-checks.sh
git show HEAD:hooks/pre-commit-checks.sh
git log --oneline -- .git/hooks/commit-msg hooks/pre-commit-checks.sh
git log --oneline -3; git status --short; git show --stat --format='%h %s' HEAD | head -5
cat >> /tmp/notes.md <<'EOF'\n- the git commit was refused by the pre-commit hook\nEOF
tee -a /tmp/notes.md <<EOF >/dev/null\ngit commit happened\nEOF
python3 - <<'EOF'\nopen("/tmp/f.md", "a").write("tree clean after git status; pre-commit hook missing")\nEOF
CMDS
  teardown_test_project
}

# --- Test (dogfood-3 review of commit detection): what runs a here-document, a pipe or a
# command string as code still counts, including forms the word split did not see:
# awk's system(), env -S, and a shell or interpreter reading /dev/stdin ---
test_dogfood3_commit_forms_still_block() {
  local cmd
  setup_test_project
  while IFS= read -r cmd; do
    cmd=$(printf '%b' "$cmd")
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(ee_input "$cmd")")
    assert_exit_code "2" "$EXIT_CODE" "a commit must block: $cmd"
  done << 'CMDS'
git commit-tree HEAD^{tree} -m x
git --no-pager -C . commit -m x
bash <<'EOF'\ngit commit -m x\nEOF
sh -s <<EOF\ngit commit -m x\nEOF
bash /dev/stdin <<'EOF'\ngit commit -m x\nEOF
cat <<'EOF' | sh\ngit commit -m x\nEOF
cat <<'EOF' | bash /dev/stdin\ngit commit -m x\nEOF
echo 'git commit -m x' | bash /dev/stdin
python3 /dev/fd/0 <<'EOF'\nimport os; os.system("git commit -m x")\nEOF
source /dev/stdin <<'EOF'\ngit commit -m x\nEOF
awk 'BEGIN{system("git commit -m x")}'
awk 'BEGIN { system("git commit -m x.") }'
gawk -f /dev/stdin <<'EOF'\nBEGIN{system("git commit -m x")}\nEOF
env -S 'git commit -m x'
env --split-string='git commit -m x'
sudo -u git git commit -m x
find . -name git -exec git commit -m x \\;
CMDS
  teardown_test_project
}

# --- Test (dogfood-3 review 2): a here-document is code unless every command on the
# line that opened it only reads data or is git — csh, make -f -, sqlite3 and sort
# (--compress-program) run it ---
test_heredoc_code_readers_block() {
  local cmd
  setup_test_project
  while IFS= read -r cmd; do
    cmd=$(printf '%b' "$cmd")
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(ee_input "$cmd")")
    assert_exit_code "2" "$EXIT_CODE" "a commit must block: $cmd"
  done << 'CMDS'
csh <<EOF\ngit commit -m x\nEOF
make -f - <<EOF\nall:\n\tgit commit -m x\nEOF
sqlite3 :memory: <<EOF\n.shell git commit -m x\nEOF
sort -S 1024 --compress-program=sh <<'EOF'\ngit commit -m x\nEOF
echo ok; csh <<EOF\ngit commit -m x\nEOF
git commit -F - <<EOF\nmsg mentioning git commit\nEOF
gh alias set ci -s - <<EOF; gh ci\ngit commit -m x\nEOF
gh alias set ci -s - <<EOF\ngit commit -m x\nEOF; gh ci
CMDS
  teardown_test_project
}

# --- Test (dogfood-3 review 2): a code string given to a command the split does not
# follow (csh -c, expect -c, sqlite3 .shell, vim -c, Rscript -e, behind sudo or
# nohup) runs the commit it names ---
test_code_strings_block() {
  local cmd
  setup_test_project
  while IFS= read -r cmd; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(ee_input "$cmd")")
    assert_exit_code "2" "$EXIT_CODE" "a commit must block: $cmd"
  done << 'CMDS'
csh -c "git commit -m x"
tcsh -c "git commit -m x"
expect -c "exec git commit -m x"
sqlite3 :memory: ".shell git commit -m x"
vim -es -c "!git commit -m x" -c q
Rscript -e 'system("git commit -m x")'
sudo csh -c "git commit -m x"
nohup tcsh -c "git commit -m x"
gh alias set ci '!git commit -m x'
CMDS
  teardown_test_project
}

# --- Test (dogfood-3 review 2): text only a data reader, gh or git sees, a here-document
# on a later line than another command, and a script file run by a listed interpreter
# stay no commit ---
test_data_readers_pass() {
  local cmd
  setup_test_project
  while IFS= read -r cmd; do
    cmd=$(printf '%b' "$cmd")
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(ee_input "$cmd")")
    assert_exit_code "0" "$EXIT_CODE" "not a commit: $cmd"
  done << 'CMDS'
cat >> /tmp/notes <<EOF\nremember: git commit then pre-commit\nEOF
npm test\ncat >> /tmp/notes <<EOF\ngit commit later\nEOF
git log -1; git show --stat
echo "then git commit" >> notes.md
printf '%s\\n' "git commit later"
gh pr create --title t --body "run git commit after"
bash scripts/pending-approval.sh --offer "Approve: stage then git commit"
sh -c "ls"
if grep -q "git commit" notes.md; then echo y; fi
cd sub && cat > notes.md <<EOF\nthen git commit\nEOF
which git
command -v git
find . -name git
brew upgrade git
grep "git commit" log | wc -l
make test && echo "ready for git commit"
gh pr view 5 --json body | jq -r .body
echo 'see\\ngit commit docs' | wc -l
grep -n 'pre-commit' f
CMDS
  teardown_test_project
}

# --- Test (dogfood-3 review 2): git given its subcommand by input (xargs, parallel, a {}
# placeholder), a real git commit beside a construct that falls back, and a pipe into a
# command that is not a known reader all count ---
test_hidden_commit_forms_block() {
  local cmd
  setup_test_project
  while IFS= read -r cmd; do
    cmd=$(printf '%b' "$cmd")
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(ee_input "$cmd")")
    assert_exit_code "2" "$EXIT_CODE" "a commit must block: $cmd"
  done << 'CMDS'
xargs git <<EOF\ncommit -m x\nEOF
echo commit -m x | xargs git
xargs -I{} git {} -m x
parallel git ::: commit
find . -name x -exec git {} -m y \\;
xargs true; g""it commit -m x
echo $(true); g""it commit -m x
echo 'git commit -m x' | sort --compress-program=sh
echo 'git commit -m x' | csh
printf '.shell git commit -m x\\n' | sqlite3 :memory:
printf 'all:\\n\\t%s\\n' 'git commit -m x' | make -f -
echo 'g'"it commit -m x" | csh
printf 'all:\\n\\tgit commit -m x\\n' | make -f -
printf 'true\\n\\tgit commit -m x\\n' | sh
CMDS
  teardown_test_project
}

# --- Test (4.4.3): a script run by a relative path is a file the agent runs, not a code
# runner: the approval question about a commit, run as Solo's builders-guide says, and
# its output piped on, are not commits ---
test_script_run_by_path_passes() {
  local cmd
  setup_test_project
  while IFS= read -r cmd; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(ee_input "$cmd")")
    assert_exit_code "0" "$EXIT_CODE" "not a commit: $cmd"
  done << 'CMDS'
scripts/pending-approval.sh --offer "Stage then git commit the fix" --option "A1:approve"
./scripts/pending-approval.sh --offer "Stage then git commit the fix"
bash scripts/pending-approval.sh --offer "Stage then git commit the fix"
./scripts/escalate-to-user.sh --question "OK to git commit?"
./scripts/pending-approval.sh --offer "Stage then git commit the fix" 2>&1 | tail -3
scripts/run-checks.py --note "before git commit"
CMDS
  teardown_test_project
}

# --- Test (4.4.3): a code runner named by an absolute path is still judged as one ---
test_absolute_path_runners_block() {
  local cmd
  setup_test_project
  while IFS= read -r cmd; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(ee_input "$cmd")")
    assert_exit_code "2" "$EXIT_CODE" "a commit must block: $cmd"
  done << 'CMDS'
/bin/csh -c "git commit -m x"
/usr/bin/expect -c "exec git commit -m x"
echo 'git commit -m x' | /bin/csh
csh -c "git commit -m x"
echo 'git commit -m x' | csh
CMDS
  teardown_test_project
}

# --- Test (4.4.3 review): only a script file under the session's folder counts as a
# script run: a path that climbs with .. or starts at ~, a runner with no script
# extension (a copy of csh, node_modules/.bin/tsx) and a path after cd are judged as
# code runners ---
test_script_path_limits_block() {
  local cmd
  setup_test_project
  while IFS= read -r cmd; do
    EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(ee_input "$cmd")")
    assert_exit_code "2" "$EXIT_CODE" "a commit must block: $cmd"
  done << 'CMDS'
../../../../../../../../bin/csh -c "git commit -m x"
~/../../bin/csh -c "git commit -m x"
echo "git commit -m x" | ../../../../../../../../bin/csh
cd / && usr/bin/expect -c "exec git commit -m x"
./../bin/csh -c "git commit -m x"
node_modules/.bin/tsx -e "require('child_process').execSync('git commit -m x')"
cp /bin/csh ./c; ./c -c 'git commit -m x'
cd /usr/bin && ./scandeps.pl -x -e 'system("git commit -m x")'
../../../../../../../../usr/bin/scandeps.pl -x -e 'system("git commit -m x")'
~/../../usr/bin/scandeps.pl -x -e 'system("git commit -m x")'
~/bin/runner.py -c "git commit -m x"
/usr/bin/scandeps.pl -x -e 'system("git commit -m x")'
CMDS
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
test_code_running_config_refused
test_config_mentions_pass
test_commit_shape_under_approval
test_state_changes_void_the_approval
test_override_and_legacy_markers
test_dogfood3_not_commits
test_dogfood3_commit_forms_still_block
test_heredoc_code_readers_block
test_code_strings_block
test_data_readers_pass
test_hidden_commit_forms_block
test_script_run_by_path_passes
test_absolute_path_runners_block
test_script_path_limits_block
run_tests
