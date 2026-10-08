#!/usr/bin/env bash
# _shared.sh — Functions shared between init.sh and sync.sh
# Sourced by other scripts via: source "$(dirname "$0")/_shared.sh"

# Generate settings.json hooks section from a list of active hook names.
# Usage: generate_settings_json hook1 hook2 hook3 ...
# Output: JSON object with { "hooks": { ... } } structure
generate_settings_json() {
  local prefix='"$CLAUDE_PROJECT_DIR"/.claude/framework/hooks/'

  # Build JSON entries for each hook, one per line, using jq for safe encoding
  local entries=""
  for hook in "$@"; do
    local event="" matcher=""
    case "$hook" in
      session-start)        event="SessionStart"; matcher="" ;;
      session-end)          event="SessionEnd";   matcher="" ;;
      compliance-reinforce) event="UserPromptSubmit"; matcher="" ;;
      enforce-evaluate)     event="PreToolUse";   matcher="Bash" ;;
      enforce-superpowers)  event="PreToolUse";   matcher="Write|Edit|NotebookEdit" ;;
      pre-commit-checks)    event="PreToolUse";   matcher="Bash" ;;
      branch-safety)        event="PreToolUse";   matcher="Bash" ;;
      stop-checklist)       event="Stop";         matcher="" ;;
      changelog-sync-check) event="PreToolUse";   matcher="Write|Edit|NotebookEdit" ;;
      marker-tracker)       event="PostToolUse";  matcher="" ;;
      scalability-check)    event="PreToolUse";   matcher="Write|Edit|NotebookEdit" ;;
      pre-deploy-check)     event="PreToolUse";   matcher="Bash" ;;
      marker-guard)         event="PreToolUse";   matcher="Bash|Write|Edit|NotebookEdit" ;;
      config-guard)         event="PreToolUse";   matcher="Bash|Write|Edit|NotebookEdit" ;;
      enforce-plan-tracking) event="PreToolUse";  matcher="Write|Edit|NotebookEdit" ;;
      enforce-context7)      event="PreToolUse";   matcher="Write|Edit|NotebookEdit" ;;
      verification-gate)     event="PreToolUse";   matcher="Bash" ;;
      *) continue ;;
    esac
    entries="${entries}$(jq -n --arg e "$event" --arg m "$matcher" --arg c "${prefix}${hook}.sh" \
      '{event:$e,matcher:$m,command:$c}')"$'\n'
    # The evaluate gate's approvals come from the user's pick of a recorded question, read
    # by record-approval.sh on UserPromptSubmit (approval design B). Registered with the
    # gate, so an existing project gets it on its next sync without a manifest change.
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
  echo "$entries" | jq -s --argjson deny "$deny_rules" '
    group_by(.event + "\u0000" + .matcher) |
    map({
      event: .[0].event,
      matcher: .[0].matcher,
      hooks: map({"type":"command","command":.command})
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
