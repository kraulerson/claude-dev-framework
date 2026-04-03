# --prepopulate Flag Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `--prepopulate <path>` flag to `scripts/init.sh` that reads a JSON file containing pre-answered discovery data, skipping the interactive interview entirely. Also add dependency install checks (Superpowers + Context7) to init.sh.

**Architecture:** Modify init.sh flag parsing from `for arg` to `while/shift` to support value flags. Add validation logic before the discovery integration point. Add a dependency check section sourcing `_helpers.sh` for `check_context7()`. Existing `--skip-plugin-check` flag skips all dependency checks.

**Tech Stack:** Bash, jq

---

## File Map

### Modified Files

| File | What Changes |
|------|-------------|
| `scripts/init.sh` | Flag parsing rewrite, prepopulate validation + integration, dependency install section, source _helpers.sh |
| `README.md` | Document `--prepopulate` flag, update hook/test counts for v4 |

### New Files

| File | Responsibility |
|------|---------------|
| `tests/test-prepopulate.sh` | Tests for prepopulate validation: valid JSON, invalid JSON, missing file, no branch key, fallback behavior |

---

### Task 1: Write Prepopulate Tests

**Files:**
- Create: `tests/test-prepopulate.sh`

- [ ] **Step 1: Write the test file**

Create `tests/test-prepopulate.sh`:

```bash
#!/usr/bin/env bash
# test-prepopulate.sh — Tests for --prepopulate flag in init.sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

INIT_SCRIPT="$(cd "$SCRIPT_DIR/.." && pwd)/scripts/init.sh"

# Helper: create a temp git repo suitable for init.sh
setup_init_project() {
  TEST_DIR=$(mktemp -d)
  git -C "$TEST_DIR" init --quiet
  git -C "$TEST_DIR" config user.email "test@test.com"
  git -C "$TEST_DIR" config user.name "Test"
  echo "init" > "$TEST_DIR/README.md"
  git -C "$TEST_DIR" add README.md
  git -C "$TEST_DIR" commit -m "Initial commit" --quiet
  # Set a different remote so init.sh doesn't think we're in the framework repo
  git -C "$TEST_DIR" remote add origin "https://github.com/test/test-project.git" 2>/dev/null || true
}

teardown_init_project() {
  [ -n "$TEST_DIR" ] && rm -rf "$TEST_DIR"
  unset TEST_DIR
}

# --- Test: valid prepopulate JSON is used ---
test_valid_prepopulate() {
  setup_init_project
  cat > "$TEST_DIR/discovery.json" << 'JSON'
{
  "branch:main": {
    "purpose": "main development branch",
    "devOS": "Darwin",
    "targetPlatform": "web",
    "buildTools": "typescript"
  },
  "futurePlatforms": null,
  "discoveryDate": "2026-04-03",
  "lastReviewDate": "2026-04-03"
}
JSON
  OUTPUT=$(cd "$TEST_DIR" && bash "$INIT_SCRIPT" --skip-plugin-check --prepopulate "$TEST_DIR/discovery.json" 2>&1)
  assert_contains "$OUTPUT" "Using pre-populated discovery from" "should log prepopulate message"
  assert_contains "$OUTPUT" "Installation Complete" "should complete installation"

  # Verify discovery data made it into manifest
  DISC_PURPOSE=$(jq -r '.discovery["branch:main"].purpose' "$TEST_DIR/.claude/manifest.json" 2>/dev/null || echo "")
  assert_equals "main development branch" "$DISC_PURPOSE" "manifest should contain prepopulated discovery"

  teardown_init_project
}

# --- Test: missing file falls back with warning ---
test_missing_file_warns() {
  setup_init_project
  OUTPUT=$(cd "$TEST_DIR" && echo "" | echo "" | echo "" | echo "" | echo "" | echo "" | bash "$INIT_SCRIPT" --skip-plugin-check --prepopulate "/nonexistent/file.json" 2>&1)
  assert_contains "$OUTPUT" "WARNING" "should warn about missing file"
  assert_contains "$OUTPUT" "not found" "should say file not found"
  teardown_init_project
}

# --- Test: invalid JSON falls back with warning ---
test_invalid_json_warns() {
  setup_init_project
  echo "not json at all {{{" > "$TEST_DIR/bad.json"
  OUTPUT=$(cd "$TEST_DIR" && echo "" | echo "" | echo "" | echo "" | echo "" | echo "" | bash "$INIT_SCRIPT" --skip-plugin-check --prepopulate "$TEST_DIR/bad.json" 2>&1)
  assert_contains "$OUTPUT" "WARNING" "should warn about invalid JSON"
  assert_contains "$OUTPUT" "not valid JSON" "should say not valid JSON"
  teardown_init_project
}

# --- Test: JSON without branch key falls back with warning ---
test_no_branch_key_warns() {
  setup_init_project
  cat > "$TEST_DIR/nobranch.json" << 'JSON'
{
  "futurePlatforms": null,
  "discoveryDate": "2026-04-03"
}
JSON
  OUTPUT=$(cd "$TEST_DIR" && echo "" | echo "" | echo "" | echo "" | echo "" | echo "" | bash "$INIT_SCRIPT" --skip-plugin-check --prepopulate "$TEST_DIR/nobranch.json" 2>&1)
  assert_contains "$OUTPUT" "WARNING" "should warn about missing branch key"
  assert_contains "$OUTPUT" "no branch" "should mention no branch key"
  teardown_init_project
}

# --- Test: prepopulate takes priority over reconfigure ---
test_prepopulate_overrides_reconfigure() {
  setup_init_project
  # First do a normal install so reconfigure has something to work with
  cd "$TEST_DIR" && echo "" | echo "" | echo "" | echo "" | echo "" | echo "" | bash "$INIT_SCRIPT" --skip-plugin-check 2>&1 >/dev/null

  cat > "$TEST_DIR/discovery.json" << 'JSON'
{
  "branch:main": {
    "purpose": "overridden by prepopulate",
    "devOS": "Linux",
    "targetPlatform": "api",
    "buildTools": "go"
  },
  "discoveryDate": "2026-04-03",
  "lastReviewDate": "2026-04-03"
}
JSON
  OUTPUT=$(cd "$TEST_DIR" && bash "$INIT_SCRIPT" --skip-plugin-check --reconfigure --prepopulate "$TEST_DIR/discovery.json" 2>&1)
  assert_contains "$OUTPUT" "Using pre-populated discovery from" "prepopulate should take priority over reconfigure"

  DISC_PURPOSE=$(jq -r '.discovery["branch:main"].purpose' "$TEST_DIR/.claude/manifest.json" 2>/dev/null || echo "")
  assert_equals "overridden by prepopulate" "$DISC_PURPOSE" "prepopulated data should be in manifest"

  teardown_init_project
}

# --- Run all tests ---
echo "init.sh --prepopulate"
test_valid_prepopulate
test_missing_file_warns
test_invalid_json_warns
test_no_branch_key_warns
test_prepopulate_overrides_reconfigure
run_tests
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-prepopulate.sh`
Expected: FAIL — init.sh doesn't recognize `--prepopulate` yet.

- [ ] **Step 3: Commit test file**

```bash
git add tests/test-prepopulate.sh
git commit -m "test: add tests for --prepopulate flag (red)"
```

---

### Task 2: Rewrite Flag Parsing in init.sh

**Files:**
- Modify: `scripts/init.sh:9-17`

- [ ] **Step 1: Replace the for-arg loop with while/shift**

In `scripts/init.sh`, replace lines 9-17:

```bash
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
```

With:

```bash
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
```

- [ ] **Step 2: Run existing tests to confirm no breakage**

Run: `bash tests/run-tests.sh`
Expected: All 148 tests pass (flag parsing change doesn't affect hook tests).

- [ ] **Step 3: Commit**

```bash
git add scripts/init.sh
git commit -m "refactor: rewrite init.sh flag parsing to while/shift for value flags"
```

---

### Task 3: Add Prepopulate Validation and Integration

**Files:**
- Modify: `scripts/init.sh:268-272` (discovery integration point)

- [ ] **Step 1: Replace the discovery section**

In `scripts/init.sh`, replace:

```bash
# Run discovery if clean setup or reconfigure
DISCOVERY_JSON="{}"
if [ "$HAS_EXISTING" = false ] || [ "$RECONFIGURE" = true ]; then
  DISCOVERY_JSON=$(run_discovery)
fi
```

With:

```bash
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
```

- [ ] **Step 2: Run prepopulate tests**

Run: `bash tests/test-prepopulate.sh`
Expected: All 5 tests pass (valid JSON used, missing file warns, invalid JSON warns, no branch key warns, prepopulate overrides reconfigure).

- [ ] **Step 3: Commit**

```bash
git add scripts/init.sh
git commit -m "feat: add --prepopulate flag to skip interactive discovery with pre-answered JSON"
```

---

### Task 4: Add Dependency Install Section

**Files:**
- Modify: `scripts/init.sh` (after the Phase 5 plugin check block, around line 229)

- [ ] **Step 1: Source _helpers.sh for check_context7**

In `scripts/init.sh`, after the existing `source "$(dirname "$0")/_shared.sh"` line (line 92), add:

```bash
source "$FRAMEWORK_CLONE/hooks/_helpers.sh" 2>/dev/null || true
```

- [ ] **Step 2: Expand the Phase 5 plugin check to include Context7**

In `scripts/init.sh`, replace the existing Phase 5 block (lines 218-229):

```bash
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
```

With:

```bash
  # Phase 5: DEPENDENCY CHECK
  if [ "$SKIP_PLUGINS" = false ]; then
    echo "── Phase 5: DEPENDENCY CHECK ──"

    # Superpowers plugin
    if [ -f "$HOME/.claude/settings.json" ] && command -v jq &>/dev/null; then
      SP=$(jq -r '.enabledPlugins["superpowers@claude-plugins-official"] // false' "$HOME/.claude/settings.json" 2>/dev/null || echo "false")
      if [ "$SP" = "true" ]; then
        echo "  ✓ Superpowers plugin: INSTALLED"
      else
        echo "  ✗ Superpowers plugin: NOT INSTALLED (required)"
        echo "    Install: Run claude > /plugins > search 'superpowers' > install"
      fi
    fi

    # Context7 MCP
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
```

- [ ] **Step 3: Also add dependency check for clean installs (non-migration path)**

The Phase 5 block above only runs inside the migration `if` block (line 151). For clean installs, add a similar check after the "=== Installing Framework ===" line (around line 237). Insert before the `mkdir -p` line:

```bash
# Dependency check (clean install path)
if [ "$SKIP_PLUGINS" = false ]; then
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
```

- [ ] **Step 4: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/init.sh
git commit -m "feat: add Superpowers and Context7 dependency checks to init.sh"
```

---

### Task 5: Update README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add --prepopulate documentation to Quick Start section**

After the existing Quick Start section (line 65), add a new section:

```markdown
## Programmatic Setup

For tools that install the framework as a dependency (e.g., project scaffolders, orchestrators):

```bash
# Create a discovery JSON file with your project context
cat > .claude/discovery-prepopulated.json << 'EOF'
{
  "branch:main": {
    "purpose": "main development branch",
    "devOS": "Darwin",
    "targetPlatform": "web",
    "buildTools": "typescript"
  },
  "futurePlatforms": null,
  "discoveryDate": "2026-04-03",
  "lastReviewDate": "2026-04-03"
}
EOF

# Run init with pre-populated discovery (skips interactive interview)
bash ~/.claude-dev-framework/scripts/init.sh --prepopulate .claude/discovery-prepopulated.json

# If your tool handles dependency installation itself:
bash ~/.claude-dev-framework/scripts/init.sh --skip-plugin-check --prepopulate .claude/discovery-prepopulated.json
```

The `--prepopulate` flag accepts a JSON file with the same structure as the discovery interview output. The file must contain at least one `branch:*` key. If the file is missing, invalid, or lacks a branch key, init.sh falls back to the interactive interview with a warning.
```

- [ ] **Step 2: Update hook count and test count**

On line 69, change `**13 hooks**` to `**18 hooks**`.

On line 134, change `71 automated assertions across 12 test files` to `148+ automated assertions across 21+ test files`.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: document --prepopulate flag and update v4 counts in README"
```

---

### Task 6: Final Validation

- [ ] **Step 1: Run prepopulate tests**

Run: `bash tests/test-prepopulate.sh`
Expected: All 5 tests pass.

- [ ] **Step 2: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass.

- [ ] **Step 3: Verify end-to-end with a temp project**

```bash
TMPDIR=$(mktemp -d)
cd "$TMPDIR"
git init && git commit --allow-empty -m "init"
git remote add origin https://github.com/test/fake.git
cat > discovery.json << 'EOF'
{
  "branch:main": {
    "purpose": "test",
    "devOS": "Darwin",
    "targetPlatform": "web",
    "buildTools": "node"
  },
  "discoveryDate": "2026-04-03",
  "lastReviewDate": "2026-04-03"
}
EOF
bash ~/.claude-dev-framework/scripts/init.sh --skip-plugin-check --prepopulate discovery.json
cat .claude/manifest.json | jq '.discovery'
cd - && rm -rf "$TMPDIR"
```

Expected: Discovery section in manifest.json contains the prepopulated values.

- [ ] **Step 4: Verify --skip-plugin-check skips Context7 check**

Run the same command above — no Context7 install prompt should appear.
