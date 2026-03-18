# Glossary

Canonical terms for the Claude Dev Framework. All rules, hooks, documentation, and scripts should use these terms consistently.

## Framework Components

| Concept | Canonical Term | Description | Do Not Use |
|---------|---------------|-------------|------------|
| The overall system | **the framework** | The Claude Dev Framework as a whole — the concept, not a specific directory | "the system", "the tool" |
| The GitHub repository | **upstream repo** | The source of truth at `github.com/kraulerson/claude-dev-framework` | "global template repo", "global repo" |
| `~/.claude-dev-framework/` | **local clone** | The git clone of the upstream repo on each development machine | "framework clone", "global clone", "global version" |
| `.claude/framework/` in a project | **project copy** | The synced copy of hooks and rules inside a project directory | "synced copy", "local framework" |

## Hook Behavior

| Concept | Canonical Term | Description | Do Not Use |
|---------|---------------|-------------|------------|
| Hooks that hard-stop an action | **blocks** | Hooks that exit with code 2 or return `{"decision": "block"}`. The action cannot proceed. | Do not use "blocks" for advisory hooks |
| Hooks that inject context | **advises** or **warns** | Hooks that return `additionalContext` JSON. The action proceeds; Claude receives guidance. | "blocks" (when the hook is advisory) |

## Code Concepts

| Concept | Canonical Term | Description | Do Not Use |
|---------|---------------|-------------|------------|
| Files with code extensions (.py, .js, .ts, etc.) | **source files** | Matches the `is_source_file()` helper function | "source code changes", "implementation code", "source code" (as a noun for files) |
| Changes not requiring evaluation | **trivial** | A change is trivial if it touches only formatting, typos, config values, or version numbers and requires no design decisions | "routine", "mechanical" (as standalone synonyms) |

## Workflow Terms

| Concept | Canonical Term | Description | Do Not Use |
|---------|---------------|-------------|------------|
| Getting user confirmation to proceed | **user approval** | The user explicitly agrees to the proposed approach or action | "user confirms", "receiving user approval", "user confirmation" |

## Manifest Path Notation

| Context | Convention | Example |
|---------|-----------|---------|
| Human-readable docs (rules, README, guides) | Arrow notation | `manifest.json -> projectConfig -> changelogFile` |
| Code and comments in scripts/hooks | jq dot notation | `.projectConfig.changelogFile` |
