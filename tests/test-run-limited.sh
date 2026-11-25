#!/usr/bin/env bash
# test-run-limited.sh — scripts/run-limited.sh: a wall-clock limit that kills the whole
# process tree and dies with its launcher (#54, Solo acceptance tests T1-T5).
# Safety (owner rule): every process a test starts carries a marker argument, and a
# guard of the test's own kills everything naming that marker after a few seconds, so a
# bug in the wrapper cannot leave a spinner behind. On Darwin the kernel zone that
# panicked on 2026-11-11 is sampled before and after the file.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RL="$REPO_DIR/scripts/run-limited.sh"
# Hermetic: a suite run under run-limited.sh (or a shell that set these) must not move
# the tests' ledger or give the CLI a default limit.
unset CDF_WATCHDOG_LEDGER CDF_RUN_LIMIT
RUN_ID="cdfrl-$$"
GUARD_DIR=$(mktemp -d)

zone_count() {
  [ "$(uname)" = Darwin ] && command -v zprint >/dev/null 2>&1 || return 0
  zprint 2>/dev/null | awk '$1=="data.kalloc.1024"{print $7}'
}
ZONE_BEFORE=$(zone_count)

# guard_start SECS MARK — after SECS, SIGKILL every process whose command line names
# MARK and record that the guard fired. guard_stop ends it (and its sleep).
guard_start() {
  ( trap 'kill "$gs" 2>/dev/null; exit 0' TERM
    sleep "$1" & gs=$!
    wait "$gs"
    pkill -KILL -f "$2" && echo fired > "$GUARD_DIR/$2" ) </dev/null >/dev/null 2>&1 &
  GUARD_PID=$!
}
guard_stop() { kill "$GUARD_PID" 2>/dev/null; wait "$GUARD_PID" 2>/dev/null; }
survivors() { pgrep -f "$1" | tr '\n' ' ' | sed 's/ $//'; }

# A fresh project folder with .claude/, the wrapper's default ledger location.
new_proj() { PROJ=$(mktemp -d); mkdir -p "$PROJ/.claude"; LEDGER="$PROJ/.claude/watchdog.jsonl"; }

# run_fn MARK ARGS... — cdf_run_limited ARGS in a fresh bash whose command line names
# MARK (so the guard reaches the wrapper and its sidecar too), from PROJ. Sets RC, OUT,
# ERR and DUR (seconds).
run_fn() {
  local mark="$1" t0; shift
  t0=$SECONDS
  (cd "$PROJ" && bash -c 'source "$1"; shift; cdf_run_limited "$@"' "$mark" "$RL" "$@" \
    >"$PROJ/out" 2>"$PROJ/err" </dev/null)
  RC=$?; DUR=$((SECONDS - t0)); OUT=$(cat "$PROJ/out"); ERR=$(cat "$PROJ/err")
}
# run_cli ARGS... — the CLI, executed directly, from PROJ; same outputs as run_fn.
run_cli() {
  local t0=$SECONDS
  (cd "$PROJ" && "$RL" "$@" >"$PROJ/out" 2>"$PROJ/err" </dev/null)
  RC=$?; DUR=$((SECONDS - t0)); OUT=$(cat "$PROJ/out"); ERR=$(cat "$PROJ/err")
}

# check_row REASON LIMIT MARK — the ledger holds exactly one row, with every field.
check_row() {
  local row
  assert_file_exists "$LEDGER" "$3: ledger written"
  [ -f "$LEDGER" ] || return 0
  assert_equals "1" "$(wc -l < "$LEDGER" | tr -d ' ')" "$3: one ledger row"
  row=$(head -n 1 "$LEDGER")
  assert_equals "cmd,cwd,elapsed,launcher,limit,pgid,pid,reason,ts" \
    "$(jq -r 'keys | join(",")' <<< "$row" 2>&1)" "$3: row has the nine fields"
  assert_equals "$1" "$(jq -r .reason <<< "$row")" "$3: row reason"
  assert_equals "$2" "$(jq -r .limit <<< "$row")" "$3: row limit"
  assert_equals "true" "$(jq -r '.pid == .pgid and (.pid|type) == "number" and (.elapsed|type) == "number" and (.launcher|type) == "number"' <<< "$row")" \
    "$3: pid is the group leader; numbers are numbers"
  assert_contains "$(jq -r .cmd <<< "$row")" "$3" "$3: row cmd names the command"
  assert_equals "$(cd "$PROJ" && pwd -P)" "$(cd "$(jq -r .cwd <<< "$row")" 2>/dev/null && pwd -P)" "$3: row cwd"
  assert_contains "$(jq -r .ts <<< "$row")" '^[0-9-]*T[0-9:]*Z$' "$3: row ts is UTC ISO 8601"
}
# check_line REASON LIMIT MARK — exactly one stderr line, the WATCHDOG one.
check_line() {
  assert_equals "1" "$(printf '%s\n' "$ERR" | grep -c .)" "$3: exactly one stderr line"
  assert_contains "$ERR" "^\[WATCHDOG\] KILLED reason=$1 pid=[0-9][0-9]* pgid=[0-9][0-9]* elapsed=[0-9][0-9]* limit=$2 cmd=.*$3" \
    "$3: WATCHDOG line"
}
# check_clean MARK — nothing naming MARK survives, and the test's guard never fired
# (the wrapper did the killing).
check_clean() {
  assert_equals "" "$(survivors "$1")" "$1: no survivor"
  assert_file_not_exists "$GUARD_DIR/$1" "$1: the wrapper, not the test's guard, ended the run"
}

# =====================================================================
# Usage errors: nothing runs
# =====================================================================
test_usage_errors() {
  new_proj
  run_fn "$RUN_ID-u1" -- touch "$PROJ/ran"
  assert_equals "2" "$RC" "function without a limit: exit 2"
  assert_contains "$ERR" "usage" "function without a limit: says usage"
  run_fn "$RUN_ID-u2" abc -- touch "$PROJ/ran"
  assert_equals "2" "$RC" "function with a non-numeric limit: exit 2"
  run_fn "$RUN_ID-u3" 5 --
  assert_equals "2" "$RC" "function without a command: exit 2"
  run_fn "$RUN_ID-u4" 5 notapid -- touch "$PROJ/ran"
  assert_equals "2" "$RC" "function with a non-numeric launcher: exit 2"
  (unset CDF_RUN_LIMIT; cd "$PROJ" && "$RL" -- touch "$PROJ/ran" >"$PROJ/out" 2>"$PROJ/err" </dev/null); RC=$?
  assert_equals "2" "$RC" "CLI without --limit or CDF_RUN_LIMIT: exit 2"
  assert_contains "$(cat "$PROJ/err")" "CDF_RUN_LIMIT" "CLI usage error names CDF_RUN_LIMIT"
  run_cli --limit 0 -- touch "$PROJ/ran"
  assert_equals "2" "$RC" "CLI with --limit 0: exit 2"
  run_cli --limit 5 --launcher 999999999 -- touch "$PROJ/ran"
  assert_equals "2" "$RC" "CLI with a launcher that is not running: exit 2"
  assert_file_not_exists "$PROJ/ran" "no usage error ran the command"
  assert_file_not_exists "$LEDGER" "no usage error wrote a ledger row"
  run_cli --help
  assert_equals "0" "$RC" "CLI --help: exit 0"
  assert_contains "$OUT" "run-limited.sh" "CLI --help prints the usage"
  rm -rf "$PROJ"
}

# =====================================================================
# T1: a spinner under a 2 s limit is killed, rc 124, line and row, no survivor
# =====================================================================
t1_case() {
  local form="$1" mark="$2"
  new_proj
  guard_start 15 "$mark"
  if [ "$form" = fn ]; then
    run_fn "$mark" 2 -- bash -c 'sh -c "while :; do :; done" "$1"; exit $?' x "$mark"
  else
    run_cli --limit 2 -- bash -c 'sh -c "while :; do :; done" "$1"; exit $?' x "$mark"
  fi
  guard_stop
  assert_equals "124" "$RC" "T1 $form: killed at the limit, rc 124"
  assert_equals "true" "$([ "$DUR" -ge 1 ] && [ "$DUR" -le 5 ] && echo true || echo "false ($DUR s)")" \
    "T1 $form: ended within the limit's window"
  check_clean "$mark"
  check_line limit 2 "$mark"
  check_row limit 2 "$mark"
  rm -rf "$PROJ"
}
test_t1_limit_kills_tree() {
  t1_case fn "$RUN_ID-t1fn"
  t1_case cli "$RUN_ID-t1cli"
}

# CDF_RUN_LIMIT is the CLI's default limit; CDF_WATCHDOG_LEDGER moves the ledger.
test_env_limit_and_ledger() {
  local mark="$RUN_ID-env"
  new_proj
  LEDGER="$PROJ/elsewhere.jsonl"
  guard_start 15 "$mark"
  (cd "$PROJ" && CDF_RUN_LIMIT=1 CDF_WATCHDOG_LEDGER="$LEDGER" "$RL" -- sh -c 'while :; do :; done' "$mark" \
    >"$PROJ/out" 2>"$PROJ/err" </dev/null); RC=$?; ERR=$(cat "$PROJ/err")
  guard_stop
  assert_equals "124" "$RC" "CDF_RUN_LIMIT=1: rc 124"
  check_clean "$mark"
  check_line limit 1 "$mark"
  check_row limit 1 "$mark"
  assert_file_not_exists "$PROJ/.claude/watchdog.jsonl" "CDF_WATCHDOG_LEDGER moved the row"
  rm -rf "$PROJ"
}

# A command that ignores TERM is killed with KILL after 5 s.
test_term_ignored_gets_kill() {
  local mark="$RUN_ID-kill"
  new_proj
  guard_start 20 "$mark"
  run_fn "$mark" 1 -- sh -c 'trap "" TERM; while :; do :; done' "$mark"
  guard_stop
  assert_equals "124" "$RC" "TERM ignored: still rc 124"
  assert_equals "true" "$([ "$DUR" -ge 5 ] && [ "$DUR" -le 10 ] && echo true || echo "false ($DUR s)")" \
    "TERM ignored: KILL about 5 s after TERM"
  check_clean "$mark"
  rm -rf "$PROJ"
}

# =====================================================================
# T2: the launcher dies after 1 s (each sleeper names the marker itself, so the guard
# reaches it if the wrapper does not) -> the group is killed within ~3 s, rc 125
# =====================================================================
t2_case() {
  local form="$1" mark="$2" lpid
  new_proj
  guard_start 15 "$mark"
  sleep 1 & lpid=$!
  if [ "$form" = fn ]; then
    run_fn "$mark" 30 "$lpid" -- sh -c 'perl -e "sleep 60" "$0"; :' "$mark"
  else
    run_cli --limit 30 --launcher "$lpid" -- sh -c 'perl -e "sleep 60" "$0"; :' "$mark"
  fi
  guard_stop
  wait "$lpid" 2>/dev/null
  assert_equals "125" "$RC" "T2 $form: killed because the launcher died, rc 125"
  assert_equals "true" "$([ "$DUR" -le 4 ] && echo true || echo "false ($DUR s)")" "T2 $form: within ~3 s"
  check_clean "$mark"
  check_line launcher-gone 30 "$mark"
  check_row launcher-gone 30 "$mark"
  rm -rf "$PROJ"
}
test_t2_launcher_gone() {
  t2_case fn "$RUN_ID-t2fn"
  t2_case cli "$RUN_ID-t2cli"
}

# The default launchers: the function's caller ($$) and the CLI's parent. The launcher
# is killed or exits; nothing waits on the wrapper, so the row and the absence of
# survivors are the evidence.
test_t2_default_launchers() {
  local mark="$RUN_ID-t2dfn" caller i
  new_proj
  guard_start 15 "$mark"
  (cd "$PROJ" && exec bash -c 'source "$1"; cdf_run_limited 30 -- sh -c "perl -e \"sleep 60\" \"\$0\"; :" "$0"' "$mark" "$RL" \
    >/dev/null 2>&1 </dev/null) & caller=$!
  sleep 1; kill -KILL "$caller" 2>/dev/null; wait "$caller" 2>/dev/null
  i=0; while [ $i -lt 8 ] && [ -n "$(survivors "$mark")" ]; do sleep 1; i=$((i + 1)); done
  guard_stop
  check_clean "$mark"
  check_row launcher-gone 30 "$mark"
  rm -rf "$PROJ"

  mark="$RUN_ID-t2dcli"
  new_proj
  guard_start 15 "$mark"
  (cd "$PROJ" && bash -c '"$1" --limit 30 -- sh -c "perl -e \"sleep 60\" \"\$0\"; :" "$0" & sleep 1' "$mark" "$RL" \
    >/dev/null 2>&1 </dev/null)
  i=0; while [ $i -lt 8 ] && [ -n "$(survivors "$mark")" ]; do sleep 1; i=$((i + 1)); done
  guard_stop
  check_clean "$mark"
  check_row launcher-gone 30 "$mark"
  rm -rf "$PROJ"
}

# =====================================================================
# T3: normal completion passes the rc through, writes no row and no stderr line
# =====================================================================
test_t3_normal_completion() {
  local mark="$RUN_ID-t3"
  new_proj
  guard_start 15 "$mark"
  run_fn "$mark" 30 -- sh -c 'echo hello; exit 0' "$mark"
  assert_equals "0" "$RC" "T3 fn: rc 0 passes through"
  assert_equals "hello" "$OUT" "T3 fn: the command's stdout passes through"
  assert_equals "" "$ERR" "T3 fn: no stderr line"
  assert_equals "true" "$([ "$DUR" -le 1 ] && echo true || echo "false ($DUR s)")" "T3 fn: returns at once"
  assert_equals "" "$(survivors "$mark")" "T3 fn: the sidecar is stopped"
  run_fn "$mark" 30 -- sh -c 'echo oops >&2; exit 7' "$mark"
  assert_equals "7" "$RC" "T3 fn: a non-zero rc passes through"
  assert_equals "oops" "$ERR" "T3 fn: the command's own stderr, nothing added"
  run_cli --limit 30 -- sh -c 'exit 3' "$mark"
  assert_equals "3" "$RC" "T3 cli: a non-zero rc passes through"
  assert_equals "" "$ERR" "T3 cli: no stderr line"
  run_cli --limit 30 -- true "$mark"
  assert_equals "0" "$RC" "T3 cli: rc 0"
  guard_stop
  assert_equals "" "$(survivors "$mark")" "T3: nothing left running"
  assert_file_not_exists "$LEDGER" "T3: no ledger row"
  rm -rf "$PROJ"
}

# =====================================================================
# Stragglers: the command exits normally and leaves part of its group running ->
# TERM then KILL the rest, reason=stragglers, the command's own exit code. Each sleeper
# names the marker itself (a `sh -c "sleep 60"` leaf would not), so the guard reaches it.
# =====================================================================
test_stragglers_killed() {
  local mark="$RUN_ID-strag" i
  new_proj
  guard_start 20 "$mark"
  run_fn "$mark" 30 -- bash -c 'perl -e "sleep 60" "$1" & exit 0' x "$mark"
  assert_equals "0" "$RC" "stragglers fn: the command's own rc 0"
  assert_equals "true" "$([ "$DUR" -le 6 ] && echo true || echo "false ($DUR s)")" "stragglers fn: within ~6 s"
  check_clean "$mark"
  check_line stragglers 30 "$mark"
  check_row stragglers 30 "$mark"
  rm -rf "$PROJ"
  new_proj
  run_cli --limit 30 -- bash -c 'perl -e "sleep 60" "$1" & exit 3' x "$mark"
  guard_stop
  assert_equals "3" "$RC" "stragglers cli: the command's own rc 3"
  check_clean "$mark"
  check_line stragglers 30 "$mark"
  check_row stragglers 30 "$mark"
  rm -rf "$PROJ"
}

# A straggler that ignores TERM gets KILL; one that left the group under a live
# straggler is swept with it.
test_stragglers_kill_and_sweep() {
  local mark="$RUN_ID-strag2"
  new_proj
  guard_start 25 "$mark"
  run_fn "$mark" 30 -- bash -c '
    perl -e "\$SIG{TERM} = q(IGNORE); sleep 1 while 1" "$1" &
    sh -c "perl -e \"setpgrp(0,0); exec @ARGV\" perl -e \"sleep 60\" \"\$0\" & wait" "$1" &
    sleep 1; exit 0' x "$mark"
  guard_stop
  assert_equals "0" "$RC" "stragglers: rc 0"
  check_clean "$mark"
  check_row stragglers 30 "$mark"
  rm -rf "$PROJ"
}

# =====================================================================
# T4: the ledger cannot be written -> the kill still happens, said on stderr, rc non-zero
# =====================================================================
test_t4_ledger_unwritable() {
  local mark="$RUN_ID-t4"
  new_proj
  chmod 555 "$PROJ/.claude"
  guard_start 15 "$mark"
  run_fn "$mark" 1 -- sh -c 'while :; do :; done' "$mark"
  guard_stop
  chmod 755 "$PROJ/.claude"
  assert_equals "124" "$RC" "T4: still rc 124"
  assert_equals "" "$(survivors "$mark")" "T4: the kill still happened"
  assert_contains "$ERR" "^\[WATCHDOG\] KILLED reason=limit" "T4: WATCHDOG line"
  assert_contains "$ERR" "^\[WATCHDOG\] could not write the ledger row to .*watchdog.jsonl" "T4: the failure to record is said"
  assert_file_not_exists "$LEDGER" "T4: no row"
  rm -rf "$PROJ"
}

# =====================================================================
# T5: a descendant that left the group is swept by the descendant walk
# =====================================================================
test_t5_sweep() {
  local mark="$RUN_ID-t5"
  new_proj
  guard_start 20 "$mark"
  run_fn "$mark" 2 -- bash -c 'perl -e "setpgrp(0,0); exec @ARGV" sh -c "perl -e \"sleep 60\" \"\$0\"; :" "$1"; exit $?' x "$mark"
  guard_stop
  assert_equals "124" "$RC" "T5: rc 124"
  check_clean "$mark"
  check_row limit 2 "$mark"
  rm -rf "$PROJ"
}

# A caller under `set -euo pipefail` (Solo's scripts) calling it bare, where errexit is
# in force inside the function: it still kills, records and ends with 124, and still
# passes a non-zero rc through. (Called as `f || rc=$?`, bash turns errexit off inside.)
test_caller_with_errexit() {
  local mark="$RUN_ID-strict"
  new_proj
  guard_start 15 "$mark"
  (cd "$PROJ" && bash -c 'set -euo pipefail; source "$1"; shift; cdf_run_limited "$@"; echo not-reached' \
    "$mark" "$RL" 1 -- sh -c 'while :; do :; done' "$mark" >"$PROJ/out" 2>"$PROJ/err" </dev/null)
  RC=$?
  guard_stop
  OUT=$(cat "$PROJ/out"); ERR=$(cat "$PROJ/err")
  assert_equals "124" "$RC" "set -euo pipefail caller: rc 124"
  assert_equals "" "$OUT" "set -euo pipefail caller: errexit then stops the caller"
  check_clean "$mark"
  check_line limit 1 "$mark"
  check_row limit 1 "$mark"
  (cd "$PROJ" && bash -c 'set -euo pipefail; source "$1"; cdf_run_limited 30 -- sh -c "exit 7" "$0"' \
    "$mark" "$RL" >/dev/null 2>&1 </dev/null)
  assert_equals "7" "$?" "set -euo pipefail caller: a non-zero rc passes through"
  (cd "$PROJ" && bash -c 'set -euo pipefail; source "$1"; cdf_run_limited 30 -- true "$0"; echo ok' \
    "$mark" "$RL" >"$PROJ/out" 2>&1 </dev/null)
  assert_equals "ok" "$(cat "$PROJ/out")" "set -euo pipefail caller: rc 0 continues"
  rm -rf "$PROJ"
}

# =====================================================================
# Round 3 (review): stdin, inherited traps and IFS, unreachable stragglers, row size,
# usage, an unsignallable launcher, the temp state folder, a missing jq
# =====================================================================
PROBE_STDIN='if (exec 3<&0) 2>/dev/null; then echo open; else echo closed; fi'
test_stdin_reaches_command() {
  local mark="$RUN_ID-stdin"
  new_proj
  guard_start 20 "$mark"
  OUT=$(cd "$PROJ" && printf 'a\nb\n' | "$RL" --limit 10 -- sh -c 'cat; :' "$mark" 2>"$PROJ/err"); RC=$?
  assert_equals "a
b|0" "$OUT|$RC" "stdin: piped input reaches the command (CLI)"
  printf 'from-file\n' > "$PROJ/in"
  OUT=$(cd "$PROJ" && "$RL" --limit 10 -- sh -c 'cat; :' "$mark" < "$PROJ/in" 2>"$PROJ/err")
  assert_equals "from-file" "$OUT" "stdin: < file reaches the command (CLI)"
  OUT=$(cd "$PROJ" && printf 'fn-in\n' | bash -c 'source "$1"; shift; cdf_run_limited "$@"' "$mark" "$RL" 10 -- sh -c 'cat; :' "$mark" 2>"$PROJ/err")
  assert_equals "fn-in" "$OUT" "stdin: piped input reaches the command (function)"
  OUT=$(cd "$PROJ" && "$RL" --limit 10 -- sh -c "$PROBE_STDIN" "$mark" <&- 2>"$PROJ/err")
  assert_equals "closed" "$OUT" "stdin: a closed stdin stays closed"
  (cd "$PROJ" && printf 'x\n' | "$RL" --limit 1 -- sh -c 'while :; do :; done' "$mark" >/dev/null 2>"$PROJ/err"); RC=$?
  guard_stop
  assert_equals "124" "$RC" "stdin: a spinner with piped stdin is still killed, rc 124"
  check_clean "$mark"
  rm -rf "$PROJ"
}

# A caller with set -Eeuo pipefail and an ERR trap: the trap must not reach the wrapper
# or its sidecar. It logs $BASH_SUBSHELL, so a firing inside them shows as 1 or more
# (bash 3.2 does not fire the caller's own trap for a subshell function's status).
test_caller_errtrace() {
  local mark="$RUN_ID-errtrace"
  new_proj
  guard_start 20 "$mark"
  (cd "$PROJ" && bash -c 'set -Eeuo pipefail; t=$2; trap "echo \$BASH_SUBSHELL >> \"\$t\"" ERR; source "$1"; shift 2; cdf_run_limited "$@"' \
    "$mark" "$RL" "$PROJ/errtrap" 2 -- bash -c 'perl -e "setpgrp(0,0); exec @ARGV" sh -c "perl -e \"sleep 60\" \"\$0\"; :" "$1"; exit $?' x "$mark" \
    >/dev/null 2>"$PROJ/err" </dev/null); RC=$?
  guard_stop
  ERR=$(cat "$PROJ/err")
  assert_equals "124" "$RC" "set -Eeuo pipefail + ERR trap caller: rc 124"
  assert_equals "" "$(grep -vx 0 "$PROJ/errtrap" 2>/dev/null)" "ERR trap caller: the trap never fired inside the wrapper or its sidecar"
  check_clean "$mark"
  check_line limit 2 "$mark"
  check_row limit 2 "$mark"
  rm -rf "$PROJ"
  # An ERR trap that exits wherever it fires below the caller: the wrapper and its
  # sidecar still kill, sweep and record.
  mark="$RUN_ID-errexit1"
  new_proj
  guard_start 20 "$mark"
  (cd "$PROJ" && bash -c 'set -Eeuo pipefail; trap "[ \$BASH_SUBSHELL = 0 ] || exit 1" ERR; source "$1"; shift; cdf_run_limited "$@"' \
    "$mark" "$RL" 2 -- bash -c 'perl -e "setpgrp(0,0); exec @ARGV" sh -c "perl -e \"sleep 60\" \"\$0\"; :" "$1"; exit $?' x "$mark" \
    >/dev/null 2>"$PROJ/err" </dev/null); RC=$?
  guard_stop
  ERR=$(cat "$PROJ/err")
  assert_equals "124" "$RC" "exiting ERR trap caller: rc 124"
  check_clean "$mark"
  check_line limit 2 "$mark"
  check_row limit 2 "$mark"
  rm -rf "$PROJ"
}

# A caller's IFS does not change the one-line record or the sweep.
ifs_case() {
  local label="$1" ifs="$2" mark="$3"
  new_proj
  guard_start 20 "$mark"
  (cd "$PROJ" && bash -c 'IFS="$2"; source "$1"; shift 2; cdf_run_limited "$@"' "$mark" "$RL" "$ifs" \
    2 -- bash -c 'perl -e "setpgrp(0,0); exec @ARGV" sh -c "perl -e \"sleep 60\" \"\$0\"; :" "$1"; exit $?' x "$mark" \
    >/dev/null 2>"$PROJ/err" </dev/null); RC=$?
  guard_stop
  ERR=$(cat "$PROJ/err")
  assert_equals "124" "$RC" "IFS $label: rc 124"
  check_clean "$mark"
  check_line limit 2 "$mark"
  check_row limit 2 "$mark"
  assert_contains "$(jq -r .cmd "$LEDGER" 2>/dev/null)" "^bash -c perl -e " "IFS $label: cmd joined by spaces"
  rm -rf "$PROJ"
}
test_caller_ifs() {
  ifs_case 'newline-tab' $'\n\t' "$RUN_ID-ifsnt"
  ifs_case 'colon' ':' "$RUN_ID-ifscolon"
}

# A straggler already out of reach (it left the group, its parent is gone) is not
# signalled, so nothing is recorded. The sleeper is ended here by its marker.
test_unreachable_straggler_not_recorded() {
  local mark="$RUN_ID-unreach"
  new_proj
  guard_start 20 "$mark"
  run_fn "$mark" 30 -- bash -c 'perl -e "setpgrp(0,0); exec @ARGV" perl -e "sleep 60" "$1" & exit 0' x "$mark"
  assert_equals "0" "$RC" "unreachable straggler: rc 0"
  assert_not_contains "$ERR" "KILLED" "unreachable straggler: no KILLED line"
  assert_file_not_exists "$LEDGER" "unreachable straggler: no row"
  pkill -KILL -f "$mark"
  guard_stop
  rm -rf "$PROJ"
}

# Twelve kills at once with a 4,500-character command: every row is whole JSON, cmd cut
# at 2,000 characters.
test_parallel_rows_stay_whole() {
  local mark="$RUN_ID-par" long i pids=""
  new_proj
  long=$(printf 'y%.0s' $(seq 1 4500))
  guard_start 25 "$mark"
  i=0
  while [ $i -lt 12 ]; do
    (cd "$PROJ" && bash -c 'source "$1"; shift; cdf_run_limited "$@"' "$mark" "$RL" 1 -- sh -c 'while :; do :; done' "$mark" "$long" \
      >/dev/null 2>/dev/null </dev/null) &
    pids="$pids $!"; i=$((i + 1))
  done
  for i in $pids; do wait "$i"; done
  guard_stop
  check_clean "$mark"
  assert_equals "12" "$(wc -l < "$LEDGER" | tr -d ' ')" "parallel: 12 rows"
  assert_equals "12" "$(jq -c . "$LEDGER" 2>/dev/null | wc -l | tr -d ' ')" "parallel: every row is valid JSON"
  assert_equals "2001" "$(jq -r '.cmd | length' "$LEDGER" 2>/dev/null | sort -u | tr '\n' ' ' | sed 's/ $//')" \
    "parallel: cmd cut at 2,000 characters plus the ellipsis"
  assert_contains "$(head -n 1 "$LEDGER" | jq -r .cmd)" "…$" "parallel: a cut cmd ends with …"
  rm -rf "$PROJ"
}

# --limit 00 is no limit; a launcher that kill -0 cannot signal (EPERM, here pid 1) is
# alive, not gone.
test_limit_zeros_and_eperm_launcher() {
  local mark="$RUN_ID-eperm"
  new_proj
  run_cli --limit 00 -- touch "$PROJ/ran"
  assert_equals "2" "$RC" "--limit 00: exit 2"
  assert_file_not_exists "$PROJ/ran" "--limit 00: nothing ran"
  if [ "$(id -u)" != 0 ]; then
    run_cli --limit 30 --launcher 1 -- true
    assert_equals "0" "$RC" "launcher pid 1 (EPERM): runs, rc 0"
    guard_start 15 "$mark"
    run_cli --limit 2 --launcher 1 -- sh -c 'while :; do :; done' "$mark"
    guard_stop
    assert_equals "124" "$RC" "launcher pid 1 (EPERM): killed at the limit, not as launcher-gone"
    check_clean "$mark"
  fi
  rm -rf "$PROJ"
}

# The temp state folder is removed on every exit path, including the wrapper being
# terminated.
test_state_folder_removed() {
  local mark="$RUN_ID-state" tmp w i
  new_proj
  tmp="$PROJ/tmp"; mkdir -p "$tmp"
  guard_start 20 "$mark"
  (cd "$PROJ" && TMPDIR="$tmp" "$RL" --limit 10 -- true </dev/null >/dev/null 2>&1)
  assert_equals "" "$(ls "$tmp")" "state folder: removed after normal completion"
  (cd "$PROJ" && TMPDIR="$tmp" "$RL" --limit 1 -- sh -c 'while :; do :; done' "$mark" </dev/null >/dev/null 2>&1)
  assert_equals "" "$(ls "$tmp")" "state folder: removed after a kill"
  (cd "$PROJ" && TMPDIR="$tmp" exec "$RL" --limit 3 -- sh -c 'while :; do :; done' "$mark" </dev/null >/dev/null 2>"$PROJ/err") & w=$!
  sleep 1
  # TERM to the CLI and to the wrapper subshell under it, as a signal to its process
  # group would (the command and the sidecar lead groups of their own).
  pkill -TERM -P "$w" 2>/dev/null; kill -TERM "$w" 2>/dev/null; wait "$w" 2>/dev/null
  i=0; while [ $i -lt 8 ] && [ -n "$(survivors "$mark")" ]; do sleep 1; i=$((i + 1)); done
  guard_stop
  assert_equals "" "$(ls "$tmp")" "state folder: removed when the wrapper is terminated"
  check_clean "$mark"
  rm -rf "$PROJ"
}

# Without jq the ledger line names jq.
test_missing_jq_named() {
  local mark="$RUN_ID-nojq" bin t p
  new_proj
  bin=$(mktemp -d)
  for t in bash sh ps awk sleep date mktemp rm cat perl pwd tr; do
    p=$(command -v "$t" 2>/dev/null) && case "$p" in /*) ln -s "$p" "$bin/$t" ;; esac
  done
  guard_start 15 "$mark"
  (cd "$PROJ" && PATH="$bin" "$bin/bash" "$RL" --limit 1 -- sh -c 'while :; do :; done' "$mark" </dev/null >/dev/null 2>"$PROJ/err"); RC=$?
  guard_stop
  assert_equals "124" "$RC" "no jq: still rc 124"
  check_clean "$mark"
  assert_contains "$(cat "$PROJ/err")" "^\[WATCHDOG\] could not write the ledger row to .*jq is not installed" "no jq: the ledger line names jq"
  rm -rf "$PROJ" "$bin"
}

test_usage_errors
test_caller_with_errexit
test_t1_limit_kills_tree
test_env_limit_and_ledger
test_term_ignored_gets_kill
test_t2_launcher_gone
test_t2_default_launchers
test_t3_normal_completion
test_stragglers_killed
test_stragglers_kill_and_sweep
test_t4_ledger_unwritable
test_t5_sweep
test_stdin_reaches_command
test_caller_errtrace
test_caller_ifs
test_unreachable_straggler_not_recorded
test_parallel_rows_stay_whole
test_limit_zeros_and_eperm_launcher
test_state_folder_removed
test_missing_jq_named

# Anything of this run still alive is a failure; kill it by pid.
LEFT=$(survivors "$RUN_ID-")
assert_equals "" "$LEFT" "no process of this run is left"
[ -n "$LEFT" ] && kill -KILL $LEFT 2>/dev/null
rm -rf "$GUARD_DIR"

ZONE_AFTER=$(zone_count)
if [ -n "$ZONE_BEFORE" ] && [ -n "$ZONE_AFTER" ]; then
  echo "  zone data.kalloc.1024: before=$ZONE_BEFORE after=$ZONE_AFTER"
  assert_equals "true" "$([ "$ZONE_AFTER" -le $((ZONE_BEFORE + 1000)) ] && echo true || echo false)" \
    "zone data.kalloc.1024 rises by no more than 1,000 over this file"
fi

run_tests
