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
      enforce-evaluate)     event="PreToolUse";   matcher="Bash" ;;
      enforce-superpowers)  event="PreToolUse";   matcher="Write|Edit|Read" ;;
      pre-commit-checks)    event="PreToolUse";   matcher="Bash" ;;
      branch-safety)        event="PreToolUse";   matcher="Bash" ;;
      stop-checklist)       event="Stop";         matcher="" ;;
      pre-compact-reminder) event="PreCompact";   matcher="" ;;
      changelog-sync-check) event="PreToolUse";   matcher="Write|Edit" ;;
      sync-tracker)         event="PostToolUse";  matcher="Bash" ;;
      scalability-check)    event="PreToolUse";   matcher="Write|Edit" ;;
      pre-deploy-check)     event="PreToolUse";   matcher="Bash" ;;
      *) continue ;;
    esac
    entries="${entries}$(jq -n --arg e "$event" --arg m "$matcher" --arg c "${prefix}${hook}.sh" \
      '{event:$e,matcher:$m,command:$c}')"$'\n'
  done

  # Let jq handle all grouping and JSON assembly
  echo "$entries" | jq -s --arg prefix "$prefix" '
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
    {hooks: .}
  '
}

# Merge generated hooks into an existing settings.json, preserving other keys.
# Usage: merge_hooks_into_settings hooks_json settings_file
merge_hooks_into_settings() {
  local settings_json="$1" settings_file="$2"
  local hooks_part
  hooks_part=$(echo "$settings_json" | jq '.hooks')

  if [ -f "$settings_file" ] && jq '.' "$settings_file" >/dev/null 2>&1; then
    local existing
    existing=$(cat "$settings_file")
    echo "$existing" | jq --argjson h "$hooks_part" '. + {hooks: $h}' > "${settings_file}.tmp"
    mv "${settings_file}.tmp" "$settings_file"
  else
    echo "$settings_json" > "$settings_file"
  fi
}
