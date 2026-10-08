#!/usr/bin/env bash
# test-record-approval.sh — the user's pick of a recorded question becomes the evaluation
# marker (approval design B, spec docs/superpowers/specs/2026-10-05-approval-via-pending-question-design.md)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/record-approval.sh"
FIXTURE="$SCRIPT_DIR/fixtures/userpromptsubmit.json"

# UserPromptSubmit input in the captured shape, with this test's prompt, session and cwd.
ups_input() {
  jq -c --arg p "$1" --arg s "${2:-sess-1}" --arg d "$TEST_DIR" --arg t "$HOME/.claude/projects/x/${2:-sess-1}.jsonl" \
    '.prompt = $p | .session_id = $s | .cwd = $d | .transcript_path = $t' "$FIXTURE"
}
marker() { echo "/tmp/.claude_evaluated_${TEST_HASH}"; }
shown() { echo "/tmp/.claude_approval_shown_${TEST_HASH}"; }
sentinel() { echo "$TEST_DIR/.claude/pending-approval.json"; }
write_v2() {
  cat > "$(sentinel)" << 'JSON'
{"schema": 2, "question": "Commit the parser fix?",
 "options": [{"id": "A1", "text": "Commit the staged parser fix as one commit", "approves": "commit"},
             {"id": "A2", "text": "Hold - do not commit", "approves": "none"}],
 "recommendation": "A1", "offered_at": "2026-10-05T12:00:00Z"}
JSON
}
stage_change() { echo "fix" > "$TEST_DIR/parser.py"; git -C "$TEST_DIR" add parser.py; }
ctx() { jq -r '.hookSpecificOutput.additionalContext // empty' <<< "$1" 2>/dev/null; }
decision() { jq -r '.decision // empty' <<< "$1" 2>/dev/null; }
reason() { jq -r '.reason // empty' <<< "$1" 2>/dev/null; }

# --- Test (spec 1): ids must be a letter and one or two digits, unique ignoring case ---
test_bad_ids_never_approve() {
  local opts reply
  for opts in '[{"id":"yes","text":"commit","approves":"commit"},{"id":"no","text":"hold","approves":"none"}]' \
              '[{"id":"A","text":"commit","approves":"commit"},{"id":"B","text":"hold","approves":"none"}]' \
              '[{"id":"A123","text":"commit","approves":"commit"},{"id":"B1","text":"hold","approves":"none"}]' \
              '[{"id":"1A","text":"commit","approves":"commit"},{"id":"B1","text":"hold","approves":"none"}]' \
              '[{"id":"A1","text":"commit","approves":"commit"},{"id":"a1","text":"hold","approves":"none"}]' \
              '[{"id":"A1","text":"commit","approves":"commit"},{"id":"A2","text":"commit too","approves":"commit"}]'; do
    setup_test_project; stage_change
    jq -n --argjson o "$opts" '{schema:2, question:"Commit?", options:$o, recommendation:"A1", offered_at:"2026-10-05T12:00:00Z"}' > "$(sentinel)"
    for reply in "$(jq -r '.[0].id' <<< "$opts")" "$(jq -r '.[0].id' <<< "$opts")" "yes, go ahead" "yes, go ahead"; do
      RESULT=$(run_hook "$HOOK" "$(ups_input "$reply")")
    done
    assert_file_not_exists "$(marker)" "no approval with options $opts"
    assert_contains "$(ctx "$RESULT")" "cannot be answered" "the agent is told why: $opts"
    teardown_test_project
  done
}

# --- Test (spec 2): the first id-shaped reply renders the question and blocks ---
test_first_pick_renders_and_blocks() {
  setup_test_project; stage_change; write_v2
  printf '#!/bin/sh\nexit 0\n' > "$TEST_DIR/.git/hooks/pre-commit"; chmod +x "$TEST_DIR/.git/hooks/pre-commit"
  RESULT=$(run_hook "$HOOK" "$(ups_input "A1")")
  assert_equals "block" "$(decision "$RESULT")" "the first A1 blocks"
  R=$(reason "$RESULT")
  assert_contains "$R" "Commit the parser fix?" "the render shows the question"
  assert_contains "$R" "A1 — Commit the staged parser fix as one commit \[approves committing the staged change below\]" "A1 with its effect"
  assert_contains "$R" "A2 — Hold - do not commit \[approves nothing\]" "A2 with its effect"
  assert_contains "$R" "parser.py" "the staged change is listed"
  assert_contains "$R" "Hooks that will run at commit: pre-commit" "the hooks that will run are named"
  assert_contains "$R" "Reply with the option id again" "the user is asked to confirm"
  assert_file_not_exists "$(marker)" "rendering approves nothing"
  assert_equals "sess-1" "$(jq -r .session_id "$(shown)" 2>/dev/null)" "the render record holds the session"
  assert_equals "$(git -C "$TEST_DIR" write-tree)" "$(jq -r .tree "$(shown)" 2>/dev/null)" "the render record holds the index tree"
  assert_equals "$(git -C "$TEST_DIR" rev-parse HEAD)" "$(jq -r .head "$(shown)" 2>/dev/null)" "the render record holds HEAD"
  assert_equals "$(shasum -a 256 < "$(sentinel)" | cut -c1-64)" "$(jq -r .sentinel_sha256 "$(shown)" 2>/dev/null)" "the render record holds the sentinel hash"
  assert_equals "64" "$(jq -r '.hooks_digest | length' "$(shown)" 2>/dev/null)" "the render record holds a hooks digest"
  assert_equals "64" "$(jq -r '.config_digest | length' "$(shown)" 2>/dev/null)" "the render record holds a config digest"
  teardown_test_project
}

# --- Test (spec 2): nothing staged, or an unmerged index, is said in the render ---
test_render_nothing_staged_and_conflicts() {
  setup_test_project; write_v2
  RESULT=$(run_hook "$HOOK" "$(ups_input "A1")")
  assert_contains "$(reason "$RESULT")" "Nothing is staged" "the render says nothing is staged"
  RESULT=$(run_hook "$HOOK" "$(ups_input "A1")")
  assert_file_not_exists "$(marker)" "an approving pick with nothing staged grants nothing"
  assert_contains "$(ctx "$RESULT")" "nothing is staged" "the agent is told to stage and ask again"
  assert_file_exists "$(sentinel)" "the question stays open"
  teardown_test_project
  setup_test_project
  echo base > "$TEST_DIR/f"; git -C "$TEST_DIR" add f; git -C "$TEST_DIR" commit -qm base
  git -C "$TEST_DIR" checkout -qb other; echo other > "$TEST_DIR/f"; git -C "$TEST_DIR" commit -qam other
  git -C "$TEST_DIR" checkout -q -; echo mine > "$TEST_DIR/f"; git -C "$TEST_DIR" commit -qam mine
  git -C "$TEST_DIR" merge -q other >/dev/null 2>&1
  write_v2
  RESULT=$(run_hook "$HOOK" "$(ups_input "A1")")
  assert_contains "$(reason "$RESULT")" "conflicts" "an unmerged index is named"
  assert_file_not_exists "$(shown)" "no render record with an unmerged index"
  teardown_test_project
}

# --- Test (spec 3): the second A1 in the same session approves the rendered change ---
test_second_pick_approves() {
  setup_test_project; stage_change; write_v2
  run_hook "$HOOK" "$(ups_input "A1")" >/dev/null
  RESULT=$(run_hook "$HOOK" "$(ups_input "a1. approved")")
  assert_equals "" "$(decision "$RESULT")" "the confirming pick is not blocked"
  assert_file_exists "$(marker)" "the pick writes the marker"
  assert_equals "$(git -C "$TEST_DIR" write-tree)" "$(jq -r .tree "$(marker)" 2>/dev/null)" "the marker binds the index tree"
  assert_equals "$(git -C "$TEST_DIR" rev-parse HEAD)" "$(jq -r .head "$(marker)" 2>/dev/null)" "the marker binds HEAD"
  assert_equals "A1" "$(jq -r .pick "$(marker)" 2>/dev/null)" "the marker records the pick"
  assert_equals "pick" "$(jq -r .source "$(marker)" 2>/dev/null)" "the marker records its source"
  assert_contains "$(tail -n 1 "$TEST_DIR/.claude/approvals.jsonl" 2>/dev/null)" "Commit the staged parser fix as one commit" "approvals.jsonl records the option text"
  assert_contains "$(cat "/tmp/.claude_eval_log_${TEST_HASH}" 2>/dev/null)" "pick A1" "the eval log gets its one-line entry"
  assert_file_not_exists "$(sentinel)" "the question is resolved"
  assert_file_not_exists "$(shown)" "the render record is cleared"
  assert_contains "$(ctx "$RESULT")" "approved" "Claude is told the user approved"
  teardown_test_project
}

# --- Test (spec 2/3): a pick of an option that approves nothing resolves without a marker ---
test_non_approving_pick() {
  setup_test_project; stage_change; write_v2
  run_hook "$HOOK" "$(ups_input "A2")" >/dev/null
  RESULT=$(run_hook "$HOOK" "$(ups_input "A2")")
  assert_file_not_exists "$(marker)" "A2 approves nothing"
  assert_file_not_exists "$(sentinel)" "the question is resolved"
  assert_equals "none" "$(tail -n 1 "$TEST_DIR/.claude/approvals.jsonl" | jq -r .approves)" "the record says it approved nothing"
  assert_contains "$(ctx "$RESULT")" "A2" "Claude is told what was picked"
  teardown_test_project
}

# --- Test (self-approval finding, PR 1, defect 2): a pick that approves nothing withdraws
# an earlier approval not yet used by a commit, so "hold" holds ---
test_non_approving_pick_withdraws_approval() {
  setup_test_project; stage_change; write_v2
  run_hook "$HOOK" "$(ups_input "A1")" >/dev/null
  run_hook "$HOOK" "$(ups_input "A1")" >/dev/null
  assert_file_exists "$(marker)" "precondition: A1 approved the staged change"
  write_v2
  run_hook "$HOOK" "$(ups_input "A2")" >/dev/null
  RESULT=$(run_hook "$HOOK" "$(ups_input "A2")")
  assert_file_not_exists "$(marker)" "the hold pick removes the unused approval"
  assert_contains "$(ctx "$RESULT")" "withdrawn" "Claude is told the earlier approval is withdrawn"
  assert_contains "$(tail -n 1 "/tmp/.claude_eval_log_${TEST_HASH}" 2>/dev/null)" "withdrew" "the eval log records the withdrawal"
  assert_equals "true" "$(tail -n 1 "$TEST_DIR/.claude/approvals.jsonl" | jq -r .withdrew_approval)" "approvals.jsonl records the withdrawal"
  EXIT_CODE=$(cd "$TEST_DIR" && jq -nc --arg d "$TEST_DIR" '{tool_name:"Bash",tool_input:{command:"git commit -m x"},cwd:$d}' | bash "$HOOK_DIR/enforce-evaluate.sh" >/dev/null 2>&1; echo $?)
  assert_exit_code "2" "$EXIT_CODE" "the commit is refused after the hold"
  teardown_test_project
  setup_test_project; stage_change; write_v2
  run_hook "$HOOK" "$(ups_input "A2")" >/dev/null
  RESULT=$(run_hook "$HOOK" "$(ups_input "A2")")
  assert_not_contains "$(ctx "$RESULT")" "withdrawn" "with no approval in place, nothing is said to be withdrawn"
  assert_equals "false" "$(tail -n 1 "$TEST_DIR/.claude/approvals.jsonl" | jq -r .withdrew_approval)" "the record says nothing was withdrawn"
  teardown_test_project
}

# --- Test (self-approval review F3): a withdrawal that cannot remove the marker fails
# closed: the marker is overwritten with a record carrying no approved state, and one
# that cannot be changed at all stops the turn (the prompt is blocked, nothing recorded) ---
test_withdrawal_fails_closed() {
  local shim mode
  shim=$(mktemp -d)
  printf '#!/bin/bash\nfor a in "$@"; do case "$a" in *.claude_evaluated_*) exit 1 ;; esac; done\nexec /bin/rm "$@"\n' > "$shim/rm"
  chmod +x "$shim/rm"
  for mode in unremovable unwritable; do
    setup_test_project; stage_change; write_v2
    run_hook "$HOOK" "$(ups_input "A1")" >/dev/null
    run_hook "$HOOK" "$(ups_input "A1")" >/dev/null
    write_v2
    run_hook "$HOOK" "$(ups_input "A2")" >/dev/null
    [ "$mode" = unwritable ] && chmod 444 "$(marker)"
    RESULT=$(cd "$TEST_DIR" && ups_input "A2" | PATH="$shim:$PATH" bash "$HOOK" 2>&1)
    EXIT_CODE=$(cd "$TEST_DIR" && jq -nc --arg d "$TEST_DIR" '{tool_name:"Bash",tool_input:{command:"git commit -m x"},cwd:$d}' | bash "$HOOK_DIR/enforce-evaluate.sh" >/dev/null 2>&1; echo $?)
    if [ "$mode" = unremovable ]; then
      assert_exit_code "2" "$EXIT_CODE" "unremovable: the neutralised marker approves nothing"
      assert_equals "null" "$(jq -r .tree "$(marker)" 2>/dev/null)" "unremovable: the marker no longer carries a tree"
      assert_contains "$(ctx "$RESULT")" "withdrawn" "unremovable: Claude is told the approval is withdrawn"
    else
      assert_equals "block" "$(decision "$RESULT")" "unwritable: the turn is stopped"
      assert_contains "$(reason "$RESULT")" "could not be removed" "unwritable: the user is told why"
      assert_file_exists "$(sentinel)" "unwritable: the question stays open"
      chmod 644 "$(marker)"
    fi
    teardown_test_project
  done
  rm -rf "$shim"
}

# --- Test (dogfood-3 item 1): the two replies survive a process exit. A headless driver
# sends each reply as its own `claude -p --resume <id>` process, so SessionEnd runs after
# the render and SessionStart (resume, or startup in some versions) before the pick, both
# with the same session_id. The render record is bound to that session, so it is kept;
# a different session's startup still clears it ---
test_render_survives_session_end_and_resume() {
  local src
  for src in resume startup; do
    setup_test_project; stage_change; write_v2
    run_hook "$HOOK" "$(ups_input "A1")" >/dev/null
    run_hook "$HOOK_DIR/session-end.sh" '{"session_id":"sess-1","hook_event_name":"SessionEnd","reason":"other"}' >/dev/null
    run_hook "$HOOK_DIR/session-start.sh" "{\"session_id\":\"sess-1\",\"hook_event_name\":\"SessionStart\",\"source\":\"$src\"}" >/dev/null
    RESULT=$(run_hook "$HOOK" "$(ups_input "A1")")
    assert_equals "" "$(decision "$RESULT")" "$src: the second A1 after a process exit is not re-rendered"
    assert_file_exists "$(marker)" "$src: the second A1 after a process exit approves"
    teardown_test_project
  done
  setup_test_project; stage_change; write_v2
  run_hook "$HOOK" "$(ups_input "A1")" >/dev/null
  run_hook "$HOOK_DIR/session-start.sh" '{"session_id":"sess-2","hook_event_name":"SessionStart","source":"startup"}' >/dev/null
  assert_file_not_exists "$(shown)" "another session's startup clears the render record"
  RESULT=$(run_hook "$HOOK" "$(ups_input "A1" sess-2)")
  assert_equals "block" "$(decision "$RESULT")" "the new session's A1 renders again"
  assert_file_not_exists "$(marker)" "and approves nothing"
  teardown_test_project
}

# --- Test (spec 4): anything that changed since the render voids it; the reply re-renders ---
test_changes_void_the_render() {
  local change
  for change in session sentinel stage head hooks config prompt; do
    setup_test_project; stage_change; write_v2
    run_hook "$HOOK" "$(ups_input "A1")" >/dev/null
    local sid=sess-1
    case "$change" in
      session) sid=sess-2 ;;
      sentinel) sed -i.bak 's/as one commit/and everything else/' "$(sentinel)" ;;
      stage) echo more > "$TEST_DIR/extra.py"; git -C "$TEST_DIR" add extra.py ;;
      head) git -C "$TEST_DIR" commit -q --allow-empty -m other; git -C "$TEST_DIR" add parser.py ;;
      hooks) printf '#!/bin/sh\ngit add -A\n' > "$TEST_DIR/.git/hooks/pre-commit"; chmod +x "$TEST_DIR/.git/hooks/pre-commit" ;;
      config) git -C "$TEST_DIR" config user.name "Someone Else" ;;
      prompt) run_hook "$HOOK" "$(ups_input "wait, first explain the change")" >/dev/null ;;
    esac
    RESULT=$(run_hook "$HOOK" "$(ups_input "A1" "$sid")")
    assert_file_not_exists "$(marker)" "no approval after a $change change"
    assert_equals "block" "$(decision "$RESULT")" "the reply re-renders after a $change change"
    teardown_test_project
  done
}

# --- Test (spec 5): harness turns, peer messages, pastes and commands neither pick nor void ---
test_neutral_turns() {
  local p
  setup_test_project; stage_change; write_v2
  run_hook "$HOOK" "$(ups_input "A1")" >/dev/null
  for p in "$(jq -r .prompt "$FIXTURE")" \
           '<task-notification><task-id>t1</task-id><status>completed</status><summary>Agent "A1" finished</summary><result>A1</result></task-notification>' \
           $'<pasted_content id="1">\nA1\n</pasted_content id="1">' \
           '/approvecap' \
           '  <task-notification>A1</task-notification>'; do
    RESULT=$(run_hook "$HOOK" "$(ups_input "$p")")
    assert_equals "" "$RESULT" "a neutral turn produces no output: ${p:0:40}"
    assert_file_not_exists "$(marker)" "a neutral turn does not approve: ${p:0:40}"
    assert_file_exists "$(shown)" "a neutral turn does not void the render: ${p:0:40}"
  done
  run_hook "$HOOK" "$(ups_input "A1")" >/dev/null
  assert_file_exists "$(marker)" "the user's A1 after neutral turns still approves"
  teardown_test_project
}

# --- Test (spec 6): free text and ids not first never pick ---
test_non_picks() {
  local p
  for p in "yes, go ahead" "Karl: A1 — approved" "go with A1" "A9" "approve A1"; do
    setup_test_project; stage_change; write_v2
    run_hook "$HOOK" "$(ups_input "A1")" >/dev/null
    RESULT=$(run_hook "$HOOK" "$(ups_input "$p")")
    run_hook "$HOOK" "$(ups_input "$p")" >/dev/null
    assert_file_not_exists "$(marker)" "no approval from: $p"
    assert_file_exists "$(sentinel)" "the question stays open after: $p"
    assert_contains "$(ctx "$RESULT")" "did not start with an option id" "Claude is told what reply is needed: $p"
    teardown_test_project
  done
}

# --- Test (spec 7 + interim safety): a v1 or malformed sentinel cannot be answered; the
# reply passes through with the schema-2 shape for the agent and a note for the user ---
test_v1_and_malformed_sentinels() {
  local body
  for body in '{"question":"Commit?","options":["A1: commit","A2: hold"],"recommendation":"A1","offered_at":"2026-10-05T12:00:00Z"}' \
              '{ not json'; do
    setup_test_project; stage_change
    printf '%s\n' "$body" > "$(sentinel)"
    RESULT=$(run_hook "$HOOK" "$(ups_input "A1")")
    RESULT2=$(run_hook "$HOOK" "$(ups_input "A1")")
    assert_equals "" "$(decision "$RESULT")" "the reply is not blocked: ${body:0:20}"
    assert_file_not_exists "$(marker)" "no approval: ${body:0:20}"
    assert_contains "$(ctx "$RESULT2")" "cannot be answered" "Claude is told it cannot be answered: ${body:0:20}"
    assert_contains "$(ctx "$RESULT2")" '"schema": 2' "Claude is given the schema-2 shape: ${body:0:20}"
    assert_contains "$(jq -r '.systemMessage // empty' <<< "$RESULT2")" "re-ask" "the user is told the agent must re-ask: ${body:0:20}"
    assert_file_exists "$(sentinel)" "the sentinel is left for the agent to rewrite"
    teardown_test_project
  done
}

# --- Test (spec 7): no sentinel is silent; an internal failure grants nothing and never
# blocks the prompt ---
test_no_sentinel_and_failures() {
  local bin c
  setup_test_project; stage_change
  RESULT=$(run_hook "$HOOK" "$(ups_input "A1")"); EXIT_CODE=$(run_hook_exit_code "$HOOK" "$(ups_input "A1")")
  assert_equals "" "$RESULT" "no sentinel: no output"
  assert_exit_code "0" "$EXIT_CODE" "no sentinel: exit 0"
  write_v2
  bin=$(mktemp -d); for c in bash cat dirname git shasum cut tr sed grep awk date mktemp mv rm head; do ln -s "$(command -v "$c")" "$bin/$c"; done
  RESULT=$(cd "$TEST_DIR" && ups_input A1 | PATH="$bin" /bin/bash "$HOOK" 2>/dev/null; echo "rc=$?")
  assert_contains "$RESULT" "rc=0" "without jq the hook exits 0"
  assert_contains "$RESULT" "no approval was recorded" "without jq the failure is reported"
  assert_contains "$RESULT" "additionalContext" "the failure also reaches Claude"
  assert_not_contains "$RESULT" '"decision"' "the failure never blocks the prompt"
  assert_file_not_exists "$(marker)" "without jq nothing is approved"
  rm -rf "$bin"
  teardown_test_project
}

# --- Test (spec 10): mark-evaluated.sh is the user's own override: refused under Claude
# Code, and bound to the staged state like a pick when run in the user's terminal ---
test_mark_evaluated_override() {
  setup_test_project; stage_change
  RESULT=$(cd "$TEST_DIR" && CLAUDECODE=1 bash "$HOOK_DIR/mark-evaluated.sh" "skip evaluation" 2>&1; echo "rc=$?")
  assert_not_contains "$RESULT" "rc=0" "under CLAUDECODE the override refuses"
  assert_contains "$RESULT" "separate terminal" "the refusal says where to run it"
  assert_file_not_exists "$(marker)" "no marker under CLAUDECODE"
  RESULT=$(mark_evaluated_at_terminal "skip evaluation")
  assert_contains "$RESULT" "rc=0" "in the user's terminal, with the code typed back, the override runs"
  assert_equals "override" "$(jq -r .source "$(marker)" 2>/dev/null)" "the override marker says so"
  assert_equals "$(git -C "$TEST_DIR" write-tree)" "$(jq -r .tree "$(marker)" 2>/dev/null)" "the override marker binds the index tree"
  assert_equals "skip evaluation" "$(tail -n 1 "$TEST_DIR/.claude/approvals.jsonl" | jq -r .reason)" "approvals.jsonl records the override"
  teardown_test_project
}

# --- Test (self-approval finding, PR 1): the override needs the user at a terminal. The
# agent's Bash tool has no controlling terminal, so a plain run with CLAUDECODE cleared
# refuses; a guessed answer is refused because the code is random. (A pseudo-terminal
# driver that reads the code, as mark_evaluated_at_terminal does, gets past this check;
# config-guard's name match is the barrier for the agent.) ---
test_mark_evaluated_needs_terminal_code() {
  local answer
  setup_test_project; stage_change
  RESULT=$(cd "$TEST_DIR" && run_without_ctty env -u CLAUDECODE bash "$HOOK_DIR/mark-evaluated.sh" "approved" </dev/null 2>&1; echo "rc=$?")
  assert_not_contains "$RESULT" "rc=0" "without a controlling terminal the override refuses"
  assert_contains "$RESULT" "terminal" "the refusal says it needs the user's terminal"
  assert_file_not_exists "$(marker)" "no marker without a terminal"
  assert_file_not_exists "$TEST_DIR/.claude/approvals.jsonl" "no audit record without a terminal"
  local codes=""
  for answer in yes y 0 12345; do
    RESULT=$(mark_evaluated_at_terminal "approved" "$answer")
    assert_not_contains "$RESULT" "rc=0" "a guessed answer ($answer) is refused"
    assert_file_not_exists "$(marker)" "no marker for a guessed answer ($answer)"
    codes="$codes $(sed -n 's/.*Type \([0-9]*\) .*/\1/p' <<< "$RESULT")"
  done
  assert_equals "4" "$(tr ' ' '\n' <<< "$codes" | grep . | sort -u | wc -l | tr -d ' ')" "each run shows a new code: $codes"
  RESULT=$(mark_evaluated_at_terminal "approved")
  assert_contains "$RESULT" "rc=0" "the code shown, typed back, approves"
  assert_contains "$RESULT" "Approve committing the staged change" "the terminal prompt says what is approved"
  assert_file_exists "$(marker)" "the typed code writes the marker"
  teardown_test_project
}

# --- Test (implementation review 1): a typed reply that quotes a harness tag is not read
# as an answer, but Claude is told so and the render stays ---
test_reply_quoting_a_harness_tag() {
  setup_test_project; stage_change; write_v2
  run_hook "$HOOK" "$(ups_input "A1")" >/dev/null
  local p
  for p in 'A1 - but what was that <task-notification> about?' $'A1 <cross-session-message from="x">\nA1\n</cross-session-message>'; do
    RESULT=$(run_hook "$HOOK" "$(ups_input "$p")")
    assert_file_not_exists "$(marker)" "no approval from a reply quoting a harness tag: ${p:0:30}"
    assert_contains "$(ctx "$RESULT")" "was not read as an answer" "Claude is told the reply was not read as an answer: ${p:0:30}"
    assert_file_exists "$(shown)" "the render is not voided: ${p:0:30}"
  done
  run_hook "$HOOK" "$(ups_input "A1")" >/dev/null
  assert_file_exists "$(marker)" "a plain A1 afterwards still approves"
  teardown_test_project
}

echo "record-approval.sh"
test_bad_ids_never_approve
test_first_pick_renders_and_blocks
test_render_nothing_staged_and_conflicts
test_second_pick_approves
test_non_approving_pick
test_non_approving_pick_withdraws_approval
test_withdrawal_fails_closed
test_render_survives_session_end_and_resume
test_changes_void_the_render
test_neutral_turns
test_non_picks
test_v1_and_malformed_sentinels
test_no_sentinel_and_failures
test_mark_evaluated_override
test_mark_evaluated_needs_terminal_code
test_reply_quoting_a_harness_tag
run_tests
