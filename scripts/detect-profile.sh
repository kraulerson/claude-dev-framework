#!/usr/bin/env bash
# detect-profile.sh — Interactive profile auto-detection
# Called by init.sh during setup. Outputs the profile name as the last line.
set -euo pipefail

FRAMEWORK_DIR="${HOME}/.claude-dev-framework"
PROFILES_DIR="${FRAMEWORK_DIR}/profiles"

detect_signals() {
  local signals=""
  [ -f "build.gradle.kts" ] || [ -f "build.gradle" ] && signals="${signals}gradle "
  [ -f "Package.swift" ] || compgen -G "*.xcodeproj" >/dev/null 2>&1 && signals="${signals}swift "
  [ -f "pubspec.yaml" ] && signals="${signals}flutter "
  if [ -f "package.json" ]; then
    signals="${signals}node "
    grep -q "react-native" package.json 2>/dev/null && signals="${signals}reactnative "
    grep -qiE '"(react|vue|svelte|angular|next|nuxt)"' package.json 2>/dev/null && signals="${signals}frontend "
    grep -qiE '"(express|koa|hono|fastify)"' package.json 2>/dev/null && signals="${signals}nodebackend "
  fi
  [ -f "Cargo.toml" ] && signals="${signals}rust "
  [ -f "Dockerfile" ] || [ -f "docker-compose.yml" ] && signals="${signals}docker "
  [ -f "CMakeLists.txt" ] && signals="${signals}cmake "
  if [ -f "pyproject.toml" ] || [ -f "requirements.txt" ] || [ -f "setup.py" ]; then
    signals="${signals}python "
    grep -qiE 'fastapi|django|flask|starlette|sanic' requirements.txt pyproject.toml setup.py 2>/dev/null && signals="${signals}pyweb "
  fi
  [ -f "go.mod" ] && signals="${signals}go "
  [ -f "Gemfile" ] && signals="${signals}ruby "

  # Full-stack signals: frontend + backend directories
  if [ -d "client" ] || [ -d "frontend" ] || [ -d "src/components" ]; then
    signals="${signals}frontenddir "
  fi
  if [ -d "server" ] || [ -d "backend" ] || [ -d "api" ]; then
    signals="${signals}backenddir "
  fi
  echo "$signals"
}

suggest_profile() {
  local signals="$1"

  # Full-stack web-app: frontend framework + backend (directory or dependency)
  case "$signals" in
    *frontend*nodebackend*|*frontend*backenddir*|*frontend*pyweb*) echo "web-app"; return ;;
    *frontenddir*backenddir*) echo "web-app"; return ;;
    *nodebackend*frontenddir*) echo "web-app"; return ;;
  esac

  # Mobile
  case "$signals" in
    *gradle*swift*|*gradle*flutter*) echo "mobile-app"; return ;;
    *swift*) echo "mobile-app"; return ;;
    *gradle*) echo "mobile-app"; return ;;
    *flutter*) echo "mobile-app"; return ;;
    *reactnative*) echo "mobile-app"; return ;;
  esac

  # Web API (backend only, no frontend signals)
  case "$signals" in
    *pyweb*) echo "web-api"; return ;;
    *docker*node*|*docker*python*|*docker*go*|*docker*ruby*) echo "web-api"; return ;;
    *node*) echo "web-api"; return ;;
  esac

  # CLI
  case "$signals" in
    *rust*) echo "cli-tool"; return ;;
    *python*) echo "cli-tool"; return ;;
    *go*) echo "cli-tool"; return ;;
    *cmake*) echo "cli-tool"; return ;;
  esac

  echo ""
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
