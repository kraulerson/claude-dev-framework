# Approval via a Pending Question (design B)

**Date:** 2026-10-05 (rev. 5)
**Status:** Confirmed by owner 2026-10-05 (design B, rev. 4 decisions, open questions answered as recommended), after three adversarial design reviews; rev. 5 adds the owner's keyboard checks and the interim-safety rules for projects whose Solo still writes v1
**Breaking:** Yes. `mark-evaluated.sh` stops being agent-runnable. Solo's sentinel writer must move to schema 2. A commit made under an approval must be a lone `git commit` of exactly the approved staged change. `.git/hooks/`, `.git/config` and `.git/info/` become protected, and setting a code-running git config key is refused.
**Scope:** new `hooks/record-approval.sh`; `_helpers.sh`, `enforce-evaluate.sh`, `marker-tracker.sh`, `stop-checklist.sh`, `config-guard.sh`, `marker-guard.sh`, `session-start.sh`, `session-end.sh`, `mark-evaluated.sh`, `scripts/_shared.sh`; docs; tests

---

## Problem

The evaluate-before-implement gate (`enforce-evaluate.sh`) refuses `git commit` until the marker `/tmp/.claude_evaluated_<hash>` exists. Today the agent creates that marker itself: once it believes the user approved, it runs `mark-evaluated.sh "<reason>"`, and config-guard and marker-guard allow that as a lone command. Approval is therefore self-certified. One marker also lets any commit through until HEAD moves.

The dogfood-2 run (rows 21, 23, 29, 30) showed the opposite failure as well. An honest agent ran the script in its habitual `cd … && … | tail` form and was refused, so the human had to type the marker command and the commit himself, every time.

The owner chose design B. The user answers a question the agent recorded, and a hook turns the user's own answer into an approval of one specific staged change.

## Evidence

### The dogfood round trip
Source: `~/dogfood-2026-10/transcript-2cd79720.jsonl`, 2026-10-03, interactive.

- The agent ran Solo's `escalate-to-user.sh`, which wrote `.claude/pending-approval.json` (schema "v1", below), and then stopped.
- The user replied `Karl: A1 — commit the nine named assessment files now, …` and `Karl: A1 — approved as written: one _get_json_str helper …`.
- The agent's `pending-approval.sh --resolve` plus `mark-evaluated.sh` chain was refused, and the human ran them.
- UserPromptSubmit fired 12 times: 11 typed prompts and one `<task-notification>` turn. The 8 "Stop hook feedback" turns did not fire it.

### Captures (rev. 2 and 3)
Run on 2026-10-05 with Claude Code 2.1.289 in a throwaway project under the scratchpad, using the `--model haiku` headless runs listed below. Each run used:
- passthrough hooks that recorded the hook's stdin plus the environment variables named in the table;
- a clean environment (`env -i`, so the capturing session's own variables did not leak in);
- `--setting-sources=project`.

| # | Question | Run | Result |
|---|---|---|---|
| C1 | Does an Agent-tool subagent's prompt fire UserPromptSubmit? | Main prompt asked for one general-purpose subagent with prompt `A1 SUBAGENT-PROMPT` | **No.** No UserPromptSubmit carried the subagent's prompt. The subagent's completion came back to the parent as a `<task-notification>` turn, which did fire UserPromptSubmit in the parent session (same `session_id`). Its `prompt` began `<task-notification>` and embedded the subagent's description (`Agent "A1 subagent task" finished`) and its full `<result>` text. Both are agent-controlled. |
| C2 | Does a task-notification turn fire it? | C1, and the dogfood transcript (background Bash) | **Yes**, in headless and interactive runs. `prompt` starts with `<task-notification>`. |
| C3 | Does a slash command fire it, and with what `prompt`? | `claude -p "/approvecap"`, where `.claude/commands/approvecap.md` has the body `A1 CAPTURE-COMMAND-BODY…` | **Yes, with `prompt` = `/approvecap`.** The literal command, not the expanded body. A user-typed `/skill` would arrive the same way. A skill the model invokes with the Skill tool is a tool call, not a prompt. |
| C4 | Peer / cross-session message | Owner, interactive, 2026-10-05: another session sent `A1` | **Fires UserPromptSubmit in the receiving session** with `prompt` = `<cross-session-message from="uds:/tmp/cc-socks/23797.sock" from-name="claude-dev-framework-10" from-mode="prompting">\nA1\n</cross-session-message>`. It starts with `<`, so rule 1 makes it neutral. |
| C5 | Do hooks inherit `CLAUDE_CODE_CHILD_SESSION` and `CLAUDE_CODE_SESSION_ATTENDED`? | Every run | Both are present in every hook. `CLAUDE_CODE_CHILD_SESSION=1` appears in **every** hook of a plain top-level `claude -p` session, so it marks "a process under Claude Code", not "a subagent", and is useless as a discriminator. `CLAUDE_CODE_SESSION_ATTENDED=0` in headless runs; it is `1` in the attended interactive session that launched this work. `CLAUDECODE=1` and `CLAUDE_CODE_SESSION_ID` (equal to the input's `session_id`) are present too. |
| C6 | Is a Stop hook's `systemMessage` shown? | Stop hook printed `{"systemMessage":"…"}` | `-p` text output: **not shown** (stdout held only the reply). stream-json: shown, as `{"type":"system","subtype":"informational","msg":"Stop says: …"}`. Interactive (owner, 2026-10-05): **shown** (`⎿ Stop says: CAPTURE-SYSMSG-FROM-STOP`). |
| C10 | Do `!` commands typed in Claude Code pass through hooks? | Owner, interactive: `!env \| grep -E '^CLAUDECODE\|^CLAUDE_CODE_SESSION_ATTENDED'` | **No hook fired**: no PreToolUse and no UserPromptSubmit record. Inside the command, `CLAUDECODE=1` and `CLAUDE_CODE_SESSION_ATTENDED=1`. So `mark-evaluated.sh` run via `!` refuses (`CLAUDECODE`); the override is for a separate terminal. Interactive hooks see `ATTENDED=1`. |
| C7 | Is a UserPromptSubmit `decision: "block"` reason shown? | Hook blocked prompts starting `BLOCKME` | **Yes, in both formats.** `-p` text stdout: `UserPromptSubmit operation blocked by hook:\n<reason>\n\nOriginal prompt: …`. stream-json: a `system/informational` message and the `result`. No model turn ran and no Stop fired. |
| C8 | Does headless `--resume` keep the session? | `claude -p --resume <id> "A1 — approved…"` | SessionStart `source: "resume"` with the same `session_id`; UserPromptSubmit carried the reply verbatim. |

| C9 | Can git's own hooks change what a checked commit contains? (git 2.54, scratch repo) | **Yes, both ways.** A `.git/hooks/pre-commit` that runs `git add b2` made the committed tree differ from the `git write-tree` taken just before the commit (`f749d97…` vs `22e3ce1…`). Config-defined hooks work too: `git config hook.x.event pre-commit` plus `git config hook.x.command 'git add b'` added `b` to the commit. These commands do not name `.git/config`. With `core.hooksPath=.husky`, `git rev-parse --git-path hooks` prints `.husky`, so the effective hooks directory can sit in the working tree. |

UserPromptSubmit input keys (2.1.289): `cwd, hook_event_name, permission_mode, prompt, prompt_id, session_id, transcript_path`, plus `scratchpad_dir` in the owner's interactive session (also on SessionStart and Stop; SessionStart also has `model`, Stop also has `effort` and `prompt_id`). `tests/fixtures/userpromptsubmit.json` uses this shape with sanitised paths.

### What exists today
- **Solo's writer.** `pending-approval.sh --offer` (also called by `escalate-to-user.sh`) writes v1 `{question, options: ["A1: …"], recommendation, offered_at}`. It writes atomically, refuses a second offer, and `--resolve` / `--clear` delete the file. The agent runs all of these.
- **Solo's reader.** `pre-commit-gate.sh` denies `git commit` and `gh pr create` while the file exists.
- **CDF's reader.** `stop-checklist.sh` exits 0 silently while the file exists.

## Decisions

### D1: sentinel schema 2

`.claude/pending-approval.json`:

```json
{
  "schema": 2,
  "question": "Commit the preferences fix?",
  "options": [
    {"id": "A1", "text": "Commit the staged fix and its test as one commit", "approves": "commit"},
    {"id": "A2", "text": "Hold — do not commit", "approves": "none"}
  ],
  "recommendation": "A1",
  "offered_at": "2026-10-05T12:00:00Z"
}
```

- **Option ids** must match `^[A-Za-z][0-9]{1,2}$` (A1 … Z99) and be unique case-insensitively. A sentinel with any other id cannot be answered with an approving pick: the hook refuses and says why.
  - Reason: an id that is an ordinary word (`yes`, `ok`, `go`) would turn free text into a pick.
- **`approves`** is `"commit"` or `"none"`; any other value means `"none"`. At least one option must be `"none"`.
- **What `"commit"` approves** is the staged change rendered to the user (D3), committed once as rendered. The option text is the user-facing description and is logged verbatim. It is not the binding.
- **Ignored fields.** Every other field, including any agent-written `picked`, `approved` or `answer`, is ignored.
- **Compatibility.**
  - The stop hook honours any sentinel, of any schema, by its existence (unchanged).
  - A pick on a v1 sentinel is logged and resolves it but grants nothing. v1 cannot tell "commit" from "hold" and has free-text ids.
  - Solo must write schema 2 (see Solo-side changes).

### D2: the agent records the question; that grants nothing

- The agent writes the sentinel with the Write tool, or with Solo's script, **after staging the change**.
- Writing, rewriting or deleting the file changes only what is asked. Approval is created only by `record-approval.sh`, inside a UserPromptSubmit event, from the user's prompt, against the staged state the hook itself rendered (D3).
- The path stays agent-writable.

### D3: `record-approval.sh` (UserPromptSubmit)

It acts only while `.claude/pending-approval.json` exists. Otherwise it exits 0 with no output.

**Which prompts count.**

1. **Harness turns.** A prompt whose trimmed text starts with `<` is ignored entirely: it neither picks nor invalidates. That covers `<task-notification>` turns (C1, C2), whose bodies carry agent-controlled subagent results and descriptions, `<cross-session-message …>` peer turns (C4), and marked pastes. A prompt that contains `<task-notification` or `<cross-session-message` anywhere is not read as an answer either, in case a later Claude Code version moves the wrapper. If it does not start with `<` (a user's reply that quotes such a tag), Claude is told it was not read as an answer, so it can ask for a plain reply; the render stays.
2. **Slash commands.** A prompt starting with `/` is neutral, like rule 1: it neither picks nor voids the render. The body of an agent-written `.claude/commands/*.md` never reaches `prompt` (C3), so command files need no protection for this design.
3. **Id-shaped replies.** A reply whose first token, after trimming trailing `.,:;!)` and dashes, matches an option id (case-insensitive) is a **pick candidate**.
   - `A1`, `a1.` and `A1 — approved` are candidates.
   - `Karl: A1`, `yes A1` and `go with A1` are not (Open question 1).

**Step 1: render and confirm.** It always takes two exchanges.
- The first pick candidate after the sentinel was written does **not** approve. The hook returns `decision: "block"`; its `reason` is shown to the user (C7, both headless formats) and not to Claude. The reason renders:
  - the question;
  - each option with its effect (`A1 — <text> [approves committing the staged change below]` / `[approves nothing]`);
  - the staged change: `git diff --cached --stat` and the `--name-status` list, from the hook's own git run;
  - "Reply with the option id again to confirm."
- At the same time the hook writes the render record `/tmp/.claude_approval_shown_<hash>` (JSON):
  - `session_id` and `prompt_id` from its input;
  - `sentinel_sha256`;
  - `head` (`git rev-parse HEAD`, or `none` before the first commit);
  - `tree`: the index tree from `git write-tree`, which writes only tree objects and changes no working file;
  - `hooks_digest`: sha256 over the name, mode and content of every file in the **effective** hooks directory (`git rev-parse --git-path hooks`, which honours `core.hooksPath`);
  - `config_digest`: sha256 of `git config --list --show-origin --show-scope`, covering every scope including global and system.
- **What the render also shows.** The **names** of the hooks that will run at commit: executable files in the effective hooks directory, and `hook.<name>` config entries. Names only: the digests carry the guarantee, and the render stays short.
- **`git write-tree` fails** (an unmerged index): no render record is written. The reason says the index has conflicts and must be resolved before approval.
- **Nothing staged.** If the index tree equals HEAD's tree, the render says nothing is staged. The render record is still written, so an option that approves nothing can be picked; an approving pick with nothing staged grants nothing and tells Claude to stage and ask again (implementation note: deviation from rev. 4, which wrote no record, because a "hold" answer must stay possible).
- **Why the render goes through the block path only:** the Stop `systemMessage` is shown interactively (C6) and in stream-json, but not in `-p` text. The block reason is the one display proven to reach the user in every mode, so it alone writes the render record (owner decision 6: always two exchanges).
- The render doubles as an explicit confirmation step: the user sees exactly what will be committed.

**Step 2: pick.** The next prompt that is not neutral (rules 1 and 2) is the only one that can pick. It picks only if **all** of these hold:
- It is a pick candidate.
- Its `session_id` equals the render record's.
- The sentinel's sha256 equals the render record's.
- HEAD, `git write-tree`, `hooks_digest` and `config_digest` equal the render record's.

If any of these fails:
- An id-shaped reply re-renders (a new block and a new record).
- Any other prompt deletes the render record and passes through. A later `A1` then starts at step 1 again (review item 6).

**On an approving pick:**
- Write the marker `/tmp/.claude_evaluated_<hash>` as JSON: `{session_id, head, tree, hooks_digest, config_digest, pick, question, option_text, sentinel_sha256, picked_at, attended}`. `attended` is `CLAUDE_CODE_SESSION_ATTENDED`, recorded but not required (Open question 5).
- Append the full record to `.claude/approvals.jsonl`, a new protected file (D7). Append the existing one-line form to `/tmp/.claude_eval_log_<hash>` (`<time> | pick A1 | <question>`, preserved across sessions). The full record lives only in the marker and `approvals.jsonl`.
- Delete the sentinel and the render record.
- Return `additionalContext`: "The user approved committing the staged change (tree <short>). Commit it with a lone `git commit -m …`; any change to the stage, HEAD, git hooks or git config voids the approval."

**On a non-approving pick:** log it, resolve the sentinel, no marker, and `additionalContext` says what was picked. An earlier approval no commit has used yet (a pick's or the override's) is withdrawn: the marker is removed, the record carries `withdrew_approval`, and the eval log says so (post-release fix, 2026-10-07: before it, an unused approval survived a later "hold" pick). It fails closed: a marker that cannot be removed is overwritten with a record carrying no approved state, and one that cannot be changed either blocks the prompt, so the turn stops with the question still open.

**On free text:** no marker, sentinel kept. `additionalContext` tells Claude "a question is pending; the user's reply was not an option id, so nothing was approved — ask them to reply with the id". Nothing is shown to the user beyond the agent's own reply.

**Session binding.**
- The render record carries `session_id`, and a pick must come from the same session (review item 2).
- Subagent prompts do not fire UserPromptSubmit (C1). Their completions arrive as `<task-notification>` turns, which rule 1 ignores, so a parent cannot approve itself through a subagent.
- `CLAUDE_CODE_CHILD_SESSION` is not used: it is `1` in every hook (C5).

**Fail direction.** Any internal error grants nothing and leaves the sentinel. The hook never blocks the user's prompt because of its own failure. It exits 0 with a `systemMessage` naming the failure **and** the same text as `additionalContext`. `systemMessage` is invisible in `-p` text (C6), so the model must relay the failure. A headless orchestrator treats "no approval recorded after the second `A1`" (the `additionalContext` says so) as a failure. Blocking on error would refuse every prompt while a sentinel exists, a lockout with no way out from inside the session.

**Registration.** `generate_settings_json` registers `record-approval.sh` on UserPromptSubmit whenever `enforce-evaluate` is active. `sync.sh` regenerates settings from `manifest.activeHooks` but never adds new profile hooks to old manifests, so tying the hook to `enforce-evaluate` reaches every existing project on its next sync with no manifest migration.

### D4: the commit must be the approved change

`enforce-evaluate.sh`, when **any** evaluation marker exists (a pick's or the human override's, D5), allows a commit only if all of these hold:

1. **It is a lone simple command:** one segment, with no `;`, `&&`, `|`, newline or substitution. This stops `git add evil && git commit` changing the stage after the check.
2. **It has exactly the shape `git commit <allowlisted options>`.**
   - The first word is `git` (bare name, any letter case).
   - There are no assignment words of any name (`GIT_*=`, `HOME=`, `XDG_CONFIG_HOME=`, …) and no `env`, `exec`, `command`, `nohup`, `time` or other prefix.
   - The `git` word carries no global options (`-c`, `--config-env`, `-C`, `--git-dir`, `--work-tree`, `--namespace`, …).
   - The next word is `commit`.

   One exact shape replaces an enumeration of dangerous forms. It guarantees that the hook's `rev-parse`, `write-tree` and `git config --list` run in the same effective environment as the commit. A `HOME=` or `XDG_CONFIG_HOME=` prefix would otherwise move the global config scope the digest read, and `GIT_INDEX_FILE=` would commit another index.
3. **`commit`'s options come from an allowlist** that only shapes the message or metadata:
   - `-m`/`--message`, `-F`/`--file` (each with its value);
   - `-s`/`--signoff`, `-q`/`--quiet`, `-v`/`--verbose`;
   - `--author=`, `--date=`, `--cleanup=`, `--trailer=`;
   - `-S…`/`--gpg-sign…`, `--no-gpg-sign`, `--no-edit`.

   Attached forms are parsed as one option: `-mmsg` is `-m` with value `msg`, and `--message=msg` is `--message`. A short cluster is refused unless every letter in it is allowed (`-sq` passes; `-am` is refused). Refused outright:
   - `-a`/`--all`, `-i`/`--include`, `-o`/`--only`, `-p`/`--patch`, `--interactive`;
   - `--amend`, `--fixup`, `--squash`, `--allow-empty`, `--pathspec-from-file`;
   - any pathspec (a non-option word that is not an allowed option's value);
   - any option not on the list.

   Each of these commits something other than the index the user saw, or rewrites history. `-n`/`--no-verify` stay refused as today.
4. **The state matches the marker.** `git rev-parse HEAD`, `git write-tree`, the hooks digest and the config digest all equal the marker's values.
   - Git's own hooks run inside `git commit` and can change what it commits (C9). The digests ensure the hooks and config that run are the ones present when the user approved. With item 2's exact shape, this pins the commit to the approved state.

A refusal names the failed check and says: "stage exactly the approved change, or ask again".

**After the commit.** `marker-tracker.sh` clears the marker when HEAD moves, as today. It also compares the new commit's tree (`git rev-parse HEAD^{tree}`) with the marker's `tree` and appends `matched=true|false` to `.claude/approvals.jsonl`. A hook that was present and visible at render time can still alter the stage during the commit (C9). Such drift is caught here, not prevented: a `matched=false` record is surfaced by `stop-checklist.sh` as an unfinished step: "Commit <sha> does not match the tree the user approved — tell the user." The step is shown once (the existing dedup).

**Code-running config, any time (not only under a marker).** The existing `core.hooksPath` refusal in `enforce-evaluate.sh` matches only `git … core.hooksPath`, in that order and anywhere in the text. That misses `GIT_CONFIG_PARAMETERS="'core.hooksPath=/tmp/h'" git commit` and the `GIT_CONFIG_KEY_0` form (review; to be confirmed red on current main). It also falsely blocks reads that mention the key.

**New rule.** Using the word split `git_commit_text` already has, keys are checked only in **config-setting positions**:
- the value of `-c` and of `--config-env=` (or the next word after `--config-env`) on a `git` word;
- `GIT_CONFIG_PARAMETERS=…` (every `key=` inside it) and `GIT_CONFIG_KEY_<n>=…`, as assignment words in any segment, including after `env` or `export`;
- the key argument of `git config` when it sets:
  - `git config [opts] KEY VALUE`;
  - `--add`, `--replace-all`, `--unset`, `--unset-all`;
  - `git config set|unset KEY …`;
  - `--rename-section`, `--remove-section`;
  - `git config --edit` / `-e` (an editor can set anything) is always refused.

A setting position is refused when its key (any letter case) is one of:
- **Hooks:** `core.hooksPath`, `hook.*`.
- **Programs git runs:**
  - `core.fsmonitor`, `core.sshCommand`, `core.askPass`, `core.editor`, `sequence.editor`;
  - `gpg.program`, `gpg.*.program`;
  - `filter.*.clean`, `filter.*.smudge`, `filter.*.process`;
  - `diff.external`, `diff.*.command`, `merge.*.driver`;
  - `credential.helper`.
- **Config inclusion:** `include.path`, `includeIf.*`.
- **Aliases:** `alias.*` when its value starts with `!` (a shell alias), or when the value is hidden (`--config-env`, `GIT_CONFIG_KEY_<n>`).

What still passes:
- **Reads:** `git config --get core.hooksPath`, `git config --list | grep alias.`, and `git config KEY` with no value.
- **Text that only mentions a key:** commit messages (`git commit -m "docs: explain includeIf.gitdir"`), `--grep=include.path`, `git grep -n core.fsmonitor`, and pathspecs (`git add docs/hook.push.event.md`, `git show HEAD -- src/hook.deploy.command.ts`).
- `-S` signing stays allowed. Its program is whatever `gpg.program` already is, and setting that key is refused.

**Not adopted.** A git `pre-commit` hook comparing `git write-tree` against the marker would cover `-a` and pathspecs exactly, but CDF does not own `.git/hooks` (Open question 2).

### D5: removing self-certification

- **Sanctioned scripts.** `is_sanctioned_mark_command` accepts only `mark-plan-closed.sh`. Every form of the agent running `mark-evaluated.sh` is refused by config-guard and marker-guard.
- **`mark-evaluated.sh`** remains the human's override, run in the user's own terminal (CLAUDE-GUIDE's "if the user says skip evaluation"). It refuses when `CLAUDECODE` is set: Claude Code sets it in the agent's Bash environment and in every hook (C5, and verified in the review). Since 2026-10-07 it also needs a terminal: it opens `/dev/tty`, shows a random six-digit code there and approves only when the same code is typed back. `CLAUDECODE` is one variable the agent can clear; the agent's Bash tool has no controlling terminal, so `/dev/tty` cannot be opened, and stdin is never read, so a plain run or a pipe cannot answer. It does not stop a pseudo-terminal driver (`expect`) that reads the code and types it back (review of the fix, 2026-10-07: a renamed copy driven that way produced a bound marker). The barrier for the agent is config-guard refusing the script by name (D8 row 17); a renamed copy is R-23. It records `head`, `tree`, `hooks_digest` and `config_digest` at the moment it runs, so the human stages first and then runs it, as with a pick. All four D4 checks apply to every marker, so provenance no longer decides what a marker allows. Its audit entry says `source=override`.
- **`enforce-evaluate.sh` block text.** "Stage the change, present the evaluation, record the question in `.claude/pending-approval.json` (schema 2: ids like A1/A2, at least one `"approves": "none"` option) and stop. The user approves by replying with the option id. The framework shows them the staged change and asks them to confirm. You cannot create the approval yourself."
- **Wording.** session-start's directive, marker-guard's message, `rules/evaluate-before-implement.md` and `docs/CLAUDE-GUIDE.md` drop "the sanctioned script mark-evaluated.sh" for the agent.
- **Interim safety while Solo still writes v1.** CDF must work on its own before Solo is updated.
  - The `enforce-evaluate.sh` block message gives the agent the exact schema-2 JSON shape and path. It says to stage first, write `.claude/pending-approval.json` with the Write tool, then stop. An agent in a project whose Solo writer is still v1 can therefore record a valid question itself.
  - A v1 (or otherwise invalid) sentinel still holds the stop: the agent may stop, as before. The stop hook shows the user (systemMessage, C6) that the question cannot be answered, with the schema-2 shape the agent must rewrite it in; the agent learns the same from `record-approval.sh`'s `additionalContext` when the user replies. (Implementation note: rev. 5 said the stop hook blocks once; it does not block, so the existing "existence = in flight, the agent may stop" contract holds.)
  - If the user replies to it with an id, `record-approval.sh` does not block. It passes the prompt to Claude with the same explanation in `additionalContext`, and tells the user in `systemMessage` that the agent must re-ask.
- **`mark-plan-closed.sh` stays agent-runnable.** It only silences an advisory and approves no irreversible action.
- **Migration.**
  - Sync copies the hooks and regenerates settings (D3).
  - A project on this version with an older Solo still writes v1 sentinels and cannot get commits approved, so CDF and Solo ship together.
  - A v1 sentinel in flight at upgrade still holds the stop.

### D6: headless, Solo and interactive use

- **Interactive.**
  1. The agent stages the change, writes the sentinel and stops.
  2. The user replies `A1`.
  3. The block reason shows the question and the staged change.
  4. The user replies `A1` again.
  5. The agent commits.
- **Headless.**
  - The orchestrator writes each user turn. It must answer with the id first, and twice: the first reply renders and blocks (C7: the reason is printed on stdout in text mode and as the `result` in stream-json); the second picks.
  - Both replies must reach **the same session**: `claude -p --resume <session-id> "A1"` (or `--continue`).
  - A fresh `claude -p "A1"` is a new session. Its `session_id` differs and `session-start` clears the render record on `startup`, so it can only render (review item 5; C8 confirms that `--resume` keeps the session id and SessionStart reports `source: "resume"`, which keeps the record).
  - Each `--resume` reply is its own process, so SessionEnd runs between the render and the pick. Until 2026-10-07 (dogfood-3 item 1) `session-end` deleted the render record, so a driver's second `A1` always re-rendered and could never pick; a user who closed Claude Code between the two replies hit the same wall. The record is bound to `session_id`, the sentinel hash, HEAD, the index tree and both digests, so it now survives SessionEnd, and `session-start` removes it only when it belongs to another session (on `startup`/`clear`; kept on `resume`/`compact`, and on a `startup` that reports the same `session_id`). Keeping it adds no path: only a pick in the same session, with nothing changed, can use it.
  - Solo's driver must therefore resume the asking session. The dogfood driver's `Karl: A1 …` must become `A1 — …`.
- **Whoever writes the user turn approves.** A program that writes user turns is the operator's decision. The audit record carries `attended` (0 headless, 1 interactive).
- **Free-text approval** grants nothing. The extra exchange is the price of not inferring consent; the lancache incident that created the sentinel was an agent reading an ambiguous reply as approval.

### D7: interactions and stored state

- **stop-checklist.**
  - A pending question remains a legitimate stop (unchanged: exit 0, no block).
  - It may add a `systemMessage` naming the pending question as a courtesy. It does **not** write the render record (review item 4).
- **Marker lifetime.** The evaluated marker is cleared by the next commit (marker-tracker), by a fresh session and at session end, as today, and is now also void the moment HEAD or the stage changes (D4). The render record is cleared on resolve, on any non-pick prompt, and when another session starts (`startup`/`clear` with a different `session_id`); it is kept across SessionEnd, resume and compact (dogfood-3 item 1). Concurrent sessions in one project clear each other's render on startup, which costs one more exchange and approves nothing.
- **Solo's `--resolve` / `--clear`** only delete the sentinel. That removes a hold, not an approval, so they need not be locked. Solo should take bypass-audit decisions from `.claude/approvals.jsonl`, not from the agent's `--decision` flag.
- **Protected state.**
  - `.claude/approvals.jsonl` joins config-guard's protected paths. Write/Edit and Bash writes are refused, `git add` is allowed, and an `Edit(/.claude/approvals.jsonl)` deny rule is added.
  - `approval_shown` joins marker-guard's marker-name list.
- **Protected git state (review round 2, item 1a).**
  - `.git/hooks/`, `.git/config` and `.git/info/` join config-guard's protected paths: Write/Edit/NotebookEdit, and Bash commands that name them. Matching ignores case and normalises the path, like the other protected paths. Matching `Edit(/.git/hooks/**)`, `Edit(/.git/config)` and `Edit(/.git/info/**)` deny rules are added.
  - Reads keep working through the read-only allowance (`cat .git/config`, `ls .git/hooks`).
  - Ordinary git commands that write `.git/config` without naming it (`git remote add`, `git push -u`, `git config user.email …`, `git branch --set-upstream-to`) are not seen by the text guard and keep working.
  - That is acceptable because of D4: a hook-capable key set that way is refused by name, and any config change after the render voids the approval through `config_digest`.
  - The protection's job is to stop hook files being planted outside an approval window, which the digests cannot see.
  - An effective hooks directory outside `.git` (`core.hooksPath=.husky`, set by the project) is not protected by path. The render lists its hooks, and the digest pins them during the window.
  - `.git/info/exclude` is inside a protected directory, so editing it is refused; the message says "use .gitignore".
  - **Temp fixtures.** The foreign-temp exemption (`all_protected_paths_foreign` / `path_is_foreign_temp`) is extended to the new `.git/` paths under the same rule: a literal absolute path into a system temp directory, outside the project, with symlinks resolved. Tests and agents can then still build throwaway repos with hooks, and the project's own `.git` stays protected.

### D8: threat model

| # | Agent attempt | Closed by |
|---|---|---|
| 1 | Sentinel with a pre-picked field | Ignored; a pick comes only from `prompt` |
| 2 | Word ids (`yes`, `ok`) so free text picks | Ids must match `^[A-Za-z][0-9]{1,2}$`; otherwise no approving pick |
| 3 | Only approving options, or mislabelled ones | ≥1 `"none"` option required; the hook's render shows each option's effect |
| 4 | Chat paraphrase differs from the file | The hook's block reason renders the file and the staged change; the agent's chat is not what the user confirms |
| 5 | Rewrite the sentinel after the render (e.g. from a background job) | Sentinel sha256 in the render record; a mismatch re-renders |
| 6 | Change the stage or HEAD after approval, or commit more than approved (`-a`, pathspec, `--amend`, `git add x && git commit`, `GIT_INDEX_FILE=`) | D4: HEAD and index tree bound at render and at pick, re-checked at commit; lone-command rule; option allowlist; no `GIT_*=` / `-c` in the commit segment |
| 6a | Make git's own hooks or programs alter the commit: plant `.git/hooks/pre-commit` or `post-commit`; set `hook.*`, `core.hooksPath`, `core.fsmonitor`, a filter, `gpg.program` or an editor; include a config file (C9) | Hook files under `.git/hooks/` and `.git/config` protected by path (D7). Code-running keys refused in every setting position (D4). Exact commit shape, so no environment shifts the config scope. Hooks and config digests pinned from render to commit. Hooks shown in the render. Post-commit `matched=false` surfaced by the stop hook. Residual: a hook present and visible at render time that alters the stage during the commit is detected, not prevented |
| 7 | Approve itself through a subagent | Subagent prompts fire no UserPromptSubmit (C1); its completion is a `<task-notification>` turn, ignored (rule 1); render and pick must come from the same `session_id` |
| 8 | Inject `A1` via tool output, a background task's description, or a subagent result | These reach `prompt` only inside `<task-notification>` turns (C1, C2), which are ignored |
| 9 | A slash command or skill whose body starts with `A1` | `prompt` is the literal `/name` (C3) and `/…` is never a pick |
| 10 | Pastes | Marked pastes start with `<` and are ignored; an unmarked paste is text the user chose to send |
| 11 | A peer (cross-session) message `A1` (the agent's env has `CLAUDE_CODE_MESSAGING_SOCKET`/`_TOKEN`) | **Closed.** A peer turn arrives as `<cross-session-message …>A1</cross-session-message>` (C4). It starts with `<`, so it neither picks nor voids, and a prompt containing `<cross-session-message` anywhere is treated the same |
| 12 | A pick meant for another question, or a stale sentinel | Two-step render/confirm in the same session; any other prompt in between voids the render; the render record does not survive `startup` |
| 13 | Create the marker or render record directly | marker-guard (`.claude_evaluated`, `.claude_approval_shown`), matched also with quotes and backslashes removed (post-release finding, 2026-10-07: on v4.4.0 `printf '<marker JSON>' > /tmp/.claude_eval""uated_<hash>` passed both guards, so after reading HEAD, the index tree and the digests one plain command wrote a valid approval), and the `Edit(//tmp/.claude_*)` deny rule; names built by brace expansion, a glob, `$'...'`, a variable, `$(…)` or an interpreter are R-23. That is the cheapest known residual: one line such as `python3 -c 'open("/tmp/.claude_"+"evaluated_<hash>","w").write(<JSON>)'` (or `perl -e`), with HEAD, the tree and the digests computed by reading, writes a marker enforce-evaluate accepts (reproduced end to end in the review, 2026-10-07). The quote-split check raises the bar little; the closure is the OS sandbox (R-23) |
| 14 | Edit the audit | `/tmp/.claude_eval_log_*` is already marker-guarded; `.claude/approvals.jsonl` is protected (D7) |
| 15 | Run `mark-evaluated.sh` | Allowance removed; config-guard refuses every copy by name (17); the script refuses under `CLAUDECODE` (set for the agent) and in a plain run without a terminal (D5), which a pseudo-terminal driver such as `expect` gets past, so a renamed copy is R-23. An override marker is bound like a pick's (D5) |
| 16 | Disable the hook or its registration | config-guard protects `.claude/framework/hooks/*` and `.claude/settings*.json` |
| 17 | Run another copy of a hook that writes approvals or markers, or feed it a made-up hook input (post-release finding, 2026-10-07: on v4.4.0 `CLAUDECODE= bash ~/.claude-dev-framework/hooks/mark-evaluated.sh "x"`, and `printf '<UserPromptSubmit JSON with prompt A1>' \| bash ~/.claude-dev-framework/hooks/record-approval.sh` run twice, each produced an approval that enforce-evaluate accepted; every guard returned 0, because only the project's `.claude/framework/hooks/` was protected) | config-guard refuses any command naming `mark-evaluated.sh`, `record-approval.sh`, `marker-tracker.sh`, `session-start.sh`, `session-end.sh`, `stop-checklist.sh` or a non-project `mark-plan-closed.sh`, in any folder and letter case and with quotes or backslashes removed, or naming `.claude-dev-framework/hooks`, unless every simple command only reads. `mark-evaluated.sh` also refuses a plain run without a terminal (D5), but an `expect`-driven renamed copy gets past that, so for both scripts the name match is the barrier. `record-approval.sh` has no such second layer: a real UserPromptSubmit and the agent's Bash share the user, the environment (`CLAUDECODE`, `CLAUDE_CODE_SESSION_ID`), the absent terminal and a piped stdin, and any variable the harness sets the agent can set, so no signal tells them apart. Residual (R-23): a copy whose name the shell assembles at run time (a glob such as `bash /tmp/clone/hooks/record-appr*.sh`, a variable, brace expansion), and a copy made with the Read and Write tools under another name. The same holds for a marker name the shell assembles (row 13): brace expansion and globs stay R-23 |
| 18 | Commit on an earlier, unused approval after the user picked "hold" | A non-approving pick removes the evaluation marker and logs the withdrawal (D3) |

## Files

**Add:**
- `hooks/record-approval.sh`
- `tests/test-record-approval.sh`
- `tests/fixtures/userpromptsubmit.json` (real captured shape)

**Change:**
- `hooks/_helpers.sh`:
  - sentinel read/validate (`pending_approval_read`), render (`pending_approval_render`, including the hooks list), id-pick parse (`pending_approval_pick`) and stage-state (`git_stage_state` → head, tree, hooks digest, config digest) helpers;
  - `is_sanctioned_mark_command` limited to `mark-plan-closed.sh`;
  - `.claude/approvals.jsonl`, `.git/hooks/`, `.git/config` and `.git/info/` added to `CONFIG_GUARD_PROTECTED_RE`;
  - a commit-argument parser for D4 built on `git_commit_text` (attached option forms, clusters);
  - a config-setting-position parser on `git_commit_text`'s word split, and the refused key list (D4);
  - the foreign-temp exemption extended to the `.git/` paths.
- `hooks/enforce-evaluate.sh`: D4 exact-shape and state checks for every marker; the setting-position refusal of code-running keys, replacing the order-dependent text match on `core.hooksPath`; new block text.
- `hooks/marker-tracker.sh`: post-commit tree comparison appended to `approvals.jsonl`.
- `hooks/stop-checklist.sh`: courtesy `systemMessage`; no render record; a `matched=false` record in `approvals.jsonl` since the session start becomes an unfinished step.
- `hooks/config-guard.sh`: message; new protected paths (via the helper RE, so Write/Edit/NotebookEdit and Bash both apply).
- `hooks/marker-guard.sh`: message; `approval_shown` marker name.
- `hooks/session-start.sh`: directive; clear the render record on startup/clear.
- `hooks/session-end.sh`: clear the render record.
- `hooks/mark-evaluated.sh`: human-only header; refuse under `CLAUDECODE`; marker records head, tree and both digests; `source=override` in the audit.
- `scripts/_shared.sh`: UserPromptSubmit registration tied to `enforce-evaluate`; deny rules `Edit(/.claude/approvals.jsonl)`, `Edit(/.git/hooks/**)`, `Edit(/.git/config)`, `Edit(/.git/info/**)`.
- `tests/tools/capture-hook-schemas.sh`: also capture UserPromptSubmit, and the `<task-notification>` and `/command` shapes.
- `rules/evaluate-before-implement.md`, `docs/HOOK_REFERENCE.md`, `docs/CLAUDE-GUIDE.md`, `docs/COMPLIANCE_ENGINEERING.md`.
- Tests: `test-config-guard.sh`, `test-marker-guard-v4.sh`, `test-enforce-evaluate.sh`, `test-marker-tracker.sh`, `test-stop-checklist-pending-approval.sh`, `test-session-start-v4.sh`, `test-install-matrix.sh`, `test-integration-workflow.sh`.

**Tests to write first (red).** All use the captured UserPromptSubmit shape (`cwd, hook_event_name, permission_mode, prompt, prompt_id, session_id, transcript_path`).

1. **Ids.** Word ids (`yes`, `ok`), ids like `A`, `A123` or `1A`, and duplicate ids: no approving pick.
2. **Render.** The first `A1` blocks; the reason renders the question, each effect, the staged files and the hooks that will run; the render record holds session, sentinel hash, HEAD, tree and both digests. With nothing staged, or with an unmerged index (`write-tree` fails), no record is written and the reason says why.
3. **Pick.** The second `A1` in the same session writes the marker with HEAD and tree, logs to both logs, and resolves the sentinel.
4. **Voiding.** A different `session_id`, sentinel edited after the render, a stage change, a HEAD change, a hooks-directory change, a `git config` change, or a non-pick prompt in between: no marker, and an id-shaped reply re-renders.
5. **Neutral turns.** `<task-notification>` (including one whose `<result>` is `A1`), `<pasted_content>` and `/approvecap` prompts: no pick, and the render record is not voided.
6. **Non-picks.** Free text, `Karl: A1` and `go with A1`: no marker, sentinel kept, `additionalContext` names the expected reply.
7. **v1, malformed, fail direction.** A v1 sentinel, malformed JSON, or jq missing: exit 0, no marker, the prompt is not blocked by an error, and the failure appears in both `systemMessage` and `additionalContext`.
8. **Commit checks** (enforce-evaluate under a marker):
   - allowed: lone `git commit -m x`, `-mx`, `--message=x`, `-sq -m x`, with matching state;
   - refused: `-am`, a pathspec, `--amend`, `--allow-empty`, `-C dir`, `-c k=v`, `--config-env`, `GIT_INDEX_FILE=… git commit`, `GIT_CONFIG_PARAMETERS=… git commit`, `env GIT_DIR=… git commit`, `git add f && git commit`, an unknown option;
   - refused on state: stage changed after the pick; a `.git/hooks/pre-commit` written after the render; `git config hook.x.command …` or `git remote add` run after the render (config digest);
   - the human override's marker gets the same checks (it records state too).
9. **Post-commit.** marker-tracker appends `matched=true`, or `false` when the committed tree differs; it is driven by a real `.git/hooks/pre-commit` that stages a file (C9). The stop hook then reports the mismatch once.
9a. **Code-running config, red on current main first.** With a marker present, `GIT_CONFIG_PARAMETERS="'core.hooksPath=/tmp/h'" git commit -m x` and the `GIT_CONFIG_COUNT/KEY_0/VALUE_0` form exit 0 on main (the review's finding, to reproduce red).
   - Refused after the fix, with or without a marker:
     - those two forms;
     - `git -c CORE.HOOKSPATH=x commit`;
     - `git config hook.x.command y`, `git config core.fsmonitor y`, `git config include.path f`;
     - `git config filter.x.clean c`, `git config gpg.program p`, `git config core.editor e`;
     - `git config alias.x '!sh'`, `git -c alias.x='!sh' x`;
     - `git config --edit`;
     - `export GIT_CONFIG_PARAMETERS="'core.fsmonitor=x'"; git status`.
   - **Allowed (the review's false blocks):**
     - `git config --get core.hooksPath`
     - `git log --grep=include.path`
     - `git commit -m "docs: explain includeIf.gitdir"` (without a marker)
     - `git add docs/hook.push.event.md`
     - `git grep -n core.fsmonitor`
     - `git show HEAD -- src/hook.deploy.command.ts`
     - also `git config alias.lg 'log --oneline'` and `git config user.email e`.
9c. **Exact commit shape under a marker.** Refused: `HOME=/tmp/h git commit -m x`, `XDG_CONFIG_HOME=/x git commit -m x`, `env git commit -m x`, `exec git commit -m x`, `command git commit -m x`, `/usr/bin/git commit -m x`, `git -c user.name=x commit -m x`. Allowed: `git commit -m x`, `GIT commit -m x`.
9b. **Protected git paths.**
   - Refused: Write/Edit to `.git/hooks/pre-commit`, `.git/config`, `.git/info/attributes` and `.git/info/exclude` (the message says to use `.gitignore`); Bash `cat > .git/hooks/pre-commit`, `cp x .git/hooks/post-commit` and `tee .git/config`.
   - Still pass: `cat .git/config`, `ls .git/hooks`, `git remote add o url`, `git config user.email e`.
   - Also pass: the same writes into a temp fixture repo (`$(mktemp -d)/r/.git/hooks/pre-commit`), through the extended foreign-temp exemption.
10. **Self-certification removed.** config-guard and marker-guard refuse every `mark-evaluated.sh` form; the script refuses under `CLAUDECODE=1`.
11. **Registration.** `generate_settings_json enforce-evaluate` registers the hook; without `enforce-evaluate` it does not.
12. **Integration.** Blocked commit → stage → sentinel → `A1` (render) → `A1` (pick) → commit passes → marker cleared.

Each test has a mutation it must catch:
- drop the `<` rule;
- id matched anywhere instead of start-anchored;
- word ids accepted;
- grant on the first `A1`;
- skip the session, sentinel-hash or tree check;
- allow `-a`;
- allow a chained commit;
- keep the mark-evaluated allowance.

## Solo-side changes

1. **`pending-approval.sh --offer` and `escalate-to-user.sh` write schema 2.**
   - Options become `{id, text, approves}`, with ids validated against `^[A-Za-z][0-9]{1,2}$`.
   - New `--approves <id>` flag (repeatable); at least one option must approve nothing.
   - Keep `recommendation` and `offered_at`.
   - `--validate` and `--status` read both schemas.
   - The offer step comes **after** staging; the docs say so.
2. **`--resolve` / `--clear` become abort or cleanup only.** The CDF hook resolves on the pick. Bypass-audit decisions come from `.claude/approvals.jsonl`.
3. **`pre-commit-gate.sh`.** The deny reason stops pointing at `--resolve`; it says the user answers with the option id.
4. **Docs.** `builders-guide` "Structured Decision Points", the CLAUDE.md template and the adoption guide:
   - stage, then ask;
   - the user replies with the id first, twice (render, confirm);
   - the agent then commits with a lone `git commit -m …`, with no `-a` and no pathspec.
5. **Headless driver.** Answer turns go to the same session with `claude -p --resume <id>` or `--continue`, never a fresh `-p`. The id goes first.
6. **Refresh.** Bring CDF at or above this release and Solo's schema-2 writer together; a mixed install cannot approve commits.
7. **Git hook installers.** These scripts write `.git/hooks/*`, and some write `.git/config` / `core.hooksPath`: `install-filesystem-gates.sh`, `install-contributor-hooks.sh`, `upgrade-project.sh`, `verify-install.sh` (fix functions) and `reconfigure-project.sh`.
   - After this change, config-guard refuses an agent command that **names** those paths. A script the agent runs (`bash scripts/upgrade-project.sh`) does not name them, so the text guard does not see its writes.
   - Decision: no sanctioned path. Hook installation is a human step, run in the user's own terminal, and Solo's docs say so.
   - If an agent runs an installer anyway, any open approval is voided by the hooks or config digest. Outside an approval window, the write is the R-23 class (a script writing what a command may not).
   - Agent-issued commands in Solo's docs and templates must not set a D4 code-running key (`core.hooksPath`, `hook.*`, `filter.*`, `core.editor`, …) through `git config`, `-c` or `GIT_CONFIG_*`. Those are refused in any setting position. From the user's own terminal nothing changes.
8. **Matched=false.** Solo's governance tooling should read `matched=false` records in `.claude/approvals.jsonl` as a violation (committed tree ≠ approved tree).

## Owner decisions (2026-10-05, all as recommended)

1. **Speaker label** (`Karl: A1`): no. The driver puts the id first.
2. **Exact-commit enforcement.**
   - (a) As specified: lone `git commit`, an option allowlist, HEAD, tree, hooks and config checked before the commit, and the committed tree compared after it.
   - (b) Additionally ask Solo to install a git `pre-commit` hook that compares `git write-tree` (the real to-be-committed tree, even for `-a` and pathspecs) with the marker. That would let `-a` and pathspecs be allowed when they produce the approved tree.

   Decision: (a) now, (b) as a Solo follow-up. (b) would also turn the "visible hook alters the stage during the commit" residual (threat 6a) from detected into prevented.
3. **Durable record** `.claude/approvals.jsonl`: yes.
4. **Human override** `mark-evaluated.sh`: kept, for the user's own separate terminal (C10).
5. **Require an attended session for picks**: no. `attended` is recorded. Threat 11 is closed by C4 regardless.
6. **Always two exchanges** (render, then confirm): yes.

## Owner-observed checks (done 2026-10-05)

The owner ran C4, C6 and C10 interactively with the harness in the Appendix (Claude Code 2.1.289). The results are in the capture table above.

## Not verified

- `git write-tree` cost on very large indexes. It is expected to be small (it reuses cached trees), but has not been measured.
- **The refused key list (D4) may not be complete.** It covers the config routes known to run code from git commands. A route missed here is still caught during the approval window by `config_digest`, and afterwards by the post-commit `matched` comparison.
- **The Bash tool's environment is assumed to equal the hook's** (no persistent `export` across Bash calls), so the exact-shape rule (D4.2) is enough to give the hook and the commit the same `HOME` and config scope. If a mechanism lets the agent's shell environment persist and differ (for example an env file Claude Code sources for the Bash tool), the digests could be read under a different scope. Check at implementation.
- The `core.hooksPath` bypass on current main through `GIT_CONFIG_PARAMETERS` / `GIT_CONFIG_KEY_0` was reported by the reviewer and is to be reproduced red at implementation; I did not rerun it.

## Appendix: capture harness

Used for C1–C8, and for the owner-observed checks. Pick a throwaway directory, `export CAP=<it>` (absolute path), and create the following.

`$CAP/rec.sh` (as run for this spec; the `BLOCKME` branch produced C7):

```bash
#!/bin/bash
# rec.sh EVENT — append hook stdin plus selected env to a capture file
in=$(cat)
jq -nc --arg ev "$1" --argjson in "$in" \
  --arg child "${CLAUDE_CODE_CHILD_SESSION-<unset>}" --arg att "${CLAUDE_CODE_SESSION_ATTENDED-<unset>}" \
  --arg cc "${CLAUDECODE-<unset>}" --arg sid "${CLAUDE_CODE_SESSION_ID-<unset>}" --arg sock "${CLAUDE_CODE_MESSAGING_SOCKET:+set}" \
  '{ev:$ev, env:{CHILD:$child, ATTENDED:$att, CLAUDECODE:$cc, SESSION_ID:$sid, MSG_SOCKET:$sock}, input:$in}' >> "$(dirname "$0")/capture.jsonl"
if [ "$1" = Stop ]; then echo '{"systemMessage":"CAPTURE-SYSMSG-FROM-STOP"}'; fi
if [ "$1" = UserPromptSubmit ]; then
  case "$(jq -r .prompt <<< "$in")" in BLOCKME*) echo '{"decision":"block","reason":"CAPTURE-BLOCK-REASON pending question: A1 approves the next commit"}'; exit 0 ;; esac
  echo '{"systemMessage":"CAPTURE-SYSMSG-FROM-UPS"}'
fi
exit 0
```

`$CAP/proj` is a fresh `git init`. `$CAP/proj/.claude/settings.json` (expand `$CAP` when writing it):

```json
{ "hooks": {
  "UserPromptSubmit": [ { "hooks": [ { "type": "command", "command": "bash $CAP/rec.sh UserPromptSubmit" } ] } ],
  "Stop": [ { "hooks": [ { "type": "command", "command": "bash $CAP/rec.sh Stop" } ] } ],
  "SubagentStop": [ { "hooks": [ { "type": "command", "command": "bash $CAP/rec.sh SubagentStop" } ] } ],
  "SessionStart": [ { "hooks": [ { "type": "command", "command": "bash $CAP/rec.sh SessionStart" } ] } ]
} }
```

The headless runs used a clean environment, so the capturing session's own variables did not leak in: `env -i HOME="$HOME" PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" USER="$USER" TERM=dumb claude -p "<prompt>" --model haiku --setting-sources=project --output-format=<text|stream-json> [--verbose] --permission-mode=bypassPermissions < /dev/null`, run from `$CAP/proj`. The slash-command check used `$CAP/proj/.claude/commands/approvecap.md`, with the body `A1 CAPTURE-COMMAND-BODY. Reply with just: ok`.
