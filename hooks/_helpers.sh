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
    # Data formats. JSON Lines covers the framework's audit logs, which stay tracked:
    # .claude/approvals.jsonl (record-approval, marker-tracker) and Solo's
    # .claude/tdd-warn-ledger.jsonl (owner ruling, 2026-10-07).
    .csv|.tsv|.parquet|.avro|.jsonl|.ndjson) return 1 ;;
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
  # git's ignore and attribute files and .editorconfig: named by a leading dot, so the
  # extension test reads the whole name (dogfood-3 row 7). Other unknown names stay
  # source (fail strict).
  case "${1##*/}" in .gitignore|.gitattributes|.dockerignore|.editorconfig) return 0 ;; esac
  return 1
}

check_context7() {
  # Three valid install paths: direct MCP in the user settings.json, direct MCP in the
  # user .claude.json (what `claude mcp add -s user` writes), or a plugin entry in the
  # user settings.json under .enabledPlugins. The user files live in $CLAUDE_CONFIG_DIR
  # when it is set (both settings.json and .claude.json), else ~/.claude and ~/.claude.json.
  check_jq || return 1
  local user_settings="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
  local user_json="$HOME/.claude.json"
  [ -n "${CLAUDE_CONFIG_DIR:-}" ] && user_json="$CLAUDE_CONFIG_DIR/.claude.json"
  [ -f "$user_settings" ] && jq -e '.mcpServers.context7 // .mcpServers["context7-mcp"] // empty' "$user_settings" >/dev/null 2>&1 && return 0
  [ -f "$user_json" ]     && jq -e '.mcpServers.context7 // .mcpServers["context7-mcp"] // empty' "$user_json"     >/dev/null 2>&1 && return 0
  [ -f "$user_settings" ] && jq -e '(.enabledPlugins // {}) | to_entries[] | select(.key | test("^context7(@|$)"; "i")) | select(.value == true)' "$user_settings" >/dev/null 2>&1 && return 0
  return 1
}

# The Claude Code settings files that can enable a plugin, highest precedence first:
# the project's local and shared settings, then the user's — under
# $CLAUDE_CONFIG_DIR when it is set, as `claude plugin install --scope user` writes
# there, else ~/.claude.
plugin_settings_files() {
  printf '%s\n' "${CLAUDE_PROJECT_DIR:-.}/.claude/settings.local.json" \
    "${CLAUDE_PROJECT_DIR:-.}/.claude/settings.json" \
    "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
}

# True when the Superpowers plugin is enabled: the first settings file that names a
# superpowers@<marketplace> entry decides.
superpowers_enabled() {
  local f v
  check_jq || return 1
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    v=$(jq -r '[(.enabledPlugins // {}) | to_entries[] | select(.key | test("^superpowers@")) | .value] | if length == 0 then "unset" else (map(. == true) | any | tostring) end' "$f" 2>/dev/null || echo unset)
    case "$v" in true) return 0 ;; false) return 1 ;; esac
  done <<< "$(plugin_settings_files)"
  return 1
}

# True when an absolute file path resolves outside the project (symlinks followed),
# e.g. a scratch file. A relative path, or one with a `.` or `..` segment, counts as
# inside: the check must not be talked out of enforcing.
path_outside_project() {
  local r proj
  r=$(resolve_path_physical "$1") || return 1
  proj=$(cd "${CLAUDE_PROJECT_DIR:-$PWD}" 2>/dev/null && pwd -P) || return 1
  r=$(tr '[:upper:]' '[:lower:]' <<< "$r/"); proj=$(tr '[:upper:]' '[:lower:]' <<< "$proj/")
  case "$r" in "$proj"*) return 1 ;; esac
  return 0
}

# ---- Approval via a pending question (approval design B) ----
# Spec: docs/superpowers/specs/2026-10-05-approval-via-pending-question-design.md

# The schema-2 shape of .claude/pending-approval.json, as the block and stop messages
# show it to the agent.
PENDING_APPROVAL_SHAPE='{"schema": 2, "question": "<what you ask the user>", "options": [{"id": "A1", "text": "<what picking it does>", "approves": "commit"}, {"id": "A2", "text": "Hold - do not commit", "approves": "none"}], "recommendation": "A1", "offered_at": "<UTC time, e.g. 2026-10-05T12:00:00Z>"}'

# Print a JSON summary of a pending-approval sentinel: {schema, question, opts:[{id,
# text, approves}], rec, problems:[…]}. problems is empty only for a schema-2 sentinel
# that can be answered: a non-empty question, two or more options whose ids are a
# letter and one or two digits (A1 … Z99) and unique ignoring case, and at least one
# option that approves nothing. `approves` is "commit" or else "none".
pending_approval_info() {
  jq -c '
    def idok: type == "string" and test("^[A-Za-z][0-9]{1,2}$");
    if type == "object" and .schema == 2 then
      { schema: 2,
        question: (if (.question | type) == "string" then .question else "" end),
        opts: [ (.options // [])[]? | { id: (.id // "" | tostring),
                                         text: (if (.text | type) == "string" then .text else "" end),
                                         approves: (if .approves == "commit" then "commit" else "none" end) } ],
        rec: (.recommendation // "" | tostring) }
      | .problems = [ (if .question == "" then "the question is empty" else empty end),
                      (if (.opts | length) < 2 then "it has fewer than two options" else empty end),
                      (if any(.opts[]; (.id | idok) | not) then "an option id is not a letter and one or two digits (A1)" else empty end),
                      (if ([.opts[].id | ascii_upcase] | unique | length) != (.opts | length) then "option ids repeat" else empty end),
                      (if any(.opts[]; .approves == "none") | not then "no option approves nothing" else empty end) ]
    else { schema: (if type == "object" then (.schema // 1) else 0 end), opts: [], problems: ["it is not schema 2"] } end
  ' "$1" 2>/dev/null || echo '{"schema":0,"opts":[],"problems":["it is not valid JSON"]}'
}

# Print why a Bash command is not a commit an approval may cover, or nothing when it is.
# Under an approval the command must be exactly `git commit <options>`: one simple
# command (fd duplication and /dev/null redirections aside), first word `git` in any
# letter case with no path, no assignment words, no env/exec/command prefix, no git
# global options, then `commit` with message and metadata options only: -m/--message,
# -F/--file, --author, --date, --cleanup, --trailer (each with a value, attached or
# separate), -s/--signoff, -q/--quiet, -v/--verbose, -S/--gpg-sign[=…], --no-gpg-sign,
# --no-edit. Everything else (-a, -i, -o, -p, --amend, --fixup, --allow-empty, a
# pathspec, any other option) commits something other than the index the user saw.
commit_shape_problem() {
  local cmd="$1" prev="" out line n i w c l
  while [ "$cmd" != "$prev" ]; do
    prev="$cmd"
    cmd=$(sed -E 's#(^|[[:space:]])[0-9]?(>&[0-9]|>>?[[:space:]]*/dev/null)([[:space:];&|)]|$)#\1\3#g' <<< "$cmd")
  done
  out=$(shell_segments "$cmd")
  if grep -q $'^\001' <<< "$out" || [ "$(grep -c . <<< "$out")" != 1 ]; then
    echo "it is not a lone git commit (no chaining, pipes, redirection or substitution)"; return 0
  fi
  line="$out"
  local -a W
  IFS=$'\037' read -r -a W <<< "$line"
  n=${#W[@]}
  if [ "$(tr '[:upper:]' '[:lower:]' <<< "${W[0]}")" != git ]; then
    echo "the command must start with a bare git (found ${W[0]})"; return 0
  fi
  [ "$n" -ge 2 ] && [ "${W[1]}" = commit ] || { echo "git options before commit are not allowed (found ${W[1]:-nothing})"; return 0; }
  i=2
  while [ "$i" -lt "$n" ]; do
    w="${W[$i]}"
    case "$w" in
      -m|-F|--message|--file|--author|--date|--cleanup|--trailer)
        i=$((i + 1)); [ "$i" -lt "$n" ] || { echo "$w needs a value"; return 0; } ;;
      --message=*|--file=*|--author=*|--date=*|--cleanup=*|--trailer=*|--gpg-sign|--gpg-sign=*|--no-gpg-sign|--no-edit|--signoff|--quiet|--verbose) ;;
      --amend) echo "--amend rewrites a commit the user did not approve"; return 0 ;;
      --*) echo "option $w is not allowed under an approval"; return 0 ;;
      -?*)
        c="${w#-}"
        while [ -n "$c" ]; do
          l="${c:0:1}"; c="${c:1}"
          case "$l" in
            s|q|v) ;;
            m|F) [ -n "$c" ] || { i=$((i + 1)); [ "$i" -lt "$n" ] || { echo "-$l needs a value"; return 0; }; }; c="" ;;
            S) c="" ;;
            *) echo "option -$l is not allowed under an approval"; return 0 ;;
          esac
        done ;;
      *) echo "a pathspec ($w) commits something other than the approved stage"; return 0 ;;
    esac
    i=$((i + 1))
  done
  return 0
}

# One line per entry of a hooks directory: name, symlink target, executable bit and
# content hash, so the digest changes when a hook is added, removed, replaced or made
# executable.
_hooks_listing() {
  local d="$1" f
  [ -d "$d" ] || return 0
  for f in "$d"/* "$d"/.[!.]*; do
    [ -e "$f" ] || [ -L "$f" ] || continue
    printf '%s|%s|%s|%s\n' "${f##*/}" "$(readlink "$f" 2>/dev/null)" "$([ -x "$f" ] && echo x)" \
      "$([ -f "$f" ] && shasum -a 256 < "$f" | cut -c1-64)"
  done
}

# The hooks directory git uses for the repository at $1 (honours core.hooksPath).
git_hooks_dir() {
  local d="${1:-.}" h
  h=$(git -C "$d" rev-parse --git-path hooks 2>/dev/null) || return 1
  case "$h" in /*) ;; *) h="$d/$h" ;; esac
  printf '%s\n' "$h"
}

# The state an approval is bound to, for the repository at $1, as JSON: head (or
# "none"), the index tree (`git write-tree`, which writes tree objects only), a digest
# of the effective hooks directory and of `git config --list --show-origin
# --show-scope` (every scope). Fails when write-tree fails (an unmerged index).
git_stage_state() {
  local d="${1:-.}" head tree hdir hd cd
  head=$(git -C "$d" rev-parse -q --verify HEAD 2>/dev/null) || head=none
  tree=$(git -C "$d" write-tree 2>/dev/null) || return 1
  hdir=$(git_hooks_dir "$d") || return 1
  hd=$(_hooks_listing "$hdir" | shasum -a 256 | cut -c1-64)
  cd=$(git -C "$d" config --list --show-origin --show-scope 2>/dev/null | shasum -a 256 | cut -c1-64)
  jq -nc --arg h "$head" --arg t "$tree" --arg hd "$hd" --arg cd "$cd" \
    '{head: $h, tree: $t, hooks_digest: $hd, config_digest: $cd}'
}

# True when nothing is staged in the repository at $1 relative to HEAD.
git_nothing_staged() {
  local d="${1:-.}" tree base
  tree=$(git -C "$d" write-tree 2>/dev/null) || return 1
  base=$(git -C "$d" rev-parse -q --verify 'HEAD^{tree}' 2>/dev/null) || base=4b825dc642cb6eb9a060e54bf8d69288fbee4904
  [ "$tree" = "$base" ]
}

# Names of the hooks that run at commit for the repository at $1: executable files in
# the effective hooks directory (not *.sample) and hook.<name> config entries.
git_hook_names() {
  local d="${1:-.}" hdir f names=""
  hdir=$(git_hooks_dir "$d") || return 0
  for f in "$hdir"/*; do
    [ -f "$f" ] && [ -x "$f" ] || continue
    case "$f" in *.sample) continue ;; esac
    names="$names ${f##*/}"
  done
  names="$names $(git -C "$d" config --get-regexp '^hook\..*\.(command|event)$' 2>/dev/null | awk '{split($1, a, "."); print "hook." a[2]}' | sort -u | tr '\n' ' ')"
  names=$(printf '%s' "$names" | tr -s ' ' | sed -e 's/^ //' -e 's/ $//')
  printf '%s\n' "${names:-none}"
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
# Also the approval audit .claude/approvals.jsonl, and git's hooks, config and info
# files: a hook planted there runs inside `git commit` and can change what an approved
# commit contains (approval design B, D7). `.gitignore` and `.github/` do not match.
CONFIG_GUARD_PROTECTED_RE='\.claude/(settings\.json|settings\.local\.json|manifest\.json|framework/hooks/|approvals\.jsonl)|\.claude/framework(/hooks)?/?([^[:alnum:]_./-]|$)|\.git/(hooks|info|config)([^[:alnum:]_.-]|$)'

# A lone command: no chaining, piping, redirection, substitution or newline.
is_lone_command() {
  ! [[ "$1" =~ [\;\&\|\`\>\<] || "$1" == *'$('* || "$1" == *$'\n'* ]]
}

# Split a Bash command the way the shell does, for the guards to judge each simple
# command on its own. Prints one line per simple command, its words (quotes and
# escapes removed) separated by \037, split at an unquoted ; & | ( ) or newline. Then
# one \001-prefixed line per construct the split cannot follow: subst (`...`, $(...),
# <(...), also inside double quotes), redirect (an unquoted < or >), comment, ansi
# ($'...'), backslash (outside quotes), unterminated (an open quote at the end) and
# pipe (an unquoted | that is not ||: a split, not a construct, for git_commit_text).
# A here-document's body is printed after the command line it belongs to, one line per
# body line, each prefixed with a word of \002 and the number of simple commands on the
# line that opened it, and split at blanks and ; & | ( ) < > with quotes and
# backslashes removed, so a caller can treat it as data (git_commit_text, when only
# data readers took it) or as commands (the others). A body
# line with $(...) or a backtick under an unquoted delimiter is flagged subst: the shell
# runs it.
shell_segments() {
  printf '%s' "$1" | awk '
    function flag(f) { flags[f] = 1 }
    function endword() {
      if (hw) { gsub(/[\n\t]/, " ", w); line = line (nw ? "\037" : "") w; nw++ }
      w = ""; hw = 0
    }
    function endseg() { endword(); if (nw) { print line; ls++ } line = ""; nw = 0 }
    # The bodies of the here-documents opened on the line just ended, from pos; returns
    # the position after the last delimiter line.
    function bodies(pos,    k, e, ln, cl, m, parts, x, out) {
      for (k = hi + 1; k <= hn; k++) {
        while (pos <= n) {
          e = index(substr(s, pos), "\n")
          ln = e ? substr(s, pos, e - 1) : substr(s, pos)
          pos += e ? e : length(ln) + 1
          cl = ln; if (hx[k]) sub(/^\t+/, "", cl)
          if (cl == hd[k]) break
          if (!hq[k] && (index(ln, "$(") || index(ln, "`"))) flag("subst")
          m = split(ln, parts, /[ \t;&|()<>]+/); out = ""
          for (x = 1; x <= m; x++) { gsub(/["\047\\]/, "", parts[x]); if (parts[x] != "") out = out "\037" parts[x] }
          if (out != "") print "\002" ls out
        }
      }
      hi = hn
      return pos
    }
    { s = s (NR > 1 ? "\n" : "") $0 }
    END {
      n = length(s); q = ""; w = ""; hw = 0; line = ""; nw = 0; hn = 0; hi = 0; ls = 0
      for (i = 1; i <= n; i++) {
        c = substr(s, i, 1); nx = substr(s, i + 1, 1)
        if (q == "\047") { if (c == "\047") q = ""; else w = w c; continue }
        if (q == "\"") {
          if (c == "\"") { q = ""; continue }
          if (c == "`" || (c == "$" && nx == "(")) flag("subst")
          if (c == "\\" && (nx == "$" || nx == "`" || nx == "\"" || nx == "\\")) { w = w nx; i++; continue }
          if (c == "\\" && nx == "\n") { i++; continue }
          w = w c; continue
        }
        if (c == "\\") { flag("backslash"); i++; if (nx != "\n") { w = w nx; hw = 1 } continue }
        if (c == "\047" || c == "\"") { if (c == "\047" && substr(s, i - 1, 1) == "$") flag("ansi"); q = c; hw = 1; continue }
        if (c == "`") { flag("subst"); endseg(); continue }
        if (c == "$" && nx == "(") { flag("subst"); endseg(); i++; continue }
        if (c == "#" && !hw) { flag("comment"); while (i < n && substr(s, i + 1, 1) != "\n") i++; continue }
        if (c == " " || c == "\t") { endword(); continue }
        if (c == "\n") { endseg(); if (hn > hi) i = bodies(i + 1) - 1; ls = 0; continue }
        if (c == "|") { if (nx == "|") i++; else flag("pipe"); endseg(); continue }
        if (c == ";" || c == "&" || c == "(" || c == ")") { endseg(); continue }
        # A here-document (<< or <<-, not <<<): read its delimiter; the body follows the
        # end of this line.
        if (c == "<" && nx == "<" && substr(s, i + 2, 1) != "<") {
          flag("redirect"); endword()
          j = i + 2; dash = 0
          if (substr(s, j, 1) == "-") { dash = 1; j++ }
          while (j <= n && (substr(s, j, 1) == " " || substr(s, j, 1) == "\t")) j++
          d = ""; dq = 0
          while (j <= n) {
            ch = substr(s, j, 1)
            if (ch ~ /[ \t\n;&|<>()]/) break
            if (ch == "\047" || ch == "\"") {
              dq = 1; k = index(substr(s, j + 1), ch)
              if (!k) { d = d substr(s, j + 1); j = n + 1; break }
              d = d substr(s, j + 1, k - 1); j += k + 1; continue
            }
            if (ch == "\\") { dq = 1; d = d substr(s, j + 1, 1); j += 2; continue }
            d = d ch; j++
          }
          hn++; hd[hn] = d; hq[hn] = dq; hx[hn] = dash
          i = j - 1; continue
        }
        # A redirection to or from a file descriptor (2>&1, <&3, &>file) does not end the
        # simple command.
        if (c == "&" && nx == ">") { flag("redirect"); endword(); i++; continue }
        if (c == "<" || c == ">") { flag("redirect"); if (nx == "(") flag("subst"); else if (nx == "&") i++; endword(); continue }
        w = w c; hw = 1
      }
      if (q != "") flag("unterminated")
      endseg()
      for (f in flags) print "\001" f
    }'
}

# True when a Bash command runs `git commit`, and prints the commit as the shell runs
# it (the commit's simple commands, quotes removed, words joined by spaces; the whole
# command where the text rule decides), for checks on the commit's flags. A simple
# command with a word `git` (any path, any position, so `env git commit` and
# `git -C dir commit` count) and a later word naming commit (`commit`,
# `alias.ci=commit`) is a commit. Words are taken after quote removal, so prose that
# only mentions a commit inside a quoted argument (`printf '...git status... commit'`,
# `--question "...git commit..."`) is not. Config given with the command can make a
# subcommand that is not a long-standing git builtin an alias for commit
# (git_name_can_alias). It counts as a commit when git runs such a subcommand
# and the config either defines an alias whose value names commit or starts with `!`
# (`git -c alias.ci='commit -am x' ci`, GIT_CONFIG_PARAMETERS) or hides the value
# (--config-env=alias.*, GIT_CONFIG_GLOBAL/SYSTEM/COUNT/KEY_n/VALUE_n, GIT_CONFIG,
# a value in a $variable or $'...'), in the same simple command or an earlier
# `export`. So `GIT_CONFIG_GLOBAL=x git log` is not a commit. `git` is matched in
# any letter case: a case-insensitive disk runs `GIT commit`. Setting such an alias
# for later (`git config alias.ci 'commit -m x'`, or a `!` value) counts as a commit
# too; an alias already in a config file does not. Where the text can run more
# than it shows, the plain-text rule decides instead (any `git` followed later by
# `commit`): a command substitution, a variable as the command word,
# eval/xargs/source/watch/parallel, an interpreter given code with -c/-e, read from
# stdin, or given something that is not a file path. Any other command that does not
# only read data (csh, expect, sqlite3, vim, Rscript, sudo, ...) runs what it is given:
# a word of it naming a git commit (`csh -c "git commit"`) is a commit, and so is a
# here-document it reads that runs one, or, with a pipe in the command, a `git` followed
# by `commit` anywhere in the command, with quotes removed (`echo 'git commit' | csh`).
# git given its subcommand by xargs or parallel, or a {} one, is a commit; a
# subcommand in a $variable is assembled at run time and is not seen (R-23). A real
# git commit beside a construct that falls back is a commit whatever the text rule says.
git_commit_text() {
  local cmd="$1" out verdict
  if [ "${#cmd}" -le 65536 ]; then
    out=$(shell_segments "$cmd" | awk -F'\037' '
      function base(x) { sub(/.*\//, "", x); return x }
      # The text rule (at the end) on one line of text.
      function text_commits(x) { return x ~ /(^|[^A-Za-z0-9_]|\\[ntr])[Gg][Ii][Tt]([^-.\/A-Za-z0-9_]|[^A-Za-z0-9_].*[^-.\/A-Za-z0-9_])commit([^A-Za-z0-9_]|$)/ }
      function names_commit(x) { return x ~ /(^|[^A-Za-z0-9_])commit([^A-Za-z0-9_]|$)/ }
      # The value of an alias.NAME=VALUE word runs a commit (or anything, with `!`).
      function alias_commits(x,  v) { v = x; sub(/^.*[Aa][Ll][Ii][Aa][Ss]\.[^=]*=/, "", v); return names_commit(v) || v ~ /^!/ }
      /^\001subst$/ { fb = 1; next }
      # $'...' can spell an alias value the text does not show.
      /^\001ansi$/ { opaque = 1; next }
      /^\001pipe$/ { pipe = 1; next }
      /^\001/ { next }
      # A here-document body is data when every simple command on the line that opened
      # it only reads data or is git, which judges its own subcommand (commit -F -,
      # tag -F -). Otherwise its lines are read as commands; a shell or interpreter on
      # stdin, source and awk -f - also fall back below.
      /^\002/ {
        d = 1
        for (x = nseg - substr($1, 2) + 1; x <= nseg; x++) if (!data[x]) d = 0
        if (d) next
        body = 1; $0 = substr($0, index($0, "\037") + 1)
      }
      {
        k = 1
        while (k < NF && $k ~ /^(if|then|else|elif|fi|do|done|while|until|!|\{|\})$/) k++
        while (k < NF && $k ~ /^[A-Za-z_][A-Za-z0-9_]*=/) k++
        if ($k ~ /\$/ || $k == ".") fb = 1
        # Commands that never run their arguments or stdin as code (not sed, which has
        # `e`, nor sort, which has --compress-program). gh alias and gh extension define
        # what gh runs; any other gh runs an alias or extension only after a step that
        # wrote its config (residual, R-23).
        cb = base($k)
        dr = (cb ~ /^(echo|printf|cat|tee|grep|egrep|fgrep|rg|head|tail|wc|uniq|cut|tr|jq|diff|cmp|test|\[|true|:|ls|cd|gh)$/) && !(cb == "gh" && $(k + 1) ~ /^(alias|extension|extensions|ext)$/)
        kn = dr || tolower(cb) == "git" || cb ~ /^(bash|sh|zsh|dash|ksh|fish|python[0-9.]*|perl|ruby|node|php|lua|osascript|pwsh|tclsh|deno|bun|awk|gawk|nawk|mawk)$/
        # A script file of the project run by path (scripts/pending-approval.sh) is like
        # `bash scripts/x.sh`: its arguments are text (an approval question about a
        # commit). It counts only when the path is relative to the session folder, which
        # Claude Code keeps in the project: no leading / or ~, no .. and no cd, pushd or
        # popd in the command (moved, at the end); and only with a script extension, so
        # a copied runner (cp /bin/csh ./c) or node_modules/.bin/tsx stays a code runner.
        # A script the agent wrote can commit without showing it (R-23).
        sp = !kn && $k ~ /\// && $k !~ /^[\/~]/ && $k !~ /(^|\/)\.\.(\/|$)/ && cb ~ /\.(sh|bash|zsh|py|rb|pl|js|mjs|cjs|ts|php)$/
        isb = body; body = 0
        if (!isb) { data[++nseg] = dr || tolower(cb) == "git"; if (!kn) { if (sp) spunk = 1; else unk = 1 } }
        # Any other command runs a code string it is given (csh -c, expect -c, sqlite3
        # .shell, vim -c, Rscript -e, sudo csh -c): a word that names a git commit by the
        # text rule is one.
        if (!kn) for (j = k + 1; j <= NF; j++) if (text_commits($j)) { if (sp) spcode = 1; else code = 1 }
        g = 0; seghit = 0; line = ""; runner = 0
        for (j = 1; j <= NF; j++) {
          b = base($j); line = line (j > 1 ? " " : "") $j
          if (b ~ /^(cd|pushd|popd)$/) moved = 1
          if (b ~ /^(eval|xargs|source|watch|parallel)$/) fb = 1
          if (b ~ /^(bash|sh|zsh|dash|ksh|fish|python[0-9.]*|perl|ruby|node|php|lua|osascript|pwsh|tclsh|deno|bun)$/) {
            arg = ""
            for (m = j + 1; m <= NF; m++) {
              if ($m == "-" || $m ~ /^-[A-Za-z]*[ceE][A-Za-z]*$/ || $m ~ /^--(command|eval|exec)/) fb = 1
              if (arg == "" && $m !~ /^-/) arg = $m
            }
            # stdin by another name is not a file the agent wrote.
            if (arg == "" || arg !~ /[\/.]/ || arg ~ /^\/(dev\/(stdin|fd\/)|proc\/self\/fd\/)/) fb = 1
          }
          # awk runs commands through system(), print | "cmd" and "cmd" | getline, and
          # reads its program from stdin with -f -; env -S splits a string into a command.
          if (b ~ /^(awk|gawk|nawk|mawk)$/) {
            for (m = j + 1; m <= NF; m++) {
              if ($m ~ /system|\|/) fb = 1
              if (($m == "-f" && $(m + 1) ~ /^(-|\/dev\/(stdin|fd\/)|\/proc\/self\/fd\/)/) || $m ~ /^-f(-|\/dev\/(stdin|fd\/))/) fb = 1
            }
          }
          if (b == "env") for (m = j + 1; m <= NF; m++) if ($m ~ /^-[A-Za-z]*S/ || $m ~ /^--split-string/) fb = 1
          # Config in a variable, here or in an earlier export.
          if ($j ~ /^GIT_CONFIG(_GLOBAL|_SYSTEM|_COUNT|_KEY_[0-9]+|_VALUE_[0-9]+)?=/) opaque = 1
          if ($j ~ /^GIT_CONFIG_PARAMETERS=/ && $j ~ /\$/) opaque = 1
          if ($j ~ /^GIT_CONFIG_PARAMETERS=/ && tolower($j) ~ /alias\./) { if (alias_commits($j)) cfgc = 1; else opaque = 1 }
          # GIT, Git, /usr/bin/GIT: a case-insensitive disk runs git for each. Every git
          # word counts (sudo -u git git commit, find -name git -exec git commit), and for
          # each the commit is its subcommand, the first word after its global options:
          # a file name (pre-commit-checks.sh) or a pathspec naming commit is not one.
          if (tolower(b) == "git") {
            if (!g) { g = 1; gi = j }
            m = j + 1
            while (m <= NF && $m ~ /^-/) { if ($m ~ /^(-C|-c|--git-dir|--work-tree|--namespace|--config-env|--super-prefix|--attr-source)$/) m++; m++ }
            if (m <= NF && names_commit($m)) seghit = 1
            # A subcommand xargs or parallel supplies from input (xargs git), or a {} one
            # (xargs -I{} git {}, find -exec git {}).
            if ((runner && m > NF) || (m <= NF && $m ~ /\{\}/)) code = 1
          }
          if (b ~ /^(xargs|parallel)$/) runner = 1
        }
        if (g) {
          # The subcommand: the first word after git and its global options.
          m = gi + 1
          while (m <= NF && $m ~ /^-/) { if ($m ~ /^(-C|-c|--git-dir|--work-tree|--namespace|--config-env|--super-prefix|--attr-source)$/) m++; m++ }
          sc = (m <= NF ? $m : "")
          # Each (git, subcommand) pair once: a long chain asks git once per pair.
          if (sc != "" && !((gw = $gi "\037" sc) in seen)) { seen[gw] = 1; scs = scs (scs == "" ? "" : "\036") gw }
          for (m = gi + 1; m <= NF; m++) {
            lw = tolower($m)
            if (lw ~ /^--config-env=alias\./ || (lw == "--config-env" && tolower($(m + 1)) ~ /^alias\./)) opaque = 1
            # A value in a variable: -c "$KV", alias.x="$V", --config-env=$X.
            if (($m == "-c" || $m == "--config-env") && $(m + 1) ~ /\$/) opaque = 1
            if ((lw ~ /^alias\.[^=]*=/ || lw ~ /^--config-env=/) && $m ~ /\$/) opaque = 1
            if (lw ~ /^alias\.[^=]*=/ && alias_commits($m)) cfgc = 1
            # git config [opts] alias.NAME VALUE: an alias for later that commits.
            if (sc == "config" && lw ~ /^alias\.[^=]*$/ && m < NF && (names_commit($(m + 1)) || $(m + 1) ~ /^!/)) seghit = 1
          }
        }
        if (seghit) { hit = 1; text = text line "\n" }
        if (g) gtext = gtext line "\n"
        if (!isb) words = words " " line
      }
      END {
        # After a cd a script path may name any file: judge it as a code runner.
        if (moved) { if (spcode) code = 1; if (spunk) unk = 1 }
        # A pipe into a command that is not a known reader: the text rule on the whole
        # command with quotes removed.
        if (pipe && unk && text_commits(words)) code = 1
        if (code || (fb && hit)) print "code"
        else if (fb) print "fallback"
        else if (hit) printf "commit\n%s", text
        else if ((cfgc || opaque) && scs != "") printf "cfg\n%s\n%s", scs, gtext
        else print "none"
      }')
    verdict="${out%%$'\n'*}"
  else
    verdict=fallback
  fi
  case "$verdict" in
    commit) printf '%s\n' "${out#*$'\n'}"; return 0 ;;
    code) printf '%s\n' "$cmd"; return 0 ;;
    none) return 1 ;;
    cfg)
      # Config that can define an alias: a commit when git runs a subcommand that
      # an alias could be (git_name_can_alias).
      local rest scs text pair
      rest="${out#*$'\n'}"; scs="${rest%%$'\n'*}"; text="${rest#*$'\n'}"
      while IFS= read -r pair; do
        git_name_can_alias "${pair#*$'\037'}" "${pair%%$'\037'*}" && { printf '%s\n' "$text"; return 0; }
      done <<< "$(printf '%s' "$scs" | tr '\036' '\n')"
      return 1 ;;
    # The text rule: a git and, later on the same line, commit as a word of its own
    # (not pre-commit, hooks/commit-msg or .commit). A \n, \t or \r escape before git
    # is a boundary too: printf turns it into a newline or a blank (printf '\tgit commit').
    *) grep -qE '(^|[^[:alnum:]_]|\\[ntr])[Gg][Ii][Tt]\b.*(^|[^-./[:alnum:]_])commit\b' <<< "$cmd" && printf '%s\n' "$cmd" ;;
  esac
}

# Builtins that every git in use is assumed to have: every name is a builtin in git
# 2.25.0 and later (checked against git.c's command table at v2.25.0 and v2.30.0).
# A newer builtin (backfill, diagnose, diff-pairs, for-each-repo, history, hook,
# last-modified, maintenance, refs, replay, repo, ...) and one that was a script or
# a separate program until recently (bisect, fast-import, credential-cache,
# credential-store, upload-pack, upload-archive, ...) is left out, so an older git
# the agent runs by path cannot turn it into an alias.
GIT_BASELINE_BUILTINS="add am annotate apply archive blame branch bundle cat-file check-attr check-ignore check-mailmap check-ref-format checkout checkout-index cherry cherry-pick clean clone column commit commit-graph commit-tree config count-objects credential describe diff diff-files diff-index diff-tree difftool fast-export fetch fetch-pack fmt-merge-msg for-each-ref format-patch fsck fsck-objects gc grep hash-object help index-pack init init-db interpret-trailers log ls-files ls-remote ls-tree mailinfo mailsplit merge merge-base merge-file merge-index merge-ours merge-recursive merge-subtree merge-tree mktag mktree multi-pack-index mv name-rev notes pack-objects pack-redundant pack-refs patch-id prune prune-packed pull push range-diff read-tree rebase receive-pack reflog remote repack replace rerere reset restore rev-list rev-parse revert rm send-pack shortlog show show-branch show-index show-ref sparse-checkout stage stash status stripspace switch symbolic-ref tag unpack-file unpack-objects update-index update-ref update-server-info var verify-commit verify-pack verify-tag version whatchanged worktree write-tree"

# Load into _GB the builtins of a git, $1 being the command's git word: an absolute
# path to an executable is asked itself; a relative path (./git, sub/git, ~/bin/git)
# names a binary the hook does not resolve, so _GB is left empty (every subcommand
# aliasable); a bare name asks the git on the hook's PATH. Each is asked once per
# hook run (no subshell, so the cache holds). _GB is empty when that git runs but
# cannot list them, "nogit" when no git runs at all.
_git_builtins_load() {
  local g="$1"
  case "$g" in
    /*) [ -x "$g" ] || g=git ;;
    */*) _GB=""; return 0 ;;
    *) g=git ;;
  esac
  if [ "$g" = git ] && [ -n "${_GB_PATH+x}" ]; then _GB="$_GB_PATH"; return 0; fi
  if [ "$g" != git ] && [ "${_GB_ABS_FOR:-}" = "$g" ]; then _GB="$_GB_ABS"; return 0; fi
  if _GB=$("$g" --list-cmds=builtins 2>/dev/null) && [ -n "$_GB" ]; then
    :
  elif "$g" --version >/dev/null 2>&1; then
    _GB=""
  else
    _GB=nogit
  fi
  if [ "$g" = git ]; then _GB_PATH="$_GB"; else _GB_ABS_FOR="$g"; _GB_ABS="$_GB"; fi
  return 0
}

# True when `git NAME` could run an alias, $2 being the command's git word. NAME is
# taken as a builtin, which no alias can shadow, only when it is both in
# GIT_BASELINE_BUILTINS and a builtin of that git. Whether an installed git-NAME
# shadows an alias depends on PATH, GIT_EXEC_PATH and --exec-path when the command
# runs, which the command can change, so externals never count. A git that runs
# but cannot list its builtins makes every name aliasable (fail strict); with no
# working git the baseline alone decides.
git_name_can_alias() {
  local sc="$1"
  [ -n "$sc" ] || return 1
  case " $GIT_BASELINE_BUILTINS " in *" $sc "*) ;; *) return 0 ;; esac
  _git_builtins_load "${2:-git}"
  [ "$_GB" = nogit ] && return 1
  grep -qxF -- "$sc" <<< "$_GB" && return 1
  return 0
}

# True when a Bash command runs `git commit` (git_commit_text, without the text).
command_runs_git_commit() { git_commit_text "$1" >/dev/null; }

# Print the git config key a Bash command SETS that runs code inside git, and return 0;
# return 1 when it sets none (approval design B, D4). Only config-setting positions
# count, so reads, messages, --grep and pathspecs that mention a key pass:
#   - the value of `-c` and of `--config-env[=]` on a git word;
#   - GIT_CONFIG_PARAMETERS=… (each key= inside it) and GIT_CONFIG_KEY_<n>=… as
#     assignment words in any segment (also after env / export);
#   - the key of a setting `git config`: KEY VALUE, --add, --replace-all, --unset(-all),
#     --rename-section, --remove-section, `set` / `unset`; --edit / -e / `edit` always.
# Refused keys: core.hooksPath, hook.*, core.fsmonitor, core.sshCommand, core.askPass,
# core.editor, sequence.editor, gpg.program, gpg.*.program, filter.*.clean|smudge|process,
# diff.external, diff.*.command, merge.*.driver, credential.helper,
# credential.*.helper, include.path, includeIf.*, and alias.* whose value starts with
# `!` or is hidden (--config-env, GIT_CONFIG_KEY_<n>, a $variable). A key itself hidden
# in a $variable counts as refused. A command the split cannot follow (substitution)
# falls back to a text match of the refused keys.
GIT_CODE_CONFIG_RE='core\.hookspath|(^|[^[:alnum:]_.])hook\.|core\.fsmonitor|core\.sshcommand|core\.askpass|core\.editor|sequence\.editor|gpg\.([^[:space:]=]*\.)?program|filter\.[^[:space:]=]*\.(clean|smudge|process)|diff\.external|diff\.[^[:space:]=]*\.command|merge\.[^[:space:]=]*\.driver|credential\.([^[:space:]=]*\.)?helper|include\.path|includeif\.'
git_sets_code_config() {
  local cmd="$1" out
  if [ "${#cmd}" -le 65536 ]; then
    out=$(shell_segments "$cmd" | awk -F'\037' '
      function base(x) { sub(/.*\//, "", x); return x }
      function refused(k,   l) {
        l = tolower(k)
        if (l ~ /\$/) return 1
        return (l == "core.hookspath" || l ~ /^hook\./ || l == "core.fsmonitor" || \
                l == "core.sshcommand" || l == "core.askpass" || l == "core.editor" || \
                l == "sequence.editor" || l == "gpg.program" || l ~ /^gpg\..*\.program$/ || \
                l ~ /^filter\..*\.(clean|smudge|process)$/ || l == "diff.external" || \
                l ~ /^diff\..*\.command$/ || l ~ /^merge\..*\.driver$/ || \
                l == "credential.helper" || l ~ /^credential\..*\.helper$/ || \
                l == "include.path" || l ~ /^includeif\./)
      }
      function checkkv(kv, hidden,   i, k, v) {
        i = index(kv, "=")
        if (i) { k = substr(kv, 1, i - 1); v = substr(kv, i + 1) } else { k = kv; v = "" }
        if (v ~ /\$/) hidden = 1
        if (hit == "" && refused(k)) hit = k
        if (hit == "" && tolower(k) ~ /^alias\./ && (hidden || v ~ /^!/)) hit = k
      }
      function section_refused(sec,   l) {
        l = tolower(sec)
        return (l ~ /^(hook|includeif|include|filter|diff|merge|gpg|credential|core|sequence|alias)(\.|$)/)
      }
      /^\001subst$/ { subst = 1; next }
      /^\001/ { next }
      {
        g = 0
        for (j = 1; j <= NF && !g; j++) if (tolower(base($j)) == "git") { g = 1; gi = j }
        # Config passed through the environment, as an assignment word anywhere in the
        # segment (X=… git …, env X=… git …, export X=…).
        for (j = 1; j <= NF; j++) {
          w = $j
          if (w ~ /^GIT_CONFIG_PARAMETERS=/) {
            val = substr(w, index(w, "=") + 1)
            if (val ~ /\$/ && hit == "") hit = "GIT_CONFIG_PARAMETERS"
            n = split(val, parts, /[ \t]+/)
            for (q = 1; q <= n; q++) { p = parts[q]; gsub(/\047/, "", p); if (p ~ /=/) checkkv(p, 0) }
          } else if (w ~ /^GIT_CONFIG_KEY_[0-9]+=/) checkkv(substr(w, index(w, "=") + 1), 1)
        }
        if (!g) next
        m = gi + 1
        while (m <= NF && $m ~ /^-/) {
          if ($m == "-c" && m < NF) { checkkv($(m + 1), 0); m += 2; continue }
          if ($m ~ /^--config-env=/) { checkkv(substr($m, 14), 1); m++; continue }
          if ($m == "--config-env" && m < NF) { checkkv($(m + 1), 1); m += 2; continue }
          if ($m ~ /^(-C|--git-dir|--work-tree|--namespace|--super-prefix|--attr-source|--exec-path)$/) m++
          m++
        }
        if (m > NF || $m != "config") next
        setting = 0; reading = 0; pos = 0; split("", posw)
        for (r = m + 1; r <= NF; r++) {
          w = $r
          if (w == "--edit" || w == "-e") { if (hit == "") hit = "config --edit"; break }
          if (w ~ /^--(add|replace-all|unset|unset-all|rename-section|remove-section)$/) { setting = 1; if (w ~ /section$/) sect = 1; continue }
          if (w ~ /^--(get|get-all|get-regexp|get-urlmatch|get-color|get-colorbool|list|show-origin|show-scope|name-only)$/ || w == "-l") { reading = 1; continue }
          if (w ~ /^(-f|--file|--blob|--type|--default|--comment|--value|--file=.*)$/) { if (w !~ /=/) r++; continue }
          if (w ~ /^-/) continue
          pos++; posw[pos] = w
        }
        if (posw[1] == "edit") { if (hit == "") hit = "config edit"; next }
        if (posw[1] == "get" || posw[1] == "list") next
        if (posw[1] == "set") { checkkv(posw[2] "=" posw[3], 0); next }
        if (posw[1] == "unset") { checkkv(posw[2], 0); next }
        if (posw[1] == "rename-section" || posw[1] == "remove-section" || sect) {
          for (q = 1; q <= pos; q++) if (posw[q] != "rename-section" && posw[q] != "remove-section" && section_refused(posw[q]) && hit == "") hit = posw[q]
          next
        }
        if (reading && !setting) next
        if (pos >= 2 || setting) checkkv(posw[1] "=" posw[2], 0)
      }
      END { if (hit != "") print hit; else if (subst) print "?subst" }')
  else
    out="?subst"
  fi
  case "$out" in
    '') return 1 ;;
    '?subst') grep -qiE "$GIT_CODE_CONFIG_RE" <<< "$cmd" && grep -qiE '(^|[^[:alnum:]_])git([^[:alnum:]_]|$)' <<< "$cmd" && { echo "(config inside a substitution)"; return 0; }; return 1 ;;
    *) printf '%s\n' "$out"; return 0 ;;
  esac
}

# True when every simple command in a Bash command only reads, or stages files with a
# plain `git add` (staging copies what is on disk into the index; it changes no file
# in the working tree, so a framework-written .claude file can be staged for commit
# while writing it stays blocked). Allowed: cd with one argument; cat, head, tail,
# more, wc, file, stat, ls, grep, jq, echo, pwd, true; rg without --pre; sed -n with
# a line-range print script (`1,15p`); git diff/log/show/blame/status/ls-files/
# ls-tree/cat-file/rev-parse/reflog/describe/name-rev/grep/check-ignore without
# --output, --ext-diff or --textconv, which run configured drivers (and git grep
# without -O); git add with no option but `--`. Anything the
# split cannot follow refuses: substitution, a backslash, a comment, $'...', an open
# quote, and any redirection except fd duplication (2>&1) and /dev/null.
command_only_reads() { [ -z "$(command_read_problem "$1")" ]; }

# Print what keeps a Bash command from being read-only (command_only_reads): the first
# simple command that is not allowed, or the construct the split cannot follow; print
# nothing when every simple command only reads or stages. Besides the commands listed
# above: find without an action that runs or writes (-exec, -execdir, -ok, -okdir,
# -delete, -fprint*, -fls); cmp; diff; test and [; the shell keywords that only open
# or close a compound command (if, then, else, elif, fi, do, done, while, until, !,
# { and }), the command after them judged on its own; a `for NAME in WORDS` head; and
# a simple command made only of assignments, except to a name that changes what a
# later read runs or how (PATH, IFS, the GIT_*, LD_*, DYLD_* and pager variables, ...).
# An assignment in front of a command still refuses.
command_read_problem() {
  local cmd="$1" prev=""
  [ "${#cmd}" -le 16384 ] || { echo "a command longer than 16384 characters"; return 0; }
  case "$cmd" in *\\*) echo "a backslash"; return 0 ;; esac
  while [ "$cmd" != "$prev" ]; do
    prev="$cmd"
    cmd=$(sed -E 's#(^|[[:space:]])[0-9]?(>&[0-9]|>>?[[:space:]]*/dev/null)([[:space:];&|)]|$)#\1\3#g' <<< "$cmd")
  done
  shell_segments "$cmd" | awk -F'\037' '
    function show(   x, t) { t = ""; for (x = 1; x <= NF; x++) t = t (x > 1 ? " " : "") $x; return t }
    /^\001pipe$/ { next }
    /^\001/ {
      f = substr($0, 2)
      if (f == "subst") why = "a command substitution"
      else if (f == "redirect") why = "a redirection or here-document"
      else if (f == "ansi") why = "a $'\''...'\'' string"
      else if (f == "unterminated") why = "an open quote"
      else why = "a " f
      if (bad == "") bad = why
      next
    }
    /^\002/ { if (bad == "") bad = "a here-document"; next }
    {
      nseg++
      # Keywords that only open or close a compound command: judge what follows.
      while (NF > 0 && $1 ~ /^(if|then|else|elif|fi|do|done|while|until|!|\{|\})$/) { sub(/^[^\037]*\037?/, "") }
      if (NF == 0) next
      ok = 0; c = $1
      if (c == "for") ok = (NF == 2 || (NF >= 3 && $3 == "in"))
      else if (c ~ /^[A-Za-z_][A-Za-z0-9_]*=/) {
        ok = 1
        for (j = 1; j <= NF; j++) {
          if ($j !~ /^[A-Za-z_][A-Za-z0-9_]*=/) ok = 0
          nm = $j; sub(/=.*/, "", nm)
          if (nm ~ /^(PATH|HOME|IFS|CDPATH|ENV|BASH_ENV|SHELL|SHELLOPTS|BASHOPTS|PS4|PROMPT_COMMAND|EDITOR|VISUAL|PAGER|MANPAGER|MORE|TMPDIR|LESS.*|GIT_.*|LD_.*|DYLD_.*|XDG_.*|BASH_FUNC_.*|PYTHON.*|PERL.*|RUBY.*|NODE_.*|JQ_.*|GREP_.*|RIPGREP_CONFIG_PATH|BAT_.*|CLAUDE.*)$/) ok = 0
        }
      }
      else if (c == "cd") ok = (NF <= 2)
      else if (c ~ /^(cat|head|tail|more|wc|file|stat|ls|grep|jq|echo|pwd|true|cmp|diff|test|\[)$/) ok = 1
      else if (c == "find") { ok = 1; for (j = 2; j <= NF; j++) if ($j ~ /^-(exec|execdir|ok|okdir|delete|fprint|fprint0|fprintf|fls)$/) ok = 0 }
      else if (c == "rg") { ok = 1; for (j = 2; j <= NF; j++) if ($j ~ /^--pre(=|$)/) ok = 0 }
      else if (c == "sed") {
        ok = ($2 == "-n" && $3 ~ /^([0-9]+|\$)(,([0-9]+|\$))?p$/)
        for (j = 4; j <= NF; j++) if ($j ~ /^-/) ok = 0
      }
      else if (c == "git" && $2 ~ /^(diff|log|show|blame|status|ls-files|ls-tree|cat-file|rev-parse|reflog|describe|name-rev|grep|check-ignore)$/) {
        ok = 1
        for (j = 3; j <= NF; j++) {
          if ($j ~ /^--output/ || $j ~ /^--(ext-diff|textconv)$/) ok = 0
          if ($2 == "grep" && ($j ~ /^--open-files-in-pager/ || $j ~ /^-[A-Za-z0-9]*O/)) ok = 0
        }
      }
      else if (c == "git" && $2 == "add") { ok = 1; for (j = 3; j <= NF; j++) if ($j ~ /^-/ && $j != "--") ok = 0 }
      if (!ok && bad == "") bad = show()
    }
    END { if (bad == "" && nseg == 0) bad = "no command"; if (bad != "") print bad }'
}

# True when COMMAND is a lone invocation of the project's own mark-plan-closed.sh.
# mark-evaluated.sh is not sanctioned for the agent: approval comes from the user's
# pick of a recorded question (record-approval.sh), and the script is the user's own
# override, run in a separate terminal (approval design B, D5). The first word must be a plain path, and that path — taken
# relative to $2, the agent's working directory from the hook input — must resolve
# to <project>/.claude/framework/hooks/. A script of the same name anywhere else
# does not count.
is_sanctioned_mark_command() {
  local cmd="$1" base="${2:-${CLAUDE_PROJECT_DIR:-$PWD}}" path name dir hooks
  is_lone_command "$cmd" || return 1
  [[ "$cmd" =~ ^[[:space:]]*(bash[[:space:]]+)?([[:alnum:]_./+@,:%-]*mark-plan-closed\.sh)([[:space:]]|$) ]] || return 1
  path="${BASH_REMATCH[2]}"
  case "$path" in /*) ;; *) path="$base/$path" ;; esac
  name="${path##*/}"
  [ "$name" = "mark-plan-closed.sh" ] || return 1
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
  local re='(^|[^[:alnum:]_./+@,:%-])([[:alnum:]_./+@,:%-]*\.([cC][lL][aA][uU][dD][eE]|[gG][iI][tT]/)[[:alnum:]_./+@,:%-]*)'
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
