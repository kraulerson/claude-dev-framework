RULE: Use the Superpowers plugin workflow (brainstorm → plan → implement) for all non-trivial work. Do not skip it.

## Superpowers Workflow

### What This Rule Requires
Before writing source files for any non-trivial task, invoke the appropriate Superpowers skill:
- **Brainstorming** — for new features, design decisions, creative work
- **Writing Plans** — for multi-step implementation tasks
- **TDD** — for test-driven development cycles
- **Debugging** — for investigating bugs and unexpected behavior
- **Code Review** — after completing major implementation steps

### Marker
After invoking any Superpowers skill, create the marker:
`touch /tmp/.claude_superpowers_{project_hash}`

### When to Skip
- Only when the user explicitly says "skip superpowers" or "this is trivial". Claude must not decide on its own that a change is trivial enough to skip.
- Test files (TDD writes tests first, before the Superpowers cycle)
