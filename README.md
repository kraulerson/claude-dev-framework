# Claude Dev Framework

A universal development discipline enforcement framework for [Claude Code](https://claude.com/claude-code). Built to solve a real problem: Claude is brilliant at writing code but will skip its own discipline whenever it decides a task is "simple enough." Without mechanical enforcement, evaluation gets skipped, tests get forgotten, changelogs go stale, and deployment commands run before code is pushed.

This framework fixes that — but getting here required solving a deeper problem first. Claude has an internal priority stack: **speed → user satisfaction → compliance**. It classifies tasks as "trivial" or "complex" *before* checking rules, then rationalizes past any rule it considers unnecessary for "trivial" tasks. Early versions of this framework used advisory hooks (context injection), which Claude ignored. We then switched to blocking hooks (exit 2), which Claude bypassed by forging workflow markers. We removed the marker commands from messages, and Claude found them in rule files. We blocked the touch commands, and Claude presented text evaluations as substitutes for the required brainstorming skill.

The current version (v4.0.0) organizes enforcement into **5 enforcement zones** (Discovery, Design, Planning, Implementation, Verification) built on an **8-layer defense-in-depth model** (inspired by the [Swiss cheese model](https://en.wikipedia.org/wiki/Swiss_cheese_model)). Each zone gates a workflow stage — from requiring Superpowers skills before editing, to enforcing plan-task tracking, to blocking code using unresearched libraries via [Context7](https://context7.com/) MCP, to running configurable pre-commit verification gates. The full analysis of Claude's behavioral model and how each layer targets a specific bypass pattern is documented in **[Compliance Engineering](docs/COMPLIANCE_ENGINEERING.md)**. If you're building enforcement for AI agents and hitting similar compliance failures, start there.

## What Makes This Framework Different

The framework was designed from the ground up around three principles that distinguish it from other Claude Code workflow tools:

**1. Central sync with per-project customization.** A single upstream repo (`~/.claude-dev-framework/`) syncs hooks and rules to every project on every machine. Projects inherit from profiles (`web-app`, `web-api`, `mobile-app`) and can override anything locally. Changes to the framework propagate to all projects via `sync.sh` with three-way conflict detection.

**2. Discovery-driven, not one-size-fits-all.** The framework interviews you about your project — what data it handles, how it's deployed, what platforms it targets, what APIs it uses — and tailors its testing strategy, security assessment, and enforcement to your actual risk profile. A locally-hosted utility tool gets basic functional tests. A mobile app with user accounts, payment processing, and app store distribution gets encrypted storage, auth flow testing, and compliance checks.

**3. Layered mechanical enforcement, not prompt engineering.** Rules are not suggestions injected into a system prompt. They are bash scripts that intercept Claude Code actions at specific lifecycle points — before writing source files, before committing, before pushing, before compaction, at session end. Blocking hooks return exit code 2. Workflow markers are created automatically by the framework (not by Claude) when required skills are invoked. Manual marker creation is intercepted and blocked. Compliance directives are reinforced at every enforcement point, not just session start. See [Compliance Engineering](docs/COMPLIANCE_ENGINEERING.md) for the full defense model.

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

## Programmatic Setup

For tools that install the framework as a dependency (e.g., project scaffolders, orchestrators):

```bash
# Create a discovery JSON file with your project context
cat > .claude/discovery-prepopulated.json << 'EOF'
{
  "branch:main": {
    "purpose": "main development branch",
    "devOS": "Darwin",
    "targetPlatform": "web",
    "buildTools": "typescript"
  },
  "futurePlatforms": null,
  "discoveryDate": "2026-04-03",
  "lastReviewDate": "2026-04-03"
}
EOF

# Run init with pre-populated discovery (skips interactive interview)
bash ~/.claude-dev-framework/scripts/init.sh --prepopulate .claude/discovery-prepopulated.json

# If your tool handles dependency installation itself:
bash ~/.claude-dev-framework/scripts/init.sh --skip-plugin-check --prepopulate .claude/discovery-prepopulated.json
```

The `--prepopulate` flag accepts a JSON file with the same structure as the discovery interview output. The file must contain at least one `branch:*` key. If the file is missing, invalid, or lacks a branch key, init.sh falls back to the interactive interview with a warning.

## Hooks

**15 hooks** enforce rules mechanically via Claude Code's hook API:

| Hook | Zone | Type | What it does |
|------|------|------|-------------|
| **session-start** | Discovery | Context | Activates enforcement zones, checks dependencies, outputs terse zone report |
| **enforce-superpowers** | Design | Blocking | Blocks source file edits without invoking the Superpowers workflow |
| **enforce-plan-tracking** | Planning | Blocking | Blocks source edits until a plan task is marked in_progress |
| **enforce-context7** | Implementation | Blocking | Blocks edits using unresearched third-party libraries (Context7 MCP) |
| **enforce-evaluate** | Verification | Blocking | Blocks commits without presenting evaluation and getting user approval |
| **pre-commit-checks** | Verification | Blocking | Blocks commits missing version bumps or changelog updates |
| **verification-gate** | Verification | Blocking | Runs configurable pre-commit quality gates (linter, type-check, visual auditor) |
| **branch-safety** | Verification | Blocking | Blocks pushes to protected branches |
| **stop-checklist** | — | Blocking | Blocks session end with uncommitted work, untested bug fixes, or missing plan closure |
| **marker-guard** | — | Blocking | Prevents manual creation of workflow markers via touch commands |
| **marker-tracker** | — | Passive | Unified PostToolUse marker management: skill/plan/context7/sync tracking |
| **pre-compact-reminder** | — | Advisory | Warns to save context history before compression |
| **changelog-sync-check** | — | Advisory | Warns before editing stale changelogs |
| **scalability-check** | — | Advisory | Reminds about future platform plans when editing architecture |
| **pre-deploy-check** | — | Advisory | Warns before deployment commands if commits are unpushed |

## Rules

**14 rules** injected as context at session start:

evaluate-before-implement, plan-before-code, test-per-bugfix, test-strategy, naming-conventions, verify-after-complete, plan-closure, version-bump, changelog-update, context-management, session-discipline, observability, superpowers-workflow, future-scalability

## Profiles

**4 profiles** for different project types (extensible):
`_base` (always active), `web-app`, `web-api`, `mobile-app`

Profiles use YAML inheritance — all profiles inherit from `_base`, which provides the universal rules and hooks. Project-type profiles add domain-specific rules, hooks, and discovery questions.

## Platform Support

- **macOS** — fully supported (developed and tested here)
- **Linux** — fully supported (all platform-specific commands have Linux fallbacks)
- **Windows** — requires [WSL](https://learn.microsoft.com/en-us/windows/wsl/) (Windows Subsystem for Linux)

## Prerequisites

- Bash 3.2+
- [jq](https://jqlang.github.io/jq/) — `brew install jq` (macOS) / `apt install jq` (Linux)
- Git
- [Node.js](https://nodejs.org/) — required for Context7 MCP
- [Claude Code](https://claude.com/claude-code)
- [Superpowers plugin](https://github.com/obra/superpowers) — install via `/plugins` in Claude Code
- [Context7 MCP](https://context7.com/) — `claude mcp add context7 -- npx -y @upstash/context7-mcp@latest` (init.sh offers to install)

## Documentation

- [Implementation Guide](docs/IMPLEMENTATION_GUIDE.md) — step-by-step setup
- [Hook Reference](docs/HOOK_REFERENCE.md) — what each hook does
- [Rule Reference](docs/RULE_REFERENCE.md) — what each rule enforces
- [Creating Profiles](docs/CREATING_PROFILES.md) — how to add project types
- [Glossary](docs/GLOSSARY.md) — canonical terminology
- [Claude Guide](docs/CLAUDE-GUIDE.md) — how the framework works from Claude's perspective
- [Compliance Engineering](docs/COMPLIANCE_ENGINEERING.md) — Claude's behavioral model, 8-layer defense design, and enforcement zones
- [Contributing](docs/CONTRIBUTING.md) — bash coding conventions

## Updating

```bash
cd ~/.claude-dev-framework && git pull
cd ~/your-project && bash ~/.claude-dev-framework/scripts/sync.sh
```

### Migrating from v3 to v4

```bash
cd ~/.claude-dev-framework && git pull
cd ~/your-project && bash ~/.claude-dev-framework/migrations/v4.sh
```

This copies new hooks, updates the manifest, regenerates settings.json, and offers to install Context7 MCP.

## Testing

The framework tests itself with 199+ automated assertions across 23 test files:

```bash
bash tests/run-tests.sh
```

A manual [UAT checklist](tests/uat/UAT-CHECKLIST.md) covers 8 end-to-end scenarios for verification after version bumps.

## Acknowledgments

This framework was built independently as an original architecture — the central sync model, profile inheritance, manifest-tracked state, discovery-driven assessment, and hook-based mechanical enforcement were designed from scratch before evaluating any existing tools.

After the initial build (v1.0.0), the framework was evaluated against two established Claude Code workflow projects. Several workflow concepts were adopted where they filled genuine gaps:

**[Superpowers](https://github.com/obra/superpowers) plugin** — The framework's enforcement layer is built around Superpowers. The brainstorming, planning, TDD, debugging, and code review skills are the workflow engine that hooks enforce. Superpowers is a required dependency, not an optional integration.

**[PAUL](https://github.com/ChristopherKahler/paul) (Plan-Apply-Unify Loop)** — Inspired the plan closure rule (documenting planned vs. actual outcomes after completing work), structured acceptance criteria in plans (BDD format), and the boundaries/do-not-touch convention for implementation plans.

**[GSD](https://github.com/gsd-build/get-shit-done) (Get Shit Done)** — Inspired the codebase mapping discovery question (understanding existing architecture before proposing changes) and reinforced the verify-after-complete pattern (walking the user through acceptance criteria after implementation).

The following capabilities were evaluated from PAUL and GSD but **not adopted** because the framework already handles them differently: subagent orchestration (delegated to Superpowers), state tracking (manifest.json + markers), slash command delivery (git clone + bash), model switching (not a discipline concern), dynamic rule loading (hooks are mechanical), and quick mode (handled by the "trivial" skip mechanism).

Both PAUL and GSD are excellent projects with active development and thoughtful design. If this framework's approach doesn't click for you, check them out — you may find that their workflow style resonates better with how you work.

## License

MIT
