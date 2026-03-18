# Claude Dev Framework

A universal development discipline enforcement framework for [Claude Code](https://claude.com/claude-code). Built to solve a real problem: Claude is brilliant at writing code but forgets its own discipline during long sessions. Without mechanical enforcement, evaluation gets skipped, tests get forgotten, changelogs go stale, and deployment commands run before code is pushed.

This framework fixes that. It uses Claude Code's hook API to mechanically enforce development rules — not through prompts that Claude can rationalize away, but through hooks that fire automatically at the right moments. Advisory hooks remind Claude to follow the workflow. Blocking hooks hard-stop actions that would violate project requirements. The result is consistent, disciplined development across every session, every project, every machine.

## What Makes This Framework Different

The framework was designed from the ground up around three principles that distinguish it from other Claude Code workflow tools:

**1. Central sync with per-project customization.** A single upstream repo (`~/.claude-dev-framework/`) syncs hooks and rules to every project on every machine. Projects inherit from profiles (`mobile-app`, `web-api`, `cli-tool`) and can override anything locally. Changes to the framework propagate to all projects via `sync.sh` with three-way conflict detection.

**2. Discovery-driven, not one-size-fits-all.** The framework interviews you about your project — what data it handles, how it's deployed, what platforms it targets, what APIs it uses — and tailors its testing strategy, security assessment, and enforcement to your actual risk profile. A locally-hosted utility tool gets basic functional tests. A mobile app with user accounts, payment processing, and app store distribution gets encrypted storage, auth flow testing, and compliance checks.

**3. Mechanical enforcement via hooks, not prompt engineering.** Rules are not suggestions injected into a system prompt. They are bash scripts that intercept Claude Code actions at specific lifecycle points — before writing source files, before committing, before pushing, before compaction, at session end. Advisory hooks inject context. Blocking hooks return exit code 2. Claude cannot skip them.

## The Development Workflow

The framework enforces a complete development loop:

```
evaluate -> plan (AC + boundaries) -> implement -> verify -> close
```

1. **Evaluate** — before implementing, present pros/cons/alternatives and get user approval
2. **Plan** — for non-trivial work, create a structured plan with acceptance criteria and boundaries (files not to touch)
3. **Implement** — write source files through the Superpowers workflow (brainstorm/plan/implement)
4. **Verify** — after completing planned work, walk the user through verifying each acceptance criterion
5. **Close** — document the outcome: planned vs. actual, decisions made, issues deferred

Each step is enforced by hooks and tracked by markers. After each commit, markers reset so the next change goes through the full workflow again.

## Architecture

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
│  ├── framework/  ← synced from local clone       │
│  ├── project/    ← your project-specific rules   │
│  ├── manifest.json                               │
│  └── settings.json                               │
└─────────────────────────────────────────────────┘
```

## Quick Start

```bash
# 1. Clone the framework
git clone https://github.com/kraulerson/claude-dev-framework.git ~/.claude-dev-framework

# 2. Navigate to your project
cd ~/your-project

# 3. Run setup
bash ~/.claude-dev-framework/scripts/init.sh
```

## Hooks

**11 hooks** enforce rules mechanically via Claude Code's hook API:

| Hook | Type | What it does |
|------|------|-------------|
| **session-start** | Context | Loads all rules, injects marker instructions, checks framework freshness |
| **enforce-evaluate** | Advisory | Advises before committing without presenting evaluation |
| **enforce-superpowers** | Advisory | Advises before writing source files without Superpowers workflow |
| **pre-commit-checks** | Blocking | Blocks commits missing version bumps or changelog updates |
| **branch-safety** | Blocking | Blocks pushes to protected branches |
| **stop-checklist** | Blocking | Blocks session end with uncommitted work, untested bug fixes, or missing plan closure |
| **pre-compact-reminder** | Advisory | Warns to save context history before compression |
| **changelog-sync-check** | Advisory | Warns before editing stale changelogs |
| **scalability-check** | Advisory | Reminds about future platform plans when editing architecture |
| **pre-deploy-check** | Advisory | Warns before deployment commands if commits are unpushed |
| **sync-tracker** | Passive | Tracks sync operations and clears markers after commits |

## Rules

**13 rules** injected as context at session start:

evaluate-before-implement, plan-before-code, test-per-bugfix, test-strategy, verify-after-complete, plan-closure, version-bump, changelog-update, context-management, session-discipline, observability, superpowers-workflow, future-scalability

## Profiles

**4 profiles** for different project types (extensible):
`_base` (always active), `mobile-app`, `web-api`, `cli-tool`

Profiles use YAML inheritance — all profiles inherit from `_base`, which provides the universal rules and hooks. Project-type profiles add domain-specific rules, hooks, and discovery questions.

## Platform Support

- **macOS** — fully supported (developed and tested here)
- **Linux** — fully supported (all platform-specific commands have Linux fallbacks)
- **Windows** — requires [WSL](https://learn.microsoft.com/en-us/windows/wsl/) (Windows Subsystem for Linux)

## Prerequisites

- Bash 3.2+
- [jq](https://jqlang.github.io/jq/) — `brew install jq` (macOS) / `apt install jq` (Linux)
- Git
- [Claude Code](https://claude.com/claude-code)
- [Superpowers plugin](https://claude.com/claude-code) — install via `/plugins` in Claude Code

## Documentation

- [Implementation Guide](docs/IMPLEMENTATION_GUIDE.md) — step-by-step setup
- [Hook Reference](docs/HOOK_REFERENCE.md) — what each hook does
- [Rule Reference](docs/RULE_REFERENCE.md) — what each rule enforces
- [Creating Profiles](docs/CREATING_PROFILES.md) — how to add project types
- [Glossary](docs/GLOSSARY.md) — canonical terminology
- [Claude Guide](docs/CLAUDE-GUIDE.md) — how the framework works from Claude's perspective
- [Contributing](docs/CONTRIBUTING.md) — bash coding conventions

## Updating

```bash
cd ~/.claude-dev-framework && git pull
cd ~/your-project && bash ~/.claude-dev-framework/scripts/sync.sh
```

## Testing

The framework tests itself with 59 automated assertions across 11 test files:

```bash
bash tests/run-tests.sh
```

A manual [UAT checklist](tests/uat/UAT-CHECKLIST.md) covers 8 end-to-end scenarios for verification after version bumps.

## Acknowledgments

This framework was built independently as an original architecture — the central sync model, profile inheritance, manifest-tracked state, discovery-driven assessment, and hook-based mechanical enforcement were designed from scratch before evaluating any existing tools.

After the initial build (v1.0.0), the framework was evaluated against two established Claude Code workflow projects. Several workflow concepts were adopted where they filled genuine gaps:

**[Superpowers](https://github.com/anthropics/claude-code) plugin** — The framework's enforcement layer is built around Superpowers. The brainstorming, planning, TDD, debugging, and code review skills are the workflow engine that hooks enforce. Superpowers is a required dependency, not an optional integration.

**[PAUL](https://github.com/cline/PAUL) (Plan-Apply-Unify Loop)** — Inspired the plan closure rule (documenting planned vs. actual outcomes after completing work), structured acceptance criteria in plans (BDD format), and the boundaries/do-not-touch convention for implementation plans.

**[GSD](https://github.com/fredheir/get-shit-done) (Get Shit Done)** — Inspired the codebase mapping discovery question (understanding existing architecture before proposing changes) and reinforced the verify-after-complete pattern (walking the user through acceptance criteria after implementation).

The following capabilities were evaluated from PAUL and GSD but **not adopted** because the framework already handles them differently: subagent orchestration (delegated to Superpowers), state tracking (manifest.json + markers), slash command delivery (git clone + bash), model switching (not a discipline concern), dynamic rule loading (hooks are mechanical), and quick mode (handled by the "trivial" skip mechanism).

Both PAUL and GSD are excellent projects with active development and thoughtful design. If this framework's approach doesn't click for you, check them out — you may find that their workflow style resonates better with how you work.

## License

MIT
