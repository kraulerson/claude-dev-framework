#!/usr/bin/env bash
# capture-hook-schemas.sh — refresh/verify the real Claude Code hook-input fixtures.
#
# Registers passthrough hooks in a throwaway git project, runs a live `claude`
# session that executes one Bash command and stops, records the raw stdin each
# hook received, then diffs the captured input schema against the committed
# fixtures in tests/fixtures/. Requires the `claude` CLI and network access.
# NOT run by run-tests.sh (see tests/fixtures/README.md).
#
# Drift semantics: the committed fixtures are the scrubbed authoritative shapes
# (they omit session-specific keys like session_id/transcript_path/cwd — see
# §0.1 of the review-remediation plan). A live capture therefore legitimately
# carries EXTRA keys. Drift = a key documented in a fixture is MISSING from the
# live capture (Claude Code dropped/renamed a field the tests depend on), which
# is exactly the failure the 2026-07 review caught (a fictional exit_code field).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FIXTURE_DIR="$(cd "$SCRIPT_DIR/../fixtures" && pwd)"
POST_FIXTURE="$FIXTURE_DIR/posttooluse-bash.json"
STOP_FIXTURE="$FIXTURE_DIR/stop.json"
UPS_FIXTURE="$FIXTURE_DIR/userpromptsubmit.json"

command -v claude >/dev/null 2>&1 || { echo "ERROR: claude CLI not found on PATH" >&2; exit 1; }
command -v jq >/dev/null 2>&1     || { echo "ERROR: jq not found on PATH" >&2; exit 1; }
[ -f "$POST_FIXTURE" ] || { echo "ERROR: missing fixture $POST_FIXTURE" >&2; exit 1; }
[ -f "$STOP_FIXTURE" ] || { echo "ERROR: missing fixture $STOP_FIXTURE" >&2; exit 1; }
[ -f "$UPS_FIXTURE" ] || { echo "ERROR: missing fixture $UPS_FIXTURE" >&2; exit 1; }

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/cdf-capture.XXXXXX")
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

POST_CAPTURE="$WORK_DIR/capture-post.jsonl"
STOP_CAPTURE="$WORK_DIR/capture-stop.jsonl"
UPS_CAPTURE="$WORK_DIR/capture-ups.jsonl"
SETTINGS="$WORK_DIR/settings.json"

( cd "$WORK_DIR" && git init -q )

# Passthrough hooks: append whatever each hook receives on stdin.
cat > "$SETTINGS" <<EOF
{
  "hooks": {
    "PostToolUse": [
      { "matcher": "Bash", "hooks": [ { "type": "command", "command": "cat >> $POST_CAPTURE" } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "cat >> $STOP_CAPTURE" } ] }
    ],
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "cat >> $UPS_CAPTURE" } ] }
    ]
  }
}
EOF

# Gotchas learned capturing the originals:
#  - the prompt must be the FIRST argument after -p;
#  - use `=` for flag values (--allowedTools is variadic and will otherwise
#    swallow a trailing prompt);
#  - redirect stdin from /dev/null so claude does not block on a TTY.
( cd "$WORK_DIR" && claude -p "Run this exact bash command: echo hello world. Then reply with just: done" \
    --model haiku \
    --settings="$SETTINGS" \
    --allowedTools="Bash(echo *)" \
    < /dev/null ) || true

DRIFT=0

# compare_keys LABEL CAPTURE_FILE FIXTURE_FILE JQ_FILTER
# Asserts every key produced by JQ_FILTER on the fixture is also present in the
# same filter's output on the last captured object.
compare_keys() {
  label="$1"; cap="$2"; fix="$3"; filter="$4"
  if [ ! -s "$cap" ]; then
    echo "DRIFT ($label): no hook input captured — did the session run?" >&2
    DRIFT=1
    return
  fi
  want=$(jq -S "$filter" "$fix" 2>/dev/null || echo "null")
  got=$(jq -s ".[-1] | ($filter)" "$cap" 2>/dev/null | jq -S . 2>/dev/null || echo "null")
  missing=$(jq -n --argjson want "$want" --argjson got "$got" '$want - $got' 2>/dev/null || echo '["<parse-error>"]')
  if [ "$missing" = "[]" ]; then
    echo "OK ($label)"
  else
    echo "DRIFT ($label): keys present in fixture but missing from live capture:" >&2
    echo "  missing:  $missing" >&2
    echo "  captured: $got" >&2
    DRIFT=1
  fi
}

compare_keys "PostToolUse top-level"     "$POST_CAPTURE" "$POST_FIXTURE" "keys"
compare_keys "PostToolUse tool_response" "$POST_CAPTURE" "$POST_FIXTURE" ".tool_response | keys"
compare_keys "Stop top-level"            "$STOP_CAPTURE" "$STOP_FIXTURE" "keys"
# scratchpad_dir appears in interactive sessions only (the fixture is an interactive
# capture, this run is headless), so it is left out of the comparison.
compare_keys "UserPromptSubmit top-level" "$UPS_CAPTURE" "$UPS_FIXTURE" '[keys[] | select(. != "scratchpad_dir")]'

if [ "$DRIFT" -ne 0 ]; then
  echo "" >&2
  echo "Schema drift detected. If Claude Code changed its hook input shape, update the" >&2
  echo "fixtures in tests/fixtures/ and any tests that assert on the affected fields." >&2
  exit 1
fi

echo "All captured hook-input schemas match the committed fixtures."
exit 0
