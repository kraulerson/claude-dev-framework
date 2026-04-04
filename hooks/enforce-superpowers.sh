#!/usr/bin/env bash
# enforce-superpowers.sh — PreToolUse (Write|Edit) blocking hook
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 1
source "$SCRIPT_DIR/_preflight.sh"

preflight_init
preflight_skip_non_source && exit 0

HASH=$(get_project_hash)
[ -f "/tmp/.claude_superpowers_${HASH}" ] && exit 0

cat >&2 << 'MSG'
BLOCKED — Source file edit requires Superpowers workflow.

You MUST invoke superpowers:brainstorming before editing source files.
Do NOT present a text evaluation as a substitute.
Do NOT ask the user if you should proceed without brainstorming.
Do NOT skip this because the change seems simple.
Do NOT create the marker manually — it is created automatically when you invoke a Superpowers skill.

Invoke the skill now, then retry the edit.

COMPLIANCE REMINDER: Your obligation is compliance first, speed second. There is no task small enough to skip this requirement. Do not classify this change as trivial. Do not run a cost-benefit analysis against the process. Follow the required workflow, then proceed.
MSG
exit 2
