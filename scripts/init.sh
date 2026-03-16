#!/usr/bin/env bash
# init.sh — First-time setup + migration for Claude Dev Framework
set -euo pipefail

FRAMEWORK_CLONE="$HOME/.claude-dev-framework"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---- Flags ----
MIGRATE=false; RECONFIGURE=false; ARCHIVE=false; SKIP_PLUGINS=false
for arg in "$@"; do
  case "$arg" in
    --migrate) MIGRATE=true ;;
    --reconfigure) RECONFIGURE=true ;;
    --archive) ARCHIVE=true ;;
    --skip-plugin-check) SKIP_PLUGINS=true ;;
  esac
done

# ---- Safety Checks ----
if ! git rev-parse --git-dir &>/dev/null; then
  echo "ERROR: Not inside a git repository. Run this from your project root." >&2; exit 1
fi

if [ ! -d "$FRAMEWORK_CLONE/.git" ]; then
  echo "ERROR: Framework not found at $FRAMEWORK_CLONE" >&2
  echo "Clone it first: git clone https://github.com/kraulerson/claude-dev-framework.git ~/.claude-dev-framework" >&2
  exit 1
fi

PROJ_REMOTE=$(git remote get-url origin 2>/dev/null || echo "")
FW_REMOTE=$(cd "$FRAMEWORK_CLONE" && git remote get-url origin 2>/dev/null || echo "")
if [ "$PROJ_REMOTE" = "$FW_REMOTE" ] && [ -n "$PROJ_REMOTE" ]; then
  echo "ERROR: You appear to be inside the framework repo itself. Run this from your project directory." >&2; exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "WARNING: jq not installed. Some features will be limited." >&2
  echo "Install: brew install jq (macOS) or apt install jq (Linux)" >&2
fi

# ---- Archive Mode ----
if [ "$ARCHIVE" = true ]; then
  echo "=== Archive Mode ==="
  if [ -f ".claude/manifest.json" ] && command -v jq &>/dev/null; then
    CANDIDATES=$(jq -r '.files | to_entries[] | select(.value.candidateForGlobal == true) | .key' .claude/manifest.json 2>/dev/null || true)
    if [ -n "$CANDIDATES" ]; then
      echo "Unpushed global candidates found:"
      echo "$CANDIDATES"
      read -rp "Push these to the global framework? (y/n): " choice
      [ "$choice" = "y" ] && echo "Run push-up.sh for each file individually."
    else
      echo "No unpushed global candidates."
    fi
  fi
  exit 0
fi

# ---- Reconfigure Mode ----
if [ "$RECONFIGURE" = true ]; then
  echo "=== Reconfiguring Discovery ==="
  # Fall through to discovery interview below
fi

# ---- Detect Existing Setup ----
HAS_EXISTING=false
[ -d ".claude" ] || [ -f "CLAUDE.md" ] || ls .git/hooks/pre-* &>/dev/null 2>&1 && HAS_EXISTING=true

# ---- Helper: Parse YAML profile (basic — reads rules: and hooks: lists) ----
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

# ---- Helper: Generate settings.json from active hooks ----
generate_settings_json() {
  # Hook registry: name -> event:matcher
  # Stored as flat list of "hookname=event:matcher" for bash 3.2 compat
  local REG_ENTRIES="
session-start=SessionStart:
enforce-evaluate=PreToolUse:Bash
enforce-superpowers=PreToolUse:Write|Edit
pre-commit-checks=PreToolUse:Bash
branch-safety=PreToolUse:Bash
stop-checklist=Stop:
pre-compact-reminder=PreCompact:
changelog-sync-check=PreToolUse:Write|Edit
sync-tracker=PostToolUse:Bash
scalability-check=PreToolUse:Write|Edit
"

  # Lookup a hook's mapping from the registry
  _reg_lookup() {
    local needle="$1"
    echo "$REG_ENTRIES" | while IFS='=' read -r name mapping; do
      [ "$name" = "$needle" ] && echo "$mapping" && return
    done
  }

  # Build grouped entries as lines: "event|matcher|json_entry"
  local grouped_lines=""
  for hook in "$@"; do
    local mapping
    mapping=$(_reg_lookup "$hook")
    [ -z "$mapping" ] && continue
    local event="${mapping%%:*}"
    local matcher="${mapping#*:}"
    local entry='{"type":"command","command":"$CLAUDE_PROJECT_DIR/.claude/framework/hooks/'"${hook}"'.sh"}'
    grouped_lines="${grouped_lines}${event}|${matcher}|${entry}"$'\n'
  done

  # Get unique event|matcher keys
  local unique_keys
  unique_keys=$(echo "$grouped_lines" | awk -F'|' 'NF>=2{print $1"|"$2}' | sort -u)

  # Assemble JSON
  local result='{'
  local first_event=true
  local open_events=""
  while IFS= read -r key; do
    [ -z "$key" ] && continue
    local event="${key%%|*}"
    local matcher="${key#*|}"

    # Collect all entries for this key
    local entries=""
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      local line_event="${line%%|*}"
      local rest="${line#*|}"
      local line_matcher="${rest%%|*}"
      local line_entry="${rest#*|}"
      if [ "${line_event}|${line_matcher}" = "$key" ]; then
        [ -n "$entries" ] && entries="${entries},"
        entries="${entries}${line_entry}"
      fi
    done <<< "$grouped_lines"

    # Check if this event was already started
    local event_started=false
    case "$open_events" in
      *"|${event}|"*) event_started=true ;;
    esac

    if [ "$event_started" = false ]; then
      [ "$first_event" = false ] && result="${result}],"
      result="${result}\"${event}\":["
      open_events="${open_events}|${event}|"
      first_event=false
    else
      result="${result},"
    fi

    if [ -n "$matcher" ]; then
      result="${result}{\"matcher\":\"${matcher}\",\"hooks\":[${entries}]}"
    else
      result="${result}{\"hooks\":[${entries}]}"
    fi
  done <<< "$unique_keys"
  # Close last event array if any
  [ "$first_event" = false ] && result="${result}]"
  result="${result}}"

  # Merge with existing settings if present
  if [ -f ".claude/settings.json" ] && command -v jq &>/dev/null; then
    local existing
    existing=$(cat .claude/settings.json)
    echo "$existing" | jq --argjson h "$(echo "$result" | jq '.')" '.hooks = $h.hooks // $h'
  else
    echo "{\"hooks\":$(echo "$result" | jq '.' 2>/dev/null || echo "$result")}" | jq '.' 2>/dev/null || echo "{\"hooks\":$result}"
  fi
}

# ---- Helper: Discovery Interview ----
run_discovery() {
  echo ""
  echo "=== Project Discovery Interview ==="
  echo "All questions are optional. Press Enter to skip any question."
  echo ""

  local branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
  read -rp "1. What does the '$branch' branch represent? (e.g., 'iOS development', 'main dev branch'): " branch_purpose
  read -rp "2. What OS are you developing ON? (e.g., macOS, Windows, Linux): " dev_os
  read -rp "3. What platform does this branch TARGET? (e.g., iOS 16+, Android API 26+, web, N/A): " target_platform
  read -rp "4. Are there other branches with different configurations? (y/n): " has_other_branches

  local other_branches_json=""
  if [ "$has_other_branches" = "y" ]; then
    read -rp "   List branch names (comma-separated): " other_list
    IFS=',' read -ra BRANCHES <<< "$other_list"
    for ob in "${BRANCHES[@]}"; do
      ob=$(echo "$ob" | xargs)  # trim
      read -rp "   Branch '$ob' — purpose? " ob_purpose
      read -rp "   Branch '$ob' — target platform? " ob_target
      other_branches_json="${other_branches_json},\"branch:${ob}\":{\"purpose\":\"${ob_purpose}\",\"targetPlatform\":\"${ob_target}\"}"
    done
  fi

  read -rp "5. Build tools or constraints? (e.g., 'Xcode, Gradle', 'needs CUDA'): " build_tools
  read -rp "6. Will this project expand to other platforms in the future? (e.g., 'might add web dashboard'): " future_platforms

  local today=$(date +%Y-%m-%d)
  local discovery_json="{\"branch:${branch}\":{\"purpose\":\"${branch_purpose}\",\"devOS\":\"${dev_os}\",\"targetPlatform\":\"${target_platform}\",\"buildTools\":\"${build_tools}\"}${other_branches_json},\"futurePlatforms\":$([ -n "$future_platforms" ] && echo "\"$future_platforms\"" || echo "null"),\"discoveryDate\":\"${today}\",\"lastReviewDate\":\"${today}\"}"
  echo "$discovery_json"
}

# ---- Migration Path ----
if [ "$HAS_EXISTING" = true ] && [ "$RECONFIGURE" = false ]; then
  echo "=== Existing project detected — entering migration mode ==="
  echo ""

  # Phase 1: SCAN
  echo "── Phase 1: SCAN ──"
  EXISTING_ITEMS=""
  [ -d ".claude" ] && EXISTING_ITEMS="${EXISTING_ITEMS}  .claude/ directory\n"
  [ -f ".claude/settings.json" ] && EXISTING_ITEMS="${EXISTING_ITEMS}  .claude/settings.json (has hook config)\n"
  [ -f ".claude/settings.local.json" ] && EXISTING_ITEMS="${EXISTING_ITEMS}  .claude/settings.local.json (permissions)\n"
  [ -f "CLAUDE.md" ] && EXISTING_ITEMS="${EXISTING_ITEMS}  CLAUDE.md\n"
  ls CLAUDE-*.md &>/dev/null 2>&1 && EXISTING_ITEMS="${EXISTING_ITEMS}  CLAUDE-*.md platform files\n"
  ls .git/hooks/pre-* &>/dev/null 2>&1 && EXISTING_ITEMS="${EXISTING_ITEMS}  .git/hooks/ custom hooks\n"
  [ -d "docs/superpowers" ] && EXISTING_ITEMS="${EXISTING_ITEMS}  docs/superpowers/ (Superpowers artifacts)\n"
  printf "Found:\n%b\n" "$EXISTING_ITEMS"

  # Phase 2-3: ANALYZE + REPORT
  echo "── Phase 2-3: ANALYZE + REPORT ──"
  echo ""
  echo "── NO CONFLICTS ──"
  [ -f "CLAUDE.md" ] && echo "  ✓ CLAUDE.md — will be preserved (project-specific)"
  ls CLAUDE-*.md &>/dev/null 2>&1 && echo "  ✓ CLAUDE-*.md — will be preserved (project-specific)"
  [ -f ".claude/settings.local.json" ] && echo "  ✓ .claude/settings.local.json — will be preserved (permissions)"
  [ -d "docs/superpowers" ] && echo "  ✓ docs/superpowers/ — will be preserved"
  echo ""
  echo "── POTENTIAL CONFLICTS ──"
  [ -f ".claude/settings.json" ] && echo "  ⚠ .claude/settings.json — hooks key will be merged (other keys preserved)"
  [ -f "CLAUDE.md" ] && echo "  ⚠ CLAUDE.md rules may overlap with framework rules (both will be active — redundant but safe)"
  ls .git/hooks/pre-* &>/dev/null 2>&1 && echo "  ⚠ .git/hooks/ — framework uses .claude/ hooks, not .git/hooks. Existing git hooks preserved."
  echo ""

  # Phase 4: BACKUP
  echo "── Phase 4: BACKUP ──"
  TIMESTAMP=$(date +%Y-%m-%dT%H%M%S)
  BACKUP_DIR=".claude-backup/${TIMESTAMP}"
  mkdir -p "$BACKUP_DIR"
  [ -d ".claude" ] && cp -r .claude "$BACKUP_DIR/"
  [ -f "CLAUDE.md" ] && cp CLAUDE.md "$BACKUP_DIR/"
  ls CLAUDE-*.md &>/dev/null 2>&1 && cp CLAUDE-*.md "$BACKUP_DIR/"
  ls .git/hooks/pre-* &>/dev/null 2>&1 && mkdir -p "$BACKUP_DIR/.git-hooks" && cp .git/hooks/pre-* "$BACKUP_DIR/.git-hooks/" 2>/dev/null || true

  cat > "$BACKUP_DIR/RESTORE.md" << RESTOREMD
# Framework Migration Backup — $TIMESTAMP

## How to Restore
\`\`\`bash
bash $BACKUP_DIR/restore.sh
\`\`\`

## What Was Backed Up
$(ls -la "$BACKUP_DIR/" | grep -v total | grep -v '\.$')
RESTOREMD

  cat > "$BACKUP_DIR/restore.sh" << RESTORESH
#!/usr/bin/env bash
set -euo pipefail
echo "Restoring from backup: $BACKUP_DIR"
read -rp "This will remove .claude/framework/ and .claude/project/. Continue? (y/n): " confirm
[ "\$confirm" != "y" ] && exit 0
rm -rf .claude/framework .claude/project .claude/manifest.json
[ -f "$BACKUP_DIR/.claude/settings.json" ] && cp "$BACKUP_DIR/.claude/settings.json" .claude/settings.json
echo "Restored. Framework hooks removed, original settings restored."
RESTORESH
  chmod +x "$BACKUP_DIR/restore.sh"
  echo "Backup created at $BACKUP_DIR"
  echo ""

  # Phase 5: PLUGIN CHECK
  if [ "$SKIP_PLUGINS" = false ] && [ -f "$HOME/.claude/settings.json" ] && command -v jq &>/dev/null; then
    echo "── Phase 5: PLUGIN CHECK ──"
    SP=$(jq -r '.enabledPlugins["superpowers@claude-plugins-official"] // false' "$HOME/.claude/settings.json" 2>/dev/null || echo "false")
    if [ "$SP" = "true" ]; then
      echo "  ✓ Superpowers plugin: INSTALLED"
    else
      echo "  ✗ Superpowers plugin: NOT INSTALLED (required)"
      echo "    Install: Run claude → /plugins → search 'superpowers' → install"
    fi
    echo ""
  fi

  read -rp "Proceed with framework installation? (y/n): " proceed
  [ "$proceed" != "y" ] && { echo "Aborted."; exit 0; }
fi

# ---- Phase 6: INSTALL (both clean and migration converge here) ----
echo ""
echo "=== Installing Framework ==="

# Create directories
mkdir -p .claude/framework/hooks .claude/framework/rules .claude/project/hooks .claude/project/rules

# Copy framework files (excluding .git)
cp "$FRAMEWORK_CLONE"/hooks/*.sh .claude/framework/hooks/
cp "$FRAMEWORK_CLONE"/rules/*.md .claude/framework/rules/
chmod +x .claude/framework/hooks/*.sh

# Detect profile (clean setup) or use existing
if [ "$RECONFIGURE" = true ] || [ "$HAS_EXISTING" = false ]; then
  PROFILE=$(bash "$FRAMEWORK_CLONE/scripts/detect-profile.sh" | tail -1)
else
  PROFILE="mobile-app"  # Default for migration; user can reconfigure
  echo "Using default profile: $PROFILE (run init.sh --reconfigure to change)"
fi

# Parse profile to get rules and hooks
ALL_RULES=()
ALL_HOOKS=()
while IFS= read -r line; do
  case "$line" in
    rule:*) ALL_RULES+=("${line#rule:}") ;;
    hook:*) ALL_HOOKS+=("${line#hook:}") ;;
  esac
done <<< "$(parse_profile "$PROFILE")"

# Build manifest
FW_VERSION=$(cat "$FRAMEWORK_CLONE/FRAMEWORK_VERSION")
FW_COMMIT=$(cd "$FRAMEWORK_CLONE" && git rev-parse --short HEAD 2>/dev/null || echo "unknown")
TODAY=$(date +%Y-%m-%dT%H:%M:%SZ)

RULES_JSON=$(printf '%s\n' "${ALL_RULES[@]}" | jq -R . | jq -s '.')
HOOKS_JSON=$(printf '%s\n' "${ALL_HOOKS[@]}" | jq -R . | jq -s '.')

# Run discovery if clean setup or reconfigure
DISCOVERY_JSON="{}"
if [ "$HAS_EXISTING" = false ] || [ "$RECONFIGURE" = true ]; then
  DISCOVERY_JSON=$(run_discovery)
fi

# Write manifest
jq -n \
  --arg fv "$FW_VERSION" \
  --arg fc "$FW_COMMIT" \
  --arg sd "$TODAY" \
  --arg pr "$PROFILE" \
  --argjson rules "$RULES_JSON" \
  --argjson hooks "$HOOKS_JSON" \
  --argjson disc "$(echo "$DISCOVERY_JSON" | jq '.' 2>/dev/null || echo '{}')" \
  '{
    frameworkVersion: $fv,
    frameworkCommit: $fc,
    frameworkRepo: "kraulerson/claude-dev-framework",
    localClonePath: "~/.claude-dev-framework",
    lastSyncDate: $sd,
    profile: $pr,
    profileInherits: ["_base"],
    files: {},
    activeRules: $rules,
    activeHooks: $hooks,
    projectConfig: {
      _base: {
        sourceExtensions: [".py",".js",".ts",".go",".rs",".java",".kt",".swift"],
        protectedBranches: ["main"]
      },
      branches: []
    },
    discovery: $disc
  }' > .claude/manifest.json

# Generate settings.json
SETTINGS=$(generate_settings_json "${ALL_HOOKS[@]}")
if [ -f ".claude/settings.json" ]; then
  # Merge: preserve existing keys, replace hooks
  EXISTING=$(cat .claude/settings.json)
  echo "$EXISTING" | jq --argjson h "$(echo "$SETTINGS" | jq '.hooks')" '. + {hooks: $h}' > .claude/settings.json.tmp
  mv .claude/settings.json.tmp .claude/settings.json
else
  echo "$SETTINGS" > .claude/settings.json
fi

# Phase 7: VERIFY
echo ""
echo "=== Installation Complete ==="
echo "Profile: $PROFILE"
echo "Active rules: ${#ALL_RULES[@]}"
echo "Active hooks: ${#ALL_HOOKS[@]}"
echo "Framework version: $FW_VERSION"
echo ""
echo "Files created:"
echo "  .claude/framework/hooks/ ($(ls .claude/framework/hooks/*.sh 2>/dev/null | wc -l | xargs) scripts)"
echo "  .claude/framework/rules/ ($(ls .claude/framework/rules/*.md 2>/dev/null | wc -l | xargs) rules)"
echo "  .claude/manifest.json"
echo "  .claude/settings.json"
echo ""
echo "Start a new Claude Code session to activate the framework."
