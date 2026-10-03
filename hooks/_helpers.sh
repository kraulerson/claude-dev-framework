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

# Split a Bash command the way the shell does, for the guards to judge each simple
# command on its own. Prints one line per simple command, its words (quotes and
# escapes removed) separated by \037, split at an unquoted ; & | ( ) or newline. Then
# one \001-prefixed line per construct the split cannot follow: subst (`...`, $(...),
# <(...), also inside double quotes), redirect (an unquoted < or >), comment, ansi
# ($'...'), backslash (outside quotes) and unterminated (an open quote at the end).
# A here-document's body is split as if it were commands.
shell_segments() {
  printf '%s' "$1" | awk '
    function flag(f) { flags[f] = 1 }
    function endword() {
      if (hw) { gsub(/[\n\t]/, " ", w); line = line (nw ? "\037" : "") w; nw++ }
      w = ""; hw = 0
    }
    function endseg() { endword(); if (nw) print line; line = ""; nw = 0 }
    { s = s (NR > 1 ? "\n" : "") $0 }
    END {
      n = length(s); q = ""; w = ""; hw = 0; line = ""; nw = 0
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
        if (c == ";" || c == "&" || c == "|" || c == "(" || c == ")" || c == "\n") { endseg(); continue }
        if (c == "<" || c == ">") { flag("redirect"); if (nx == "(") flag("subst"); endword(); continue }
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
# stdin, or given something that is not a file path.
git_commit_text() {
  local cmd="$1" out verdict
  if [ "${#cmd}" -le 65536 ]; then
    out=$(shell_segments "$cmd" | awk -F'\037' '
      function base(x) { sub(/.*\//, "", x); return x }
      function names_commit(x) { return x ~ /(^|[^A-Za-z0-9_])commit([^A-Za-z0-9_]|$)/ }
      # The value of an alias.NAME=VALUE word runs a commit (or anything, with `!`).
      function alias_commits(x,  v) { v = x; sub(/^.*[Aa][Ll][Ii][Aa][Ss]\.[^=]*=/, "", v); return names_commit(v) || v ~ /^!/ }
      /^\001subst$/ { fb = 1; next }
      # $'...' can spell an alias value the text does not show.
      /^\001ansi$/ { opaque = 1; next }
      /^\001/ { next }
      {
        k = 1
        while (k < NF && $k ~ /^[A-Za-z_][A-Za-z0-9_]*=/) k++
        if ($k ~ /\$/ || $k == ".") fb = 1
        g = 0; seghit = 0; line = ""
        for (j = 1; j <= NF; j++) {
          b = base($j); line = line (j > 1 ? " " : "") $j
          if (b ~ /^(eval|xargs|source|watch|parallel)$/) fb = 1
          if (b ~ /^(bash|sh|zsh|dash|ksh|fish|python[0-9.]*|perl|ruby|node|php|lua|osascript|pwsh|tclsh|deno|bun)$/) {
            arg = ""
            for (m = j + 1; m <= NF; m++) {
              if ($m == "-" || $m ~ /^-[A-Za-z]*[ceE][A-Za-z]*$/ || $m ~ /^--(command|eval|exec)/) fb = 1
              if (arg == "" && $m !~ /^-/) arg = $m
            }
            if (arg == "" || arg !~ /[\/.]/) fb = 1
          }
          # Config in a variable, here or in an earlier export.
          if ($j ~ /^GIT_CONFIG(_GLOBAL|_SYSTEM|_COUNT|_KEY_[0-9]+|_VALUE_[0-9]+)?=/) opaque = 1
          if ($j ~ /^GIT_CONFIG_PARAMETERS=/ && $j ~ /\$/) opaque = 1
          if ($j ~ /^GIT_CONFIG_PARAMETERS=/ && tolower($j) ~ /alias\./) { if (alias_commits($j)) cfgc = 1; else opaque = 1 }
          # GIT, Git, /usr/bin/GIT: a case-insensitive disk runs git for each.
          if (tolower(b) == "git" && !g) { g = 1; gi = j }
          else if (g && $j !~ /[ \t]/ && names_commit($j)) seghit = 1
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
      }
      END {
        if (fb) print "fallback"
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
    *) grep -qE '\b[Gg][Ii][Tt]\b.*\bcommit\b' <<< "$cmd" && printf '%s\n' "$cmd" ;;
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
command_only_reads() {
  local cmd="$1" prev=""
  [ "${#cmd}" -le 16384 ] || return 1
  case "$cmd" in *\\*) return 1 ;; esac
  while [ "$cmd" != "$prev" ]; do
    prev="$cmd"
    cmd=$(sed -E 's#(^|[[:space:]])[0-9]?(>&[0-9]|>>?[[:space:]]*/dev/null)([[:space:];&|)]|$)#\1\3#g' <<< "$cmd")
  done
  [ "$(shell_segments "$cmd" | awk -F'\037' '
    /^\001/ { bad = 1; next }
    {
      ok = 0; c = $1
      if (c == "cd") ok = (NF <= 2)
      else if (c ~ /^(cat|head|tail|more|wc|file|stat|ls|grep|jq|echo|pwd|true)$/) ok = 1
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
      if (!ok) bad = 1
    }
    END { print (bad || NR == 0 ? "no" : "yes") }')" = yes ]
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
