# Claude Dev Framework

A universal development discipline enforcement framework for [Claude Code](https://claude.com/claude-code). Mechanically enforces rules that Claude forgets during long sessions — evaluation before implementation, Superpowers workflows, test-per-bugfix, version bumps, changelog updates, and session management.

## Quick Start

```bash
# 1. Clone the framework
git clone https://github.com/kraulerson/claude-dev-framework.git ~/.claude-dev-framework

# 2. Navigate to your project
cd ~/your-project

# 3. Run setup
bash ~/.claude-dev-framework/scripts/init.sh
```

## How It Works

```
┌─────────────────────────────────────────────────┐
│  Upstream Repo (this repo)                       │
│  ~/.claude-dev-framework/ (local clone)          │
│  Universal hooks, rules, profiles                │
└──────────────────────┬──────────────────────────┘
                       │ init.sh / sync.sh
                       ▼
┌─────────────────────────────────────────────────┐
│  Your Project .claude/                           │
│  ├── framework/  ← synced from local clone        │
│  ├── project/    ← your project-specific rules   │
│  ├── manifest.json                               │
│  └── settings.json                               │
└─────────────────────────────────────────────────┘
```

**10 hooks** enforce rules mechanically via Claude Code's hook API:
- **evaluate-before-implement** — advises before committing without presenting evaluation
- **enforce-superpowers** — advises before writing source files without invoking Superpowers workflow
- **pre-commit-checks** — blocks commits missing version bumps or changelog updates
- **branch-safety** — blocks pushes to protected branches
- **stop-checklist** — blocks session end without committing work
- **session-start** — loads all rules as context at session start
- **pre-compact-reminder** — warns before context compression
- **changelog-sync-check** — warns before editing stale changelogs
- **scalability-check** — reminds about future platform considerations
- **sync-tracker** — tracks successful sync operations

**10 rules** injected as context (one-line summaries at session start, full text available):
evaluate-before-implement, plan-before-code, test-per-bugfix, version-bump, changelog-update, context-management, session-discipline, observability, superpowers-workflow, future-scalability

**4 profiles** for different project types (extensible):
`_base` (always active), `mobile-app`, `web-api`, `cli-tool`

## Prerequisites

- Bash 4+
- [jq](https://stedolan.github.io/jq/) — `brew install jq` (macOS) / `apt install jq` (Linux)
- Git
- [Claude Code](https://claude.com/claude-code)
- [Superpowers plugin](https://claude.com/claude-code) — install via `/plugins` in Claude Code

## Documentation

- [Implementation Guide](docs/IMPLEMENTATION_GUIDE.md) — step-by-step setup
- [Hook Reference](docs/HOOK_REFERENCE.md) — what each hook does
- [Rule Reference](docs/RULE_REFERENCE.md) — what each rule enforces
- [Creating Profiles](docs/CREATING_PROFILES.md) — how to add project types
- [Glossary](docs/GLOSSARY.md) — canonical terminology

## Updating

```bash
cd ~/.claude-dev-framework && git pull
cd ~/your-project && bash ~/.claude-dev-framework/scripts/sync.sh
```

## License

MIT
