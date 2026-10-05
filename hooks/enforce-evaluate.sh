#!/usr/bin/env bash
# enforce-evaluate.sh — PreToolUse (Bash) blocking hook
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 1

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")

# Config that runs code inside git (hooks, core.hooksPath, fsmonitor, filters, editors,
# signing programs, credential helpers, includes, shell aliases) can disable the
# security hooks or change what a commit contains. It is refused wherever it is SET,
# in any command, not only inline with `git commit` (git_sets_code_config in
# _helpers.sh; approval design B, D4). A _helpers.sh older than this hook lacks the
# parser: fall back to the old core.hooksPath text match.
if type git_sets_code_config >/dev/null 2>&1; then
  if CODE_KEY=$(git_sets_code_config "$COMMAND"); then
    printf "BLOCKED — Setting git config that runs code (%s) is not permitted. Hooks, core.hooksPath, fsmonitor, filters, editors, signing programs, credential helpers, includes and shell aliases run inside git commands and can disable the security hooks or change what a commit contains. Ask the user to make this change in their own terminal.\n\nCOMPLIANCE REMINDER: Your obligation is compliance first, speed second." "$CODE_KEY" >&2
    exit 2
  fi
elif echo "$COMMAND" | grep -qiE '\bgit\b.*core\.hooksPath'; then
  echo "NOTE — the framework's _helpers.sh is older than enforce-evaluate.sh; run the framework sync." >&2
  printf "BLOCKED — Overriding core.hooksPath disables git security hooks (runs code). Run git normally.\n\nCOMPLIANCE REMINDER: Your obligation is compliance first, speed second." >&2
  exit 2
fi

# COMMIT_TEXT is the commit as the shell runs it (quotes removed), so the flag checks
# below also see `git "comm""it" --no-verify`; they read it beside the raw command.
# A _helpers.sh older than this hook (a framework sync left half done) lacks the
# detector: judge by the text rule then, never let the commit through unchecked.
if type git_commit_text >/dev/null 2>&1; then
  COMMIT_TEXT=$(git_commit_text "$COMMAND") || exit 0
else
  echo "NOTE — the framework's _helpers.sh is older than enforce-evaluate.sh; run the framework sync. Judging commits by the text rule until then." >&2
  echo "$COMMAND" | grep -qE '\b[Gg][Ii][Tt]\b.*\bcommit\b' || exit 0
  COMMIT_TEXT="$COMMAND"
fi
CHECK_TEXT="$COMMAND
$COMMIT_TEXT"

# Block --no-verify (bypasses git security hooks). Git accepts any UNAMBIGUOUS
# abbreviation of a long option, so `--no-verify`, `--no-verif`, and `--no-veri`
# all skip the hooks (`--no-ver`/`--no-v` are ambiguous with --no-verbose and git
# rejects them). Match the shortest unambiguous prefix `--no-veri`.
if echo "$CHECK_TEXT" | grep -qE '\b[Gg][Ii][Tt]\b.*\bcommit\b.*--no-veri'; then
  printf "BLOCKED — The --no-verify flag bypasses security hooks (gitleaks, Semgrep). Remove --no-verify and commit normally.\n\nCOMPLIANCE REMINDER: Your obligation is compliance first, speed second. There is no task small enough to skip this requirement." >&2
  exit 2
fi

# -n is the short form of --no-verify; catch it in any short-flag cluster (e.g. -an).
# Known acceptable false positive: this also catches a bare `-n` used for another
# tool's flag within the same command — acceptable given the security stakes.
if echo "$CHECK_TEXT" | grep -qE '(^|[[:space:]])-[a-zA-Z]*n[a-zA-Z]*([[:space:]]|$)'; then
  printf "BLOCKED — The -n flag is shorthand for --no-verify and bypasses git security hooks. Remove it and commit normally.\n\nCOMPLIANCE REMINDER: Your obligation is compliance first, speed second." >&2
  exit 2
fi

# Warn on --amend (rewrites commit history)
if echo "$CHECK_TEXT" | grep -qE '\b[Gg][Ii][Tt]\b.*\bcommit\b.*--amend'; then
  printf "WARNING — git commit --amend rewrites the previous commit. Ensure the amended content has been through the full workflow. If this amend adds new source code, consider a new commit instead.\n" >&2
fi

HASH=$(get_project_hash)
MARKER="/tmp/.claude_evaluated_${HASH}"
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo ""); [ -n "$CWD" ] || CWD="$PWD"

# --- An approval exists: the commit must be the approved change (approval design B, D4) ---
if [ -f "$MARKER" ]; then
  refuse() {
    printf "BLOCKED — This commit is not the change the user approved: %s.\n\nCommit the approved staged change with a lone \`git commit -m \"…\"\` (message options only; no -a, no paths, nothing else on the line). If the change itself must differ, stage it and ask the user again.\n\nCOMPLIANCE REMINDER: Your obligation is compliance first, speed second.\n" "$1" >&2
    exit 2
  }
  if ! type git_stage_state >/dev/null 2>&1 || ! type commit_shape_problem >/dev/null 2>&1; then
    refuse "the framework's _helpers.sh is older than enforce-evaluate.sh, so the approval cannot be checked (run the framework sync)"
  fi
  if ! jq -e '(.tree | type) == "string" and (.head | type) == "string"' "$MARKER" >/dev/null 2>&1; then
    refuse "the approval marker carries no approved state (an older framework or a hand-made marker made it), so it approves nothing; ask the user again"
  fi
  PROBLEM=$(commit_shape_problem "$COMMAND")
  [ -z "$PROBLEM" ] || refuse "$PROBLEM"
  STATE=$(git_stage_state "$CWD") || refuse "the staged state cannot be read (unresolved conflicts, or not the approved repository)"
  CHANGED=$(jq -r --argjson st "$STATE" '[ (if .head != $st.head then "HEAD" else empty end),
      (if .tree != $st.tree then "the staged change" else empty end),
      (if .hooks_digest != $st.hooks_digest then "the git hooks" else empty end),
      (if .config_digest != $st.config_digest then "the git config" else empty end) ] | join(", ")' "$MARKER" 2>/dev/null) \
    || refuse "the approval marker cannot be read"
  [ -z "$CHANGED" ] || refuse "${CHANGED} changed since the user approved"
  exit 0
fi

PENDING_NOTE=""
[ -f "${CLAUDE_PROJECT_DIR:-.}/.claude/pending-approval.json" ] && PENDING_NOTE="
A question is already recorded in .claude/pending-approval.json: if you presented it, stop and wait for the user's reply.
"
SHAPE="${PENDING_APPROVAL_SHAPE:-}"
[ -n "$SHAPE" ] || SHAPE='{"schema": 2, "question": "<what you ask the user>", "options": [{"id": "A1", "text": "<what picking it does>", "approves": "commit"}, {"id": "A2", "text": "Hold - do not commit", "approves": "none"}], "recommendation": "A1", "offered_at": "<UTC time>"}'
cat >&2 << MSG
BLOCKED — Commit requires the user's approval (evaluate-before-implement workflow).
${PENDING_NOTE}
You MUST present an evaluation (pros, cons, alternatives) and get the user's approval through a recorded question:
1. Stage exactly the change to commit (git add <files>).
2. Write .claude/pending-approval.json with the Write tool, in exactly this shape (schema 2; option ids are one letter and one or two digits; at least one option must approve nothing):
   ${SHAPE}
3. Stop and ask the user to reply with the option id. The framework then shows them the question, the staged change and the hooks that will run, and asks them to reply with the id again to confirm.
4. After the confirming reply, commit with a lone git commit -m "…" (no -a, no paths, nothing else on the line).

You cannot create the approval yourself. Do NOT commit and explain afterward. Do NOT assume the user approves because they asked for the change. Do NOT skip this because the change seems simple. (The user can also run bash .claude/framework/hooks/mark-evaluated.sh "<reason>" in their own separate terminal.)

COMPLIANCE REMINDER: Your obligation is compliance first, speed second. There is no task small enough to skip this requirement. Do not classify this change as trivial. Do not run a cost-benefit analysis against the process. Follow the required workflow, then proceed.
MSG
exit 2
