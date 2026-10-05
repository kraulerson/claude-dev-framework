RULE: Before implementing any feature, bug fix, or change — evaluate feasibility, present pros/cons/alternatives, and get user approval.

## Evaluate Before Implement

### What This Rule Requires
Before writing any source files, you MUST:
1. Evaluate the request — is it feasible, does it fit the architecture, are there edge cases or risks?
2. Present your evaluation: pros, cons, effort estimate, and any concerns
3. Suggest better alternatives if they exist
4. Wait for user approval before proceeding

### When It Applies
- New features and functionality changes
- Bug fix approaches (not the fix itself — the approach)
- Refactoring and architectural changes
- Testing strategies
- Any work beyond trivial tasks (typo fixes, version bumps, config changes)

### When to Skip
- Trivial changes: typo fixes, config updates, version bumps
- The user explicitly says "skip evaluation" or "just do it"
- Emergency hotfixes where the user has already decided the approach

### Existing Codebase Awareness

For projects with existing code, the first evaluation or planning session should include understanding the current architecture, file structure, patterns, and conventions. This can be done through Superpowers brainstorming or by reading key files before proposing changes.

### Marker
The evaluation marker is created only by the user's answer to a question you record. Stage exactly the change to commit, write `.claude/pending-approval.json` with the Write tool in the schema-2 shape the `enforce-evaluate.sh` block message gives (option ids like A1/A2; at least one option that approves nothing), present the question and stop. The user replies with the option id; the framework shows them the question and the staged change and asks them to reply with the id again to confirm, and then `record-approval.sh` creates the marker, bound to that staged change. Commit it with a lone `git commit -m "…"`. You cannot create the marker yourself: `mark-evaluated.sh` is the user's own override for their separate terminal, and `marker-guard.sh` refuses `touch`, redirects and file tools aimed at the marker. If the user says "skip evaluation", record a question whose approving option says so; the user still picks it.
