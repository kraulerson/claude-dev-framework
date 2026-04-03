#!/usr/bin/env bash
# v4.sh — Migration script from v3.x to v4.0.0
# Run from project root: bash ~/.claude-dev-framework/migrations/v4.sh
set -euo pipefail

FRAMEWORK_CLONE="$HOME/.claude-dev-framework"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
FRAMEWORK_DIR="$PROJECT_DIR/.claude/framework"
MANIFEST="$PROJECT_DIR/.claude/manifest.json"

echo "=== Migrating to v4.0.0 ==="
echo "Project: $PROJECT_DIR"
echo ""

# 1. Verify v3 framework exists
if [ ! -f "$MANIFEST" ]; then
  echo "ERROR: No manifest.json found at $MANIFEST" >&2
  echo "Run init.sh first for new projects." >&2
  exit 1
fi

CURRENT_VER=$(jq -r '.frameworkVersion // "unknown"' "$MANIFEST" 2>/dev/null || echo "unknown")
echo "Current version: $CURRENT_VER"

# 2. Copy new hook files
echo "Copying new hooks..."
for hook in enforce-plan-tracking.sh plan-tracker.sh enforce-context7.sh context7-tracker.sh verification-gate.sh known-stdlib.txt; do
  cp "$FRAMEWORK_CLONE/hooks/$hook" "$FRAMEWORK_DIR/hooks/$hook"
  [ "${hook##*.}" = "sh" ] && chmod +x "$FRAMEWORK_DIR/hooks/$hook"
  echo "  + hooks/$hook"
done

# 3. Copy updated hooks
echo "Updating existing hooks..."
for hook in session-start.sh skill-tracker.sh sync-tracker.sh marker-guard.sh stop-checklist.sh _helpers.sh; do
  cp "$FRAMEWORK_CLONE/hooks/$hook" "$FRAMEWORK_DIR/hooks/$hook"
  echo "  ~ hooks/$hook"
done

# 4. Copy gates directory
echo "Copying gates..."
mkdir -p "$FRAMEWORK_DIR/gates"
cp "$FRAMEWORK_CLONE/gates/visual-auditor.sh" "$FRAMEWORK_DIR/gates/visual-auditor.sh"
chmod +x "$FRAMEWORK_DIR/gates/visual-auditor.sh"
echo "  + gates/visual-auditor.sh"

# 5. Update manifest
echo "Updating manifest.json..."
TMPFILE=$(mktemp)
jq '.frameworkVersion = "4.0.0" |
    .projectConfig._base.verificationGates = (.projectConfig._base.verificationGates // [])' \
    "$MANIFEST" > "$TMPFILE" && mv "$TMPFILE" "$MANIFEST"

# 6. Add new hooks to activeHooks
CURRENT_HOOKS=$(jq -r '.activeHooks[]' "$MANIFEST" 2>/dev/null || true)
NEW_HOOKS="enforce-plan-tracking plan-tracker enforce-context7 context7-tracker verification-gate"
for h in $NEW_HOOKS; do
  if ! echo "$CURRENT_HOOKS" | grep -qx "$h"; then
    jq --arg h "$h" '.activeHooks += [$h]' "$MANIFEST" > "$TMPFILE" && mv "$TMPFILE" "$MANIFEST"
    echo "  + activeHooks: $h"
  fi
done

# 7. Regenerate settings.json
echo "Regenerating settings.json..."
source "$FRAMEWORK_CLONE/scripts/_shared.sh"
ALL_HOOKS=$(jq -r '.activeHooks[]' "$MANIFEST" 2>/dev/null)
SETTINGS_JSON=$(generate_settings_json $ALL_HOOKS)
merge_hooks_into_settings "$SETTINGS_JSON" "$PROJECT_DIR/.claude/settings.json"
echo "  ~ .claude/settings.json"

# 8. Context7 check
echo ""
echo "Checking Context7 MCP server..."
source "$FRAMEWORK_CLONE/hooks/_helpers.sh"
if check_context7; then
  echo "  Context7: installed"
else
  echo "  Context7: NOT installed"
  echo ""
  read -rp "Context7 MCP is required for v4.0.0. Install now? (requires Node.js) [y/N] " REPLY
  if [[ "$REPLY" =~ ^[Yy]$ ]]; then
    echo "Installing Context7..."
    claude mcp add context7 -- npx -y @upstash/context7-mcp@latest
    echo "  Context7: installed"
  else
    echo "  Context7: skipped (Implementation Zone will be degraded)"
  fi
fi

echo ""
echo "=== Migration to v4.0.0 complete ==="
echo ""
echo "Next steps:"
echo "  1. Run 'bash ~/.claude-dev-framework/scripts/init.sh --reconfigure' to configure verification gates"
echo "  2. Review .claude/settings.json to confirm new hooks are registered"
echo "  3. Start a new Claude session to verify zone activation"
