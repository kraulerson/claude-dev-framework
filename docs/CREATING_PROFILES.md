# Creating Profiles

## When to Create a New Profile

When `detect-profile.sh` doesn't recognize your project type, it offers to create a new profile. You can also create profiles manually.

## YAML Format

```yaml
name: my-profile
description: One-line description of the project type
inherits: _base    # Always inherit from _base

rules:             # Additional rules beyond _base
  - version-bump
  - changelog-update

hooks:             # Additional hooks beyond _base
  - pre-commit-checks
  - branch-safety

discovery_questions:   # Optional — asked during init
  - key: my_question
    question: "What framework do you use?"
    examples: "Express, Django, Rails"

suggests:              # Optional — default config values
  sourceExtensions: [".py", ".js"]
  changelogFile: "CHANGELOG.md"
  protectedBranches: ["main"]
```

## Profile Inheritance

All profiles inherit from `_base.yml`, which provides:
- 9 universal rules (evaluate, plan, test-per-bugfix, test-strategy, context, session, superpowers, verify-after-complete, plan-closure)
- 5 universal hooks (session-start, enforce-evaluate, enforce-superpowers, stop-checklist, pre-compact-reminder)

Your profile adds project-type-specific rules and hooks on top.

## Contributing Profiles

After creating a profile that could help others:
```bash
bash ~/.claude-dev-framework/scripts/push-up.sh .claude/project/profiles/my-profile.yml --global
```
