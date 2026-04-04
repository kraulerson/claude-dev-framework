#!/usr/bin/env bash
# _helpers.sh — Shared utility functions for all framework hooks.
# Sourced by other hooks via: source "$(dirname "$0")/_helpers.sh"

check_jq() { command -v jq &>/dev/null; }

_MANIFEST_CACHE=""
_get_manifest_json() {
  if [ -z "$_MANIFEST_CACHE" ]; then
    local manifest; manifest="$(get_manifest_path)"
    [ -f "$manifest" ] && _MANIFEST_CACHE=$(cat "$manifest") || _MANIFEST_CACHE="{}"
  fi
  echo "$_MANIFEST_CACHE"
}

get_manifest_path() { echo "${CLAUDE_PROJECT_DIR:-.}/.claude/manifest.json"; }
get_framework_dir() { echo "${CLAUDE_PROJECT_DIR:-.}/.claude/framework"; }
get_project_hash() { echo -n "${CLAUDE_PROJECT_DIR:-$PWD}" | shasum -a 256 | cut -c1-12; }

get_manifest_value() {
  ! check_jq && { echo ""; return 0; }
  local json; json=$(_get_manifest_json)
  [ "$json" = "{}" ] && { echo ""; return 0; }
  echo "$json" | jq -r "$1 // empty" 2>/dev/null || echo ""
}

get_manifest_array() {
  ! check_jq && return 0
  local json; json=$(_get_manifest_json)
  [ "$json" = "{}" ] && return 0
  echo "$json" | jq -r "$1 // empty" 2>/dev/null || true
}

get_branch() { git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown"; }

get_branch_config_value() {
  local jq_path="$1" branch base_val branch_val
  branch="$(get_branch)"
  ! check_jq && { echo ""; return 0; }
  local json; json=$(_get_manifest_json)
  [ "$json" = "{}" ] && { echo ""; return 0; }
  base_val=$(echo "$json" | jq -r ".projectConfig._base${jq_path} // empty" 2>/dev/null || echo "")
  branch_val=$(echo "$json" | jq -r --arg b "$branch" '.projectConfig.branches[] | select(.match == $b) | .config'"${jq_path}"' // empty' 2>/dev/null || echo "")
  if [ -z "$branch_val" ]; then
    local patterns; patterns=$(echo "$json" | jq -r '.projectConfig.branches[].match // empty' 2>/dev/null || true)
    while IFS= read -r pattern; do
      [ -z "$pattern" ] && continue
      if [[ "$branch" == $pattern ]]; then
        local inherits; inherits=$(echo "$json" | jq -r --arg p "$pattern" '.projectConfig.branches[] | select(.match == $p) | .inherits // empty' 2>/dev/null || echo "")
        [ -n "$inherits" ] && branch_val=$(echo "$json" | jq -r --arg b "$inherits" '.projectConfig.branches[] | select(.match == $b) | .config'"${jq_path}"' // empty' 2>/dev/null || echo "")
        local overlay; overlay=$(echo "$json" | jq -r --arg p "$pattern" '.projectConfig.branches[] | select(.match == $p) | .config'"${jq_path}"' // empty' 2>/dev/null || echo "")
        [ -n "$overlay" ] && branch_val="$overlay"
        break
      fi
    done <<< "$patterns"
  fi
  if [ -n "$branch_val" ]; then echo "$branch_val"; elif [ -n "$base_val" ]; then echo "$base_val"; else echo ""; fi
}

get_branch_config_array() {
  local jq_path="$1" branch result
  branch="$(get_branch)"
  ! check_jq && return 0
  local json; json=$(_get_manifest_json)
  [ "$json" = "{}" ] && return 0
  result=$(echo "$json" | jq -r --arg b "$branch" '(.projectConfig.branches[] | select(.match == $b) | .config'"${jq_path}"'[]?) // empty' 2>/dev/null || true)
  [ -z "$result" ] && result=$(echo "$json" | jq -r ".projectConfig._base${jq_path}[]? // empty" 2>/dev/null || true)
  echo "$result"
}

is_source_file() {
  local ext=".${1##*.}"

  # 1. Deny known generated compound extensions (before allowlist — .min.js is not .js)
  case "$1" in
    *.min.js|*.min.css|*.d.ts) return 1 ;;
  esac

  # 2. Explicit allowlist from manifest (or fallback) — user override
  local extensions
  extensions=$(get_branch_config_array '.sourceExtensions')
  if [ -z "$extensions" ]; then
    extensions=".html .css .scss .less .sass .jsx .tsx .vue .svelte"
    extensions="$extensions .js .ts .mjs .cjs"
    extensions="$extensions .py .ipynb"
    extensions="$extensions .java .kt .kts .scala .groovy"
    extensions="$extensions .cs .fs .vb"
    extensions="$extensions .swift .m .mm"
    extensions="$extensions .c .cpp .h .hpp .rs .go .zig .asm .s"
    extensions="$extensions .rb .erb"
    extensions="$extensions .php"
    extensions="$extensions .sh .bash .zsh"
    extensions="$extensions .bat .cmd .ps1 .psm1 .vbs"
    extensions="$extensions .dart"
    extensions="$extensions .ex .exs .erl"
    extensions="$extensions .hs"
    extensions="$extensions .clj .cljs"
    extensions="$extensions .lua"
    extensions="$extensions .r .R"
    extensions="$extensions .pl .pm"
    extensions="$extensions .sql .graphql .proto"
    extensions="$extensions .tf .hcl"
  fi
  for e in $extensions; do [ "$ext" = "$e" ] && return 0; done

  # 3. Doc/config files are not source
  is_doc_or_config "$1" && return 1

  # 4. Denylist: binary, generated, and data formats
  case "$ext" in
    # Images
    .png|.jpg|.jpeg|.gif|.svg|.ico|.webp|.bmp) return 1 ;;
    # Audio/video
    .mp3|.mp4|.wav|.mov|.avi|.ogg|.flac|.mkv) return 1 ;;
    # Documents/archives
    .pdf|.zip|.tar|.gz|.7z|.rar|.bz2|.xz) return 1 ;;
    # Fonts
    .woff|.woff2|.ttf|.eot|.otf) return 1 ;;
    # Compiled/binary
    .jar|.dll|.exe|.so|.dylib|.o|.pyc|.class|.wasm) return 1 ;;
    # Lock/database
    .lock|.sqlite|.db) return 1 ;;
    # Generated
    .map) return 1 ;;
    # Data formats
    .csv|.tsv|.parquet|.avro) return 1 ;;
  esac

  # 5. Default: treat unknown extensions as source
  return 0
}

is_test_file() {
  local basename; basename="$(basename "$1")"
  case "$basename" in *Test*|*test*|*Spec*|*spec*|*_test.*) return 0 ;; esac
  case "$1" in */tests/*|*/test/*|*/Tests/*|*/__tests__/*|*/spec/*) return 0 ;; esac
  return 1
}

is_doc_or_config() {
  case ".${1##*.}" in .md|.txt|.json|.yml|.yaml|.xml|.toml|.ini|.cfg|.conf) return 0 ;; esac
  return 1
}

validate_file_path() {
  case "$1" in
    *../*|*/../*) echo "REJECTED: path traversal" >&2; return 1 ;;
  esac
  return 0
}

check_context7() {
  # Check if Context7 MCP server is registered in Claude Code
  local settings="$HOME/.claude/settings.json"
  [ ! -f "$settings" ] && return 1
  check_jq || return 1
  jq -e '.mcpServers.context7 // .mcpServers["context7-mcp"] // empty' "$settings" >/dev/null 2>&1
}
