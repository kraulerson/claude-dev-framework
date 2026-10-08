#!/usr/bin/env bash
# test-settings-merge.sh — merge_hooks_into_settings keeps a project's own hooks
# The fixture has the shape of a Solo-adopted project's .claude/settings.json (see
# tests/fixtures/README.md): framework commands share matcher groups with the project's.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURE="$SCRIPT_DIR/fixtures/settings-solo-adopted.json"
# shellcheck source=/dev/null
source "$REPO_DIR/scripts/_shared.sh"

# The fixture's framework hooks minus pre-deploy-check, changelog-sync-check and
# session-end, which this sync's activeHooks no longer list (stale registrations).
ACTIVE=(marker-tracker enforce-evaluate verification-gate pre-commit-checks branch-safety
  config-guard marker-guard enforce-superpowers enforce-plan-tracking enforce-context7
  scalability-check session-start stop-checklist compliance-reinforce)

FW='.claude/framework/hooks/'

# One line per command: event|matcher|command, in file order. $1 = jq select on .command.
command_lines() {
  jq -r --arg fw "$FW" "
    .hooks | to_entries[] | .key as \$e | .value[] | (.matcher // \"\") as \$m
    | .hooks[] | select(.command | $1) | \"\(\$e)|\(\$m)|\(.command)\"" "$2"
}

merged_fixture() {
  local dir="$1"
  cp "$FIXTURE" "$dir/settings.json"
  merge_hooks_into_settings "$(generate_settings_json "${ACTIVE[@]}")" "$dir/settings.json"
}

# =====================================================================
# 1. The project's hooks survive; a mixed group loses only its framework commands
# =====================================================================
test_project_hooks_survive() {
  local tmp; tmp=$(mktemp -d)
  merged_fixture "$tmp"
  assert_equals "$(command_lines 'contains($fw) | not' "$FIXTURE")" \
    "$(command_lines 'contains($fw) | not' "$tmp/settings.json")" \
    "project hooks: every project command kept, same event, matcher and order"
  assert_equals "13" "$(command_lines 'contains($fw) | not' "$tmp/settings.json" | wc -l | tr -d ' ')" \
    "project hooks: all 13 project commands present"
  assert_equals '{"matcher":"Bash","hooks":[{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR\"/scripts/project-commit-gate.sh"}]}' \
    "$(jq -c '.hooks.PreToolUse[0]' "$tmp/settings.json")" \
    "mixed group: the Bash group keeps its project command and loses its framework ones"
  assert_equals '["bash \"$CLAUDE_PROJECT_DIR\"/scripts/project-stop-reminder.sh","bash \"$CLAUDE_PROJECT_DIR\"/scripts/hooks/project-detector.sh"]' \
    "$(jq -c '[.hooks.Stop[0].hooks[].command]' "$tmp/settings.json")" \
    "mixed group: the Stop group keeps both project commands"
  assert_equals "$(jq -c '[.hooks.PreToolUse[] | select(.matcher == "Write" or .matcher == "Edit")]' "$FIXTURE")" \
    "$(jq -c '[.hooks.PreToolUse[] | select(.matcher == "Write" or .matcher == "Edit")]' "$tmp/settings.json")" \
    "project-only groups: Write and Edit groups unchanged"
  assert_equals "$(jq -c '.permissions.allow' "$FIXTURE")" "$(jq -c '.permissions.allow' "$tmp/settings.json")" \
    "other keys: permissions.allow unchanged"
  assert_equals "0" "$(jq '[.hooks[][] | select(.hooks | length == 0)] | length' "$tmp/settings.json")" \
    "no matcher group is left with an empty hooks array"
  rm -rf "$tmp"
}

# =====================================================================
# 2. Framework hooks no longer active are removed, in every form ever written
# =====================================================================
test_stale_framework_hooks_removed() {
  local tmp; tmp=$(mktemp -d)
  merged_fixture "$tmp"
  local stale
  for stale in pre-deploy-check.sh changelog-sync-check.sh session-end.sh; do
    assert_equals "0" "$(jq --arg s "/$stale" '[.. | .command? // empty | select(endswith($s))] | length' "$tmp/settings.json")" \
      "stale: $stale removed"
  done
  assert_equals "null" "$(jq -c '.hooks.SessionEnd' "$tmp/settings.json")" \
    "stale: SessionEnd, left with no groups, is dropped"

  # Older generators wrote "$CLAUDE_PROJECT_DIR/.claude/framework/hooks/x.sh" and
  # $CLAUDE_PROJECT_DIR/.claude/framework/hooks/x.sh; a bash-prefixed form is matched too.
  cat > "$tmp/legacy.json" <<'EOF'
{"hooks":{"SessionStart":[{"hooks":[
  {"type":"command","command":"\"$CLAUDE_PROJECT_DIR/.claude/framework/hooks/session-start.sh\""},
  {"type":"command","command":"$CLAUDE_PROJECT_DIR/.claude/framework/hooks/retired-hook.sh"},
  {"type":"command","command":"bash .claude/framework/hooks/stop-checklist.sh"},
  {"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR\"/scripts/project-version-check.sh"}]}]}}
EOF
  merge_hooks_into_settings "$(generate_settings_json session-start)" "$tmp/legacy.json"
  assert_equals '[["bash \"$CLAUDE_PROJECT_DIR\"/scripts/project-version-check.sh"],["\"$CLAUDE_PROJECT_DIR\"/.claude/framework/hooks/session-start.sh"]]' \
    "$(jq -c '[.hooks.SessionStart[] | [.hooks[].command]]' "$tmp/legacy.json")" \
    "legacy forms: old framework commands replaced by the generated one, project command kept"
  rm -rf "$tmp"
}

# =====================================================================
# 3. The generated hooks are present exactly once
# =====================================================================
test_generated_hooks_once() {
  local tmp; tmp=$(mktemp -d)
  merged_fixture "$tmp"
  generate_settings_json "${ACTIVE[@]}" > "$tmp/generated.json"
  assert_equals "$(command_lines 'contains($fw)' "$tmp/generated.json" | sort)" \
    "$(command_lines 'contains($fw)' "$tmp/settings.json" | sort)" \
    "generated: framework commands are exactly the generated set, each once"
  assert_equals "1" "$(jq '[.hooks.UserPromptSubmit[].hooks[].command | select(endswith("/record-approval.sh"))] | length' "$tmp/settings.json")" \
    "generated: record-approval.sh added once"
  rm -rf "$tmp"
}

# =====================================================================
# 4. Merging twice gives the same bytes as merging once
# =====================================================================
test_idempotent() {
  local tmp gen; tmp=$(mktemp -d)
  merged_fixture "$tmp"
  cp "$tmp/settings.json" "$tmp/once.json"
  gen=$(generate_settings_json "${ACTIVE[@]}")
  merge_hooks_into_settings "$gen" "$tmp/settings.json"
  cmp -s "$tmp/once.json" "$tmp/settings.json"
  assert_equals "0" "$?" "idempotent: second merge is byte-identical to the first"
  rm -rf "$tmp"
}

# =====================================================================
# 5. An event only the project uses survives
# =====================================================================
test_project_only_event_survives() {
  local tmp; tmp=$(mktemp -d)
  merged_fixture "$tmp"
  assert_equals "$(jq -c '.hooks.PostToolUseFailure' "$FIXTURE")" "$(jq -c '.hooks.PostToolUseFailure' "$tmp/settings.json")" \
    "project-only event: PostToolUseFailure unchanged"
  rm -rf "$tmp"
}

# =====================================================================
# 6. The legacy Write(path) deny rules are still removed; the project's rules kept
# =====================================================================
test_legacy_deny_cleanup() {
  local tmp; tmp=$(mktemp -d)
  merged_fixture "$tmp"
  assert_equals "0" "$(jq '[.permissions.deny[] | select(startswith("Write(/.claude/") or startswith("Write(//"))] | length' "$tmp/settings.json")" \
    "deny: the framework's legacy Write rules removed"
  assert_equals "2" "$(jq '[.permissions.deny[] | select(. == "Read(./.env)" or . == "Bash(curl * | bash)")] | length' "$tmp/settings.json")" \
    "deny: the project's own rules kept"
  assert_equals "1" "$(jq '[.permissions.deny[] | select(. == "Edit(/.git/config)")] | length' "$tmp/settings.json")" \
    "deny: current framework rules added"
  rm -rf "$tmp"
}

# =====================================================================
# 7. A hooks block it cannot read stops the merge and leaves the file as it was
# =====================================================================
test_malformed_fails_loud() {
  local tmp gen rc bad; tmp=$(mktemp -d)
  gen=$(generate_settings_json session-start)
  for bad in '{"hooks":"bash scripts/x.sh"}' \
             '{"hooks":{"Stop":{"hooks":[]}}}' \
             '{"hooks":{"Stop":[{"matcher":"","command":"bash scripts/x.sh"}]}}' \
             '{"hooks":{"Stop":[{"hooks":["bash scripts/x.sh"]}]}}'; do
    printf '%s\n' "$bad" > "$tmp/settings.json"
    cp "$tmp/settings.json" "$tmp/before.json"
    ( merge_hooks_into_settings "$gen" "$tmp/settings.json" ) 2>"$tmp/err"
    rc=$?
    assert_equals "1" "$rc" "malformed: merge fails for $bad"
    cmp -s "$tmp/before.json" "$tmp/settings.json"
    assert_equals "0" "$?" "malformed: settings left unchanged for $bad"
    assert_contains "$(cat "$tmp/err")" "ERROR" "malformed: says why for $bad"
    assert_file_not_exists "$tmp/settings.json.tmp" "malformed: no temp file left for $bad"
  done
  rm -rf "$tmp"
}

# =====================================================================
# 8. A settings file that is not one JSON object stops the merge; a missing one is
# written from the generated settings
# =====================================================================
test_unparseable_fails_loud() {
  local tmp gen rc bad; tmp=$(mktemp -d)
  gen=$(generate_settings_json session-start)
  for bad in '{"hooks":{"Stop":[' '' '[]' '{}{}'; do
    printf '%s' "$bad" > "$tmp/settings.json"
    cp "$tmp/settings.json" "$tmp/before.json"
    ( merge_hooks_into_settings "$gen" "$tmp/settings.json" ) 2>"$tmp/err"
    rc=$?
    assert_equals "1" "$rc" "unparseable: merge fails for '$bad'"
    cmp -s "$tmp/before.json" "$tmp/settings.json"
    assert_equals "0" "$?" "unparseable: settings left unchanged for '$bad'"
    assert_contains "$(cat "$tmp/err")" "ERROR: .*: not valid JSON" "unparseable: says why for '$bad'"
    assert_file_not_exists "$tmp/settings.json.tmp" "unparseable: no temp file left for '$bad'"
  done
  rm -f "$tmp/settings.json"
  merge_hooks_into_settings "$gen" "$tmp/settings.json"
  assert_equals "$(echo "$gen" | jq -c .)" "$(jq -c . "$tmp/settings.json")" \
    "missing file: written from the generated settings"
  rm -rf "$tmp"
}

# =====================================================================
# 9. A merge whose output is not one JSON object is not installed (a jq that
# truncates its output and exits 0 would otherwise leave Claude Code no hooks)
# =====================================================================
test_bad_merge_output_not_installed() {
  local tmp real_jq gen rc; tmp=$(mktemp -d)
  real_jq=$(command -v jq)
  mkdir -p "$tmp/bin"
  # Truncates only the merge's own jq call (the one given the legacy deny rules).
  cat > "$tmp/bin/jq" <<EOF
#!/bin/bash
case " \$* " in *" legacy "*) "$real_jq" "\$@" | head -c 40; exit 0 ;; esac
exec "$real_jq" "\$@"
EOF
  chmod +x "$tmp/bin/jq"
  gen=$(generate_settings_json session-start)
  cp "$FIXTURE" "$tmp/settings.json"
  ( PATH="$tmp/bin:$PATH"; merge_hooks_into_settings "$gen" "$tmp/settings.json" ) 2>"$tmp/err"
  rc=$?
  assert_equals "1" "$rc" "bad merge output: merge fails"
  cmp -s "$FIXTURE" "$tmp/settings.json"
  assert_equals "0" "$?" "bad merge output: settings left unchanged"
  assert_contains "$(cat "$tmp/err")" "ERROR: .*: merged settings failed validation" "bad merge output: says why"
  assert_file_not_exists "$tmp/settings.json.tmp" "bad merge output: no temp file left"
  rm -rf "$tmp"
}

echo "settings-merge (merge_hooks_into_settings)"
test_project_hooks_survive
test_stale_framework_hooks_removed
test_generated_hooks_once
test_idempotent
test_project_only_event_survives
test_legacy_deny_cleanup
test_malformed_fails_loud
test_unparseable_fails_loud
test_bad_merge_output_not_installed
run_tests
