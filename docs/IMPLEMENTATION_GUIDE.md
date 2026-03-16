# Implementation Guide

## Prerequisites

1. **Bash 4+** — native on Linux, ships with macOS
2. **jq** — JSON processor: `brew install jq` (macOS) or `apt install jq` (Linux)
3. **Git** — version control
4. **Claude Code** — Anthropic's CLI tool
5. **Superpowers plugin** — install via Claude Code:
   - Run `claude`
   - Type `/plugins`
   - Search for `superpowers`
   - Install `superpowers@claude-plugins-official`

## New Project Setup

### 1. Clone the framework (one-time, per machine)

```bash
git clone https://github.com/kraulerson/claude-dev-framework.git ~/.claude-dev-framework
```

### 2. Navigate to your project

```bash
cd ~/your-project
```

### 3. Run init

```bash
bash ~/.claude-dev-framework/scripts/init.sh
```

The script will:
- Detect your project type (mobile app, web API, CLI tool, etc.)
- Ask discovery questions (all optional)
- Create `.claude/framework/` with hooks and rules
- Generate `manifest.json` and `settings.json`
- Verify Superpowers plugin is installed

### 4. Start a Claude Code session

```bash
claude
```

You should see the framework's rule summaries and marker instructions at session start.

## Existing Project Migration

If your project already has `.claude/`, `CLAUDE.md`, or custom hooks:

```bash
bash ~/.claude-dev-framework/scripts/init.sh
```

The script auto-detects existing config and enters migration mode:
1. **SCAN** — inventories existing files
2. **ANALYZE** — classifies conflicts
3. **REPORT** — shows findings
4. **BACKUP** — creates `.claude-backup/{timestamp}/` with restore script
5. **PLUGIN CHECK** — verifies Superpowers
6. **INSTALL** — merges framework (only touches `hooks` key in settings.json)
7. **VERIFY** — confirms installation

## Multi-Machine Setup

Clone the framework on each machine:
```bash
# Machine 1 (macOS)
git clone https://github.com/kraulerson/claude-dev-framework.git ~/.claude-dev-framework

# Machine 2 (Windows/WSL or Linux)
git clone https://github.com/kraulerson/claude-dev-framework.git ~/.claude-dev-framework
```

Each machine syncs independently. The project's `.claude/manifest.json` is committed per-branch.

## Updating the Framework

```bash
cd ~/.claude-dev-framework && git pull
cd ~/your-project && bash ~/.claude-dev-framework/scripts/sync.sh
```

The sync script compares file hashes, preserves local modifications, and handles conflicts interactively.

## Troubleshooting

- **Hooks not firing:** Claude Code snapshots hooks at startup. Restart the session.
- **jq not found:** Install jq (see Prerequisites).
- **Permission denied:** Run `chmod +x .claude/framework/hooks/*.sh`
- **Superpowers conflict:** There should be none — they use different hook events.
