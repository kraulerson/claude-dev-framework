RULE: Before implementing any feature, bug fix, or change — evaluate feasibility, present pros/cons/alternatives, and get user approval.

## Evaluate Before Implement

### What This Rule Requires
Before writing any implementation code, you MUST:
1. Evaluate the request — is it feasible, does it fit the architecture, are there edge cases or risks?
2. Present your evaluation: pros, cons, effort estimate, and any concerns
3. Suggest better alternatives if they exist
4. Wait for the user to confirm before proceeding

### When It Applies
- New features and functionality changes
- Bug fix approaches (not the fix itself — the approach)
- Refactoring and architectural changes
- Testing strategies
- Any work beyond trivial/routine tasks (typo fixes, version bumps, config changes)

### When to Skip
- Trivial changes: typo fixes, config updates, version bumps
- The user explicitly says "skip evaluation" or "just do it"
- Emergency hotfixes where the user has already decided the approach

### Marker
After presenting an evaluation AND getting user approval, create the marker:
`touch /tmp/.claude_evaluated_{project_hash}`
