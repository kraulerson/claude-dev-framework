#!/usr/bin/env bash
# _helpers.sh — Shared utility functions for all framework hooks.
# Sourced by other hooks via: source "$(dirname "$0")/_helpers.sh"

check_jq() { command -v jq &>/dev/null; }

_get_manifest_json() {
  local manifest; manifest="$(get_manifest_path)"
  [ -f "$manifest" ] && cat "$manifest" || echo "{}"
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

_SOURCE_EXTS_CACHE=""
is_source_file() {
  local ext=".${1##*.}"

  # 1. Deny known generated compound extensions (before allowlist — .min.js is not .js)
  case "$1" in
    *.min.js|*.min.css|*.d.ts) return 1 ;;
  esac

  # 2. Explicit allowlist from manifest (or fallback) — user override
  if [ -z "$_SOURCE_EXTS_CACHE" ]; then
    _SOURCE_EXTS_CACHE=$(get_branch_config_array '.sourceExtensions')
    if [ -z "$_SOURCE_EXTS_CACHE" ]; then
      _SOURCE_EXTS_CACHE=".html .css .scss .less .sass .jsx .tsx .vue .svelte"
      _SOURCE_EXTS_CACHE="$_SOURCE_EXTS_CACHE .js .ts .mjs .cjs"
      _SOURCE_EXTS_CACHE="$_SOURCE_EXTS_CACHE .py .ipynb"
      _SOURCE_EXTS_CACHE="$_SOURCE_EXTS_CACHE .java .kt .kts .scala .groovy"
      _SOURCE_EXTS_CACHE="$_SOURCE_EXTS_CACHE .cs .fs .vb"
      _SOURCE_EXTS_CACHE="$_SOURCE_EXTS_CACHE .swift .m .mm"
      _SOURCE_EXTS_CACHE="$_SOURCE_EXTS_CACHE .c .cpp .h .hpp .rs .go .zig .asm .s"
      _SOURCE_EXTS_CACHE="$_SOURCE_EXTS_CACHE .rb .erb"
      _SOURCE_EXTS_CACHE="$_SOURCE_EXTS_CACHE .php"
      _SOURCE_EXTS_CACHE="$_SOURCE_EXTS_CACHE .sh .bash .zsh"
      _SOURCE_EXTS_CACHE="$_SOURCE_EXTS_CACHE .bat .cmd .ps1 .psm1 .vbs"
      _SOURCE_EXTS_CACHE="$_SOURCE_EXTS_CACHE .dart"
      _SOURCE_EXTS_CACHE="$_SOURCE_EXTS_CACHE .ex .exs .erl"
      _SOURCE_EXTS_CACHE="$_SOURCE_EXTS_CACHE .hs"
      _SOURCE_EXTS_CACHE="$_SOURCE_EXTS_CACHE .clj .cljs"
      _SOURCE_EXTS_CACHE="$_SOURCE_EXTS_CACHE .lua"
      _SOURCE_EXTS_CACHE="$_SOURCE_EXTS_CACHE .r .R"
      _SOURCE_EXTS_CACHE="$_SOURCE_EXTS_CACHE .pl .pm"
      _SOURCE_EXTS_CACHE="$_SOURCE_EXTS_CACHE .sql .graphql .proto"
      _SOURCE_EXTS_CACHE="$_SOURCE_EXTS_CACHE .tf .hcl"
    fi
  fi
  for e in $_SOURCE_EXTS_CACHE; do [ "$ext" = "$e" ] && return 0; done

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

check_context7() {
  # Three valid install paths: direct MCP in ~/.claude/settings.json, direct MCP in ~/.claude.json (what `claude mcp add -s user` writes), or plugin entry in ~/.claude/settings.json under .enabledPlugins.
  check_jq || return 1
  local user_settings="$HOME/.claude/settings.json"
  local user_json="$HOME/.claude.json"
  [ -f "$user_settings" ] && jq -e '.mcpServers.context7 // .mcpServers["context7-mcp"] // empty' "$user_settings" >/dev/null 2>&1 && return 0
  [ -f "$user_json" ]     && jq -e '.mcpServers.context7 // .mcpServers["context7-mcp"] // empty' "$user_json"     >/dev/null 2>&1 && return 0
  [ -f "$user_settings" ] && jq -e '(.enabledPlugins // {}) | to_entries[] | select(.key | test("^context7(@|$)"; "i")) | select(.value == true)' "$user_settings" >/dev/null 2>&1 && return 0
  return 1
}

# ---- Guard path helpers (marker-guard.sh, config-guard.sh; #11) ----

# Normalize a path lexically (no disk access): collapse `//`, drop `/.` segments,
# and resolve `/..` so non-canonical forms like `/tmp/./.claude_x`, `/tmp//.claude_x`,
# and `/tmp/foo/../.claude_x` cannot slip past the marker-path glob (R-07).
_normalize_path() {
  local input="$1" lead="" seg oldIFS out noglob=""
  case "$input" in /*) lead="/";; esac
  # Split on `/` without glob expansion: a `*` segment must stay literal.
  case "$-" in *f*) noglob=1 ;; esac
  set -f
  oldIFS="$IFS"; IFS='/'
  # shellcheck disable=SC2086
  set -- $input
  IFS="$oldIFS"
  [ -n "$noglob" ] || set +f
  local stack
  stack=()
  for seg in "$@"; do
    case "$seg" in
      ''|.) : ;;
      ..)
        # Popping the highest index keeps the array contiguous; rebuilding it with
        # "${stack[@]}" failed on an empty array under set -u in bash 3.2 (#11 review).
        if [ "${#stack[@]}" -gt 0 ]; then
          unset "stack[$(( ${#stack[@]} - 1 ))]"
        fi
        ;;
      *) stack[${#stack[@]}]="$seg" ;;
    esac
  done
  oldIFS="$IFS"; IFS='/'
  if [ "${#stack[@]}" -gt 0 ]; then out="${stack[*]}"; else out=""; fi
  IFS="$oldIFS"
  printf '%s%s\n' "$lead" "$out"
}

# The command text with every path's `//`, `/./`, `<segment>/../` (a segment may
# contain spaces) and a trailing `/.` or `/<segment>/..` collapsed, so a
# non-canonical spelling such as `.claude/framework/./hooks/` still names the
# protected path. Lexical and
# approximate: it only ever adds matches, so the guards check it alongside the
# original text.
normalize_command_paths() {
  local c="$1" prev=""
  while [ "$c" != "$prev" ]; do
    prev="$c"
    c=$(sed -e 's#//*#/#g' -e 's#/\./#/#g' -e 's#/[^/]*/\.\./#/#g' \
            -e 's#/\.$#/#' -e "s#/\\.\\([[:space:]'\"]\\)#/\\1#g" \
            -e 's#/[^/]*/\.\.$#/#' -e "s#/[^/]*/\\.\\.\\([[:space:]'\"]\\)#/\\1#g" <<< "$c")
  done
  printf '%s\n' "$c"
}

# The framework config paths config-guard protects, as an ERE matched case-insensitively
# (a case-insensitive disk, macOS's default, treats .Claude/Settings.json as the same
# file): settings.json, settings.local.json, manifest.json, anything under
# framework/hooks/, and the bare .claude/framework and .claude/framework/hooks
# directories, which a copy or move can target as a destination. The bare .claude
# directory is not: the word appears in commit messages and everyday commands, and a
# copy into it needs a source file already named settings.json — no cheaper than the
# write-a-script-then-run-it residual (R-23).
CONFIG_GUARD_PROTECTED_RE='\.claude/(settings\.json|settings\.local\.json|manifest\.json|framework/hooks/)|\.claude/framework(/hooks)?/?([^[:alnum:]_./-]|$)'

# A lone command: no chaining, piping, redirection, substitution or newline.
is_lone_command() {
  ! [[ "$1" =~ [\;\&\|\`\>\<] || "$1" == *'$('* || "$1" == *$'\n'* ]]
}

# True when COMMAND is a lone invocation of the project's own mark-evaluated.sh or
# mark-plan-closed.sh. The first word must be a plain path, and that path — taken
# relative to $2, the agent's working directory from the hook input — must resolve
# to <project>/.claude/framework/hooks/. A script of the same name anywhere else
# does not count.
is_sanctioned_mark_command() {
  local cmd="$1" base="${2:-${CLAUDE_PROJECT_DIR:-$PWD}}" path name dir hooks
  is_lone_command "$cmd" || return 1
  [[ "$cmd" =~ ^[[:space:]]*(bash[[:space:]]+)?([[:alnum:]_./+@,:%-]*mark-(evaluated|plan-closed)\.sh)([[:space:]]|$) ]] || return 1
  path="${BASH_REMATCH[2]}"
  case "$path" in /*) ;; *) path="$base/$path" ;; esac
  name="${path##*/}"
  [ "$name" = "mark-evaluated.sh" ] || [ "$name" = "mark-plan-closed.sh" ] || return 1
  dir=$(cd "${path%/*}/" 2>/dev/null && pwd -P) || return 1
  hooks=$(cd "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/framework/hooks" 2>/dev/null && pwd -P) || return 1
  [ "$dir" = "$hooks" ]
}

# Print an absolute path with its nearest existing ancestor resolved (symlinks
# followed) and the not-yet-existing remainder appended. Refuses a relative path
# and any `.` or `..` segment.
resolve_path_physical() {
  local p="$1" head tail=""
  case "$p" in /*) ;; *) return 1 ;; esac
  case "$p/" in */./*|*/../*) return 1 ;; esac
  head="$p"
  while [ ! -d "$head" ]; do
    tail="/${head##*/}$tail"
    head="${head%/*}"
    [ -n "$head" ] || head="/"
  done
  head=$(cd "$head" 2>/dev/null && pwd -P) || return 1
  printf '%s%s\n' "${head%/}" "$tail"
}

# True when an absolute path resolves into a system temp folder and outside the
# project — a throwaway fixture, not the project's own configuration.
path_is_foreign_temp() {
  local r proj root
  r=$(resolve_path_physical "$1") || return 1
  proj=$(cd "${CLAUDE_PROJECT_DIR:-$PWD}" 2>/dev/null && pwd -P) || return 1
  case "$r/" in "$proj"/*) return 1 ;; esac
  for root in /tmp /private/tmp /var/folders /private/var/folders; do
    root=$(cd "$root" 2>/dev/null && pwd -P) || continue
    case "$r/" in "$root"/*) return 0 ;; esac
  done
  return 1
}

# True when every .claude path in a Bash command is a literal absolute path into a temp
# fixture (path_is_foreign_temp). The command must be a single command — no `;`, `&`,
# `|` or newline — because a chained command could first point a temp path at the
# project (`ln -s <project> /tmp/x && cp f /tmp/x/.claude/settings.json`); fixture
# content goes through the Write tool. Anything the text alone cannot pin down counts
# as the project's own path: a backslash, `#`, backtick or `$` quoting/substitution
# anywhere; a path glued to a variable, glob, brace or `~`; or one inside a quoted
# string that starts earlier.
all_protected_paths_foreign() {
  local cmd="$1" rest m c tok pre prev q="" quotes i found=0
  local re='(^|[^[:alnum:]_./+@,:%-])([[:alnum:]_./+@,:%-]*\.[cC][lL][aA][uU][dD][eE][[:alnum:]_./+@,:%-]*)'
  [ "${#cmd}" -le 16384 ] || return 1
  case "$cmd" in *\\*|*\#*|*\`*|*\;*|*\&*|*\|*|*$'\n'*|*'$('*|*'${'*|*"\$'"*|*'$"'*) return 1 ;; esac
  rest="$cmd"; prev=""
  while [[ "$rest" =~ $re ]]; do
    m="${BASH_REMATCH[0]}"; c="${BASH_REMATCH[1]}"; tok="${BASH_REMATCH[2]}"
    pre="${rest%%"$m"*}"
    # Quote state up to the boundary character: only the quote characters matter, so
    # scan just those (a per-character loop over the text was quadratic on bash 3.2).
    quotes=$(tr -cd "\"'" <<< "$pre")
    for ((i = 0; i < ${#quotes}; i++)); do
      case "$q" in
        "") q="${quotes:i:1}" ;;
        *) [ "${quotes:i:1}" = "$q" ] && q="" ;;
      esac
    done
    [ -n "$pre" ] && prev="${pre:${#pre}-1:1}"
    case "$c" in
      ''|' '|$'\t'|'>'|'<') [ -z "$q" ] || return 1 ;;
      "'"|'"')
        [ -z "$q" ] || return 1
        case "$prev" in ''|' '|$'\t'|'>'|'<') ;; *) return 1 ;; esac
        q="$c" ;;
      *) return 1 ;;
    esac
    path_is_foreign_temp "$tok" || return 1
    found=1; prev="${tok:${#tok}-1:1}"
    rest="${rest#*"$m"}"
  done
  [ "$found" = 1 ]
}
