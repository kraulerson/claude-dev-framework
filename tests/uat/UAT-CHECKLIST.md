# User Acceptance Testing Checklist

Run this manual walkthrough after each framework version bump on all development machines.

**Framework Version:** ___________
**Date:** ___________
**Machine:** ___________

---

## Scenario 1: Clean Project Setup

```
Given: A new empty git repo
When:  I run bash ~/.claude-dev-framework/scripts/init.sh
```

- [ ] Profile detection prompts correctly
- [ ] Discovery interview asks relevant questions
- [ ] `.claude/framework/` is populated with hooks and rules
- [ ] `.claude/manifest.json` is correct (version, profile, rules, hooks)
- [ ] `.claude/settings.json` has hook registrations
- [ ] Starting Claude Code shows the framework banner

## Scenario 2: Enforcement Fires Correctly

```
Given: A project with the framework installed
When:  I ask Claude to write code immediately
```

- [ ] enforce-superpowers fires (advisory, not hard block)
- [ ] enforce-evaluate fires before commit (advisory, not hard block)
- [ ] Both allow skip with user approval
- [ ] Markers are created after approval

## Scenario 3: Pre-Commit Checks Block Correctly

```
Given: A project with version-bump and changelog-update active
When:  I stage source files without changelog/version
```

- [ ] Commit is hard-blocked with a clear message
- [ ] After staging changelog + version files, commit succeeds

## Scenario 4: Stop Checklist Catches Incomplete Work

```
Given: Uncommitted source file changes
When:  Claude tries to end the session
```

- [ ] Hard-blocked with "Uncommitted source file changes"
- [ ] After committing, stop succeeds

## Scenario 5: Deployment Sequencing Check

```
Given: A remotely-deployed project with unpushed commits
When:  Claude suggests deployment or remote pull commands
```

- [ ] Advisory fires with "N unpushed commit(s) — push first"
- [ ] After pushing, deploy commands pass silently

## Scenario 6: Sync Preserves Local Modifications

```
Given: A locally modified hook in .claude/framework/hooks/
When:  sync.sh runs and the upstream version also changed
```

- [ ] Conflict prompt appears with options (take upstream / keep local / show diff)
- [ ] Choosing "keep local" preserves the modification
- [ ] Choosing "take upstream" replaces with the new version

## Scenario 7: Framework Stays Out of the Way

```
Given: Doc-only changes (editing README.md, config files)
```

- [ ] enforce-superpowers does NOT fire for doc/config files
- [ ] pre-commit-checks does NOT hard-block doc-only commits
- [ ] stop-checklist does NOT block when only docs are uncommitted

## Scenario 8: Multi-Machine Consistency

```
Given: Framework installed on two different development machines
When:  Same project initialized on both
```

- [ ] manifest.json is compatible across machines
- [ ] Hooks fire identically on both machines
- [ ] sync.sh updates both to the same version

## Scenario 9: Guard Hooks Fail Closed (Claude Code 2.1.295 or later)

```
Given: A scratch project with the framework installed by init.sh or sync.sh on Claude Code 2.1.295+
When:  In a terminal I run chmod -x .claude/framework/hooks/config-guard.sh, start Claude Code, and ask it to edit a source file
```

- [ ] The edit is refused, and the failure shown names config-guard.sh
- [ ] After chmod +x .claude/framework/hooks/config-guard.sh a retry is no longer refused for config-guard.sh (other gates may still ask for their own steps)

---

## Scenario 10: A Runaway Command Is Ended (run-limited.sh, T1)

```
Given: A scratch project folder with a .claude/ folder, the framework clone at 4.6.0 or later
When:  In a terminal in that folder I run ~/.claude-dev-framework/scripts/run-limited.sh --limit 2 -- bash -c 'sh -c "while :; do :; done" uat-spin; exit $?' and then echo $?
```

- [ ] It returns after about 2 seconds and the exit code printed is 124
- [ ] One line starting `[WATCHDOG] KILLED reason=limit` was printed
- [ ] `tail -n 1 .claude/watchdog.jsonl` shows a row with `"reason":"limit"` and `"limit":2`
- [ ] `pgrep -fl uat-spin` prints nothing

---

## Scenario 11: An Orphaned Shell Is Reported (runaway-scan, T6)

```
Given: A scratch project installed by init.sh, or by sync.sh at 4.6.0 or later (from 4.5.0: git -C ~/.claude-dev-framework pull first, or run sync.sh twice), so .claude/settings.json registers runaway-scan.sh
When:  In a terminal I run ( sh -c 'sleep 900; :' uat-orphan & ), wait 11 minutes, then send Claude a prompt in that project
```

- [ ] When Claude's turn ends, a message shows an `[ORPHAN] pid=… ppid=1 …` line naming `uat-orphan`, and a line saying nothing was killed
- [ ] A new session started in that project shows the same line at its start
- [ ] After `kill <pid>` (the pid in the message) the next turn shows no `[ORPHAN]` line

---

## Scenario 12: An Idle Orphan Is Reported Once per Session (runaway-scan)

```
Given: Scenario 11's orphan, still running and already reported once in this session
When:  I send Claude two more prompts in the same session, then start a new session in that project
```

- [ ] Neither of the two later turns shows the `uat-orphan` line again
- [ ] The new session shows it once at its start
- [ ] `kill <pid>` afterwards (the pid in the message)

---

## Scenario 13: Stragglers Are Ended (run-limited.sh)

```
Given: A scratch project folder with a .claude/ folder, the framework clone at 4.6.0 or later
When:  In a terminal in that folder I run ~/.claude-dev-framework/scripts/run-limited.sh --limit 30 -- bash -c 'perl -e "sleep 60" uat-straggler & exit 0' and then echo $?
```

- [ ] It returns within about 6 seconds and the exit code printed is 0
- [ ] One line starting `[WATCHDOG] KILLED reason=stragglers` was printed
- [ ] `tail -n 1 .claude/watchdog.jsonl` shows a row with `"reason":"stragglers"`
- [ ] `pgrep -fl uat-straggler` prints nothing

---

## Notes

_Record any issues, unexpected behavior, or observations here:_

