# Hook Reference

## Enforcement Zones (v4.0.0)

| Zone | Hooks | Purpose |
|------|-------|---------|
| Discovery | session-start.sh, session-end.sh | Dependency checks, zone activation, Context7 install; session-scoped marker lifecycle (start clears stale markers, end cleans up) |
| Design | enforce-superpowers.sh, marker-tracker.sh | Blocks edits until Superpowers skill invoked |
| Planning | enforce-plan-tracking.sh, marker-tracker.sh | Blocks edits until plan task is in_progress |
| Implementation | enforce-context7.sh, marker-tracker.sh | Blocks edits using unresearched libraries |
| Verification | enforce-evaluate.sh, pre-commit-checks.sh, verification-gate.sh | Pre-commit quality gates |

---

## session-start.sh
- **Event:** SessionStart
- **Zone:** Discovery
- **Blocking:** No
- **Purpose:** Activates enforcement zones, checks dependencies (jq, Superpowers, Context7), outputs terse zone report, loads context history
- **Customize:** Edit `manifest.json → activeRules` to change rule count; `verificationGates` to change gate listing
- **Disable:** Remove `session-start` from `manifest.json → activeHooks`

## enforce-evaluate.sh
- **Event:** PreToolUse (Bash)
- **Blocking:** Yes (exit 2)
- **Purpose:** Blocks `git commit` without an evaluation marker. Also blocks `git commit --no-verify` (which would bypass git security hooks). Warns advisory on `git commit --amend`.
- **What counts as a commit:** `command_runs_git_commit` in `_helpers.sh`, shared with pre-commit-checks.sh, verification-gate.sh and marker-tracker.sh. The command is split like the shell splits it (quotes removed, at `;` `&` `|` `(` `)` and newlines); a simple command with a word `git` and a later word naming `commit` is a commit (`env git commit`, `git -C dir commit`, `git -c alias.ci=commit ci`). Config given with the command can make a subcommand an alias for commit, so git running a subcommand that an alias could be is a commit when the config defines an alias whose value names commit or starts with `!` (`git -c alias.ci='commit -am x' ci`, `GIT_CONFIG_PARAMETERS`) or hides the value (`--config-env=alias.*`, `GIT_CONFIG_GLOBAL`/`SYSTEM`/`COUNT`/`KEY_n`/`VALUE_n`, `GIT_CONFIG`, a value in a `$variable` or `$'...'`), in the same command or an earlier `export`. A subcommand is taken as one no alias can shadow only when it is both in the long-standing baseline (`GIT_BASELINE_BUILTINS` in `_helpers.sh`: every name is a builtin in git 2.25.0 and later, checked against git.c's command table at v2.25.0 and v2.30.0; later additions such as `maintenance`, `hook`, `history` or `replay`, and names that were scripts until recently such as `bisect` and `fast-import`, are left out) and a builtin of the git the command runs (`git --list-cmds=builtins` of an absolute-path git word, else of the hook's PATH git, listed once per hook run). A git named by a relative path (`./git`, `sub/git`, `~/bin/git`) is not resolved: with alias-capable config every subcommand counts as aliasable, and with none it is an ordinary command. An installed `git-NAME` never counts: whether it shadows an alias depends on `PATH`, `GIT_EXEC_PATH` and `--exec-path` when the command runs, which the command itself can change. When that git runs but cannot list its builtins, every subcommand counts as aliasable (fail strict); with no working git the baseline alone decides. So `GIT_CONFIG_GLOBAL=x git log`, `git -c alias.st=status st` and `git config --get alias.lg` are not commits, while hidden or alias-defining config with an external or recent subcommand (`GIT_CONFIG_GLOBAL=/dev/null git lfs status`, `git subtree`, `git flow`, `git maintenance`) needs the evaluation marker — an accepted cost. The command word `git` is matched in any letter case (`GIT commit`, `/usr/bin/GIT commit`): a case-insensitive disk, macOS's default, runs git for each; the `core.hooksPath`, `--no-verify`, `-n` and `--amend` checks do the same. Setting an alias for later is gated when its value names commit or starts with `!` (`git config alias.ci 'commit -m x'`); an alias already defined in a config file is not seen, so `git ci` through one passes (the R-23 residual of config written beforehand). The gate is about the `commit` subcommand (and `commit-tree`, which the word rule also matches): `git am`, `merge --no-ff`, `cherry-pick`, `revert`, `rebase`, `stash` and `notes` create commits without passing through it, as before. enforce-evaluate reads `--no-verify`, `-n` and `--amend` from the commit as the shell runs it (quotes removed) as well as from the raw text, so `git "comm""it" --no-verify` is refused. A hook newer than its `_helpers.sh` (a sync left half done) falls back to the text rule rather than letting a commit through, and says so on stderr (exit code unchanged). Text that only mentions a commit inside a quoted argument (`printf '... git status ... commit'`, `--question "... git commit ..."`) is not. Where the text can run more than it shows — a command substitution, a variable as the command word, `eval`/`xargs`/`source`/`watch`/`parallel`, an interpreter given code with `-c`/`-e`, read from stdin or given a non-path — any `git` followed by `commit` anywhere in the text counts, as before. A here-document's body is split as commands, so prose in one can still read as a commit.
- **Approval (design B):** the marker is created only by `record-approval.sh` from the user's pick of a question recorded in `.claude/pending-approval.json` (schema 2), or by the user's own `mark-evaluated.sh` run in a separate terminal. Without a marker the block message gives the agent the exact schema-2 shape: stage the change, write the file with the Write tool, stop, and let the user answer with the option id twice.
- **Commit under an approval:** the marker is JSON bound to HEAD, the index tree (`git write-tree`), a digest of the effective hooks directory and a digest of `git config --list --show-origin --show-scope`. The commit must be exactly `git commit` with message/metadata options (`commit_shape_problem` in `_helpers.sh`): one simple command (2>&1 and /dev/null redirections aside), a bare `git` in any letter case, no assignment words, no `env`/`exec`/`command` prefix, no git global options; `-m`/`--message`, `-F`/`--file`, `--author`, `--date`, `--cleanup`, `--trailer`, `-s`, `-q`, `-v`, `-S`/`--gpg-sign`, `--no-gpg-sign`, `--no-edit` only (attached forms and short clusters parsed). `-a`, `-i`, `-o`, `-p`, `--amend`, `--fixup`, `--allow-empty`, pathspecs and other options are refused. Any change to HEAD, the stage, the hooks or the git config since the approval voids it. A marker without that state (an old `touch` marker) approves nothing.
- **Code-running config:** wherever config is SET in any command (`-c`, `--config-env`, `GIT_CONFIG_PARAMETERS`, `GIT_CONFIG_KEY_n`, the key of a setting `git config`, `git config --edit`), `git_sets_code_config` refuses `core.hooksPath`, `hook.*`, `core.fsmonitor`, `core.sshCommand`, `core.askPass`, `core.editor`, `sequence.editor`, `gpg.program`, `gpg.*.program`, `filter.*.clean|smudge|process`, `diff.external`, `diff.*.command`, `merge.*.driver`, credential helpers, `include.path`, `includeIf.*`, `!` or hidden aliases and keys hidden in a `$variable`. Reads, commit messages, `--grep` and pathspecs that mention a key pass.
- **Marker:** `/tmp/.claude_evaluated_{hash}` (JSON) — created by `record-approval.sh` or the user's `mark-evaluated.sh`; cleared after the next commit
- **Refused by design (intended):** `git commit -m x --` (a `--` is a pathspec separator, so no pathspec forms are allowed under an approval); one-time setup that sets code-running config, such as `git config --unset core.hooksPath`, `git config --global credential.helper osxkeychain` or `git config core.editor vim` — the user runs these in their own terminal. A command that changes git's hooks or config without naming it (for example `git lfs install`) is not refused, but it voids an open render or approval through the hooks and config digests, so the user is asked again.
- **Disable:** Remove `enforce-evaluate` from `manifest.json → activeHooks`

## record-approval.sh
- **Event:** UserPromptSubmit (registered by `generate_settings_json` whenever `enforce-evaluate` is active)
- **Blocking:** Only to show the question (`decision: "block"`, whose reason reaches the user, not Claude); never on its own failure
- **Purpose:** Turns the user's own answer to a recorded question into the evaluation marker (approval design B; spec `docs/superpowers/specs/2026-10-05-approval-via-pending-question-design.md`). While `.claude/pending-approval.json` exists: a prompt starting with `<` (harness turns, peer messages, marked pastes) and slash commands neither pick nor void; a reply that contains `<task-notification` / `<cross-session-message` elsewhere is not read as an answer either, and Claude is told so (the render stays); a reply whose first token (trailing `.,:;!)` and dashes stripped) is an option id is a pick candidate. The first candidate is blocked and the question, each option's effect, the staged change (`git diff --cached --stat`) and the hooks that will run are rendered; a render record `/tmp/.claude_approval_shown_{hash}` stores the session, the sentinel's sha256, HEAD, the index tree and the two digests. The next non-neutral prompt in the same session picks if it names an option and nothing changed; otherwise an id-shaped reply re-renders and any other reply voids the render. An approving pick with something staged writes the marker, appends `.claude/approvals.jsonl` and the eval log, and deletes the sentinel; a non-approving pick only records and resolves. Free text never approves. A v1 or invalid sentinel cannot be answered: the reply passes, with the schema-2 shape for Claude and a note for the user. Internal errors grant nothing, exit 0 and report in both `systemMessage` and `additionalContext`.
- **Sentinel (schema 2):** `{"schema": 2, "question": "…", "options": [{"id": "A1", "text": "…", "approves": "commit"}, {"id": "A2", "text": "…", "approves": "none"}], "recommendation": "A1", "offered_at": "…"}` — ids are a letter and one or two digits, unique ignoring case; at least one option approves nothing; any other `approves` means none; other fields are ignored.
- **Disable:** Remove `enforce-evaluate` from `manifest.json → activeHooks` (it is registered with it)

## enforce-superpowers.sh
- **Event:** PreToolUse (Write|Edit|NotebookEdit)
- **Blocking:** Yes (exit 2)
- **Purpose:** Blocks source file edits until a Superpowers skill has been invoked this session
- **Skips:** Docs, config, test files, and files outside the project (an absolute path that resolves, symlinks followed, outside `$CLAUDE_PROJECT_DIR`; a relative path or one with `.`/`..` counts as inside)
- **Plugin not enabled:** when no settings file enables `superpowers@<marketplace>` — the project's `.claude/settings.local.json`, then `.claude/settings.json`, then the user's `settings.json` under `$CLAUDE_CONFIG_DIR` (else `~/.claude`), the first that names it deciding — the block says so and gives `claude plugin install --scope user superpowers@claude-plugins-official` instead of asking for a skill that cannot be invoked. session-start.sh reports the same status.
- **Marker:** `/tmp/.claude_superpowers_{hash}` — created when any Superpowers skill is invoked; cleared by a successful commit (marker-tracker.sh), by a fresh session (startup/clear) and at session end. The block message states this lifetime.
- **Disable:** Remove `enforce-superpowers` from `manifest.json → activeHooks`

## pre-commit-checks.sh
- **Event:** PreToolUse (Bash)
- **Blocking:** Yes (exit 2)
- **Purpose:** Blocks `git commit` if version files or changelog not staged alongside source changes
- **Configured by:** `manifest.json → projectConfig → versionFiles`, `changelogFile`, `sourceExtensions`
- **Disable:** Remove `pre-commit-checks` from `manifest.json → activeHooks`

## branch-safety.sh
- **Event:** PreToolUse (Bash)
- **Blocking:** Yes (exit 2)
- **Purpose:** Blocks `git push` to protected branches, pushes outside allowed dev branches, and force pushes (`--force`, `-f`, `--force-with-lease`) on any branch
- **Configured by:** `manifest.json → projectConfig → protectedBranches`, `devBranches`
- **Disable:** Remove `branch-safety` from `manifest.json → activeHooks`

## stop-checklist.sh
- **Event:** Stop
- **Blocking:** Yes (JSON `decision: "block"`)
- **Purpose:** Blocks session end if uncommitted work, missing changelog, bug fix without test, or long session without context history
- **Loop guard:** exits silently when `stop_hook_active` is true (a prior block this turn).
- **Advisory output:** The end-of-session advisory is delivered as Stop `additionalContext` JSON (not stderr).
- **Plan-closure advisory:** When the session has commits and no plan-closed marker, the advisory asks for plan closure and names the script that records it. Once the marker exists the plan-closure advisory is no longer emitted; if no other advisory remains, the hook prints nothing.
- **Marker:** `/tmp/.claude_plan_closed_{hash}` — created by `mark-plan-closed.sh` (a one-line closure summary in plain text, no shell punctuation, or `--note <path>` to an existing, non-empty closure note; an empty summary or a missing/empty note is refused). Cleared by `session-start.sh` on a fresh session (startup/clear) and by `session-end.sh`; kept across resume and compact.
- **Pending-approval sentinel:** If `${CLAUDE_PROJECT_DIR}/.claude/pending-approval.json` exists, hook exits 0 without a block. It shows the user a `systemMessage`: for a schema-2 question, the question and how to answer; for a v1 or invalid one, that it cannot be answered and the schema-2 shape the agent must rewrite it in. The agent writes this file to record a question; `record-approval.sh` resolves it when the user picks. A commit made this session whose tree is not the approved one (`matched=false` in `.claude/approvals.jsonl`) is reported as an unfinished step, once, even while a question is pending (a new question cannot hide it). The "Uncommitted source changes" block names this route, for a commit that is waiting on the user's approval (enforce-evaluate.sh). Existence alone suffices — malformed/empty content is treated as in-flight. Orphaned files (after a crash) are not auto-cleaned; `rm` manually.
- **Session-scope error dedup:** After the first block for a given error set, subsequent firings with the same errors are silent. Marker at `/tmp/.claude_stop_errors_hash_{hash}_{session_start_sha}` holds a shasum of the ERRORS string; empty errors clear it. Prevents the retry-amplification loop where repeated "Complete these, then finish" pressure would erode agent discipline.
- **Disable:** Remove `stop-checklist` from `manifest.json → activeHooks`

## changelog-sync-check.sh
- **Event:** PreToolUse (Write|Edit)
- **Blocking:** Advisory (JSON additionalContext)
- **Purpose:** Warns before editing changelog if upstream changes exist
- **Marker:** `/tmp/.claude_changelog_synced_{hash}` — created by marker-tracker
- **Disable:** Remove `changelog-sync-check` from `manifest.json → activeHooks`

## scalability-check.sh
- **Event:** PreToolUse (Write|Edit)
- **Blocking:** Advisory (JSON additionalContext)
- **Purpose:** Reminds about future platform plans when editing architecture-relevant files
- **Configured by:** `manifest.json → discovery → futurePlatforms`
- **Disable:** Remove `scalability-check` from `manifest.json → activeHooks`

## pre-deploy-check.sh
- **Event:** PreToolUse (Bash)
- **Blocking:** Advisory (JSON additionalContext)
- **Purpose:** Warns before deployment commands (docker compose, kubectl, git pull, ssh, rsync) if there are unpushed commits
- **Configured by:** `manifest.json → discovery → deployCommands` (custom deploy commands)
- **Disable:** Remove `pre-deploy-check` from `manifest.json → activeHooks`

## marker-tracker.sh
- **Event:** PostToolUse (all tools)
- **Zone:** Design + Planning + Implementation
- **Blocking:** No
- **Purpose:** Unified PostToolUse marker management. Creates superpowers/has_plan markers on Superpowers skill invoke; creates/clears plan_active marker on TaskUpdate; creates per-library c7 markers on Context7 MCP queries; creates changelog_synced marker on sync scripts; clears evaluation/superpowers/plan_active markers after a successful commit. Commit success is detected by HEAD movement (the real Bash `tool_response` has no `exit_code`): after a commit command, if `git rev-parse HEAD` differs from the recorded `last_head`, the commit succeeded and the markers are cleared; a failed commit leaves HEAD unchanged and the markers survive.
- **Approval check:** after a commit that moved HEAD under an approval marker, appends `{event: "commit", commit, approved_tree, committed_tree, matched}` to `.claude/approvals.jsonl`; a git hook present at approval time that changes the stage during the commit shows as `matched=false`.
- **Markers:** `.claude_superpowers_{hash}`, `.claude_has_plan_{hash}`, `.claude_plan_active_{hash}`, `.claude_c7_{hash}_{library}`, `.claude_changelog_synced_{hash}`, `.claude_last_head_{hash}`
- **Disable:** Remove `marker-tracker` from `manifest.json → activeHooks`

## marker-guard.sh
- **Event:** PreToolUse (Bash|Write|Edit|NotebookEdit)
- **Blocking:** Yes (exit 2)
- **Purpose:** Blocks any attempt to create or tamper with framework marker/state paths. Bash commands referencing a marker path (`superpowers`, `evaluated`, `plan_closed`, `plan_active`, `has_plan`, `skill_active`, `c7`, `c7_degraded`, `changelog_synced`, `session_start`, `last_head`, `stop_errors_hash`, `eval_log`) are blocked regardless of creation method (touch, echo redirect, cp, tee, dd, python, etc.). Write/Edit/NotebookEdit whose target path is under `/tmp/.claude_*` or `/private/tmp/.claude_*` is also blocked (R-07). Prevents Claude from forging markers or altering framework state (e.g. `last_head` to suppress post-commit resets, `session_start` to skew the stop audit, `stop_errors_hash` to silence stop blocks) to bypass enforcement.
- **Allowed:** the project's own `mark-plan-closed.sh` (since approval design B, `mark-evaluated.sh` is the user's own override and not sanctioned for the agent) — only as a lone, unchained invocation whose script path is plain (letters, digits, `_ . / + @ , : % -`; no `=`, `$` or `~`) and resolves, from the agent's working directory, to `<project>/.claude/framework/hooks/`. A script of the same name anywhere else does not count, and a command that merely contains the string (e.g. appended after `&&`, `;`, `|`, backticks, or `$(...)`) does not unlock the guard. Marker paths are matched in any letter case and after collapsing `//`, `/./` and `..`; if the guard itself fails, it blocks rather than allowing the call.
- **Disable:** Remove `marker-guard` from `manifest.json → activeHooks`

## config-guard.sh
- **Event:** PreToolUse (Bash|Write|Edit)
- **Blocking:** Yes (exit 2)
- **Purpose:** Protects framework infrastructure from modification. Blocks: (1) Write/Edit on `.claude/settings.json`, `.claude/settings.local.json`, `.claude/manifest.json`, `.claude/approvals.jsonl` (the approval audit), any `.claude/framework/*` path, and git's `.git/hooks/*`, `.git/config` and `.git/info/*` (a hook planted there runs inside `git commit`; an `.git/info/exclude` refusal points at `.gitignore`), also for Bash commands naming them; (2) Bash commands that modify framework config or hook files (sed, rm, chmod, echo redirect, etc.), including a copy or move whose destination is the bare `.claude/framework` or `.claude/framework/hooks` directory; (3) `CLAUDE_PROJECT_DIR=` environment variable assignments. Paths are matched in any letter case, since a case-insensitive disk (macOS's default) treats `.Claude/Settings.json` as the same file, and also with `//`, `/./` and `x/../` collapsed, so `.claude/framework/./hooks/` names the hooks folder. A command that merely mentions the bare `.claude` directory (a commit message, `du .claude`) is not blocked; one that names `.claude/framework` as a word is, as a copy destination would be. Quotes and backslashes inside a path (`.claude/'framework'/hooks/`) do not hide it. If the guard itself fails, it blocks rather than allowing the call; without a working jq it blocks every call and says to install jq. A path the shell assembles at run time — a glob (`.claude/framework/hook?/`), `$'\x2e'claude`, a substitution — is not inspected: the same residual as a string built in a variable, left to the OS sandbox (R-23). Git drivers configured earlier are the same residual: a `diff.external` or textconv driver runs on a plain `git diff`/`git log -p`, and a clean filter runs on `git add`, so a driver written beforehand can act during an allowed read or staging command (R-23).
- **Allowed:** a command on framework files in which EVERY simple command (split like the shell splits it, `command_only_reads` in `_helpers.sh`) only reads or stages: `cd` with one argument; `cat`, `head`, `tail`, `more`, `wc`, `file`, `stat`, `ls`, `grep`, `jq`, `echo`, `pwd`, `true`; `rg` without `--pre`; `sed -n` with a line-range print script (`1,15p`); `git diff/log/show/blame/status/ls-files/ls-tree/cat-file/rev-parse/reflog/describe/name-rev/grep/check-ignore` without `--output`, `--ext-diff`, `--textconv` or `-O`; and `git add` with no option but `--` (staging changes no file on disk, so the framework-written `.claude/manifest.json` can be staged for the commit the framework's own steps ask for, while writing it stays blocked). Chains of these (`;`, `&&`, `|`) pass; any substitution, backslash, comment, `$'...'`, open quote, assignment prefix, or redirection other than `2>&1`-style fd duplication and `/dev/null` refuses the whole line; the project's own `mark-plan-closed.sh`, as for marker-guard (`mark-evaluated.sh` is refused in every form); and a literal absolute path into a temp fixture outside the project (under `/tmp` or `/var/folders`, symlinks resolved), so a test can build its own `.claude/manifest.json`. The fixture exemption applies to a single command only (no `;`, `&`, `|` or newline, so no heredoc), because a chained command could first point the temp path at the project; write fixture content with the Write tool, which applies the same temp-fixture rule to its path. A path the command text cannot pin down — a variable, glob, `~`, `..`, backslash, `#`, substitution, or a quoted string that starts earlier (such as a quoted path containing a space) — counts as the project's.
- **Disable:** Remove `config-guard` from `manifest.json → activeHooks`

## session-end.sh
- **Event:** SessionEnd
- **Blocking:** No
- **Purpose:** Clears session-scoped workflow markers (superpowers, evaluated, has_plan, plan_active, plan_closed, c7_*, changelog_synced, stop-error dedup, session_start, last_head) at session end so stale markers can't pre-unlock enforcement zones in the next session. The eval audit log (`/tmp/.claude_eval_log_{hash}`) is intentionally preserved.
- **Disable:** Remove `session-end` from `manifest.json → activeHooks`

## compliance-reinforce.sh
- **Event:** UserPromptSubmit
- **Blocking:** No (JSON additionalContext)
- **Purpose:** Injects a one-line compliance frame on every user prompt (Layer 1 reinforcement). The session-start directive fades over task boundaries; this keeps the compliance frame present at each decision point.
- **Disable:** Remove `compliance-reinforce` from `manifest.json → activeHooks`

## enforce-plan-tracking.sh
- **Event:** PreToolUse (Write|Edit)
- **Zone:** Planning
- **Blocking:** Yes (exit 2)
- **Purpose:** Blocks source file edits until a plan task is marked in_progress via TaskUpdate
- **Skips:** Docs, config, test files; also skips if no `has_plan` marker exists (zone not armed)
- **Marker:** `/tmp/.claude_plan_active_{hash}` — created by marker-tracker.sh when TaskUpdate sets status to in_progress
- **Disable:** Remove `enforce-plan-tracking` from `manifest.json → activeHooks`

## enforce-context7.sh
- **Event:** PreToolUse (Write|Edit)
- **Zone:** Implementation
- **Blocking:** Yes (exit 2)
- **Purpose:** Scans code being written for import/require statements. Blocks if any third-party library hasn't been researched via Context7 MCP.
- **Skips:** Docs, config, test files; standard library imports (known-stdlib.txt); relative imports; degraded mode
- **Marker:** `/tmp/.claude_c7_{hash}_{library}` — one per researched library, created by marker-tracker.sh
- **Disable:** Remove `enforce-context7` from `manifest.json → activeHooks`

## verification-gate.sh
- **Event:** PreToolUse (Bash)
- **Zone:** Verification
- **Blocking:** Yes (exit 2)
- **Purpose:** Runs configurable verification gates before git commit. Gates are defined in `manifest.json → projectConfig._base.verificationGates[]`
- **Gate types:** `failOn: "exit_code"` (non-zero fails), `failOn: "stderr"` (pattern match), `failOn: "stdout"` (pattern match)
- **Built-in gates:** Linter-Gate, Visual Auditor (web-app), Type-Check Gate
- **Disable:** Remove `verification-gate` from `manifest.json → activeHooks` or set individual gates to `enabled: false`
