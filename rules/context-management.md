RULE: Manage session context proactively — save history before compression, reload after, advise fresh sessions after second compression.

## Context Management

### Session Context Lifecycle
1. At ~85% context capacity: append a session summary to the context history file
2. After first compression: re-read context history, playbook, and active source files
3. After second compression: proactively advise the user to finish current task and start a fresh session

### Context History File
Location is configured in `manifest.json → projectConfig → contextHistoryFile` (resolved per branch).

### Enforcement
- `pre-compact-reminder.sh` warns before compression if context history hasn't been updated
- `stop-checklist.sh` blocks stopping in long sessions without a context history update
