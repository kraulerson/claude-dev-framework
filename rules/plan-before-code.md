RULE: For any change touching 3+ files, create an implementation plan before writing code. Use Superpowers writing-plans skill.

## Plan Before Code

### What This Rule Requires
For non-trivial changes (touching 3 or more files), create a structured implementation plan before writing any code. The plan should cover: files affected, approach, risks, testing strategy.

### How to Plan
Use the Superpowers `writing-plans` skill, which produces a step-by-step plan with exact file paths, code, and test commands.

### Acceptance Criteria

Every plan should define acceptance criteria before listing tasks:
- Use BDD format: Given [precondition] / When [action] / Then [outcome]
- Each task should reference which AC item it satisfies
- AC items become the basis for verification and testing

Example:
  AC-1: Given a logged-in user, When they tap the settings icon, Then the settings screen opens
  AC-2: Given the settings screen, When the user toggles dark mode, Then the UI updates immediately

### Boundaries

Plans should include a "Do Not Change" section listing files and directories that must NOT be modified during this change. This is particularly important for:
- Shared libraries used by multiple branches or platforms
- Database migrations that are already deployed
- Configuration files managed by other processes
- Any file the user explicitly marks as frozen

### When to Skip
- Changes touching 1-2 files
- The user has already provided a detailed plan
- Trivial changes (rename, formatting)
