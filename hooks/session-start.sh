#!/usr/bin/env bash
# session-start.sh — SessionStart hook (v4.0.0). stdout = Claude context.
# Activates enforcement zones, checks dependencies, outputs terse zone report.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh"

# SessionStart input carries source: startup | resume | clear | compact.
# Manual runs (no stdin) get source="" and are treated as startup.
INPUT=""
if [ ! -t 0 ]; then INPUT=$(cat 2>/dev/null || true); fi
SOURCE=$(echo "$INPUT" | jq -r '.source // empty' 2>/dev/null || echo "")

HASH=$(get_project_hash)
BRANCH=$(get_branch)

# Session marker hygiene (R-06 / R-20). Fresh sessions must not inherit stale
# workflow markers that would pre-unlock enforcement zones; mid-session
# continuations (resume/compact) preserve markers and the session window.
case "$SOURCE" in
  resume|compact)
    # Mid-session continuation: keep workflow markers and the session window.
    [ -f "/tmp/.claude_session_start_${HASH}" ] || git rev-parse HEAD > "/tmp/.claude_session_start_${HASH}" 2>/dev/null || true
    [ -f "/tmp/.claude_last_head_${HASH}" ]     || git rev-parse HEAD > "/tmp/.claude_last_head_${HASH}" 2>/dev/null || true
    ;;
  *)
    # startup / clear / unknown: fresh session. Stale markers from prior
    # sessions must not pre-unlock enforcement zones (R-06).
    rm -f "/tmp/.claude_superpowers_${HASH}" \
          "/tmp/.claude_evaluated_${HASH}" \
          "/tmp/.claude_has_plan_${HASH}" \
          "/tmp/.claude_plan_active_${HASH}" \
          "/tmp/.claude_plan_closed_${HASH}" \
          "/tmp/.claude_changelog_synced_${HASH}" \
          "/tmp/.claude_c7_degraded_${HASH}"
    rm -f "/tmp/.claude_c7_${HASH}_"* 2>/dev/null || true
    rm -f "/tmp/.claude_stop_errors_hash_${HASH}"* 2>/dev/null || true
    git rev-parse HEAD > "/tmp/.claude_session_start_${HASH}" 2>/dev/null || true
    git rev-parse HEAD > "/tmp/.claude_last_head_${HASH}"     2>/dev/null || true
    ;;
esac
PROFILE=$(get_manifest_value '.profile')
FRAMEWORK_DIR="$(get_framework_dir)"
FRAMEWORK_CLONE="$HOME/.claude-dev-framework"
WARNINGS=""

# --- Start git fetch in background (overlaps with local checks below) ---
FETCH_PID=""
if [ -d "$FRAMEWORK_CLONE/.git" ]; then
  git -C "$FRAMEWORK_CLONE" fetch origin main --quiet 2>/dev/null &
  FETCH_PID=$!
fi

# --- Dependency checks (local, fast) ---

# jq
if ! check_jq; then
  WARNINGS="${WARNINGS}\n  ! jq not installed. Hooks degraded. Install: brew install jq (macOS) / apt install jq (Linux)"
fi

# Superpowers
SP_STATUS="verified"
if [ -f "$HOME/.claude/settings.json" ] && check_jq; then
  SP=$(jq -r '.enabledPlugins["superpowers@claude-plugins-official"] // false' "$HOME/.claude/settings.json" 2>/dev/null || echo "false")
  if [ "$SP" != "true" ]; then
    SP_STATUS="MISSING"
    WARNINGS="${WARNINGS}\n  ! Superpowers plugin NOT installed. Run: claude > /plugins > search superpowers > install"
  fi
fi

# Context7
C7_STATUS="ready"
if check_context7; then
  C7_STATUS="ready"
else
  C7_STATUS="not installed"
  WARNINGS="${WARNINGS}\n  ! Context7 MCP not installed. Implementation Zone degraded."
  WARNINGS="${WARNINGS}\n    To install: claude mcp add --transport http context7 https://mcp.context7.com/mcp"
  # Set degraded flag so enforce-context7.sh passes through
  touch "/tmp/.claude_c7_degraded_${HASH}"
fi

# --- Discovery review (>90 days) ---
LR=$(get_manifest_value '.discovery.lastReviewDate')
if [ -n "$LR" ]; then
  NOW=$(date +%s)
  THEN=$(date -j -f "%Y-%m-%d" "$LR" +%s 2>/dev/null || date -d "$LR" +%s 2>/dev/null || echo "$NOW")
  DAYS=$(( (NOW - THEN) / 86400 ))
  [ "$DAYS" -gt 90 ] && WARNINGS="${WARNINGS}\n  ! Discovery review overdue (last: $LR, $DAYS days ago). Run: init.sh --reconfigure"
fi

# --- Framework freshness (wait for background fetch) ---
SYNC_STATUS="unknown"
if [ -n "$FETCH_PID" ]; then
  wait "$FETCH_PID" 2>/dev/null || true
  LOCAL=$(git -C "$FRAMEWORK_CLONE" rev-parse HEAD 2>/dev/null || echo "?")
  REMOTE=$(git -C "$FRAMEWORK_CLONE" rev-parse origin/main 2>/dev/null || echo "?")
  if [ "$LOCAL" = "$REMOTE" ]; then SYNC_STATUS="up-to-date"
  elif [ "$LOCAL" != "?" ] && [ "$REMOTE" != "?" ]; then
    BEHIND=$(git -C "$FRAMEWORK_CLONE" rev-list --count HEAD..origin/main 2>/dev/null || echo "?")
    SYNC_STATUS="$BEHIND behind"
    WARNINGS="${WARNINGS}\n  ! Framework $BEHIND commits behind. Run: cd ~/.claude-dev-framework && git pull && cd - && bash ~/.claude-dev-framework/scripts/sync.sh"
  fi
fi

# --- Count active rules ---
RULE_COUNT=0
if check_jq; then
  RULE_COUNT=$(jq -r '.activeRules | length // 0' "$(get_manifest_path)" 2>/dev/null || echo "0")
fi

# --- Count verification gates ---
GATE_LIST=""
if check_jq; then
  GATE_NAMES=$(jq -r '.projectConfig._base.verificationGates[]? | select(.enabled == true) | .name' "$(get_manifest_path)" 2>/dev/null || true)
  if [ -n "$GATE_NAMES" ]; then
    GATE_LIST=$(echo "$GATE_NAMES" | tr '\n' ', ' | sed 's/, $//')
  fi
fi

# --- Context history ---
CTX_FILE=$(get_branch_config_value '.contextHistoryFile')
CTX=""
[ -n "$CTX_FILE" ] && [ -f "$CTX_FILE" ] && CTX=$(tail -30 "$CTX_FILE" 2>/dev/null || true)

# --- Output ---
FW_VER=$(cat "$FRAMEWORK_CLONE/FRAMEWORK_VERSION" 2>/dev/null || echo "?")
cat << CTXEOF
FRAMEWORK COMPLIANCE DIRECTIVE: Your primary obligation is to follow all framework hooks and rules exactly. Never skip, circumvent, rationalize past, or fake compliance -- even if a change seems simple. When a hook blocks, follow its instructions. Markers are created automatically. Violation is session failure.

ZONES ARMED:
  # Discovery      -- Context7 ${C7_STATUS}, Superpowers ${SP_STATUS}
  # Design         -- Write|Edit blocked until Superpowers skill invoked
  # Planning       -- Write|Edit blocked until plan task is in_progress
  # Implementation -- New library imports require Context7 lookup first
  # Verification   -- Pre-commit: ${GATE_LIST:-no gates configured}
CTXEOF

if [ -n "$WARNINGS" ]; then
  printf "\nWARNINGS:%b\n" "$WARNINGS"
fi

echo ""
echo "Profile: ${PROFILE:-unknown} | Branch: $BRANCH | Rules: $RULE_COUNT active | Sync: $SYNC_STATUS | v$FW_VER"

[ -n "$CTX" ] && printf "\n=== RECENT CONTEXT ===\n%s\n=== END CONTEXT ===" "$CTX"

if [ "$SOURCE" = "compact" ]; then
  echo ""
  echo "POST-COMPACTION RECOVERY: Context was just compacted. Re-read ${CTX_FILE:-your context history file} and any source files you were actively editing before continuing. Re-check the ZONES ARMED list above — enforcement is still active."
fi
exit 0
