#!/usr/bin/env bash
# branch-safety.sh — PreToolUse (Bash) BLOCKING hook
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 1

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
echo "$COMMAND" | grep -qE '\bgit\b.*\bpush\b' || exit 0

# Block force push on any branch
if echo "$COMMAND" | grep -qE '\bgit\b.*\bpush\b.*(-f\b|--force\b|--force-with-lease\b)'; then
  printf "PUSH BLOCKED — Force push is not permitted. Force push overwrites branch history and can destroy audit evidence. Use normal push.\n\nCOMPLIANCE REMINDER: Your obligation is compliance first, speed second. There is no task small enough to skip this requirement. Do not classify this change as trivial. Do not run a cost-benefit analysis against the process. Follow the required workflow, then proceed." >&2
  exit 2
fi

# `git push origin +branch` is force-push via refspec syntax. [^&|;]* keeps the
# `+` inside the same shell segment as `git push`, so a chained command like
# `git push origin main && chmod +x deploy.sh` is not mistaken for a force push.
if echo "$COMMAND" | grep -qE '\bgit\b[^&|;]*\bpush\b[^&|;]*[[:space:]]["'"'"']?\+[^[:space:]]'; then
  printf "PUSH BLOCKED — Refspec force syntax (+branch) is a force push and is not permitted. Use normal push.\n\nCOMPLIANCE REMINDER: Your obligation is compliance first, speed second. There is no task small enough to skip this requirement. Do not classify this change as trivial. Do not run a cost-benefit analysis against the process. Follow the required workflow, then proceed." >&2
  exit 2
fi

# A force refspec can also be smuggled through git config, after which a bare
# `git push` force-pushes: `git -c remote.origin.push=+main push origin`.
if echo "$COMMAND" | grep -qE '\bgit\b[^&|;]*\.push[[:space:]]*[= ][[:space:]]*["'"'"']?\+'; then
  printf "PUSH BLOCKED — Setting a force refspec (+) via git config is not permitted. Use normal push.\n\nCOMPLIANCE REMINDER: Your obligation is compliance first, speed second. There is no task small enough to skip this requirement. Do not classify this change as trivial. Do not run a cost-benefit analysis against the process. Follow the required workflow, then proceed." >&2
  exit 2
fi

BRANCH=$(get_branch)

PROTECTED=$(get_manifest_array '.projectConfig._base.protectedBranches[]')
for pb in $PROTECTED; do
  if [ "$BRANCH" = "$pb" ]; then
    printf "PUSH BLOCKED — You are on protected branch '%s'. Direct pushes are not allowed.\n\nCOMPLIANCE REMINDER: Your obligation is compliance first, speed second. There is no task small enough to skip this requirement. Do not classify this change as trivial. Do not run a cost-benefit analysis against the process. Follow the required workflow, then proceed." "$BRANCH" >&2
    exit 2
  fi
done

DEV_BRANCHES=$(get_branch_config_array '.devBranches')
if [ -n "$DEV_BRANCHES" ]; then
  ALLOWED=false
  for db in $DEV_BRANCHES; do
    [[ "$BRANCH" == $db ]] && { ALLOWED=true; break; }
  done
  if [ "$ALLOWED" = false ]; then
    printf "PUSH BLOCKED — Branch '%s' is not in the allowed dev branches for this config. Allowed: %s\n\nCOMPLIANCE REMINDER: Your obligation is compliance first, speed second. There is no task small enough to skip this requirement. Do not classify this change as trivial. Do not run a cost-benefit analysis against the process. Follow the required workflow, then proceed." "$BRANCH" "$DEV_BRANCHES" >&2
    exit 2
  fi
fi
exit 0
