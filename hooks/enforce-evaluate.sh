#!/usr/bin/env bash
# enforce-evaluate.sh — PreToolUse (Bash) blocking hook
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 1

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")

# Overriding core.hooksPath disables git hooks entirely. This is checked BEFORE the
# commit gate below because it can be set in a SEPARATE, earlier command
# (`git config core.hooksPath /dev/null`) that is not itself a commit — it must be
# blocked wherever it appears, not only inline with `git commit`.
if echo "$COMMAND" | grep -qE '\bgit\b.*core\.hooksPath'; then
  printf "BLOCKED — Overriding core.hooksPath disables git security hooks. Run git normally.\n\nCOMPLIANCE REMINDER: Your obligation is compliance first, speed second." >&2
  exit 2
fi

echo "$COMMAND" | grep -qE '\bgit\b.*\bcommit\b' || exit 0

# Block --no-verify (bypasses git security hooks). Git accepts any UNAMBIGUOUS
# abbreviation of a long option, so `--no-verify`, `--no-verif`, and `--no-veri`
# all skip the hooks (`--no-ver`/`--no-v` are ambiguous with --no-verbose and git
# rejects them). Match the shortest unambiguous prefix `--no-veri`.
if echo "$COMMAND" | grep -qE '\bgit\b.*\bcommit\b.*--no-veri'; then
  printf "BLOCKED — The --no-verify flag bypasses security hooks (gitleaks, Semgrep). Remove --no-verify and commit normally.\n\nCOMPLIANCE REMINDER: Your obligation is compliance first, speed second. There is no task small enough to skip this requirement." >&2
  exit 2
fi

# -n is the short form of --no-verify; catch it in any short-flag cluster (e.g. -an).
# Known acceptable false positive: this also catches a bare `-n` used for another
# tool's flag within the same command — acceptable given the security stakes.
if echo "$COMMAND" | grep -qE '\bgit\b.*\bcommit\b' && echo "$COMMAND" | grep -qE '(^|[[:space:]])-[a-zA-Z]*n[a-zA-Z]*([[:space:]]|$)'; then
  printf "BLOCKED — The -n flag is shorthand for --no-verify and bypasses git security hooks. Remove it and commit normally.\n\nCOMPLIANCE REMINDER: Your obligation is compliance first, speed second." >&2
  exit 2
fi

# Warn on --amend (rewrites commit history)
if echo "$COMMAND" | grep -qE '\bgit\b.*\bcommit\b.*--amend'; then
  printf "WARNING — git commit --amend rewrites the previous commit. Ensure the amended content has been through the full workflow. If this amend adds new source code, consider a new commit instead.\n" >&2
fi

HASH=$(get_project_hash)
[ -f "/tmp/.claude_evaluated_${HASH}" ] && exit 0

FRAMEWORK_DIR=$(get_framework_dir)
cat >&2 << MSG
BLOCKED — Commit requires evaluate-before-implement workflow.

You MUST present an evaluation (pros, cons, alternatives) and get user approval before committing.
Do NOT commit and explain afterward.
Do NOT assume the user approves because they asked for the change.
Do NOT skip this because the change seems simple.
Do NOT create the marker manually with touch.

After presenting your evaluation and receiving user approval, run:
bash ${FRAMEWORK_DIR}/hooks/mark-evaluated.sh "brief description of what was approved"
Then retry the commit.

COMPLIANCE REMINDER: Your obligation is compliance first, speed second. There is no task small enough to skip this requirement. Do not classify this change as trivial. Do not run a cost-benefit analysis against the process. Follow the required workflow, then proceed.
MSG
exit 2
