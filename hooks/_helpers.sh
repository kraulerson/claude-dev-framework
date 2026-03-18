#!/usr/bin/env bash
# _helpers.sh — Shared utility functions for all framework hooks.
# Sourced by other hooks via: source "$(dirname "$0")/_helpers.sh"

check_jq() { command -v jq &>/dev/null; }
check_git() { command -v git &>/dev/null; }

get_manifest_path() { echo "${CLAUDE_PROJECT_DIR:-.}/.claude/manifest.json"; }
get_framework_dir() { echo "${CLAUDE_PROJECT_DIR:-.}/.claude/framework"; }
get_project_hash() { echo -n "${CLAUDE_PROJECT_DIR:-$PWD}" | shasum -a 256 | cut -c1-12; }

get_manifest_value() {
  local manifest; manifest="$(get_manifest_path)"
  [ ! -f "$manifest" ] || ! check_jq && { echo ""; return 0; }
  jq -r "$1 // empty" "$manifest" 2>/dev/null || echo ""
}

get_manifest_array() {
  local manifest; manifest="$(get_manifest_path)"
  [ ! -f "$manifest" ] || ! check_jq && return 0
  jq -r "$1 // empty" "$manifest" 2>/dev/null || true
}

get_branch() { git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown"; }

get_branch_config_value() {
  local jq_path="$1" branch manifest base_val branch_val
  branch="$(get_branch)"; manifest="$(get_manifest_path)"
  [ ! -f "$manifest" ] || ! check_jq && { echo ""; return 0; }
  base_val=$(jq -r ".projectConfig._base${jq_path} // empty" "$manifest" 2>/dev/null || echo "")
  branch_val=$(jq -r --arg b "$branch" '.projectConfig.branches[] | select(.match == $b) | .config'"${jq_path}"' // empty' "$manifest" 2>/dev/null || echo "")
  if [ -z "$branch_val" ]; then
    local patterns; patterns=$(jq -r '.projectConfig.branches[].match // empty' "$manifest" 2>/dev/null || true)
    while IFS= read -r pattern; do
      [ -z "$pattern" ] && continue
      if [[ "$branch" == $pattern ]]; then
        local inherits; inherits=$(jq -r --arg p "$pattern" '.projectConfig.branches[] | select(.match == $p) | .inherits // empty' "$manifest" 2>/dev/null || echo "")
        [ -n "$inherits" ] && branch_val=$(jq -r --arg b "$inherits" '.projectConfig.branches[] | select(.match == $b) | .config'"${jq_path}"' // empty' "$manifest" 2>/dev/null || echo "")
        local overlay; overlay=$(jq -r --arg p "$pattern" '.projectConfig.branches[] | select(.match == $p) | .config'"${jq_path}"' // empty' "$manifest" 2>/dev/null || echo "")
        [ -n "$overlay" ] && branch_val="$overlay"
        break
      fi
    done <<< "$patterns"
  fi
  if [ -n "$branch_val" ]; then echo "$branch_val"; elif [ -n "$base_val" ]; then echo "$base_val"; else echo ""; fi
}

get_branch_config_array() {
  local jq_path="$1" branch manifest result
  branch="$(get_branch)"; manifest="$(get_manifest_path)"
  [ ! -f "$manifest" ] || ! check_jq && return 0
  result=$(jq -r --arg b "$branch" '(.projectConfig.branches[] | select(.match == $b) | .config'"${jq_path}"'[]?) // empty' "$manifest" 2>/dev/null || true)
  [ -z "$result" ] && result=$(jq -r ".projectConfig._base${jq_path}[]? // empty" "$manifest" 2>/dev/null || true)
  echo "$result"
}

is_source_file() {
  local ext=".${1##*.}" extensions
  extensions=$(get_branch_config_array '.sourceExtensions')
  [ -z "$extensions" ] && extensions=".py .js .ts .go .rs .java .kt .swift .rb .c .cpp .h .css .scss .less .html .jsx .tsx .vue .svelte"
  for e in $extensions; do [ "$ext" = "$e" ] && return 0; done
  return 1
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
