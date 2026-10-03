#!/usr/bin/env bash
# pre-commit-checks.sh — PreToolUse (Bash) BLOCKING hook
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 1

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
# A _helpers.sh older than this hook (a framework sync left half done) lacks the
# detector: judge by the text rule then, never let the commit through unchecked.
if type command_runs_git_commit >/dev/null 2>&1; then
  command_runs_git_commit "$COMMAND" || exit 0
else
  echo "NOTE — the framework's _helpers.sh is older than pre-commit-checks.sh; run the framework sync. Judging commits by the text rule until then." >&2
  echo "$COMMAND" | grep -qE '\b[Gg][Ii][Tt]\b.*\bcommit\b' || exit 0
fi

ERRORS=""
STAGED=$(git diff --cached --name-only 2>/dev/null || true)
[ -z "$STAGED" ] && exit 0

SOURCE_CHANGED=false
for f in $STAGED; do
  is_doc_or_config "$f" && continue
  is_source_file "$f" && { SOURCE_CHANGED=true; break; }
done
[ "$SOURCE_CHANGED" = false ] && exit 0

CHANGELOG=$(get_branch_config_value '.changelogFile')
if [ -n "$CHANGELOG" ] && ! echo "$STAGED" | grep -q "$CHANGELOG"; then
  ERRORS="${ERRORS}- $CHANGELOG was NOT staged. Update changelog for code changes before committing.\n"
fi

VERSION_FILES=$(get_branch_config_array '.versionFiles')
if [ -n "$VERSION_FILES" ]; then
  for vf in $VERSION_FILES; do
    if ! echo "$STAGED" | grep -q "$vf"; then
      ERRORS="${ERRORS}- Version file $vf was NOT staged. Bump version before committing.\n"
      break
    fi
  done
fi

if [ -n "$ERRORS" ]; then
  printf "COMMIT BLOCKED — Pre-commit checks failed:\n\n%b\nFix these issues, re-stage, and commit again.\n\nCOMPLIANCE REMINDER: Your obligation is compliance first, speed second. There is no task small enough to skip this requirement. Do not classify this change as trivial. Do not run a cost-benefit analysis against the process. Follow the required workflow, then proceed." "$ERRORS" >&2
  exit 2
fi
exit 0
