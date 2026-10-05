# Real hook-input fixtures

These JSON files were captured from a live Claude Code session (2026-07-09) by registering
passthrough hooks and recording stdin. They are the authoritative input shapes for hook tests —
do NOT hand-edit fields into them that Claude Code does not send (the 2026-07 review found the
suite green against a fictional `tool_response.exit_code` field while production was broken).

- `posttooluse-bash.json` — PostToolUse input for a Bash call (note: NO exit_code field)
- `stop.json` — Stop input (note: NO stop_reason field; loop guard is stop_hook_active)
- `userpromptsubmit.json` — UserPromptSubmit input captured 2026-10-05 (Claude Code 2.1.289,
  interactive) for a cross-session message: `prompt` is the exact `<cross-session-message …>` wrapper
  another session's `A1` arrived in. Ids and paths are sanitised; the keys and the prompt are as
  captured. Tests derive other prompts from it by replacing `.prompt` (and `.session_id`/`.cwd`).

Refresh after Claude Code updates with: `bash tests/tools/capture-hook-schemas.sh`
(requires the `claude` CLI and network; not run by run-tests.sh).
