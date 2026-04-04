#!/usr/bin/env bash
# scalability-check.sh — PreToolUse (Write|Edit) advisory hook
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_helpers.sh" 2>/dev/null || exit 1
source "$SCRIPT_DIR/_preflight.sh"

preflight_init
preflight_skip_non_source && exit 0

FUTURE=$(get_manifest_value '.discovery.futurePlatforms')
[ -z "$FUTURE" ] && exit 0

BASENAME=$(basename "$_PF_FILE_PATH")
case "$BASENAME" in
  *Repository*|*Service*|*API*|*Router*|*Middleware*|*Schema*|*Migration*|*build.gradle*|*Package.swift*|*Cargo.toml*|*package.json*|*Dockerfile*) ;;
  *) exit 0 ;;
esac

jq -n --arg fp "$FUTURE" '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": ("REMINDER: This project may expand to: " + $fp + ". Consider whether this architectural choice keeps that option open or closes it off. If it restricts future options, flag it in your evaluation.\n\nThis advisory is not optional guidance. Acknowledge and act on it before proceeding.")
  }
}'
exit 0
