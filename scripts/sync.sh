#!/usr/bin/env bash
# sync.sh — Smart sync: global framework → project .claude/framework/
set -euo pipefail

FRAMEWORK_CLONE="$HOME/.claude-dev-framework"
MANIFEST=".claude/manifest.json"
source "$(dirname "$0")/_shared.sh"

# Safety checks
if [ ! -d ".claude/framework" ]; then
  echo "ERROR: No .claude/framework/ found. Run init.sh first." >&2; exit 1
fi
PROJ_REMOTE=$(git remote get-url origin 2>/dev/null || echo "")
FW_REMOTE=$(cd "$FRAMEWORK_CLONE" && git remote get-url origin 2>/dev/null || echo "")
[ "$PROJ_REMOTE" = "$FW_REMOTE" ] && [ -n "$PROJ_REMOTE" ] && { echo "ERROR: Inside framework repo." >&2; exit 1; }

# Pull latest (graceful offline)
echo "Pulling latest framework..."
pushd "$FRAMEWORK_CLONE" > /dev/null
git pull origin main --quiet 2>/dev/null || echo "WARNING: Could not pull (offline?). Using local copy."
popd > /dev/null

# Check version
FW_VER=$(cat "$FRAMEWORK_CLONE/FRAMEWORK_VERSION" 2>/dev/null || echo "0.0.0")
LOCAL_VER=$(jq -r '.frameworkVersion // "0.0.0"' "$MANIFEST" 2>/dev/null || echo "0.0.0")
FW_MAJOR="${FW_VER%%.*}"; LOCAL_MAJOR="${LOCAL_VER%%.*}"
if [ "$FW_MAJOR" -gt "$LOCAL_MAJOR" ] 2>/dev/null; then
  echo "MAJOR version bump detected ($LOCAL_VER → $FW_VER). Migration may be needed."
  echo "Check ~/.claude-dev-framework/migrations/ for upgrade scripts."
fi

# Sync hooks
UPDATED=0; SKIPPED=0; NEW=0; CONFLICTS=0
echo ""
echo "Syncing hooks..."
for src in "$FRAMEWORK_CLONE"/hooks/*.sh; do
  name=$(basename "$src")
  dest=".claude/framework/hooks/$name"
  src_hash=$(shasum -a 256 "$src" | cut -c1-12)

  if [ ! -f "$dest" ]; then
    cp "$src" "$dest"; chmod +x "$dest"
    echo "  + $name (new)"; ((NEW++))
  else
    dest_hash=$(shasum -a 256 "$dest" | cut -c1-12)
    if [ "$src_hash" = "$dest_hash" ]; then
      ((SKIPPED++))
    else
      # Check if locally modified
      MANIFEST_HASH=$(jq -r ".files[\"framework/hooks/$name\"].globalHash // empty" "$MANIFEST" 2>/dev/null || echo "")
      if [ -n "$MANIFEST_HASH" ] && [ "$dest_hash" != "$MANIFEST_HASH" ]; then
        echo "  ⚠ $name (CONFLICT — locally modified AND upstream changed)"
        echo "    Local differs from last sync. Options:"
        echo "    (g) Take upstream version"
        echo "    (l) Keep local version"
        echo "    (d) Show diff"
        read -rp "    Choice [g/l/d]: " choice
        case "$choice" in
          g) cp "$src" "$dest"; chmod +x "$dest"; echo "    → Took upstream"; ((UPDATED++)) ;;
          d) diff "$dest" "$src" || true; read -rp "    Take upstream? (y/n): " yn; [ "$yn" = "y" ] && cp "$src" "$dest" && chmod +x "$dest" && ((UPDATED++)) || ((SKIPPED++)) ;;
          *) echo "    → Kept local"; ((SKIPPED++)) ;;
        esac
        ((CONFLICTS++))
      else
        cp "$src" "$dest"; chmod +x "$dest"
        ((UPDATED++))
      fi
    fi
  fi
done

# Sync rules
echo "Syncing rules..."
for src in "$FRAMEWORK_CLONE"/rules/*.md; do
  name=$(basename "$src")
  dest=".claude/framework/rules/$name"
  if [ ! -f "$dest" ]; then
    cp "$src" "$dest"; echo "  + $name (new)"; ((NEW++))
  else
    src_hash=$(shasum -a 256 "$src" | cut -c1-12)
    dest_hash=$(shasum -a 256 "$dest" | cut -c1-12)
    [ "$src_hash" != "$dest_hash" ] && { cp "$src" "$dest"; ((UPDATED++)); } || ((SKIPPED++))
  fi
done

# Update manifest
FW_COMMIT=$(cd "$FRAMEWORK_CLONE" && git rev-parse --short HEAD 2>/dev/null || echo "unknown")
TODAY=$(date +%Y-%m-%dT%H:%M:%SZ)
jq --arg fv "$FW_VER" --arg fc "$FW_COMMIT" --arg sd "$TODAY" \
  '.frameworkVersion = $fv | .frameworkCommit = $fc | .lastSyncDate = $sd' "$MANIFEST" > "${MANIFEST}.tmp"
mv "${MANIFEST}.tmp" "$MANIFEST"

# Merge profile sourceExtensions into manifest (add new, keep existing)
# Checks both _base.yml and the project's profile for suggests.sourceExtensions
_extract_yaml_extensions() {
  local file="$1"
  [ -f "$file" ] || return
  # Extract multi-line flow sequence: sourceExtensions: [ ... ]
  sed -n '/sourceExtensions: *\[/,/\]/p' "$file" 2>/dev/null \
    | sed '1s/.*sourceExtensions: *//' \
    | tr '\n' ' '
}

BEFORE=$(jq -r '.projectConfig._base.sourceExtensions | length' "$MANIFEST" 2>/dev/null || echo 0)
MERGED=false

for PROF_FILE in "$FRAMEWORK_CLONE/profiles/_base.yml" "$FRAMEWORK_CLONE/profiles/$(jq -r '.profile // empty' "$MANIFEST" 2>/dev/null).yml"; do
  EXTS_JSON=$(_extract_yaml_extensions "$PROF_FILE")
  if [ -n "$EXTS_JSON" ] && echo "$EXTS_JSON" | jq '.' >/dev/null 2>&1; then
    jq --argjson new "$EXTS_JSON" \
      '.projectConfig._base.sourceExtensions = (.projectConfig._base.sourceExtensions + $new | unique | sort)' \
      "$MANIFEST" > "${MANIFEST}.tmp"
    mv "${MANIFEST}.tmp" "$MANIFEST"
    MERGED=true
  fi
done

if [ "$MERGED" = true ]; then
  AFTER=$(jq -r '.projectConfig._base.sourceExtensions | length' "$MANIFEST" 2>/dev/null || echo 0)
  ADDED=$((AFTER - BEFORE))
  [ "$ADDED" -gt 0 ] && echo "  Merged $ADDED new source extension(s) into manifest"
fi

# Regenerate settings.json hook registrations
echo "Regenerating hook registrations..."
ACTIVE_HOOKS=()
while IFS= read -r h; do
  [ -n "$h" ] && ACTIVE_HOOKS+=("$h")
done <<< "$(jq -r '.activeHooks[]? // empty' "$MANIFEST" 2>/dev/null)"

if [ ${#ACTIVE_HOOKS[@]} -gt 0 ]; then
  SETTINGS=$(generate_settings_json "${ACTIVE_HOOKS[@]}")
  if echo "$SETTINGS" | jq '.' >/dev/null 2>&1; then
    merge_hooks_into_settings "$SETTINGS" ".claude/settings.json"
  else
    echo "  WARNING: Could not regenerate settings.json — hook registrations unchanged" >&2
  fi
fi

echo ""
echo "=== Sync Complete ==="
echo "  Updated: $UPDATED | New: $NEW | Skipped: $SKIPPED | Conflicts: $CONFLICTS"
echo "  Framework version: $FW_VER (commit: $FW_COMMIT)"
echo "  Hook registrations: regenerated"
