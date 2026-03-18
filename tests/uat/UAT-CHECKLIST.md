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

---

## Notes

_Record any issues, unexpected behavior, or observations here:_

