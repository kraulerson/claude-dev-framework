#!/usr/bin/env bash
# config-guard.sh — PreToolUse (Bash|Write|Edit) blocks modification of framework config and hooks
# Protects: .claude/settings.json, .claude/manifest.json, .claude/framework/hooks/*,
# .claude/approvals.jsonl (approval audit), .git/hooks/*, .git/config, .git/info/*
# Also blocks CLAUDE_PROJECT_DIR environment variable overrides.
# A literal path into a temp fixture outside the project (a test's own
# .claude/manifest.json under the scratchpad) is not the project's config (#11).
set -euo pipefail
# Fail closed (#11 review): Claude Code treats any exit code other than 2 as
# non-blocking, so a crash under set -e/-u must not let the call through. The EXIT
# trap blocks; the deliberate decisions below leave through guard_allow/guard_block,
# which clear it first. (bash 3.2 reports $? as 0 in an EXIT trap after an unbound
# variable, so the trap does not consult it.)
trap 'echo "BLOCKED — config-guard.sh failed internally; refusing the call rather than allowing it." >&2; exit 2' EXIT
guard_allow() { trap - EXIT; exit 0; }
guard_block() { trap - EXIT; exit 2; }
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 1

INPUT=$(cat)

# Without a working jq the input cannot be parsed, so refuse rather than let the call
# through unread (#11 review). A narrower test would not help: every real call names
# its transcript under ~/.claude. `jq --version` also catches a jq that is present
# but broken.
jq --version >/dev/null 2>&1 || {
  echo "BLOCKED — jq is not installed or not working, so config-guard.sh cannot read this call. Install jq (brew install jq / apt install jq)." >&2
  guard_block
}
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")

# --- Write/Edit/NotebookEdit tool: protect framework config files ---
if [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "NotebookEdit" ]; then
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // empty' 2>/dev/null || echo "")
  # Matched lexically normalized (`.claude//settings.json`, `.claude/x/../settings.json`)
  # and in lower case: a case-insensitive disk treats .Claude/Settings.json as the same file.
  # Assigned first, not inside `case "$(...)"`, where a failure would be swallowed.
  MATCH_PATH=$(_normalize_path "$FILE_PATH" | tr '[:upper:]' '[:lower:]')
  case "$MATCH_PATH" in
    */.claude/settings.json|*/.claude/settings.local.json|*/.claude/manifest.json|*/.claude/framework/*|\
    .claude/settings.json|.claude/settings.local.json|.claude/manifest.json|.claude/framework/*)
      path_is_foreign_temp "$FILE_PATH" && guard_allow
      printf "BLOCKED — Framework configuration files cannot be modified by Claude. These files control enforcement hooks, protected branches, and verification gates.\n\nIf a configuration change is needed, ask the user to make the edit manually in their editor.\n\nCOMPLIANCE REMINDER: Your obligation is compliance first, speed second.\n" >&2
      guard_block
      ;;
    */.claude/approvals.jsonl|.claude/approvals.jsonl)
      path_is_foreign_temp "$FILE_PATH" && guard_allow
      printf "BLOCKED — .claude/approvals.jsonl is the approval audit; only the framework writes it. Read it or stage it; do not edit it.\n\nCOMPLIANCE REMINDER: Your obligation is compliance first, speed second.\n" >&2
      guard_block
      ;;
    */.git/hooks|*/.git/hooks/*|*/.git/config|*/.git/info|*/.git/info/*|\
    .git/hooks|.git/hooks/*|.git/config|.git/info|.git/info/*)
      path_is_foreign_temp "$FILE_PATH" && guard_allow
      HINT=""
      case "$MATCH_PATH" in *.git/info/exclude) HINT=" To ignore files, edit .gitignore instead." ;; esac
      printf "BLOCKED — Git's hooks, config and info files cannot be modified by Claude: a hook or config planted there runs inside git commit and can change what an approved commit contains.%s Ask the user to make the change in their own terminal.\n\nCOMPLIANCE REMINDER: Your obligation is compliance first, speed second.\n" "$HINT" >&2
      guard_block
      ;;
  esac
  guard_allow
fi

# --- Bash tool: protect hook files and config from shell modification ---
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
[ -z "$COMMAND" ] && guard_allow
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")

# Every check below reads the command from a here-string, not `echo | grep -q`: under
# pipefail, grep exiting on its first match killed echo with SIGPIPE on a command
# longer than the pipe buffer, and the failed pipeline read as "no match" (#11).
# The path checks also read NORM_COMMAND, the same text with quotes and backslashes
# removed and `//`, `/./` and `x/../` collapsed, so `.claude/framework/./hooks/` or
# `.claude/'framework'/hooks/` cannot slip past them (#11 review).
NORM_SRC=$(tr -d "\"'\\\\" <<< "$COMMAND")
NORM_COMMAND=$(normalize_command_paths "$NORM_SRC")

# Block CLAUDE_PROJECT_DIR= assignment (not reads like echo $CLAUDE_PROJECT_DIR)
if grep -qE 'CLAUDE_PROJECT_DIR=' <<< "$COMMAND"; then
  printf "BLOCKED — CLAUDE_PROJECT_DIR cannot be overridden. This variable controls enforcement hook behavior.\n\nCOMPLIANCE REMINDER: Your obligation is compliance first, speed second.\n" >&2
  guard_block
fi

# find on the bare .claude folder with an action that deletes, runs a command or writes
# (`find .claude -name settings.json -delete` removes the hooks' registration).
FIND_ACTION_ON_CLAUDE_RE='\bfind\b[^|;&]*[[:space:]]["'"'"']?(\./)?\.claude["'"'"']?([[:space:]/][^|;&]*)?-(delete|exec|execdir|ok|okdir|fprint0?|fprintf|fls)([[:space:]]|$)'
# Destructive commands aimed at .claude itself — e.g. `rm -rf .claude`, `rm -rf .claude/`,
# `rm -rf .claude/*`, `mv .claude/ /tmp/x`. A trailing `/` is in the terminating char
# class so `.claude` followed by a slash (bare dir, glob, or subpath) is caught, while
# `.claude-backup` (next char `-`) is not.
if grep -qiE '\b(rm|mv|chmod|chown|rmdir)\b[^|;&]*[[:space:]]["'"'"']?(\./)?\.claude["'"'"']?([[:space:]/]|$)' <<< "$COMMAND" \
   || grep -qiE '\b(rm|mv|chmod|chown|rmdir)\b[^|;&]*[[:space:]]["'"'"']?(\./)?\.claude["'"'"']?([[:space:]/]|$)' <<< "$NORM_COMMAND" \
   || grep -qiE "$FIND_ACTION_ON_CLAUDE_RE" <<< "$COMMAND" || grep -qiE "$FIND_ACTION_ON_CLAUDE_RE" <<< "$NORM_COMMAND"; then
  printf "BLOCKED — Modification of the .claude directory is not permitted. Framework hooks and configuration are managed by the framework, not by Claude.\n\nCOMPLIANCE REMINDER: Your obligation is compliance first, speed second.\n" >&2
  guard_block
fi

# Framework hooks that create, change or clear a workflow marker or an approval when
# run (a hook input is just JSON on stdin, so piping a made-up one into record-approval.sh
# twice approves, and `CLAUDECODE= bash …/mark-evaluated.sh` cleared the override's
# only barrier). Any copy counts — the live install ~/.claude-dev-framework, a clone,
# another project — so they are matched by file name in any folder and any letter
# case, plus the live install's hooks folder itself (a copy or glob of it). Kept here,
# not in _helpers.sh, so a half-done sync cannot leave the guard without it. A new hook
# that writes or clears /tmp/.claude_* state or .claude/approvals.jsonl belongs in this
# list. Reads stay allowed; the project's own mark-plan-closed.sh stays sanctioned.
STATE_HOOKS_RE='(^|[^[:alnum:]_.-])(mark-evaluated|mark-plan-closed|record-approval|marker-tracker|session-start|session-end|stop-checklist)\.sh([^[:alnum:]_.-]|$)|\.claude-dev-framework/hooks([^[:alnum:]_.-]|$)'
if grep -qiE "$STATE_HOOKS_RE" <<< "$COMMAND" \
   || grep -qiE "$STATE_HOOKS_RE" <<< "$NORM_COMMAND"; then
  if [[ "$COMMAND" == *mark-plan-closed.sh* ]] \
     && is_sanctioned_mark_command "$COMMAND" "$CWD"; then
    guard_allow
  fi
  command_only_reads "$COMMAND" && guard_allow
  printf "BLOCKED — Running a framework hook that creates or clears workflow markers or approvals (mark-evaluated.sh, record-approval.sh, marker-tracker.sh, session-start.sh, session-end.sh, stop-checklist.sh, or mark-plan-closed.sh outside the project's .claude/framework/hooks/), or copying one, is not permitted, from any folder. Claude Code runs these hooks itself. mark-evaluated.sh is the user's own override, run in their separate terminal. To get a commit approved: stage the change, record the question in .claude/pending-approval.json (schema 2; see the enforce-evaluate block message for the exact shape) and stop; the user approves by replying with the option id. Reading these files (cat, grep, git log) is allowed; if a commit message only mentions one, write the message to a file and use git commit -F <file>.\n\nCOMPLIANCE REMINDER: Your obligation is compliance first, speed second.\n" >&2
  guard_block
fi

# Check if command names framework config or hook paths (CONFIG_GUARD_PROTECTED_RE in
# _helpers.sh: the config files, framework/hooks/, the bare .claude/framework and
# .claude/framework/hooks directories, the approval audit and git's hooks, config and
# info, in any letter case). The words the shell will see are read (shell_segments:
# quotes removed), each with `//`, `/./` and `x/../` collapsed.
#
# Prose (dogfood-3 rows 5, 13, 14b): in the arguments of a command that only takes
# text — echo, printf, git commit/log/show/tag with no -c or --config-env, or a shell
# or interpreter running a script file (bash scripts/x.sh "…") — a protected path
# counts only where it is a path: at the start of a word or after a character that is
# no part of a name in prose
# (/ = : , @ { …), so "/Users/me/Claude Projects/p/.claude/settings.json" and
# --output=.claude/… still count, while "(Stage .claude/framework/…" or "Refreshes
# .claude/framework via" in a question or a commit message does not (that word names a
# folder called "a .claude", never the project's .claude). Everywhere else — sed's
# `w file`, awk, bash -c, find -exec, git grep -O, a here-document — text is code or a
# target, so any occurrence counts, as before. So does every word with a `$` (an $IFS
# can split it at run time) and every line that could change what those command names
# run: an assignment in front of them, a function, alias, export, declare, typeset,
# hash, enable, eval or source anywhere in the call. A line the split cannot follow
# (substitution, backslash, $'...', an open quote, a comment), a very long one, or an
# older _helpers.sh: the whole text, as before.
WORDS=""
names_protected_path() {
  local segs strict_line=0
  if type shell_segments >/dev/null 2>&1 && [ "${#COMMAND}" -le 65536 ]; then
    segs=$(shell_segments "$COMMAND")
    if ! grep -qE $'^\001(subst|backslash|ansi|unterminated|comment)$' <<< "$segs"; then
      grep -qE '(^|[^[:alnum:]_])(alias|function|export|declare|typeset|readonly|hash|enable|eval|source)([^[:alnum:]_]|$)|[[:alnum:]_][[:space:]]*\([[:space:]]*\)' <<< "$COMMAND" && strict_line=1
      WORDS=$(awk -F'\037' -v strict="$strict_line" '
        /^\001/ { next }
        /^\002/ { for (j = 2; j <= NF; j++) print "S\t" $j; next }
        {
          k = 1; pre = 0
          while (k <= NF && $k ~ /^(if|then|else|elif|fi|do|done|while|until|!|\{|\})$/) k++
          while (k <= NF && $k ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { k++; pre = 1 }
          c = $k; r = 0
          if (c == "echo" || c == "printf") r = 1
          else if (c == "git") {
            # Config given with the command (-c, --config-env) can name a program.
            m = k + 1; cfg = 0
            while (m <= NF && $m ~ /^-/) { if ($m ~ /^(-c|--config-env)/) cfg = 1; if ($m ~ /^(-C|-c|--git-dir|--work-tree|--namespace|--config-env|--super-prefix|--attr-source)$/) m++; m++ }
            if ($m ~ /^(commit|log|show|tag)$/ && !cfg) r = 1
          }
          else if (c ~ /^(bash|sh|zsh|dash|ksh|python[0-9.]*|node|ruby|perl)$/ && $(k + 1) ~ /[\/.]/ && $(k + 1) !~ /^-/ && $(k + 1) !~ /^\/(dev|proc)\//) r = 1
          if (strict || pre) r = 0
          for (j = 1; j <= NF; j++) print ((r && $j !~ /\$/) ? "R" : "S") "\t" $j
        }' <<< "$segs")
      WORDS=$(normalize_command_paths "$WORDS")
      grep -qiE "^R"$'\t'"(.*[^[:alnum:][:space:]_.(-])?(${CONFIG_GUARD_PROTECTED_RE})" <<< "$WORDS" \
        || grep -qiE "^S"$'\t'".*(${CONFIG_GUARD_PROTECTED_RE})" <<< "$WORDS"
      return
    fi
  fi
  WORDS="$NORM_COMMAND"
  grep -qiE "$CONFIG_GUARD_PROTECTED_RE" <<< "$COMMAND" || grep -qiE "$CONFIG_GUARD_PROTECTED_RE" <<< "$NORM_COMMAND"
}
if names_protected_path; then
  # Every such path is a literal path into a temp fixture, not the project's (#11).
  all_protected_paths_foreign "$COMMAND" && guard_allow
  # The project's own mark-evaluated.sh / mark-plan-closed.sh, as a lone invocation
  # (R-11) resolved from the agent's cwd (#11). See _helpers.sh.
  if [[ "$COMMAND" == *mark-plan-closed.sh* ]] \
     && is_sanctioned_mark_command "$COMMAND" "$CWD"; then
    guard_allow
  fi
  # Read-only inspection and plain `git add` staging, alone or chained, when EVERY
  # simple command in the line qualifies (command_only_reads in _helpers.sh). A leading
  # read-only word no longer admits whatever is chained after it (#11). awk (system()),
  # bat (--pager), less (-o log file) and rg --pre can write or execute, so they are
  # not read-only here.
  command_only_reads "$COMMAND" && guard_allow
  MARK_HINT=""
  if [[ "$COMMAND" == *mark-plan-closed.sh* ]]; then
    MARK_HINT=" mark-plan-closed.sh runs only as a lone command from the project root, with no cd, pipe, redirection or chaining and a plain relative path, e.g.: bash .claude/framework/hooks/mark-plan-closed.sh \"one-line closure summary\""
  fi
  if [[ "$COMMAND" == *mark-evaluated.sh* ]]; then
    MARK_HINT="$MARK_HINT mark-evaluated.sh is the user's own override, run in their separate terminal; you cannot run it. To get a commit approved: stage the change, record the question in .claude/pending-approval.json (schema 2; see the enforce-evaluate block message for the exact shape) and stop. The user approves by replying with the option id."
  fi
  case "$NORM_COMMAND" in *.git/info/exclude*|*.GIT/INFO/EXCLUDE*) MARK_HINT="$MARK_HINT To ignore files, edit .gitignore instead." ;; esac
  # Name the path and the part that is not read-only (dogfood-3 rows 1, 19).
  NAMED=$(grep -m1 -oiE "$CONFIG_GUARD_PROTECTED_RE" <<< "$WORDS" || true)
  PART=""
  type command_read_problem >/dev/null 2>&1 && PART=$(command_read_problem "$COMMAND" || true)
  printf "BLOCKED — This command names the framework path %s and also contains %s, which is not read-only. Framework hooks and configuration are managed by the framework, not by Claude. A command that names framework config, hooks, the approval audit or git's hooks, config or info may chain only read-only commands (cat, head, tail, ls, grep, jq, find without -exec/-delete, cmp, diff, sed -n N,Mp, git diff/log/show/status, cd, if/for around them) and plain git add, with no substitution and no redirection except 2>&1 or /dev/null. Anything else in the same call — a script run such as bash scripts/x.sh, a write, a redirection — refuses the whole line: run it as a separate Bash call. Use the Read tool to view these files.%s\n\nCOMPLIANCE REMINDER: Your obligation is compliance first, speed second.\n" "${NAMED:-(see the command)}" "${PART:-a command}" "$MARK_HINT" >&2
  guard_block
fi

guard_allow
