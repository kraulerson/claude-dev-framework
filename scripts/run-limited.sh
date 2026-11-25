#!/usr/bin/env bash
# run-limited.sh — run a command under a wall-clock limit that kills its whole process
# tree, and kills it as well when the process that launched it is gone (#54).
#
# Sourced, it defines the function; executed, it is the CLI:
#   cdf_run_limited LIMIT [LAUNCHER] -- CMD [ARGS...]
#   scripts/run-limited.sh [--limit N] [--launcher PID] -- CMD [ARGS...]
#
# CMD runs as a background job under `set -m`, so it leads its own process group, with
# the caller's stdin (a closed one stays closed). A sidecar polls once a second; when
# LIMIT seconds have passed, or the launcher is gone, it sends TERM to the group, KILL
# 5 s later, then TERM and KILL to descendants that had left the group (found by
# walking `ps` from the group before the first signal). When CMD exits by itself but
# leaves part of its group running, those stragglers get the same TERM, KILL and sweep,
# recorded only when a live process was signalled. A process already re-parented to
# pid 1, or that left the group and outlived its parent, is out of its reach; the
# runaway-scan hook may report it.
#
# On a kill: one line on stderr,
#   [WATCHDOG] KILLED reason=<limit|launcher-gone|stragglers> pid=… pgid=… elapsed=… limit=… cmd=…
# and one JSON row appended to ${CDF_WATCHDOG_LEDGER:-.claude/watchdog.jsonl} (relative
# to the caller's working directory). If the row cannot be written, a second stderr
# line says so; the exit code is unchanged. cmd in the row is cut at 2,000 characters.
# Exit codes: 124 killed at the limit, 125 killed because the launcher is gone, 2 usage
# error (nothing runs), otherwise CMD's own (also when stragglers were killed).
# Limits: the limit is checked once a second against whole seconds, so a kill comes up
# to a second either side of it. CMD runs in a background process group, so at an
# interactive terminal it cannot read the terminal (it stops) and Ctrl-C does not
# reach it; the sidecar still ends it at the limit, or once the launcher exits.

_cdf_rl_usage() {
  echo "usage: cdf_run_limited LIMIT [LAUNCHER] -- CMD [ARGS...]" >&2
  echo "       run-limited.sh [--limit N] [--launcher PID] -- CMD [ARGS...]" >&2
  echo "       (CLI: N defaults to \$CDF_RUN_LIMIT; there is no other default; LAUNCHER defaults to the caller)" >&2
}

# Descendants of pid $1 and of every member of process group $1 that are outside that
# group, one per line.
_cdf_rl_departed() {
  ps -Ao pid=,ppid=,pgid= 2>/dev/null | awk -v pg="$1" '
    { par[$1] = $2; grp[$1] = $3; n++; pid[n] = $1 }
    END {
      seen[pg] = 1
      for (i = 1; i <= n; i++) if (grp[pid[i]] == pg) seen[pid[i]] = 1
      more = 1
      while (more) { more = 0
        for (i = 1; i <= n; i++) { p = pid[i]
          if (!(p in seen) && (par[p] in seen)) { seen[p] = 1; more = 1 } } }
      for (i = 1; i <= n; i++) { p = pid[i]; if ((p in seen) && grp[p] != pg) print p }
    }'
}

# _cdf_rl_end REASON ELAPSED — the kill and the record, for the sidecar (limit,
# launcher-gone) and for the wrapper (stragglers). Reads child, limit, launcher, ledger
# and the command ("$@") from the caller. TERM to the group, KILL 5 s later, then TERM
# and KILL (5 s apart) to the descendants that had left it, found before the first
# signal; then one ledger row and one stderr line.
_cdf_rl_end() {
  local reason="$1" elapsed="$2" departed="" i=0 cmd="" ledger_failed="" signalled=0
  shift 2
  departed=$(_cdf_rl_departed "$child")
  kill -TERM -- "-$child" 2>/dev/null && signalled=1
  i=0
  while [ "$i" -lt 5 ] && kill -0 -- "-$child" 2>/dev/null; do sleep 1; i=$((i + 1)); done
  kill -KILL -- "-$child" 2>/dev/null
  if [ -n "$departed" ] && _cdf_rl_alive $departed; then
    kill -TERM $departed 2>/dev/null && signalled=1
    i=0
    while [ "$i" -lt 5 ] && _cdf_rl_alive $departed; do sleep 1; i=$((i + 1)); done
    kill -KILL $departed 2>/dev/null
  fi
  # Stragglers already out of reach (gone, or left the group before the walk saw
  # them): nothing was signalled, so there is nothing to record.
  [ "$reason" = stragglers ] && [ "$signalled" = 0 ] && return 0
  cmd="$*"
  # Capped so a row stays one write: concurrent appends of rows over 4 KB interleave.
  [ "${#cmd}" -le 2000 ] || cmd="${cmd:0:2000}…"
  if ! command -v jq >/dev/null 2>&1; then
    ledger_failed=" (jq is not installed)"
  elif ! jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg reason "$reason" \
      --argjson pid "$child" --argjson elapsed "$elapsed" --argjson limit "$limit" \
      --arg cmd "$cmd" --arg cwd "$(pwd)" --argjson launcher "$launcher" \
      '{ts:$ts,reason:$reason,pid:$pid,pgid:$pid,elapsed:$elapsed,limit:$limit,cmd:$cmd,cwd:$cwd,launcher:$launcher}' \
      2>/dev/null >> "$ledger"; then
    ledger_failed=" "
  fi
  echo "[WATCHDOG] KILLED reason=$reason pid=$child pgid=$child elapsed=$elapsed limit=$limit cmd=$cmd" >&2
  [ -z "$ledger_failed" ] || echo "[WATCHDOG] could not write the ledger row to $ledger${ledger_failed% } (the kill above still happened)" >&2
}

# _cdf_rl_alive PID... — 0 when any of them still exists. kill -0 is the cheap check;
# when it fails, ps decides, since kill -0 also fails (EPERM) for a live process this
# user cannot signal (a root-owned launcher).
_cdf_rl_alive() {
  local p=""
  for p in "$@"; do
    kill -0 "$p" 2>/dev/null && return 0
    ps -p "$p" >/dev/null 2>&1 && return 0
  done
  return 1
}

# The body runs in a subshell, so `set -m`, the options and traps set here and IFS never
# reach the caller. The caller's own would otherwise reach the body: errexit or an ERR
# trap ends it on the non-zero statuses it expects (wait on a killed job, kill on a
# group already gone) before it kills or records, and an IFS without a blank breaks
# the one-line record and the sweep's word splitting.
cdf_run_limited() (
  set +eE
  trap - ERR
  IFS=$' \t\n'
  limit="${1:-}"
  launcher="$$"
  [ $# -gt 0 ] && shift
  if [ $# -gt 0 ] && [ "$1" != "--" ]; then launcher="$1"; shift; fi
  if [ "${1:-}" != "--" ]; then _cdf_rl_usage; exit 2; fi
  shift
  if [ $# -eq 0 ]; then _cdf_rl_usage; exit 2; fi
  case "$limit" in ''|*[!0-9]*) echo "cdf_run_limited: LIMIT must be a whole number of seconds above 0, got '$limit'" >&2; _cdf_rl_usage; exit 2 ;; esac
  case "$launcher" in ''|*[!0-9]*|0) echo "cdf_run_limited: LAUNCHER must be a pid, got '$launcher'" >&2; _cdf_rl_usage; exit 2 ;; esac
  if [ "${#limit}" -gt 9 ]; then echo "cdf_run_limited: LIMIT is too large: $limit" >&2; exit 2; fi
  if ! [ "$limit" -gt 0 ]; then
    echo "cdf_run_limited: LIMIT must be a whole number of seconds above 0, got '$limit'" >&2; _cdf_rl_usage; exit 2
  fi
  if ! _cdf_rl_alive "$launcher"; then
    echo "cdf_run_limited: launcher pid $launcher is not running; nothing was run" >&2; exit 2
  fi
  ledger="${CDF_WATCHDOG_LEDGER:-.claude/watchdog.jsonl}"
  case "$ledger" in /*) ;; *) ledger="$(pwd)/$ledger" ;; esac
  state=$(mktemp -d "${TMPDIR:-/tmp}/cdf-run-limited.XXXXXX") || { echo "cdf_run_limited: mktemp failed; nothing was run" >&2; exit 2; }
  # The state folder goes on every exit; a signal to the wrapper ends the wrapper only
  # (the command and the sidecar lead groups of their own, and the sidecar still ends
  # the command at the limit or once the launcher is gone).
  trap 'rm -rf "$state"' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM

  set -m
  start=$SECONDS
  # <&0: a background job's stdin is /dev/null unless it is given one, even under set -m.
  # A closed stdin stays closed.
  "$@" <&0 &
  child=$!

  # The sidecar: its own process group (set -m), stdin closed, SIGPIPE ignored so a
  # stderr reader that is gone cannot stop it before it has killed and recorded.
  (
    trap - EXIT HUP INT TERM
    trap '' PIPE
    reason=""
    while kill -0 "$child" 2>/dev/null; do
      elapsed=$((SECONDS - start))
      if [ "$elapsed" -ge "$limit" ]; then reason=limit; break; fi
      if ! _cdf_rl_alive "$launcher"; then reason=launcher-gone; break; fi
      sleep 1
    done
    [ -n "$reason" ] || exit 0
    # Committed to the kill: the wrapper's stop signal no longer applies.
    trap '' TERM
    echo "$reason" 2>/dev/null > "$state/reason"
    _cdf_rl_end "$reason" "$elapsed" "$@"
  ) </dev/null &
  sidecar=$!

  # 2>/dev/null: under set -m bash reports a job killed by a signal on wait's stderr.
  wait "$child" 2>/dev/null
  rc=$?
  if [ ! -f "$state/reason" ]; then
    kill -TERM -- "-$sidecar" 2>/dev/null
  fi
  wait "$sidecar" 2>/dev/null
  if [ -f "$state/reason" ]; then
    case "$(cat "$state/reason")" in
      limit) rc=124 ;;
      *) rc=125 ;;
    esac
  elif kill -0 -- "-$child" 2>/dev/null; then
    # CMD exited by itself and left part of its group running: end that part and what
    # it started, and keep CMD's own exit code.
    trap '' PIPE
    _cdf_rl_end stragglers "$((SECONDS - start))" "$@"
  fi
  exit "$rc"
)

_cdf_run_limited_main() {
  local limit="${CDF_RUN_LIMIT:-}" launcher="$PPID"
  while [ $# -gt 0 ]; do
    case "$1" in
      --limit) [ $# -ge 2 ] || { _cdf_rl_usage; return 2; }; limit="$2"; shift 2 ;;
      --launcher) [ $# -ge 2 ] || { _cdf_rl_usage; return 2; }; launcher="$2"; shift 2 ;;
      -h|--help) _cdf_rl_usage 2>&1; return 0 ;;
      --) break ;;
      *) _cdf_rl_usage; return 2 ;;
    esac
  done
  if [ -z "$limit" ]; then
    echo "run-limited.sh: no limit: pass --limit N or set CDF_RUN_LIMIT; nothing was run" >&2
    _cdf_rl_usage; return 2
  fi
  cdf_run_limited "$limit" "$launcher" "$@"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  _cdf_run_limited_main "$@"
  exit $?
fi
