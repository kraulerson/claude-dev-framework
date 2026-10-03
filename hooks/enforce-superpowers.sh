#!/usr/bin/env bash
# enforce-superpowers.sh — PreToolUse (Write|Edit) blocking hook
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 1
source "$SCRIPT_DIR/_preflight.sh"

preflight_init
preflight_skip_non_source && exit 0
# A file outside the project (a scratch or temp file) is not the project's source.
path_outside_project "$_PF_FILE_PATH" && exit 0

HASH=$(get_project_hash)
[ -f "/tmp/.claude_superpowers_${HASH}" ] && exit 0

# Without the plugin no Superpowers skill exists to invoke, so say so instead of
# sending the agent after a skill the Skill tool will call unknown.
if ! superpowers_enabled; then
  cat >&2 << MSG
BLOCKED — Source file edit requires the Superpowers workflow, but the Superpowers plugin is not enabled in this Claude Code configuration (checked: $(plugin_settings_files | tr '\n' ' ')), so its skills cannot be invoked.

Stop and ask the user to install it, then start a new session:
claude plugin install --scope user superpowers@claude-plugins-official
Do NOT create the marker manually, and do not edit around this check.
MSG
  exit 2
fi

cat >&2 << 'MSG'
BLOCKED — Source file edit requires Superpowers workflow.

Invoke the Superpowers skill for the work in hand before editing source files: superpowers:brainstorming for a change with no approved design yet; for a design the user has already approved, the skill that implements it (for example superpowers:test-driven-development or superpowers:executing-plans).
The marker this check reads is set when any Superpowers skill is invoked. It is cleared by a successful commit, by a new or cleared session, and at session end; a skill invoked before any of those has to be invoked again.
Do NOT present a text evaluation as a substitute.
Do NOT ask the user if you should proceed without the skill.
Do NOT skip this because the change seems simple.
Do NOT create the marker manually — it is created automatically when you invoke a Superpowers skill.

Invoke the skill now, then retry the edit.

COMPLIANCE REMINDER: Your obligation is compliance first, speed second. There is no task small enough to skip this requirement. Do not classify this change as trivial. Do not run a cost-benefit analysis against the process. Follow the required workflow, then proceed.
MSG
exit 2
