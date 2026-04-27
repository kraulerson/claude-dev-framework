# scripts/cdf-refresh.sh — refresh CDF assets in a downstream project.
#
# CDF (Development Guardrails) ships hooks/rules/gates into a project's
# .claude/framework/ subtree on first install (init.sh). Without this
# library, existing projects are frozen at whatever CDF version was
# current at first install — they don't pick up landed CDF fixes by
# running an upgrade.
#
# Originally written for Solo Orchestrator (BL-001); migrated upstream
# so CDF-only projects (without Solo) can use it standalone:
#
#   source ~/.claude-dev-framework/scripts/cdf-refresh.sh
#   refresh_cdf_assets "$PWD" "$HOME/.claude-dev-framework" "false"
#
# Solo Orchestrator's `scripts/lib/cdf-refresh.sh` is a thin wrapper
# that delegates to this canonical implementation.
#
# Usage (sourced):
#   source "$HOME/.claude-dev-framework/scripts/cdf-refresh.sh"
#   refresh_cdf_assets "$PROJECT_ROOT" "$FRAMEWORK_CLONE" "$NON_INTERACTIVE"
#
# Arguments:
#   $1  project_root      — directory containing .claude/framework/.
#   $2  framework_clone   — path to CDF clone (typically ~/.claude-dev-framework).
#   $3  non_interactive   — "true" or "false". When true and the clone
#                            is missing or pull fails, prints a clear
#                            warning to stderr and returns 0 (skip,
#                            don't fail the upgrade). When false (interactive)
#                            and the clone is missing, prompts the user.
#
# Returns 0 on success or skip-with-warning. Returns non-zero only on
# unexpected errors (e.g., project_root doesn't exist).

# shellcheck shell=bash

# Print to stderr unless caller silenced (mirrors helpers.sh `print_*`
# style without depending on it — this lib is sourced from many places).
_cdf_print_info() { echo "  [INFO] $*" >&2; }
_cdf_print_warn() { echo "  [WARN] $*" >&2; }
_cdf_print_ok()   { echo "  [ OK ] $*" >&2; }

# CDF preamble — printed once when prompting the user about a missing clone.
# Karl-approved 2026-04-27: missing-clone case must explain what CDF is and
# what running without it costs, so users actively choose vs. accept silently.
_cdf_missing_clone_preamble() {
  cat >&2 <<'EOF'

  ┌──────────────────────────────────────────────────────────────────┐
  │  Development Guardrails (CDF) clone is missing.                  │
  │                                                                  │
  │  CDF is the framework providing Claude Code's pre-commit hooks,  │
  │  rules, and gates (config-guard, branch-safety, plan-tracking,   │
  │  test-strategy, etc.). It lives at ~/.claude-dev-framework and   │
  │  ships fixes that propagate to your project's .claude/framework/ │
  │  on each upgrade.                                                │
  │                                                                  │
  │  Without CDF or a tested replacement:                            │
  │    • Pre-commit hooks may stop matching upstream behavior.       │
  │    • You won't pick up fixes like the BL-021 read-only-git       │
  │      allowlist that prevents over-blocking on debug commands.    │
  │    • New rules/gates added upstream won't reach your project.    │
  │    • Custom guardrails are your responsibility to validate.      │
  │  └──────────────────────────────────────────────────────────────────┘
EOF
}

# Read manifest and emit the framework values we'll be updating, so we
# can print a useful "X -> Y" summary line after the refresh.
_cdf_manifest_get() {
  local manifest="$1" key="$2"
  if [ -f "$manifest" ] && command -v jq >/dev/null 2>&1; then
    jq -r --arg k "$key" '.[$k] // empty' "$manifest" 2>/dev/null
  fi
}

# Update a top-level scalar field in the project manifest. Idempotent.
# Uses a tempfile so a `jq` failure can't truncate the manifest.
_cdf_manifest_set() {
  local manifest="$1" key="$2" value="$3"
  if [ ! -f "$manifest" ] || ! command -v jq >/dev/null 2>&1; then
    return 0
  fi
  local tmp
  tmp=$(mktemp)
  if jq --arg k "$key" --arg v "$value" '. + {($k): $v}' "$manifest" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$manifest"
  else
    rm -f "$tmp"
    return 1
  fi
}

# Copy <src_dir>/*.{ext} into <dst_dir>/, creating dst_dir if needed.
# Skips when src_dir is empty (so missing optional CDF subdirs don't fail).
# Uses `find` to avoid the `shopt -p nullglob` exit-status interaction with
# `set -e` in callers.
_cdf_sync_dir() {
  local src_dir="$1" dst_dir="$2"
  shift 2
  if [ ! -d "$src_dir" ]; then
    return 0
  fi
  mkdir -p "$dst_dir"
  local ext
  for ext in "$@"; do
    while IFS= read -r -d '' f; do
      cp "$f" "$dst_dir/"
    done < <(find "$src_dir" -maxdepth 1 -type f -name "*.${ext}" -print0 2>/dev/null)
  done
  return 0
}

refresh_cdf_assets() {
  local project_root="$1"
  local framework_clone="$2"
  local non_interactive="${3:-false}"

  if [ ! -d "$project_root" ]; then
    echo "[FAIL] cdf-refresh: project_root does not exist: $project_root" >&2
    return 1
  fi

  # Missing clone: skip with warning in non-interactive; prompt with
  # explanation in interactive (Karl 2026-04-27).
  if [ ! -d "$framework_clone/.git" ]; then
    if [ "$non_interactive" = "true" ]; then
      _cdf_print_warn "CDF clone not found at $framework_clone — skipping CDF asset refresh."
      _cdf_print_info "Your project keeps its existing .claude/framework/ hooks/rules/gates."
      _cdf_print_info "To re-enable: git clone https://github.com/kraulerson/claude-dev-framework.git $framework_clone"
      return 0
    fi
    _cdf_missing_clone_preamble
    local answer
    read -rp "  Clone CDF now and refresh framework assets? [y/N]: " answer
    case "$answer" in
      y|Y|yes|YES)
        _cdf_print_info "Cloning CDF to $framework_clone..."
        if ! git clone -q --depth 1 https://github.com/kraulerson/claude-dev-framework.git "$framework_clone" 2>/dev/null; then
          _cdf_print_warn "git clone failed. Skipping CDF asset refresh."
          _cdf_print_info "Manually clone with: git clone https://github.com/kraulerson/claude-dev-framework.git $framework_clone"
          return 0
        fi
        _cdf_print_ok "CDF cloned."
        ;;
      *)
        _cdf_print_warn "User declined CDF clone — skipping CDF asset refresh."
        _cdf_print_info "Your project keeps its existing .claude/framework/ hooks/rules/gates."
        return 0
        ;;
    esac
  fi

  # Pull latest CDF if it's a git clone we own. --ff-only fails loudly
  # on dirty/divergent state rather than silently overwriting.
  if [ -d "$framework_clone/.git" ]; then
    if ! git -C "$framework_clone" pull --ff-only --quiet 2>/dev/null; then
      _cdf_print_warn "CDF git pull --ff-only failed. CDF clone may be dirty or on a branch with local commits."
      _cdf_print_info "Asset refresh will proceed using the current CDF working tree at $framework_clone."
      _cdf_print_info "To pick up upstream fixes, manually resolve CDF state then re-run upgrade."
    fi
  fi

  # Copy hooks (.sh + .txt for known-stdlib.txt and friends), rules (.md), gates (.sh).
  _cdf_sync_dir "$framework_clone/hooks" "$project_root/.claude/framework/hooks" sh txt
  _cdf_sync_dir "$framework_clone/rules" "$project_root/.claude/framework/rules" md
  _cdf_sync_dir "$framework_clone/gates" "$project_root/.claude/framework/gates" sh

  # Make hook + gate scripts executable (cp doesn't preserve mode reliably across filesystems).
  if [ -d "$project_root/.claude/framework/hooks" ]; then
    chmod +x "$project_root/.claude/framework/hooks/"*.sh 2>/dev/null || true
  fi
  if [ -d "$project_root/.claude/framework/gates" ]; then
    chmod +x "$project_root/.claude/framework/gates/"*.sh 2>/dev/null || true
  fi

  # Update manifest with CDF version + commit. Both come from the CDF
  # clone we just synced from, so the manifest reflects what's actually
  # on disk in the project.
  local manifest="$project_root/.claude/manifest.json"
  local fw_version=""
  local fw_commit=""
  if [ -f "$framework_clone/FRAMEWORK_VERSION" ]; then
    fw_version=$(tr -d '[:space:]' < "$framework_clone/FRAMEWORK_VERSION")
  fi
  if [ -d "$framework_clone/.git" ]; then
    fw_commit=$(git -C "$framework_clone" rev-parse HEAD 2>/dev/null || echo "")
  fi
  local prev_version prev_commit
  prev_version=$(_cdf_manifest_get "$manifest" frameworkVersion)
  prev_commit=$(_cdf_manifest_get "$manifest" frameworkCommit)

  if [ -n "$fw_version" ]; then
    _cdf_manifest_set "$manifest" frameworkVersion "$fw_version" \
      || _cdf_print_warn "Failed to update manifest.frameworkVersion (manifest may be invalid JSON)"
  fi
  if [ -n "$fw_commit" ]; then
    _cdf_manifest_set "$manifest" frameworkCommit "$fw_commit" \
      || _cdf_print_warn "Failed to update manifest.frameworkCommit (manifest may be invalid JSON)"
  fi

  if [ -n "$prev_version" ] && [ "$prev_version" != "$fw_version" ]; then
    _cdf_print_ok "CDF assets refreshed: $prev_version -> ${fw_version:-unknown}"
  elif [ -n "$fw_version" ]; then
    _cdf_print_ok "CDF assets refreshed (version $fw_version)"
  else
    _cdf_print_ok "CDF assets refreshed"
  fi
  if [ -n "$prev_commit" ] && [ -n "$fw_commit" ] && [ "$prev_commit" != "$fw_commit" ]; then
    _cdf_print_info "Commit: ${prev_commit:0:12} -> ${fw_commit:0:12}"
  fi

  return 0
}
