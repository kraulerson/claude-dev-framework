RULE: Follow session discipline — commit before ending, use imperative commit messages, verify builds before moving on.

## Session Discipline

### Commit Before Ending
All work must be committed before the session ends. Uncommitted changes are lost context.

### Commit Message Format
Use imperative mood for commit messages: "Add feature" not "Added feature" or "Adds feature".

### Build Verification
After implementing a change, verify the build succeeds before moving to the next task. Do not assume code that compiles is correct.

### One Major Feature Per Session
As a rule of thumb, tackle one major feature per session to avoid context degradation.

### Session Handoff

When ending a session with work in progress:
- Document the current state: what was completed, what's pending, what's next
- Include specific file paths and line numbers if mid-implementation
- Note any decisions made during the session that aren't captured in code or commits
- Save to the context history file so the next session can pick up cleanly

A good handoff answers: "If I start a fresh session tomorrow, what do I need to know to continue this work without re-discovering anything?"
