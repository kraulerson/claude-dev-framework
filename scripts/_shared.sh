#!/usr/bin/env bash
# _shared.sh — Functions shared between init.sh and sync.sh
# Sourced by other scripts via: source "$(dirname "$0")/_shared.sh"

# The first Claude Code that honours "onFailure":"block" on a hook entry. Before it, a
# hook that times out, exits with a code other than 0 or 2, cannot start or prints
# invalid JSON is a non-blocking error: the action it guards goes ahead.
CDF_ON_FAILURE_MIN_VERSION=2.1.295

# Print the version of the claude on PATH as MAJOR.MINOR.PATCH (the first one on the
# first line of `claude --version`), or nothing when there is no claude, no version, or
# a part longer than 9 digits (more than shell arithmetic can compare).
cdf_claude_code_version() {
  command -v claude >/dev/null 2>&1 || return 0
  claude --version 2>/dev/null | head -n 1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 \
    | grep -E '^[0-9]{1,9}\.[0-9]{1,9}\.[0-9]{1,9}$'
}

# Inside a Claude Code session (CLAUDECODE non-empty) a claude that is missing from this
# shell's PATH or prints no version is a contradiction (an alias or an app-bundled Claude
# Code is not visible to scripts; so is a changed PATH): return 1 before anything is
# written, so the policy is never silently dropped. Outside a session, and for an old
# version, return 0.
cdf_require_claude_in_session() {
  [ -n "${CLAUDECODE:-}" ] || return 0
  [ -n "$(cdf_claude_code_version)" ] && return 0
  echo "ERROR: claude is not on this shell's PATH or prints no version (an alias or an app-bundled Claude Code is not visible to scripts), yet this runs inside a Claude Code session. Nothing was written. Run init.sh or sync.sh from a terminal outside Claude Code, with claude on PATH." >&2
  return 1
}

# Return 0 when VERSION (MAJOR.MINOR.PATCH, parts of 1 to 9 digits) is
# CDF_ON_FAILURE_MIN_VERSION or later, comparing each part as a number; 1 otherwise, and
# for anything not in that form.
# Usage: cdf_on_failure_supported VERSION
cdf_on_failure_supported() {
  local v="$1" floor="$CDF_ON_FAILURE_MIN_VERSION" i a b
  printf '%s\n' "$v" | grep -qE '^[0-9]{1,9}\.[0-9]{1,9}\.[0-9]{1,9}$' || return 1
  for i in 1 2 3; do
    a=$(printf '%s' "$v" | cut -d. -f"$i"); b=$(printf '%s' "$floor" | cut -d. -f"$i")
    [ "$a" -gt "$b" ] && return 0
    [ "$a" -lt "$b" ] && return 1
  done
  return 0
}

# Generate settings.json hooks section from a list of active hook names.
# Usage: generate_settings_json hook1 hook2 hook3 ...
# Output: JSON object with { "hooks": { ... } } structure
# A hook whose row sets a timeout is a guard that blocks: its entry gets that timeout
# and, on a Claude Code that has it, "onFailure":"block", so a guard that hangs, crashes
# or cannot start refuses the action. On an older, unreadable or missing Claude Code the
# timeouts are still written and one warning goes to stderr; inside a Claude Code session
# a missing or unreadable claude generates nothing (return 1, cdf_require_claude_in_session).
generate_settings_json() {
  local prefix='"$CLAUDE_PROJECT_DIR"/.claude/framework/hooks/'
  local cc_version on_failure='{"onFailure":"block"}'
  cdf_require_claude_in_session || return 1
  cc_version=$(cdf_claude_code_version)
  if ! cdf_on_failure_supported "$cc_version"; then
    on_failure='{}'
    local found fix
    if [ -n "$cc_version" ]; then
      found="Claude Code $cc_version"
      fix="run \`claude update\`, then re-run sync.sh in this project."
    elif ! command -v claude >/dev/null 2>&1; then
      found="Claude Code not found on PATH"
      fix="install Claude Code $CDF_ON_FAILURE_MIN_VERSION or later (https://claude.com/claude-code) so that \`claude\` is on PATH, then re-run sync.sh in this project."
    else
      found="Claude Code found, but its version could not be read"
      fix="run \`claude --version\`; if it is older than $CDF_ON_FAILURE_MIN_VERSION, run \`claude update\`; then re-run sync.sh in this project."
    fi
    echo "WARNING: $found; fail-closed hooks need Claude Code $CDF_ON_FAILURE_MIN_VERSION or later. Until then the guard hooks will not fail closed when they time out, crash or cannot start: the action they guard goes ahead. Fix: $fix" >&2
  fi

  # Build JSON entries for each hook, one per line, using jq for safe encoding
  local entries=""
  for hook in "$@"; do
    local event="" matcher="" timeout="null"
    case "$hook" in
      session-start)        event="SessionStart"; matcher="" ;;
      session-end)          event="SessionEnd";   matcher="" ;;
      compliance-reinforce) event="UserPromptSubmit"; matcher="" ;;
      enforce-evaluate)     event="PreToolUse";   matcher="Bash"; timeout=30 ;;
      enforce-superpowers)  event="PreToolUse";   matcher="Bash|Write|Edit|NotebookEdit"; timeout=30 ;;
      pre-commit-checks)    event="PreToolUse";   matcher="Bash"; timeout=30 ;;
      branch-safety)        event="PreToolUse";   matcher="Bash"; timeout=30 ;;
      stop-checklist)       event="Stop";         matcher="" ;;
      changelog-sync-check) event="PreToolUse";   matcher="Bash|Write|Edit|NotebookEdit" ;;
      # PostToolUse cannot block: a failure is shown to Claude.
      marker-tracker)       event="PostToolUse";  matcher=""; timeout=30 ;;
      scalability-check)    event="PreToolUse";   matcher="Bash|Write|Edit|NotebookEdit" ;;
      pre-deploy-check)     event="PreToolUse";   matcher="Bash" ;;
      marker-guard)         event="PreToolUse";   matcher="Bash|Write|Edit|NotebookEdit"; timeout=30 ;;
      config-guard)         event="PreToolUse";   matcher="Bash|Write|Edit|NotebookEdit"; timeout=30 ;;
      enforce-plan-tracking) event="PreToolUse";  matcher="Bash|Write|Edit|NotebookEdit"; timeout=30 ;;
      enforce-context7)      event="PreToolUse";   matcher="Bash|Write|Edit|NotebookEdit"; timeout=30 ;;
      # Runs the project's linters, so it gets the time Claude Code gives a hook by default.
      verification-gate)     event="PreToolUse";   matcher="Bash"; timeout=600 ;;
      *) continue ;;
    esac
    entries="${entries}$(jq -n --arg e "$event" --arg m "$matcher" --arg c "${prefix}${hook}.sh" \
      --argjson t "$timeout" '{event:$e,matcher:$m,command:$c,timeout:$t}')"$'\n'
    # The evaluate gate's approvals come from the user's pick of a recorded question, read
    # by record-approval.sh on UserPromptSubmit (approval design B). Registered with the
    # gate, so an existing project gets it on its next sync without a manifest change.
    # No failure policy: it never blocks the user's prompt on its own failure.
    if [ "$hook" = enforce-evaluate ]; then
      entries="${entries}$(jq -n --arg c "${prefix}record-approval.sh" \
        '{event:"UserPromptSubmit",matcher:"",command:$c}')"$'\n'
    fi
  done

  # Static defense-in-depth permission rules (R-08). Leading `/` anchors at the
  # project root; `//` is an absolute filesystem path — current Claude Code
  # permission-rule syntax. Enforced by the harness before hooks run. An Edit(path)
  # rule covers every built-in tool that writes files (Edit, Write, NotebookEdit);
  # Claude Code never consults a Write(path) rule and warns about one at startup, so
  # none is generated (FRAMEWORK_LEGACY_DENY_RULES lists the ones older versions did).
  # https://code.claude.com/docs/en/permissions ("Read and Edit").
  local deny_rules
  deny_rules=$(jq -n '[
    "Edit(/.claude/settings.json)",
    "Edit(/.claude/settings.local.json)",
    "Edit(/.claude/manifest.json)",
    "Edit(/.claude/framework/**)",
    "Edit(//tmp/.claude_*)",
    "Edit(//private/tmp/.claude_*)",
    "Edit(/.claude/approvals.jsonl)",
    "Edit(/.git/hooks/**)",
    "Edit(/.git/config)",
    "Edit(/.git/info/**)"
  ] | sort')

  # Let jq handle all grouping and JSON assembly
  echo "$entries" | jq -s --argjson deny "$deny_rules" --argjson onfail "$on_failure" '
    group_by(.event + "\u0000" + .matcher) |
    map({
      event: .[0].event,
      matcher: .[0].matcher,
      hooks: map({"type":"command","command":.command}
                 + if .timeout then {timeout: .timeout} + $onfail else {} end)
    }) |
    group_by(.event) |
    map({
      key: .[0].event,
      value: map(
        if .matcher != "" then {matcher: .matcher, hooks: .hooks}
        else {hooks: .hooks}
        end
      )
    }) |
    from_entries |
    {hooks: ., permissions: {deny: $deny}}
  '
}

# The Write(path) deny rules earlier framework versions generated beside their
# Edit(path) twins. A merge removes exactly these, so a refreshed install stops
# carrying rules Claude Code ignores; a user's own deny rules are kept.
FRAMEWORK_LEGACY_DENY_RULES='[
  "Write(/.claude/settings.json)", "Write(/.claude/settings.local.json)",
  "Write(/.claude/manifest.json)", "Write(/.claude/framework/**)",
  "Write(//tmp/.claude_*)", "Write(//private/tmp/.claude_*)"
]'

# Merge generated hooks into an existing settings.json, preserving other keys.
# A command containing .claude/framework/hooks/ is the framework's (every form the
# generator has written); all of those are removed and the generated groups appended
# to each event, so the project's own hooks and groups stay as they were. A hooks
# block in an unexpected shape, or a file that is not one JSON object, stops the merge
# (return 1) and leaves the file alone. A missing file is written from hooks_json.
# Usage: merge_hooks_into_settings hooks_json settings_file
merge_hooks_into_settings() {
  local settings_json="$1" settings_file="$2"
  local hooks_part perms_part
  # One JSON object, nothing else: jq accepts an empty file and a stream of values.
  local one_object='length == 1 and (.[0] | type) == "object"'
  hooks_part=$(echo "$settings_json" | jq '.hooks')
  perms_part=$(echo "$settings_json" | jq '.permissions.deny // []')

  if [ -f "$settings_file" ]; then
    if ! jq -s -e "$one_object" "$settings_file" >/dev/null 2>&1; then
      echo "ERROR: $settings_file: not valid JSON (a settings file is one JSON object); hooks not merged; the file is unchanged. Fix it and re-run." >&2
      return 1
    fi
    if ! jq --argjson h "$hooks_part" --argjson d "$perms_part" \
        --argjson legacy "$FRAMEWORK_LEGACY_DENY_RULES" '
      (if .hooks == null then {} else .hooks end) as $old
      | if ($old | type) != "object" then error("hooks is not an object") else . end
      | .hooks = ($old
          | with_entries(.key as $e
              | if (.value | type) != "array" then error("hooks.\($e) is not an array") else . end
              | .value |= map(
                  if type != "object" or (.hooks | type) != "array" or any(.hooks[]; type != "object")
                  then error("hooks.\($e) has a matcher group without a hooks array of objects") else . end
                  | .hooks |= map(select(((.command | type) == "string"
                                          and (.command | contains(".claude/framework/hooks/"))) | not))
                  | select(.hooks | length > 0)))
          | reduce ($h | to_entries[]) as $g (.; .[$g.key] = ((.[$g.key] // []) + $g.value))
          | with_entries(select(.value | length > 0)))
      | .permissions = ((.permissions // {}) | .deny = (((.deny // []) - $legacy + $d) | unique | sort))
    ' "$settings_file" > "${settings_file}.tmp"; then
      rm -f "${settings_file}.tmp"
      echo "ERROR: $settings_file: hooks not merged; the file is unchanged. Fix the hooks block and re-run." >&2
      return 1
    fi
    if ! jq -s -e "$one_object" "${settings_file}.tmp" >/dev/null 2>&1; then
      rm -f "${settings_file}.tmp"
      echo "ERROR: $settings_file: merged settings failed validation; the file is unchanged. Re-run, and check the jq on PATH." >&2
      return 1
    fi
    mv "${settings_file}.tmp" "$settings_file"
  else
    echo "$settings_json" > "$settings_file"
  fi
}
