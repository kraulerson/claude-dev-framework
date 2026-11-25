# Runaway-process safeguard — design (CDF 4.6.0, issue #54; also closes #53)

Owner decision 2026-11-12 (Karl): CDF ships the generic parts; Solo Orchestrator consumes them. Source brief: the Solo session's `2026-11-12-CDF-brief-runaway-safeguard.md` (copy under `~/dogfood-2026-10/cdf-work/impl-460/solo-brief.md`).

## Intent

On 2026-11-11 a `sh` grandchild of a Claude Code Bash-tool shell outlived the tool's 600 s timeout by 13 h 20 min, spun on one core, and exhausted a kernel zone (panic). Nothing in CDF or Solo could have ended it or even reported it. Two things close that: a wrapper that bounds a framework-launched run and kills the whole process tree when the run overruns or its launcher disappears, and a scan at every session start and stop that reports a runaway so a human can act at the next turn instead of the next morning.

## Goals / non-goals

- Goals: bound framework-launched runs (Solo's test aggregator, lints); report orphaned or CPU-pinned shells at every turn; never silent; bash 3.2 (macOS) and bash 5.2 (ubuntu runners); no `timeout`/`gtimeout`.
- Non-goals (phase 2, not here): rewriting every Bash tool call through the wrapper (PreToolUse `updatedInput`); any killing by the scan (a human change-card action); the host zone tripwire (launchd + zprint, outside both repos).
- Anti-goal: a reproduction of a suspected loop that runs unattended or inside a background agent.

## Part A — `scripts/run-limited.sh`

Sourceable and executable. Sourced, it defines `cdf_run_limited`; executed, it is the CLI.

```
cdf_run_limited <limit-seconds> -- <cmd> [args...]
scripts/run-limited.sh [--limit N] [--launcher PID] -- <cmd> [args...]
```

- The command runs in its own process group: a `set -m` subshell starts it as a background job (its pgid = its pid), measured to work on bash 3.2.57 and to let `kill -TERM -- -<pgid>` reach a `sh -c` grandchild.
- A sidecar (own background process, stdin `</dev/null`) polls once a second: when elapsed ≥ limit, or `kill -0 <launcher>` fails, it sends TERM to the group, waits 5 s, sends KILL, then sweeps descendants that left the group by walking `ps -Ao pid,ppid` from the child pid (TERM then KILL). A process already re-parented to pid 1 is Part B's job.
- Launcher: `--launcher PID` / second argument of the function; default `$$` of the caller. `CDF_RUN_LIMIT` is the default limit for the CLI; with neither, usage error (exit 2), nothing runs.
- Exit codes: 124 killed at the limit; 125 killed because the launcher died; otherwise the command's own exit code; 2 usage.
- On a kill, exactly one stderr line: `[WATCHDOG] KILLED reason=<limit|launcher-gone> pid=<pid> pgid=<pgid> elapsed=<s> limit=<s> cmd=<argv>` and one JSON row `{"ts","reason","pid","pgid","elapsed","limit","cmd","cwd","launcher"}` appended to the ledger `${CDF_WATCHDOG_LEDGER:-.claude/watchdog.jsonl}` (relative to the caller's cwd). If the row cannot be written: one stderr line saying so, the kill still happens, the exit code is still 124/125.
- Normal completion: no row, no stderr line, the sidecar is stopped.
- The ledger is an audit file: `Edit(/.claude/watchdog.jsonl)` joins the generated deny rules and the path joins config-guard's protected files beside `approvals.jsonl` (reads pass; the wrapper's own append is a redirect inside the script, not in the command text).

## Part B — `hooks/runaway-scan.sh`

Registered by `generate_settings_json` on **SessionStart** and **Stop** (two entries for one script, as record-approval is emitted beside enforce-evaluate); `timeout` 10, no `onFailure` (no effect on Stop; a report must never block).

- One `ps -Ao pid,ppid,pgid,etime,%cpu,command` read. Budget ≤ 30 ms for the whole hook on this Mac; measure and state the figure. A process is reported when (a) its command names this project's path (`$CLAUDE_PROJECT_DIR` or cwd) OR it is `sh`/`bash`/`perl`/`python3` with ppid 1, AND (b) etime > 10 min (`[[dd-]hh:]mm:ss`) OR %cpu > 90. The hook's own ancestry (its pid chain) is excluded.
- Output: JSON on stdout, exit 0: `{"systemMessage": "<one [ORPHAN] line per process, joined by newlines>"}` so the user sees it; on SessionStart additionally `hookSpecificOutput.additionalContext` with the same text so Claude sees it. Nothing is printed when nothing matched — never "clean".
- `ps` failure or empty output → `{"systemMessage":"[ORPHAN] not scanned: <why>"}`.
- Darwin: when `zprint` is available and `data.kalloc.1024` in-use (column 7) exceeds 5,000, add `[ZONE] data.kalloc.1024 in use: N (panic at 21,257,712 on 2026-11-11)`. Measure `zprint`'s cost; if it alone exceeds 20 ms, run it on SessionStart only and say so in HOOK_REFERENCE. Linux: on SessionStart only, add `[ZONE] data.kalloc.1024 not applicable on this OS`.
- Report only. Killing is a human change-card action; the message says so.

## Part C — `sync.sh` ordering (#53)

`scripts/sync.sh` pulls the live install (line 22) after sourcing `_shared.sh` (line 7), so the first sync after a release generates settings with the previous generator. Move the `source` after the pull (nothing in between needs it). Test with a lab clone whose `origin/main` carries a marker in `generate_settings_json`.

## Version and docs

`FRAMEWORK_VERSION` 4.6.0. HOOK_REFERENCE: a `run-limited.sh` section (library, not a hook) and a `runaway-scan` section; the failure-policy list gains runaway-scan under "No failure policy (timeout only)"; README hook list and count; UAT rows for T1 and T6. Solo's contract: names, ledger path, exit codes as above, tag `v4.6.0`.

## Left to the builder

The exact sidecar/flag-file mechanics, the descendant walk, etime parsing, the test harness for planted processes (every spinner bounded by an outer limit of the test's own; zone counter sampled before and after on Darwin), and the `systemMessage` field's exact placement per the hooks reference (fetch https://code.claude.com/docs/en/hooks.md; the local copies were cleaned from /tmp).

## Revisions after review (2026-11-24, owner rulings and adversarial review)

These supersede the parts above where they differ.

- **Part A, stdin (review 1):** the command starts as `"$@" <&0 &`. A background job's stdin is /dev/null unless it is given one, even under `set -m`, so `run-limited.sh -- jq . < f` read nothing. A closed stdin stays closed.
- **Part A, the caller's shell state:** the subshell body starts with `set +eE; trap - ERR; IFS=$' \t\n'`. A caller's errexit or ERR trap ended the wrapper or sidecar on statuses they expect; an IFS without a blank broke the one-line record and the sweep.
- **Part A, stragglers (owner ruling A; review 3):** when the command exits by itself and its process group still has members, they get the same TERM, KILL and sweep, recorded as reason `stragglers` only when at least one live process was signalled; the exit code stays the command's own. A child that left the group and outlived the command is out of reach and is not recorded.
- **Part A, other review fixes:** `cmd` in the row is cut at 2,000 characters (with `…`) so rows stay one write; `--limit 00` is a usage error; a launcher is alive while `kill -0` succeeds or `ps -p` lists it (EPERM); the temp state folder is removed on every exit (EXIT trap; TERM, INT and HUP end the wrapper only); the ledger line names jq when jq is missing.
- **Part B, once per session (owner ruling B):** a process above 90 % CPU is reported at every turn; one matched by age alone once per session, through a seen-file `${TMPDIR:-/tmp}/cdf-runaway-seen.<uid>.<session_id>` the hook creates. A seen-file that cannot be written or is a symlink, or an input without `session_id`: report every turn and say so in one line.
- **Part B, the incident's shape (review 6a):** whatever its parent, an `sh`, `bash`, `perl` or `python3` above 90 % CPU and older than 10 minutes is reported. On 2026-11-11 the `sh` had a live `bash` ← `zsh` parent chain, so the "parent pid 1" rule missed it.
- **Part B, other review fixes:** Claude Code's own processes (program `claude`) are skipped; the project path loses a trailing slash and needs a boundary on both sides.
- **Part B, zone threshold (review 6f):** `${CDF_ZONE_WARN:-50000}` instead of 5,000. The reference Mac idles near 20,000 with no runaway.
- **Settings merge, monotonic (review 7, #51):** when a regeneration wrote no `onFailure` anywhere, its entries that carry a timeout keep the `onFailure` already in `settings.json`, matched by event and hook file name, with one stderr line; nothing else is carried. A Bash write after `cd .claude` is still a gap (#57).
- **Upgrade from 4.5.0:** 4.5.0's `sync.sh` loads its generator before pulling, so the first sync to 4.6.0 needs `git -C ~/.claude-dev-framework pull` first, or a second `sync.sh` run.

