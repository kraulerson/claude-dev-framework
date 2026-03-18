# Rule Reference

| Rule | Summary | Enforced By | When to Skip |
|------|---------|-------------|--------------|
| evaluate-before-implement | Present evaluation with pros/cons/alternatives before implementing | enforce-evaluate.sh + session-start.sh | Trivial changes, user says "skip" |
| plan-before-code | Create implementation plan for changes touching 3+ files | enforce-superpowers.sh + Superpowers plugin | 1-2 file changes, user provided plan |
| test-per-bugfix | Every bug fix must include a regression test | stop-checklist.sh | N/A — always required for bug fixes |
| test-strategy | Assess testing/security needs based on project risk profile during planning | session-start.sh (context injection) | Project already has current TEST-STRATEGY.md |
| version-bump | Bump version before committing source changes | pre-commit-checks.sh | Doc-only commits |
| changelog-update | Update changelog alongside source commits | pre-commit-checks.sh | Doc-only commits |
| context-management | Save context history before compression, reload after | pre-compact-reminder.sh + stop-checklist.sh | Short sessions |
| session-discipline | Commit before ending, imperative commit messages, verify builds | stop-checklist.sh | N/A |
| observability | Evaluate monitoring/logging needs, never swallow errors | session-start.sh (context injection) | Internal utilities |
| superpowers-workflow | Use Superpowers brainstorm/plan/implement for non-trivial work | enforce-superpowers.sh | Trivial changes, user says "skip" |
| verify-after-complete | Walk user through verifying acceptance criteria after completing planned work | session-start.sh (context injection) | Trivial changes, user says "skip" |
| plan-closure | Document outcome of Superpowers-planned work: planned vs. actual, decisions, deferred issues | stop-checklist.sh (advisory) | Trivial changes, user says "skip" |
| future-scalability | Consider future platform plans in architecture decisions | scalability-check.sh | No future platforms configured |
