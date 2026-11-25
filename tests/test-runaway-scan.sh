#!/usr/bin/env bash
# test-runaway-scan.sh — hooks/runaway-scan.sh on SessionStart and Stop (#54, Solo T6).
# The process table is a `ps` shim on PATH printing a crafted table (no real 11-minute
# wait), except for one real `sh` re-parented to pid 1, whose elapsed time the shim
# rewrites. `uname` and `zprint` shims drive the zone line. Every planted process names
# a marker and is bounded by a guard of the test's own; on Darwin the kernel zone is
# sampled before and after the file.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

HOOK="$HOOK_DIR/runaway-scan.sh"
RUN_ID="cdfscan-$$"
REAL_PS=$(command -v ps)

zone_count() {
  [ "$(uname)" = Darwin ] && command -v zprint >/dev/null 2>&1 || return 0
  zprint 2>/dev/null | awk '$1=="data.kalloc.1024"{print $7}'
}
ZONE_BEFORE=$(zone_count)

START_INPUT='{"session_id":"t","hook_event_name":"SessionStart","source":"startup"}'
STOP_INPUT='{"session_id":"t","hook_event_name":"Stop","stop_hook_active":false}'

# A shim folder put first on PATH: ps prints $SHIM/table (SELF is the shim's parent,
# the hook or a subshell of it, and SELFUP that one's parent), uname prints $SHIM/os,
# zprint prints a zone line with $SHIM/zone in use and leaves $SHIM/zprint-ran.
new_shims() {
  SHIM=$(mktemp -d)
  cat > "$SHIM/ps" <<EOF
#!/bin/sh
here=\$(dirname "\$0")
[ -f "\$here/table" ] || exit 1
up=\$("$REAL_PS" -o ppid= -p \$PPID | tr -d ' ')
sed -e "s/SELFUP/\$up/g" -e "s/SELF/\$PPID/g" "\$here/table"
EOF
  printf '#!/bin/sh\ncat "$(dirname "$0")/os"\n' > "$SHIM/uname"
  cat > "$SHIM/zprint" <<'EOF'
#!/bin/sh
here=$(dirname "$0")
: > "$here/zprint-ran"
echo "zone name                   size        size        size      #elts       #elts       inuse   size  count"
printf 'data.kalloc.1024            1024          0K          0K          0           0        %s     0K      0\n' "$(cat "$here/zone")"
EOF
  chmod +x "$SHIM/ps" "$SHIM/uname" "$SHIM/zprint"
  echo Darwin > "$SHIM/os"; echo 700 > "$SHIM/zone"
  mkdir -p "$SHIM/tmp"
}
# scan INPUT — run the hook from TEST_DIR with the shims first on PATH and TMPDIR (where
# the hook keeps the processes it has reported) in the shim folder. Sets OUT, RC.
scan() {
  OUT=$(cd "$TEST_DIR" && printf '%s' "$1" | TMPDIR="$SHIM/tmp" PATH="$SHIM:$PATH" bash "$HOOK" 2>/dev/null); RC=$?
}
stop_in() { printf '{"session_id":"%s","hook_event_name":"Stop","stop_hook_active":false}' "$1"; }
msg() { jq -r '.systemMessage // empty' <<< "$OUT" 2>/dev/null; }
ctx() { jq -r '.hookSpecificOutput.additionalContext // empty' <<< "$OUT" 2>/dev/null; }

# write_table ROWS — header plus rows (pid ppid pgid etime %cpu command).
write_table() { { echo "  PID  PPID  PGID     ELAPSED  %CPU COMMAND"; printf '%s\n' "$1"; } > "$SHIM/table"; }

# A healthy table: young shells of pid 1, old daemons of pid 1 that are not shells, an
# old process naming another project whose path starts with this one's, a young process
# naming this project, and the process that runs ps for the hook (SELF), naming this
# project, old and busy.
healthy_rows() {
  cat <<EOF
    1     0     1 01-05:49:04   0.1 /sbin/launchd
   94     1    94 01-05:48:58   0.1 /usr/libexec/logd
  200     1   200    00:05   0.0 sh -c sleep 5
  201     1   201    09:59   3.0 bash ./build.sh
  202     1   202 2-00:00:00  10.0 /usr/sbin/syslogd
  203   500   203 05:00:00  12.0 node $TEST_DIR-other/server.js
  204   500   204    00:30   2.0 node $TEST_DIR/server.js
 SELF SELFUP   600    30:00  95.0 bash $TEST_DIR/.claude/framework/hooks/runaway-scan.sh
EOF
}

# =====================================================================
# A healthy table: nothing on stdout, exit 0
# =====================================================================
test_healthy_table_is_silent() {
  setup_test_project; new_shims
  write_table "$(healthy_rows)"
  scan "$STOP_INPUT"
  assert_equals "0" "$RC" "healthy, Stop: exit 0"
  assert_equals "" "$OUT" "healthy, Stop: no output (never 'clean')"
  scan "$START_INPUT"
  assert_equals "0" "$RC" "healthy, SessionStart: exit 0"
  assert_equals "" "$OUT" "healthy, SessionStart (zone 700): no output"
  rm -rf "$SHIM"; teardown_test_project
}

# =====================================================================
# T6: planted rows are reported: an 11-minute sh of pid 1, a 95 % CPU process, and
# an old process naming this project
# =====================================================================
test_planted_rows_reported() {
  setup_test_project; new_shims
  write_table "$(healthy_rows)
  300     1   300    11:00   0.0 sh -c while :; do sleep 1; done
  301   777   301    00:12  95.0 python3 $TEST_DIR/spin.py
  302   777   302 1-02:03:04   0.0 perl -e 1 $TEST_DIR
  303     1   303    00:40  99.9 /usr/bin/perl -e loop
  304     1   304 1:00:00   0.0 -bash"
  scan "$STOP_INPUT"
  assert_equals "0" "$RC" "planted, Stop: exit 0"
  assert_equals "true" "$(jq -e 'type == "object" and (.systemMessage | type) == "string"' <<< "$OUT" 2>&1)" \
    "planted, Stop: valid JSON with systemMessage"
  assert_equals "null" "$(jq -c '.hookSpecificOutput' <<< "$OUT")" "planted, Stop: no additionalContext (it would continue the turn)"
  M=$(msg)
  assert_contains "$M" '^\[ORPHAN\] pid=300 ppid=1 pgid=300 etime=11:00 cpu=0.0% cmd=sh -c while' "an 11-minute sh of pid 1 is reported"
  assert_contains "$M" '^\[ORPHAN\] pid=301 .*cpu=95.0%' "a 95 % CPU process naming the project is reported"
  assert_contains "$M" '^\[ORPHAN\] pid=302 .*etime=1-02:03:04' "a day-old process naming the project is reported"
  assert_contains "$M" '^\[ORPHAN\] pid=303 ' "a 99.9 % CPU perl of pid 1 is reported (path stripped)"
  assert_contains "$M" '^\[ORPHAN\] pid=304 ' "an hour-old login-style -bash of pid 1 is reported"
  assert_equals "5" "$(grep -c '^\[ORPHAN\] pid=' <<< "$M")" "exactly the five planted rows are reported"
  assert_contains "$M" "nothing was killed" "the message says it only reports"
  scan "$START_INPUT"
  assert_equals "0" "$RC" "planted, SessionStart: exit 0"
  assert_equals "$(msg)" "$(ctx)" "planted, SessionStart: additionalContext carries the same text"
  assert_equals "SessionStart" "$(jq -r '.hookSpecificOutput.hookEventName' <<< "$OUT")" "planted, SessionStart: hookEventName"
  rm -rf "$SHIM"; teardown_test_project
}

# A real sh whose parent exits re-parents to pid 1; the shim reports it 11 minutes old.
test_real_orphan_reported() {
  local mark="$RUN_ID-orphan" opid i guard gs
  setup_test_project; new_shims
  ( trap 'kill "$gs" 2>/dev/null; exit 0' TERM; sleep 20 & gs=$!; wait "$gs"; pkill -KILL -f "$mark" ) </dev/null >/dev/null 2>&1 &
  guard=$!
  ( sh -c 'perl -e "sleep 15" "$0"; :' "$mark" </dev/null >/dev/null 2>&1 & )
  i=0; opid=""
  while [ $i -lt 20 ] && [ -z "$opid" ]; do
    opid=$("$REAL_PS" -Ao pid=,ppid=,command= | awk -v m="$mark" '$2 == 1 && index($0, m) && $3 == "sh" { print $1 }')
    [ -n "$opid" ] || sleep 0.1; i=$((i + 1))
  done
  assert_equals "true" "$([ -n "$opid" ] && echo true || echo false)" "the planted sh re-parented to pid 1"
  cat > "$SHIM/ps" <<EOF
#!/bin/sh
"$REAL_PS" "\$@" | awk -v p="$opid" '\$1 == p { sub(/[0-9:-]+ +[0-9.]+ +sh /, "11:00 0.0 sh ") } { print }'
EOF
  scan "$STOP_INPUT"
  assert_equals "0" "$RC" "real orphan: exit 0"
  assert_contains "$(msg)" "^\[ORPHAN\] pid=$opid ppid=1 .*etime=11:00 .*$mark" "real orphan of pid 1 is reported"
  pkill -KILL -f "$mark"   # the planted sh and its sleeper
  kill "$guard" 2>/dev/null; wait "$guard" 2>/dev/null
  assert_equals "" "$(pgrep -f "$mark")" "real orphan: nothing left"
  rm -rf "$SHIM"; teardown_test_project
}

# =====================================================================
# ps unavailable or failing: "not scanned", never silence
# =====================================================================
test_ps_unavailable_not_scanned() {
  local bin t p
  setup_test_project; new_shims
  bin=$(mktemp -d)
  for t in bash sh cat awk sed dirname; do p=$(command -v "$t") && ln -s "$p" "$bin/$t"; done
  OUT=$(cd "$TEST_DIR" && printf '%s' "$STOP_INPUT" | TMPDIR="$SHIM/tmp" PATH="$bin" "$bin/bash" "$HOOK" 2>/dev/null); RC=$?
  assert_equals "0" "$RC" "no ps: exit 0"
  assert_contains "$(msg)" '^\[ORPHAN\] not scanned: ps not found' "no ps: says not scanned"
  rm -f "$SHIM/table"   # the shim then exits 1
  scan "$STOP_INPUT"
  assert_equals "0" "$RC" "ps fails: exit 0"
  assert_contains "$(msg)" '^\[ORPHAN\] not scanned: ps failed' "ps fails: says not scanned"
  : > "$SHIM/table"; printf '#!/bin/sh\nexit 0\n' > "$SHIM/ps"
  scan "$STOP_INPUT"
  assert_contains "$(msg)" '^\[ORPHAN\] not scanned: ps listed no processes' "ps prints nothing: says not scanned"
  rm -rf "$SHIM" "$bin"; teardown_test_project
}

# =====================================================================
# The zone line: Darwin above 5,000 on SessionStart; Linux "not applicable" on
# SessionStart; zprint never runs on Stop
# =====================================================================
test_zone_line() {
  setup_test_project; new_shims
  write_table "$(healthy_rows)"
  echo 50001 > "$SHIM/zone"
  scan "$START_INPUT"
  assert_equals "[ZONE] data.kalloc.1024 in use: 50001 (panic at 21,257,712 on 2026-11-11)" "$(msg)" "Darwin, zone 50001: the zone line (default threshold 50,000)"
  assert_equals "$(msg)" "$(ctx)" "Darwin zone line also reaches Claude on SessionStart"
  echo 50000 > "$SHIM/zone"
  scan "$START_INPUT"
  assert_equals "" "$OUT" "Darwin, zone 50000: nothing"
  echo 19342 > "$SHIM/zone"
  scan "$START_INPUT"
  assert_equals "" "$OUT" "Darwin, zone 19342 (this Mac idling): nothing"
  CDF_ZONE_WARN=6000 scan "$START_INPUT"
  assert_contains "$(msg)" "^\[ZONE\] data.kalloc.1024 in use: 19342 " "CDF_ZONE_WARN=6000: the zone line"
  CDF_ZONE_WARN=abc scan "$START_INPUT"
  assert_equals "" "$OUT" "CDF_ZONE_WARN not a number: the default threshold"
  rm -f "$SHIM/zprint-ran"; echo 9999 > "$SHIM/zone"
  scan "$STOP_INPUT"
  assert_equals "" "$OUT" "Stop: no zone line"
  assert_file_not_exists "$SHIM/zprint-ran" "Stop: zprint does not run (it costs ~190 ms)"
  echo Linux > "$SHIM/os"
  scan "$START_INPUT"
  assert_equals "[ZONE] data.kalloc.1024 not applicable on this OS" "$(msg)" "Linux, SessionStart: not applicable"
  scan "$STOP_INPUT"
  assert_equals "" "$OUT" "Linux, Stop: nothing"
  write_table "$(healthy_rows)
  300     1   300    11:00   0.0 sh -c x"
  scan "$START_INPUT"
  assert_equals "2" "$(msg | grep -c '^\[ORPHAN\] ')" "Linux, SessionStart with a find: the row and the report-only line"
  assert_equals "1" "$(msg | grep -c '^\[ZONE\] ')" "Linux, SessionStart with a find: and the zone line"
  rm -rf "$SHIM"; teardown_test_project
}

# Commands with quotes, backslashes and tabs still give valid JSON; long ones are cut.
test_json_escaping() {
  local long
  setup_test_project; new_shims
  long=$(printf 'x%.0s' $(seq 1 400))
  write_table "  400     1   400    20:00   0.0 sh -c echo \"a\\\\b\"	tab $long"
  scan "$STOP_INPUT"
  assert_equals "0" "$RC" "escaping: exit 0"
  assert_contains "$(msg)" 'cmd=sh -c echo "a\\\\b"' "escaping: quotes and backslash survive"
  assert_equals "true" "$([ "$(msg | head -n 1 | wc -c)" -lt 320 ] && echo true || echo false)" "escaping: a long command is cut"
  rm -rf "$SHIM"; teardown_test_project
}

# =====================================================================
# Once per session for age alone; every turn above 90 % CPU
# =====================================================================
test_age_only_reported_once_per_session() {
  setup_test_project; new_shims
  write_table "$(healthy_rows)
  300     1   300    11:00   0.0 sh -c sleep 900; :
  301     1   301    00:20  95.0 sh -c while :; do :; done
  302     1   302    45:00  97.0 bash -c spin"
  scan "$(stop_in sessA)"
  M=$(msg)
  assert_contains "$M" '^\[ORPHAN\] pid=300 ' "first Stop: the 11-minute row is reported"
  assert_contains "$M" '^\[ORPHAN\] pid=301 ' "first Stop: the 95 % row is reported"
  assert_contains "$M" '^\[ORPHAN\] pid=302 ' "first Stop: the old and busy row is reported"
  assert_equals "true" "$(ls "$SHIM/tmp" | grep -q . && echo true || echo false)" "the hook created its seen-file"
  scan "$(stop_in sessA)"
  M=$(msg)
  assert_not_contains "$M" 'pid=300 ' "second Stop, same session: the age-only row is not repeated"
  assert_contains "$M" '^\[ORPHAN\] pid=301 ' "second Stop: the 95 % row is reported again"
  assert_contains "$M" '^\[ORPHAN\] pid=302 ' "second Stop: the old and busy row is reported again"
  scan "$(stop_in sessB)"
  assert_contains "$(msg)" '^\[ORPHAN\] pid=300 ' "another session: the age-only row is reported again"
  # Only age-only rows, already seen: nothing at all.
  write_table "$(healthy_rows)
  300     1   300    11:00   0.0 sh -c sleep 900; :"
  scan "$(stop_in sessA)"
  assert_equals "" "$OUT" "an already reported age-only row alone: no output"
  # Same pid, another command (the pid was reused): reported.
  write_table "$(healthy_rows)
  300     1   300    11:00   0.0 bash ./other.sh"
  scan "$(stop_in sessA)"
  assert_contains "$(msg)" '^\[ORPHAN\] pid=300 .*other.sh' "a reused pid with another command is reported"
  rm -rf "$SHIM"; teardown_test_project
}

# The seen-file cannot be written: every turn reports, and says why once.
test_seen_file_unwritable() {
  setup_test_project; new_shims
  chmod 555 "$SHIM/tmp"
  write_table "$(healthy_rows)
  300     1   300    11:00   0.0 sh -c sleep 900; :
  304     1   304    20:00   0.0 perl -e sleep"
  scan "$(stop_in sessA)"
  assert_equals "0" "$RC" "unwritable: exit 0"
  scan "$(stop_in sessA)"
  M=$(msg)
  assert_contains "$M" '^\[ORPHAN\] pid=300 ' "unwritable, second Stop: the age-only row is reported again"
  assert_equals "1" "$(grep -c 'could not record' <<< "$M")" "unwritable: said once in the message"
  chmod 755 "$SHIM/tmp"
  rm -rf "$SHIM"; teardown_test_project
}

# =====================================================================
# Round 3 (review): the 2026-11-11 shape, Claude Code's own process, path boundaries,
# a symlinked seen-file
# =====================================================================
# The incident: sh at 100 % for hours under a live bash <- zsh <- zsh chain, not pid 1.
test_incident_shape_reported() {
  setup_test_project; new_shims
  write_table "$(healthy_rows)
57243 57001 57243 11:20:00   0.1 -zsh
57288 57243 57288 11:19:58   0.0 zsh -c source snapshot.sh && eval x
57290 57288 57288 11:19:58   0.0 bash -c run-harness
57300 57290 57288 10:55:00 100.0 sh
58001 57290 57288    00:30  99.0 sh -c make
58002 57290 57288    45:00   0.0 bash -c idle
58003 57290 57288    45:00  99.0 node build.js"
  scan "$(stop_in sessI)"
  M=$(msg)
  assert_contains "$M" '^\[ORPHAN\] pid=57300 ppid=57290 .*etime=10:55:00 cpu=100.0% cmd=sh$' "the incident's sh (busy and old, live parent) is reported"
  assert_not_contains "$M" 'pid=58001 ' "a busy shell younger than 10 minutes with a live parent is not"
  assert_not_contains "$M" 'pid=58002 ' "an old idle shell with a live parent is not"
  assert_not_contains "$M" 'pid=58003 ' "an old busy non-shell with a live parent is not"
  assert_equals "1" "$(grep -c '^\[ORPHAN\] pid=' <<< "$M")" "only the incident's sh"
  rm -rf "$SHIM"; teardown_test_project
}

test_claude_code_skipped() {
  setup_test_project; new_shims
  write_table "$(healthy_rows)
  700     1   700  2:00:00  95.0 claude daemon run --spawned-by {\"cwd\":\"$TEST_DIR\"}
  701   500   701  3:00:00   1.0 /usr/local/bin/claude --resume $TEST_DIR"
  scan "$(stop_in sessC)"
  assert_equals "" "$OUT" "Claude Code's own processes are not reported"
  rm -rf "$SHIM"; teardown_test_project
}

test_project_path_boundaries() {
  setup_test_project; new_shims
  write_table "$(healthy_rows)
  800   500   800    20:00   0.0 node /other$TEST_DIR/x.js
  801   500   801    20:00   0.0 node --dir=$TEST_DIR/app
  802   500   802    20:00   0.0 node \"$TEST_DIR/q.js\""
  scan "$(stop_in sessP)"
  M=$(msg)
  assert_not_contains "$M" 'pid=800 ' "a path that only contains the project path (/other<proj>/x) is not the project"
  assert_contains "$M" '^\[ORPHAN\] pid=801 ' "the project path after = counts"
  assert_contains "$M" '^\[ORPHAN\] pid=802 ' "the project path after a quote counts"
  # A trailing slash on CLAUDE_PROJECT_DIR changes nothing.
  write_table "$(healthy_rows)
  803   500   803    20:00   0.0 node $TEST_DIR/y.js"
  OUT=$(cd "$TEST_DIR" && stop_in sessQ | CLAUDE_PROJECT_DIR="$TEST_DIR/" TMPDIR="$SHIM/tmp" PATH="$SHIM:$PATH" bash "$HOOK" 2>/dev/null)
  assert_contains "$(msg)" '^\[ORPHAN\] pid=803 ' "CLAUDE_PROJECT_DIR with a trailing slash still matches"
  rm -rf "$SHIM"; teardown_test_project
}

# A seen-file that is a symlink is not used (it could point anywhere): every turn
# reports, the message says why once, and the link's target is untouched.
test_seen_file_symlink_refused() {
  local seen
  setup_test_project; new_shims
  echo keep > "$SHIM/target"
  seen="$SHIM/tmp/cdf-runaway-seen.$(id -u).sessL"
  ln -s "$SHIM/target" "$seen"
  write_table "$(healthy_rows)
  300     1   300    11:00   0.0 sh -c sleep 900; :"
  scan "$(stop_in sessL)"
  scan "$(stop_in sessL)"
  M=$(msg)
  assert_contains "$M" '^\[ORPHAN\] pid=300 ' "symlinked seen-file: the age-only row is reported again"
  assert_equals "1" "$(grep -c 'could not record.*symlink' <<< "$M")" "symlinked seen-file: said once, naming the symlink"
  assert_equals "keep" "$(cat "$SHIM/target")" "symlinked seen-file: the target is untouched"
  rm -rf "$SHIM"; teardown_test_project
}

test_healthy_table_is_silent
test_incident_shape_reported
test_claude_code_skipped
test_project_path_boundaries
test_seen_file_symlink_refused
test_age_only_reported_once_per_session
test_seen_file_unwritable
test_planted_rows_reported
test_real_orphan_reported
test_ps_unavailable_not_scanned
test_zone_line
test_json_escaping

LEFT=$(pgrep -f "$RUN_ID-" | tr '\n' ' ' | sed 's/ $//')
assert_equals "" "$LEFT" "no process of this run is left"
[ -n "$LEFT" ] && kill -KILL $LEFT 2>/dev/null

ZONE_AFTER=$(zone_count)
if [ -n "$ZONE_BEFORE" ] && [ -n "$ZONE_AFTER" ]; then
  echo "  zone data.kalloc.1024: before=$ZONE_BEFORE after=$ZONE_AFTER"
  assert_equals "true" "$([ "$ZONE_AFTER" -le $((ZONE_BEFORE + 1000)) ] && echo true || echo false)" \
    "zone data.kalloc.1024 rises by no more than 1,000 over this file"
fi

run_tests
