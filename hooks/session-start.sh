#!/usr/bin/env bash
# session-start.sh — SessionStart hook. stdout = Claude context.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh"

HASH=$(get_project_hash)
BRANCH=$(get_branch)

# Record session start commit for stop-checklist multi-commit detection
git rev-parse HEAD > "/tmp/.claude_session_start_${HASH}" 2>/dev/null || true
PROFILE=$(get_manifest_value '.profile')
FRAMEWORK_DIR="$(get_framework_dir)"
FRAMEWORK_CLONE="$HOME/.claude-dev-framework"
WARNINGS=""

# 1. Dependency checks
if ! check_jq; then
  WARNINGS="${WARNINGS}\n!! WARNING: jq not installed. Hooks degraded. Install: brew install jq (macOS) / apt install jq (Linux) !!"
fi
if [ -f "$HOME/.claude/settings.json" ] && check_jq; then
  SP=$(jq -r '.enabledPlugins["superpowers@claude-plugins-official"] // false' "$HOME/.claude/settings.json" 2>/dev/null || echo "false")
  [ "$SP" != "true" ] && WARNINGS="${WARNINGS}\n!! REQUIRED: Superpowers plugin NOT installed. Run claude > /plugins > search superpowers > install !!"
fi

# 2. Framework freshness
SYNC_STATUS="unknown"
if [ -d "$FRAMEWORK_CLONE/.git" ]; then
  pushd "$FRAMEWORK_CLONE" > /dev/null
  git fetch origin main --quiet 2>/dev/null || true
  LOCAL=$(git rev-parse HEAD 2>/dev/null || echo "?")
  REMOTE=$(git rev-parse origin/main 2>/dev/null || echo "?")
  if [ "$LOCAL" = "$REMOTE" ]; then SYNC_STATUS="up-to-date"
  elif [ "$LOCAL" != "?" ] && [ "$REMOTE" != "?" ]; then
    BEHIND=$(git rev-list --count HEAD..origin/main 2>/dev/null || echo "?")
    SYNC_STATUS="$BEHIND behind"
    WARNINGS="${WARNINGS}\n!! Framework $BEHIND commits behind. Run: cd ~/.claude-dev-framework && git pull !!"
  fi
  popd > /dev/null
fi

# 3. Load active rules (one-line summaries)
RULES=""
RULES_DIR="$FRAMEWORK_DIR/rules"
if [ -d "$RULES_DIR" ]; then
  while IFS= read -r rule; do
    [ -z "$rule" ] && continue
    F="$RULES_DIR/${rule}.md"
    [ -f "$F" ] && RULES="${RULES}\n  - $(head -1 "$F" | sed 's/^RULE: //')"
  done <<< "$(get_manifest_array '.activeRules[]')"
fi

# 4. Context history
CTX_FILE=$(get_branch_config_value '.contextHistoryFile')
CTX=""
[ -n "$CTX_FILE" ] && [ -f "$CTX_FILE" ] && CTX=$(tail -30 "$CTX_FILE" 2>/dev/null || true)

# 5. Discovery review (>90 days)
DISC_WARN=""
LR=$(get_manifest_value '.discovery.lastReviewDate')
if [ -n "$LR" ]; then
  NOW=$(date +%s)
  THEN=$(date -j -f "%Y-%m-%d" "$LR" +%s 2>/dev/null || date -d "$LR" +%s 2>/dev/null || echo "$NOW")
  DAYS=$(( (NOW - THEN) / 86400 ))
  [ "$DAYS" -gt 90 ] && DISC_WARN="\n!! Discovery last reviewed $DAYS days ago. Ask user if project config has changed. Run init.sh --reconfigure to update. !!"
fi

# 6. Output
FW_VER=$(cat "$FRAMEWORK_CLONE/FRAMEWORK_VERSION" 2>/dev/null || echo "?")
cat << CTXEOF
=== CLAUDE DEV FRAMEWORK v${FW_VER} ===
Profile: ${PROFILE:-unknown} | Branch: $BRANCH | Sync: $SYNC_STATUS
$([ -n "$WARNINGS" ] && printf "%b" "$WARNINGS")$([ -n "$DISC_WARN" ] && printf "%b" "$DISC_WARN")

ACTIVE RULES:${RULES:-"  (none configured)"}

MARKER INSTRUCTIONS (MANDATORY — you MUST follow these):
  After presenting an evaluation and getting user approval, run:
    touch /tmp/.claude_evaluated_${HASH}
  After invoking a Superpowers skill (brainstorming, planning, TDD), run:
    touch /tmp/.claude_superpowers_${HASH}
  After documenting plan closure (planned vs. actual, decisions, deferred), run:
    touch /tmp/.claude_plan_closed_${HASH}
  If the user says "skip evaluation" or "skip superpowers", run the
  corresponding touch command to create the marker.
  These markers are checked by enforcement hooks. Without them, you will
  receive advisory reminders before writing source files or committing.
CTXEOF

[ -n "$CTX" ] && printf "\n=== RECENT CONTEXT HISTORY ===\n%s\n=== END CONTEXT HISTORY ===" "$CTX"
