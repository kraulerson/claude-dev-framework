#!/usr/bin/env bash
# detect-profile.sh — Interactive profile auto-detection
# Called by init.sh during setup. Outputs the profile name as the last line.
set -euo pipefail

FRAMEWORK_DIR="${HOME}/.claude-dev-framework"
PROFILES_DIR="${FRAMEWORK_DIR}/profiles"

detect_signals() {
  local signals=""
  [ -f "build.gradle.kts" ] || [ -f "build.gradle" ] && signals="${signals}gradle "
  [ -f "Package.swift" ] || ls *.xcodeproj &>/dev/null 2>&1 && signals="${signals}swift "
  [ -f "pubspec.yaml" ] && signals="${signals}flutter "
  [ -f "package.json" ] && signals="${signals}node "
  [ -f "Cargo.toml" ] && signals="${signals}rust "
  [ -f "Dockerfile" ] || [ -f "docker-compose.yml" ] && signals="${signals}docker "
  [ -f "CMakeLists.txt" ] && signals="${signals}cmake "
  [ -f "pyproject.toml" ] || [ -f "requirements.txt" ] || [ -f "setup.py" ] && signals="${signals}python "
  [ -f "go.mod" ] && signals="${signals}go "
  [ -f "Gemfile" ] && signals="${signals}ruby "
  echo "$signals"
}

suggest_profile() {
  local signals="$1"
  case "$signals" in
    *gradle*swift*|*gradle*flutter*) echo "mobile-app" ;;
    *swift*) echo "mobile-app" ;;
    *gradle*) echo "mobile-app" ;;
    *flutter*) echo "mobile-app" ;;
    *docker*node*|*docker*python*|*docker*go*|*docker*ruby*) echo "web-api" ;;
    *node*) echo "web-api" ;;
    *rust*) echo "cli-tool" ;;
    *python*) echo "cli-tool" ;;
    *go*) echo "cli-tool" ;;
    *cmake*) echo "cli-tool" ;;
    *) echo "" ;;
  esac
}

echo "=== Profile Detection ==="
echo ""
SIGNALS=$(detect_signals)
SUGGESTED=$(suggest_profile "$SIGNALS")

if [ -n "$SUGGESTED" ]; then
  echo "Detected signals: $SIGNALS"
  echo "Suggested profile: $SUGGESTED"
  echo ""
  echo "Available profiles:"
  for f in "$PROFILES_DIR"/*.yml; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .yml)
    [ "$name" = "_base" ] && continue
    desc=$(grep '^description:' "$f" | sed 's/description: //')
    marker=""
    [ "$name" = "$SUGGESTED" ] && marker=" ← suggested"
    echo "  - $name: $desc$marker"
  done
  echo ""
  read -rp "Use '$SUGGESTED'? (y/n/other profile name): " choice
  case "$choice" in
    y|Y|yes|"") echo "$SUGGESTED" ;;
    n|N|no)
      read -rp "Enter profile name: " custom
      echo "$custom"
      ;;
    *) echo "$choice" ;;
  esac
else
  echo "No recognized project signals found."
  echo ""
  echo "Available profiles:"
  for f in "$PROFILES_DIR"/*.yml; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .yml)
    [ "$name" = "_base" ] && continue
    desc=$(grep '^description:' "$f" | sed 's/description: //')
    echo "  - $name: $desc"
  done
  echo ""
  read -rp "Enter a profile name (or 'new' to create one): " choice
  if [ "$choice" = "new" ]; then
    read -rp "What kind of project is this? " project_type
    PROFILE_NAME=$(echo "$project_type" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
    cat > "$PROFILES_DIR/${PROFILE_NAME}.yml" << YMLEOF
name: $PROFILE_NAME
description: $project_type
inherits: _base

rules:
  - version-bump
  - changelog-update

hooks:
  - pre-commit-checks
  - branch-safety

discovery_questions: []
suggests:
  sourceExtensions: []
  changelogFile: "CHANGELOG.md"
  protectedBranches: ["main"]
YMLEOF
    echo "Created new profile: $PROFILE_NAME"
    echo ""
    read -rp "Push this profile to the global framework repo? (y/n): " push_choice
    if [ "$push_choice" = "y" ]; then
      pushd "$FRAMEWORK_DIR" > /dev/null
      git add "profiles/${PROFILE_NAME}.yml"
      git commit -m "Add new profile: $PROFILE_NAME"
      git push origin main 2>/dev/null || echo "Push failed — you can push manually later."
      popd > /dev/null
    fi
    echo "$PROFILE_NAME"
  else
    echo "$choice"
  fi
fi
