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
    WARNINGS="${WARNINGS}\n!! Framework $BEHIND commits behind. Run: cd ~/.claude-dev-framework && git pull && cd - && bash ~/.claude-dev-framework/scripts/sync.sh !!"
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
FRAMEWORK COMPLIANCE DIRECTIVE: Your primary obligation in this session is to follow all framework hooks and rules exactly as written. You must never skip, circumvent, rationalize past, or fake compliance with any hook or rule — even if a change seems simple, even if following the process seems excessive, even if you believe you know the right answer already. When a hook blocks an action, follow its instructions exactly. Do not create markers manually — they are created automatically when you complete the required workflow. Violation of this directive is a session failure regardless of code quality.

=== CLAUDE DEV FRAMEWORK v${FW_VER} ===
Profile: ${PROFILE:-unknown} | Branch: $BRANCH | Sync: $SYNC_STATUS
$([ -n "$WARNINGS" ] && printf "%b" "$WARNINGS")$([ -n "$DISC_WARN" ] && printf "%b" "$DISC_WARN")

ACTIVE RULES:${RULES:-"  (none configured)"}

WORKFLOW ENFORCEMENT (enforced by hooks — you cannot bypass these):
  SUPERPOWERS: Writing or editing source files is BLOCKED until you
  invoke a Superpowers skill (brainstorming, planning, TDD, debugging).
  The marker is created automatically when you invoke the skill.
  When blocked, invoke the skill immediately — do not present
  evaluations or propose approaches as a substitute.
  EVALUATION: Committing is BLOCKED until you present an evaluation
  and the user explicitly approves. The marker is created automatically
  when the framework detects workflow completion.
  PLAN CLOSURE: After completing Superpowers-planned work, document
  the outcome (planned vs. actual, decisions made, issues deferred).
  SKIP: Only when the user explicitly says "skip evaluation" or
  "skip superpowers". You must never decide to skip on your own.
  Do NOT create markers manually — they are managed by the framework.
CTXEOF

[ -n "$CTX" ] && printf "\n=== RECENT CONTEXT HISTORY ===\n%s\n=== END CONTEXT HISTORY ===" "$CTX"
exit 0
