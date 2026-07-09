#!/usr/bin/env bash
# v4.sh — Robust, fully NON-INTERACTIVE migration of a v3.x CDF project
# to whatever CDF version is currently installed at ~/.claude-dev-framework.
#
# Everything is DERIVED from the current framework clone (files + profiles),
# nothing is hardcoded, so it never crashes on hooks a newer release removed
# and never hangs waiting for input.
#
# Usage:  CLAUDE_PROJECT_DIR=/path/to/project bash v4-fixed.sh </dev/null
set -euo pipefail

# ---- Header vars ------------------------------------------------------------
FRAMEWORK_CLONE="$HOME/.claude-dev-framework"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
FRAMEWORK_DIR="$PROJECT_DIR/.claude/framework"
MANIFEST="$PROJECT_DIR/.claude/manifest.json"

echo "=== CDF migration (derive-from-current) ==="
echo "Project:   $PROJECT_DIR"
echo "Framework: $FRAMEWORK_CLONE"
echo ""

# ---- Preconditions ----------------------------------------------------------
if [ ! -f "$MANIFEST" ]; then
  echo "ERROR: No manifest.json found at $MANIFEST" >&2
  echo "This project is not a CDF project — run init.sh first." >&2
  exit 1
fi
if [ ! -f "$FRAMEWORK_CLONE/FRAMEWORK_VERSION" ]; then
  echo "ERROR: Framework clone not found at $FRAMEWORK_CLONE" >&2
  exit 1
fi
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required." >&2; exit 1; }

# ---- Snapshot the BEFORE state (for the delta summary) ----------------------
OLD_VERSION=$(jq -r '.frameworkVersion // "unknown"' "$MANIFEST")
OLD_HOOKS=$(jq -r '.activeHooks[]?' "$MANIFEST" 2>/dev/null || true)

# ---- Determine profile ------------------------------------------------------
profile=$(jq -r '.profile // "_base"' "$MANIFEST")
echo "Profile: $profile"

# ---- parse_profile (copied verbatim from scripts/init.sh lines 88-108) ------
parse_profile() {
  local profile_name="$1"
  local profile_file="$FRAMEWORK_CLONE/profiles/${profile_name}.yml"
  [ ! -f "$profile_file" ] && return

  local inherits=$(grep '^inherits:' "$profile_file" | awk '{print $2}')
  [ -n "$inherits" ] && [ "$inherits" != "null" ] && parse_profile "$inherits"

  # Extract list items under a top-level YAML key, stopping at the next top-level key
  _yaml_list() {
    local key="$1" file="$2"
    sed -n "/^${key}:/,/^[a-zA-Z_]/p" "$file" | grep '^ *- ' | sed 's/^ *- //'
  }

  _yaml_list rules "$profile_file" | while read -r line; do
    echo "rule:$line"
  done
  _yaml_list hooks "$profile_file" | while read -r line; do
    echo "hook:$line"
  done
}

# ---- Derive ordered, de-duplicated activeHooks + activeRules -----------------
# base items come first (recursion into inherits:), profile items after.
ALL_RULES=()
ALL_HOOKS=()
_seen_rules=" "
_seen_hooks=" "
while IFS= read -r line; do
  case "$line" in
    rule:*)
      r="${line#rule:}"
      [ -z "$r" ] && continue
      case "$_seen_rules" in *" $r "*) continue ;; esac
      _seen_rules="$_seen_rules$r "
      ALL_RULES+=("$r")
      ;;
    hook:*)
      h="${line#hook:}"
      [ -z "$h" ] && continue
      case "$_seen_hooks" in *" $h "*) continue ;; esac
      _seen_hooks="$_seen_hooks$h "
      ALL_HOOKS+=("$h")
      ;;
  esac
done <<< "$(parse_profile "$profile")"

if [ ${#ALL_HOOKS[@]} -eq 0 ]; then
  echo "ERROR: profile '$profile' yielded no hooks — refusing to wipe activeHooks." >&2
  exit 1
fi

# ---- Sync framework FILES from the clone (current files only) ---------------
echo ""
echo "── Syncing framework files from clone ──"
mkdir -p "$FRAMEWORK_DIR/hooks" "$FRAMEWORK_DIR/rules" "$FRAMEWORK_DIR/gates"

synced_hooks=0 synced_rules=0 synced_gates=0

for src in "$FRAMEWORK_CLONE"/hooks/*.sh "$FRAMEWORK_CLONE"/hooks/*.txt; do
  [ -f "$src" ] || continue
  base=$(basename "$src")
  cp "$src" "$FRAMEWORK_DIR/hooks/$base"
  case "$base" in *.sh) chmod +x "$FRAMEWORK_DIR/hooks/$base" ;; esac
  synced_hooks=$((synced_hooks + 1))
done

for src in "$FRAMEWORK_CLONE"/rules/*.md; do
  [ -f "$src" ] || continue
  cp "$src" "$FRAMEWORK_DIR/rules/$(basename "$src")"
  synced_rules=$((synced_rules + 1))
done

for src in "$FRAMEWORK_CLONE"/gates/*.sh; do
  [ -f "$src" ] || continue
  base=$(basename "$src")
  cp "$src" "$FRAMEWORK_DIR/gates/$base"
  chmod +x "$FRAMEWORK_DIR/gates/$base"
  synced_gates=$((synced_gates + 1))
done
echo "  hooks synced: $synced_hooks   rules synced: $synced_rules   gates synced: $synced_gates"

# ---- Remove ORPHANED framework files ----------------------------------------
# Only ever touch $FRAMEWORK_DIR (.claude/framework). NEVER .claude/project.
echo ""
echo "── Removing orphaned framework files ──"
ORPHANS_REMOVED=""
orphan_count=0

for f in "$FRAMEWORK_DIR"/hooks/*.sh; do
  [ -f "$f" ] || continue
  base=$(basename "$f")
  if [ ! -f "$FRAMEWORK_CLONE/hooks/$base" ]; then
    rm -f "$f"
    ORPHANS_REMOVED="${ORPHANS_REMOVED}hooks/$base"$'\n'
    orphan_count=$((orphan_count + 1))
    echo "  - removed orphan: hooks/$base"
  fi
done

for f in "$FRAMEWORK_DIR"/rules/*.md; do
  [ -f "$f" ] || continue
  base=$(basename "$f")
  if [ ! -f "$FRAMEWORK_CLONE/rules/$base" ]; then
    rm -f "$f"
    ORPHANS_REMOVED="${ORPHANS_REMOVED}rules/$base"$'\n'
    orphan_count=$((orphan_count + 1))
    echo "  - removed orphan: rules/$base"
  fi
done
[ "$orphan_count" -eq 0 ] && echo "  (no orphans)"

# ---- Update manifest: activeHooks + activeRules -----------------------------
echo ""
echo "── Updating manifest ──"
HOOKS_JSON=$(printf '%s\n' "${ALL_HOOKS[@]}" | jq -R . | jq -s '.')
RULES_JSON=$(printf '%s\n' "${ALL_RULES[@]}" | jq -R . | jq -s '.')

jq --argjson h "$HOOKS_JSON" --argjson r "$RULES_JSON" \
  '.activeHooks = $h | .activeRules = $r' \
  "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"

# ---- Update manifest: version / commit / lastSyncDate / verificationGates ---
FW_VERSION=$(cat "$FRAMEWORK_CLONE/FRAMEWORK_VERSION")
FW_COMMIT=$(git -C "$FRAMEWORK_CLONE" rev-parse --short HEAD 2>/dev/null || echo "unknown")
NOW=$(date +%Y-%m-%dT%H:%M:%SZ)

jq --arg fv "$FW_VERSION" --arg fc "$FW_COMMIT" --arg sd "$NOW" \
  '.frameworkVersion = $fv
   | .frameworkCommit = $fc
   | .lastSyncDate = $sd
   | .projectConfig._base.verificationGates = (.projectConfig._base.verificationGates // [])' \
  "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"
echo "  frameworkVersion: $OLD_VERSION -> $FW_VERSION"
echo "  frameworkCommit:  $FW_COMMIT"
echo "  activeHooks: ${#ALL_HOOKS[@]}   activeRules: ${#ALL_RULES[@]}"

# ---- Regenerate settings.json -----------------------------------------------
echo ""
echo "── Regenerating settings.json ──"
# shellcheck disable=SC1090
source "$FRAMEWORK_CLONE/scripts/_shared.sh"
HOOKS=("${ALL_HOOKS[@]}")
SETTINGS=$(generate_settings_json "${HOOKS[@]}")
if ! echo "$SETTINGS" | jq '.' >/dev/null 2>&1; then
  echo "ERROR: generate_settings_json produced invalid JSON:" >&2
  echo "$SETTINGS" >&2
  exit 1
fi
merge_hooks_into_settings "$SETTINGS" "$PROJECT_DIR/.claude/settings.json"
echo "  ~ .claude/settings.json regenerated"

# ---- Context7 check (NON-interactive; never prompts, never fails) -----------
echo ""
echo "── Context7 MCP ──"
# shellcheck disable=SC1090
source "$FRAMEWORK_CLONE/hooks/_helpers.sh" 2>/dev/null || true
c7_ok=false
if command -v check_context7 >/dev/null 2>&1; then
  if check_context7 2>/dev/null; then
    c7_ok=true
  fi
fi
if [ "$c7_ok" = true ]; then
  echo "  Context7: installed"
else
  echo "  WARNING: Context7 MCP is NOT installed."
  echo "           The 'enforce-context7' hook will WARN on every edit until it is."
  echo "           Install (one-time):"
  echo "             claude mcp add --transport http context7 https://mcp.context7.com/mcp"
  echo "           Migration continues regardless — this is not a failure."
fi

# ---- Summary ----------------------------------------------------------------
ADDED=$(comm -13 <(printf '%s\n' "$OLD_HOOKS" | sort -u) \
                 <(printf '%s\n' "${ALL_HOOKS[@]}" | sort -u) | sed '/^$/d')
REMOVED=$(comm -23 <(printf '%s\n' "$OLD_HOOKS" | sort -u) \
                   <(printf '%s\n' "${ALL_HOOKS[@]}" | sort -u) | sed '/^$/d')

echo ""
echo "=== Migration summary ==="
echo "Version:        $OLD_VERSION -> $FW_VERSION"
echo "Files synced:   $((synced_hooks + synced_rules + synced_gates)) (hooks=$synced_hooks rules=$synced_rules gates=$synced_gates)"
echo "Orphans removed: $orphan_count"
if [ -n "$ADDED" ]; then
  echo "Hooks ADDED:"
  printf '%s\n' "$ADDED" | sed 's/^/  + /'
else
  echo "Hooks ADDED:    (none)"
fi
if [ -n "$REMOVED" ]; then
  echo "Hooks REMOVED:"
  printf '%s\n' "$REMOVED" | sed 's/^/  - /'
else
  echo "Hooks REMOVED:  (none)"
fi
echo "settings.json:  regenerated"
echo ""
echo "=== Migration complete ==="
