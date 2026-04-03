#!/usr/bin/env bash
# init.sh — First-time setup + migration for Claude Dev Framework
set -euo pipefail

FRAMEWORK_CLONE="$HOME/.claude-dev-framework"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---- Flags ----
MIGRATE=false; RECONFIGURE=false; ARCHIVE=false; SKIP_PLUGINS=false; PREPOPULATE_FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --migrate) MIGRATE=true ;;
    --reconfigure) RECONFIGURE=true ;;
    --archive) ARCHIVE=true ;;
    --skip-plugin-check) SKIP_PLUGINS=true ;;
    --prepopulate) shift; PREPOPULATE_FILE="${1:-}" ;;
  esac
  shift
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

# ---- Shared functions (generate_settings_json, merge_hooks_into_settings) ----
source "$(dirname "$0")/_shared.sh"
source "$FRAMEWORK_CLONE/hooks/_helpers.sh" 2>/dev/null || true

# ---- Helper: Discovery Interview ----
run_discovery() {
  echo "" >&2
  echo "=== Project Discovery Interview ===" >&2
  echo "All questions are optional. Press Enter to skip any question." >&2
  echo "" >&2

  local branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
  read -rp "1. What does the '$branch' branch represent? (e.g., 'iOS development', 'main dev branch'): " branch_purpose
  read -rp "2. What OS are you developing ON? (e.g., macOS, Windows, Linux): " dev_os
  read -rp "3. What platform does this branch TARGET? (e.g., iOS 16+, Android API 26+, web, N/A): " target_platform
  read -rp "4. Are there other branches with different configurations? (y/n): " has_other_branches

  local other_branches=""
  if [ "$has_other_branches" = "y" ]; then
    read -rp "   List branch names (comma-separated): " other_list
    IFS=',' read -ra BRANCHES <<< "$other_list"
    for ob in "${BRANCHES[@]}"; do
      ob=$(echo "$ob" | xargs)  # trim
      read -rp "   Branch '$ob' — purpose? " ob_purpose
      read -rp "   Branch '$ob' — target platform? " ob_target
      other_branches="${other_branches}$(jq -n --arg name "$ob" --arg p "$ob_purpose" --arg t "$ob_target" \
        '{("branch:" + $name): {purpose: $p, targetPlatform: $t}}')"$'\n'
    done
  fi

  read -rp "5. Build tools or constraints? (e.g., 'Xcode, Gradle', 'needs CUDA'): " build_tools
  read -rp "6. Will this project expand to other platforms in the future? (e.g., 'might add web dashboard'): " future_platforms

  local today=$(date +%Y-%m-%d)

  # Build discovery JSON safely with jq (no manual string concatenation)
  local base
  base=$(jq -n \
    --arg branch "$branch" \
    --arg purpose "$branch_purpose" \
    --arg os "$dev_os" \
    --arg target "$target_platform" \
    --arg tools "$build_tools" \
    --arg future "$future_platforms" \
    --arg today "$today" \
    '{
      ("branch:" + $branch): {purpose: $purpose, devOS: $os, targetPlatform: $target, buildTools: $tools},
      futurePlatforms: (if $future != "" then $future else null end),
      discoveryDate: $today,
      lastReviewDate: $today
    }')

  # Merge in other branches if any
  if [ -n "$other_branches" ]; then
    echo "$other_branches" | jq -s --argjson base "$base" '$base + (map(.) | add)'
  else
    echo "$base"
  fi
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

  # Phase 5: DEPENDENCY CHECK
  if [ "$SKIP_PLUGINS" = false ]; then
    echo "── Phase 5: DEPENDENCY CHECK ──"

    if [ -f "$HOME/.claude/settings.json" ] && command -v jq &>/dev/null; then
      SP=$(jq -r '.enabledPlugins["superpowers@claude-plugins-official"] // false' "$HOME/.claude/settings.json" 2>/dev/null || echo "false")
      if [ "$SP" = "true" ]; then
        echo "  ✓ Superpowers plugin: INSTALLED"
      else
        echo "  ✗ Superpowers plugin: NOT INSTALLED (required)"
        echo "    Install: Run claude > /plugins > search 'superpowers' > install"
      fi
    fi

    if check_context7 2>/dev/null; then
      echo "  ✓ Context7 MCP: INSTALLED"
    else
      echo "  ✗ Context7 MCP: NOT INSTALLED (required for v4.0.0)"
      read -rp "    Install Context7 now? (requires Node.js) [y/N]: " c7_reply
      if [[ "$c7_reply" =~ ^[Yy]$ ]]; then
        echo "    Installing Context7..."
        claude mcp add context7 -- npx -y @upstash/context7-mcp@latest 2>/dev/null && echo "  ✓ Context7 MCP: INSTALLED" || echo "  ✗ Context7 install failed. Implementation Zone will be degraded."
      else
        echo "    Skipped. Implementation Zone will be degraded until Context7 is installed."
      fi
    fi

    echo ""
  fi

  read -rp "Proceed with framework installation? (y/n): " proceed
  [ "$proceed" != "y" ] && { echo "Aborted."; exit 0; }
fi

# ---- Dependency check (clean install path) ----
if [ "$HAS_EXISTING" = false ] && [ "$SKIP_PLUGINS" = false ]; then
  echo "── Checking Dependencies ──"

  if [ -f "$HOME/.claude/settings.json" ] && command -v jq &>/dev/null; then
    SP=$(jq -r '.enabledPlugins["superpowers@claude-plugins-official"] // false' "$HOME/.claude/settings.json" 2>/dev/null || echo "false")
    if [ "$SP" = "true" ]; then
      echo "  ✓ Superpowers plugin: INSTALLED"
    else
      echo "  ✗ Superpowers plugin: NOT INSTALLED (required)"
      echo "    Install: Run claude > /plugins > search 'superpowers' > install"
    fi
  fi

  if check_context7 2>/dev/null; then
    echo "  ✓ Context7 MCP: INSTALLED"
  else
    echo "  ✗ Context7 MCP: NOT INSTALLED (required for v4.0.0)"
    read -rp "    Install Context7 now? (requires Node.js) [y/N]: " c7_reply
    if [[ "$c7_reply" =~ ^[Yy]$ ]]; then
      echo "    Installing Context7..."
      claude mcp add context7 -- npx -y @upstash/context7-mcp@latest 2>/dev/null && echo "  ✓ Context7 MCP: INSTALLED" || echo "  ✗ Context7 install failed. Implementation Zone will be degraded."
    else
      echo "    Skipped. Implementation Zone will be degraded until Context7 is installed."
    fi
  fi

  echo ""
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

# Detect profile (runs for all paths — clean, migration, and reconfigure)
PROFILE=$(bash "$FRAMEWORK_CLONE/scripts/detect-profile.sh" | tail -1)

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

# Run discovery — prepopulate takes priority over interactive interview
DISCOVERY_JSON="{}"
if [ -n "$PREPOPULATE_FILE" ]; then
  if [ ! -f "$PREPOPULATE_FILE" ]; then
    echo "WARNING: Prepopulate file not found: $PREPOPULATE_FILE. Falling back to interview." >&2
  elif ! jq '.' "$PREPOPULATE_FILE" >/dev/null 2>&1; then
    echo "WARNING: Prepopulate file is not valid JSON: $PREPOPULATE_FILE. Falling back to interview." >&2
  elif ! jq -e 'keys[] | select(startswith("branch:"))' "$PREPOPULATE_FILE" >/dev/null 2>&1; then
    echo "WARNING: Prepopulate file has no branch:* keys: $PREPOPULATE_FILE. Falling back to interview." >&2
  else
    DISCOVERY_JSON=$(cat "$PREPOPULATE_FILE")
    echo "Using pre-populated discovery from $PREPOPULATE_FILE" >&2
  fi
  # If validation failed, DISCOVERY_JSON is still "{}" — fall back to interview
  if [ "$DISCOVERY_JSON" = "{}" ]; then
    DISCOVERY_JSON=$(run_discovery)
  fi
elif [ "$HAS_EXISTING" = false ] || [ "$RECONFIGURE" = true ]; then
  DISCOVERY_JSON=$(run_discovery)
fi

# Validate all JSON before passing to jq (diagnose which value is bad)
DISC_CLEAN=$(echo "$DISCOVERY_JSON" | jq '.' 2>/dev/null || echo '{}')
for _name in RULES_JSON HOOKS_JSON DISC_CLEAN; do
  eval "_val=\$$_name"
  if ! echo "$_val" | jq '.' >/dev/null 2>&1; then
    echo "ERROR: $_name is not valid JSON:" >&2
    echo "$_val" >&2
    exit 1
  fi
done

# Write manifest
jq -n \
  --arg fv "$FW_VERSION" \
  --arg fc "$FW_COMMIT" \
  --arg sd "$TODAY" \
  --arg pr "$PROFILE" \
  --argjson rules "$RULES_JSON" \
  --argjson hooks "$HOOKS_JSON" \
  --argjson disc "$DISC_CLEAN" \
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
if ! echo "$SETTINGS" | jq '.' >/dev/null 2>&1; then
  echo "ERROR: generate_settings_json produced invalid JSON:" >&2
  echo "$SETTINGS" >&2
  exit 1
fi

merge_hooks_into_settings "$SETTINGS" ".claude/settings.json"

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
