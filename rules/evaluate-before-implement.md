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
The evaluation marker is created automatically by the framework when the workflow is completed. Do not create it manually.
