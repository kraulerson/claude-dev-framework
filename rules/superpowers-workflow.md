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
- Trivial changes (typo fixes, config updates)
- The user explicitly says "skip superpowers"
- Test files (TDD writes tests first, before the Superpowers cycle)
