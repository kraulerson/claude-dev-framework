#!/usr/bin/env bash
# runaway-scan.sh — SessionStart and Stop: report orphaned or CPU-pinned processes (#54)
# One `ps` read. A process is reported when (a) its command names this project's path,
# or it is sh, bash, perl or python3 with parent pid 1, AND (b) it has run more than
# 10 minutes or sits above 90 % CPU; and, whatever its parent, when it is sh, bash, perl
# or python3 both above 90 % CPU and older than 10 minutes (2026-11-11: an sh at 100 %
# under a live bash <- zsh chain). The hook, its ancestors and its children, and Claude
# Code's own processes (program `claude`), are skipped. A process above 90 % CPU is reported at every turn; one matched by age alone,
# once per session: its pid and command go to a seen-file in the per-user temp folder,
# ${TMPDIR:-/tmp}/cdf-runaway-seen.<uid>.<session_id>, created here. When that file
# cannot be written (or the input has no session_id) every turn reports, and says so.
# Report only: ending a process is the user's decision (a change-card action).
# Output: {"systemMessage": …} for the user; on SessionStart also
# hookSpecificOutput.additionalContext for Claude. Nothing when nothing matched. A `ps`
# that is missing, fails or lists nothing says "not scanned".
# The kernel zone that panicked on 2026-11-11 (data.kalloc.1024) is read on
# SessionStart only, on Darwin: `zprint` takes ~190 ms, and Stop fires every turn.
# The zone line appears above ${CDF_ZONE_WARN:-50000} (this Mac idles well above 5,000).
# Always exits 0; registered with a timeout and no failure policy.

INPUT=$(cat)
EVENT=Stop
[[ "$INPUT" =~ \"hook_event_name\"[[:space:]]*:[[:space:]]*\"SessionStart\" ]] && EVENT=SessionStart
PROJ="${CLAUDE_PROJECT_DIR:-$(pwd)}"
PROJ="${PROJ%/}"

SID=""
[[ "$INPUT" =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && SID="${BASH_REMATCH[1]}"
SID="${SID//[^A-Za-z0-9_.-]/_}"
SEEN=""
SEEN_WHY=""
if [ -z "$SID" ]; then
  SEEN_WHY="the hook input has no session_id"
else
  SEEN="${TMPDIR:-/tmp}"
  SEEN="${SEEN%/}/cdf-runaway-seen.$UID.$SID"
  if [ -L "$SEEN" ]; then
    SEEN_WHY="$SEEN is a symlink"
    SEEN=""
  elif ! { : >> "$SEEN"; } 2>/dev/null; then
    SEEN_WHY="$SEEN cannot be written"
    SEEN=""
  fi
fi

WHY=""
command -v ps >/dev/null 2>&1 || WHY="ps not found"

ZONE=""
ZONE_WARN="${CDF_ZONE_WARN:-50000}"
case "$ZONE_WARN" in ''|*[!0-9]*) ZONE_WARN=50000 ;; esac
if [ "$EVENT" = SessionStart ]; then
  if [ "$(uname -s 2>/dev/null)" = Darwin ]; then
    if command -v zprint >/dev/null 2>&1; then
      N=$(zprint 2>/dev/null | awk '$1 == "data.kalloc.1024" { print $7; exit }')
      case "$N" in
        ''|*[!0-9]*) ;;
        *) [ "$N" -gt "$ZONE_WARN" ] && ZONE="[ZONE] data.kalloc.1024 in use: $N (panic at 21,257,712 on 2026-11-11)" ;;
      esac
    fi
  else
    ZONE="[ZONE] data.kalloc.1024 not applicable on this OS"
  fi
fi

# ps straight into awk (they run side by side; Stop fires every turn), its exit code on
# a last line of its own.
{ [ -z "$WHY" ] && LC_ALL=C ps -Ao pid,ppid,pgid,etime,%cpu,command 2>/dev/null; echo "CDF_PS_RC $?"; } \
| awk -v self="$$" -v proj="$PROJ" -v why="$WHY" -v zone="$ZONE" -v event="$EVENT" \
      -v seen="$SEEN" -v seenwhy="$SEEN_WHY" '
  function secs(t,   d, n, p, s, i) {
    d = 0
    if (index(t, "-")) { d = substr(t, 1, index(t, "-") - 1); t = substr(t, index(t, "-") + 1) }
    n = split(t, p, ":"); s = 0
    for (i = 1; i <= n; i++) s = s * 60 + p[i]
    return d * 86400 + s
  }
  # The project path as a whole path in the command: at the start or after a blank, a
  # quote, = or :, and followed by /, a blank, a quote or the end, so /x/proj does not
  # match /x/proj-other or /other/x/proj.
  function names_proj(c,   i, at, pv, nx) {
    if (proj == "" || proj == "/") return 0
    at = 0
    while ((i = index(substr(c, at + 1), proj)) > 0) {
      at += i
      pv = (at == 1) ? "" : substr(c, at - 1, 1)
      nx = substr(c, at + length(proj), 1)
      if ((pv == "" || pv == " " || pv == "\t" || pv == "\"" || pv == "\047" || pv == "=" || pv == ":") \
          && (nx == "" || nx == "/" || nx == " " || nx == "\t" || nx == "\"" || nx == "\047")) return 1
    }
    return 0
  }
  function esc(s) {
    gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); gsub(/\t/, "\\t", s); gsub(/\n/, "\\n", s)
    gsub(/[\001-\037]/, "?", s)
    return s
  }
  /^CDF_PS_RC [0-9]+$/ { rc = $2; next }
  NR == 1 || NF < 6 { next }
  {
    rows++; all[rows] = $1; par[$1] = $2
    # Full parse only for a candidate: a child of pid 1, a row naming the project path or
    # one above 90 % CPU; a few rows out of hundreds.
    if (!($2 == 1 || $5 + 0 > 90 || (proj != "" && proj != "/" && index($0, proj)))) next
    c = $0
    for (k = 1; k <= 5; k++) sub(/^[ \t]*[^ \t]+/, "", c)
    sub(/^[ \t]+/, "", c)
    n++; pid[n] = $1; ppid[n] = $2; pgid[n] = $3; et[n] = $4; cpu[n] = $5; cmd[n] = c
  }
  END {
    if (why == "" && rc != 0) why = "ps failed (exit " rc ")"
    if (why == "" && rows == 0) why = "ps listed no processes"
    # The hook itself, its ancestors and its descendants (the subshells and ps it runs).
    p = self
    while (p != "" && !(p in mine)) { mine[p] = 1; if (!(p in par) || p == 1) break; p = par[p] }
    kid[self] = 1; more = 1
    while (more) { more = 0
      for (i = 1; i <= rows; i++) { q = all[i]; if (!(q in kid) && (par[q] in kid)) { kid[q] = 1; mine[q] = 1; more = 1 } } }
    # Age-only rows already reported this session: "pid command" lines.
    if (seen != "") { while ((getline l < seen) > 0) was[l] = 1; close(seen) }
    out = ""; aged = 0
    for (i = 1; i <= n; i++) {
      if (pid[i] in mine) continue
      w = cmd[i]; sub(/[ \t].*/, "", w); sub(/.*\//, "", w); sub(/^-/, "", w)
      if (w == "claude") continue
      shell = (w == "sh" || w == "bash" || w == "perl" || w == "python3")
      busy = cpu[i] + 0 > 90
      old = secs(et[i]) > 600
      a = names_proj(cmd[i]) || (ppid[i] == 1 && shell)
      b = old || busy
      if (!((a && b) || (shell && busy && old))) continue
      c = cmd[i]; if (length(c) > 200) c = substr(c, 1, 200) "..."
      if (!busy) {
        key = pid[i] " " c; gsub(/\t/, " ", key)
        if (key in was) continue
        if (seen != "") print key >> seen
        aged = 1
      }
      out = out (out == "" ? "" : "\n") "[ORPHAN] pid=" pid[i] " ppid=" ppid[i] " pgid=" pgid[i] " etime=" et[i] " cpu=" cpu[i] "% cmd=" c
    }
    if (seen != "") close(seen)
    if (aged && seenwhy != "") out = out "\n[ORPHAN] could not record reported processes (" seenwhy "), so one matched by age alone is reported at every turn."
    if (out != "") out = out "\n[ORPHAN] report only: nothing was killed. Ending a process is the user'"'"'s decision (a change-card action), e.g. kill <pid> after checking it."
    if (why != "") out = "[ORPHAN] not scanned: " why
    if (zone != "") out = out (out == "" ? "" : "\n") zone
    if (out == "") exit
    m = esc(out)
    if (event == "SessionStart")
      printf "{\"systemMessage\":\"%s\",\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"%s\"}}\n", m, m
    else
      printf "{\"systemMessage\":\"%s\"}\n", m
  }'
exit 0
