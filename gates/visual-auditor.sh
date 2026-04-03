#!/usr/bin/env bash
# visual-auditor.sh — Playwright-based visual audit gate for web-app profile
# Takes a screenshot of the running app and outputs the path for Claude to self-reflect.
# Exits 0 always — Claude self-reflects on the screenshot, the gate itself doesn't judge.
# If Playwright or dev server is not available, exits 0 with advisory.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_DIR="$(cd "$SCRIPT_DIR/../hooks" && pwd)"
source "$HOOK_DIR/_helpers.sh" 2>/dev/null || exit 0

# Read visual auditor config from manifest
DEV_CMD=$(get_manifest_value '.projectConfig._base.visualAuditor.devServerCommand')
DEV_URL=$(get_manifest_value '.projectConfig._base.visualAuditor.devServerUrl')

if [ -z "$DEV_CMD" ] || [ -z "$DEV_URL" ]; then
  echo "Visual Auditor: No devServerCommand or devServerUrl configured in manifest. Skipping." >&2
  exit 0
fi

# Check Playwright is available
if ! npx playwright --version >/dev/null 2>&1; then
  echo "Visual Auditor: Playwright not installed. Run 'npx playwright install' to enable. Skipping." >&2
  exit 0
fi

# Start dev server in background
eval "$DEV_CMD" &
DEV_PID=$!
trap "kill $DEV_PID 2>/dev/null; wait $DEV_PID 2>/dev/null" EXIT

# Wait for server to be ready (up to 30 seconds)
READY=false
for i in $(seq 1 30); do
  if curl -s -o /dev/null -w "%{http_code}" "$DEV_URL" 2>/dev/null | grep -qE '^(200|301|302)'; then
    READY=true
    break
  fi
  sleep 1
done

if [ "$READY" = false ]; then
  echo "Visual Auditor: Dev server at $DEV_URL did not become ready in 30s. Skipping." >&2
  exit 0
fi

# Take screenshot
SCREENSHOT="/tmp/.claude_visual_audit_$(date +%s).png"
npx playwright screenshot --browser chromium "$DEV_URL" "$SCREENSHOT" 2>/dev/null

if [ -f "$SCREENSHOT" ]; then
  echo "Visual Auditor: Screenshot saved to $SCREENSHOT"
  echo "Review the screenshot and confirm the UI matches the spec before proceeding."
  exit 0
else
  echo "Visual Auditor: Screenshot failed. Skipping." >&2
  exit 0
fi
