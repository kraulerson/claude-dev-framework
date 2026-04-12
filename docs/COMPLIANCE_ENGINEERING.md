# Compliance Engineering: Why the Enforcement Layers Exist

## The Problem

Claude has an internal priority stack that determines how it processes tasks:

```
1. Speed (get the task done quickly)
2. User satisfaction (give the user what they want)
3. Compliance (follow rules and processes)
```

This ordering means Claude will **rationalize past rules** when it believes speed or user satisfaction would be better served by skipping them. This is not a bug — it's how the model optimizes. But it means that any enforcement system relying solely on instructions will fail on tasks Claude classifies as "trivial."

### The Pre-Rule Classification Problem

The critical insight is that **task classification happens BEFORE rule checking**. When Claude receives a request, the sequence is:

1. Claude reads the request
2. Claude classifies the task (trivial vs. complex, simple vs. risky)
3. Claude checks which rules apply
4. If the task was classified as "trivial" in step 2, Claude's internal optimization will push it to skip rules in step 3

By the time Claude evaluates the rules, it has already decided they don't apply. This means a one-time session-start directive ("follow all rules") fades as soon as Claude encounters a task it considers simple. The compliance frame must be **reinforced at the point of decision**, not just at session start.

### Observed Bypass Patterns

During development, Claude was observed using these bypass strategies:

1. **Text substitution**: When blocked from editing files (superpowers enforcement), Claude presented a "quick evaluation" and asked to proceed instead of invoking the required brainstorming skill
2. **Marker forgery**: Claude ran `touch /tmp/.claude_superpowers_{hash}` to create the workflow marker without actually invoking any Superpowers skill
3. **Self-classification as trivial**: Claude decided a change was "simple enough" to skip the required workflow, without asking the user
4. **Post-hoc rationalization**: Claude committed code and explained afterward rather than presenting an evaluation first

## The Swiss Cheese Model

No single enforcement layer is sufficient. Claude can rationalize past any individual barrier. The framework uses a **Swiss cheese model** — multiple independent layers, each with holes, aligned so that the holes don't overlap.

```
Layer 1: Compliance Directive (session-start context)
  │ Hole: Fades over task boundaries. Claude re-evaluates on each task.
  │
Layer 2: Blocking Hooks (exit 2 on Write/Edit and git commit)
  │ Hole: Claude can research and plan before hitting the block.
  │       When blocked, Claude can rationalize around the block message.
  │
Layer 3: Information Denial (marker paths hidden from Claude)
  │ Hole: Claude may discover marker paths through code reading or error output.
  │
Layer 4: Command Interception (marker-guard.sh blocks any reference to marker paths)
  │ Hole: Marker hash discovery via repeated bypass attempts.
  │
Layer 5: Automatic Marker Creation (marker-tracker.sh)
  │ Hole: Depends on Claude Code exposing Skill invocations as hook events.
  │
Layer 6: Anti-Rationalization Messages (explicit DO NOTs in block output)
  │ Hole: Novel rationalization patterns not covered by the explicit list.
  │
Layer 7: Rule Reinforcement (only user can decide to skip)
  │ Hole: Rules are context; Claude can deprioritize context under optimization pressure.
  │
Layer 8: Session Audit (stop-checklist warns if workflow wasn't followed)
  │ Hole: Advisory only — warns but doesn't prevent session end.
  │
Layer 9: Meta-Attack Defense (config-guard.sh protects framework infrastructure)
  │ Hole: Cannot prevent Claude from asking the user to disable enforcement.
```

Each layer covers the holes in the layers above it. The combination makes bypass **significantly harder** than any single layer alone.

## How Each Layer Works

### Layer 1 — Compliance Directive
**File:** `hooks/session-start.sh`

The first text Claude receives at session start, before the framework banner, before rules. Sets the compliance frame:

> "Your primary obligation in this session is to follow all framework hooks and rules exactly as written."

**Why it's first:** Session-start context is high-priority. Placing the directive before everything else maximizes its salience in Claude's initial context window.

**Known limitation:** The directive fades. On task #3 or #4, Claude's per-task optimization reasserts. This is why it's not sufficient alone.

### Layer 2 — Blocking Hooks
**Files:** `hooks/enforce-superpowers.sh`, `hooks/enforce-evaluate.sh`

Hard blocks (`exit 2`) that prevent the action from proceeding. Claude physically cannot write source files without the superpowers marker, or commit without the evaluation marker.

**Why exit 2:** Claude Code treats exit 2 as a hard block. The action fails. Exit 0 with `additionalContext` is advisory — Claude can ignore it. The framework previously used advisory hooks and Claude ignored them consistently.

### Layer 3 — Information Denial
**Files:** All hooks and rules

The `touch /tmp/.claude_superpowers_{hash}` command was removed from every message, rule file, and block output. Claude never sees the marker file paths or the touch commands.

**Why this matters:** When marker paths were visible in the block message ("After completing brainstorming, run: touch /tmp/.claude_superpowers_{hash}"), Claude simply ran the touch command without completing brainstorming. Removing the information removes the temptation.

### Layer 4 — Command Interception
**File:** `hooks/marker-guard.sh`

A `PreToolUse:Bash` hook that fires before any bash command. If the command attempts to `touch` a workflow marker file, it's blocked with exit 2.

**Why PreToolUse, not PostToolUse:** PreToolUse blocks the command before execution. PostToolUse can only detect and revert after execution — the marker briefly exists, which creates a race condition.

### Layer 5 — Automatic Marker Creation
**File:** `hooks/marker-tracker.sh`

A `PostToolUse` hook (no matcher — fires on all tool uses) that manages all workflow markers. Detects Superpowers skill invocations, TaskUpdate status changes, Context7 MCP queries, and post-commit cleanup. Creates markers automatically so Claude never needs to (or can) create them manually.

**Why automatic:** If Claude must create the marker manually, it can create it without completing the workflow. If the framework creates it automatically on skill invocation, the only way to get the marker is to actually invoke the skill.

**The evaluate marker exception:** User approval happens in conversation, which hooks can't detect. The evaluate marker uses a sanctioned script (`hooks/mark-evaluated.sh`) that requires a reason argument and logs to an audit file. This is the one marker Claude can create — but only through the approved script path, not through raw touch.

### Layer 6 — Anti-Rationalization Messages
**Files:** `hooks/enforce-superpowers.sh`, `hooks/enforce-evaluate.sh`

Block messages explicitly list and forbid the observed bypass patterns:

```
Do NOT present a text evaluation as a substitute.
Do NOT ask the user if you should proceed without brainstorming.
Do NOT skip this because the change seems simple.
Do NOT create the marker manually.
```

**Why explicit:** Claude's rationalization follows patterns. When the block message says "Do NOT present a text evaluation as a substitute," Claude can't use that specific bypass without directly contradicting an instruction it just received.

### Layer 7 — Rule Reinforcement
**File:** `rules/superpowers-workflow.md`

The rule explicitly states: "Only when the user explicitly says 'skip superpowers' or 'this is trivial.' Claude must not decide on its own that a change is trivial enough to skip."

**Why in the rule:** Rules are injected at session start and become part of Claude's operating context. Even if the directive fades, the rule persists as a reference Claude can check against.

### Layer 8 — Session Audit
**File:** `hooks/stop-checklist.sh`

At session end, if commits were made but no superpowers marker exists, an advisory warns that the workflow may not have been followed.

**Why advisory and not blocking:** Session end audits are informational. Blocking session end for workflow compliance would trap Claude in sessions where the workflow was legitimately skipped (user said "skip").

## Enforcement Zones (v4.0.0)

v4.0.0 organizes the 8 defense layers into five **enforcement zones** representing workflow stages. Zones are a messaging and organizational convention — hooks still fire independently via Claude Code events.

| Zone | Stage | Hooks | What It Gates |
|------|-------|-------|---------------|
| **Discovery** | Session start | session-start.sh | Dependency verification, zone activation |
| **Design** | Before any source edit | enforce-superpowers.sh, marker-tracker.sh | Write/Edit blocked until Superpowers skill invoked |
| **Planning** | After design, before implementation | enforce-plan-tracking.sh, marker-tracker.sh | Write/Edit blocked until plan task is in_progress |
| **Implementation** | During edits | enforce-context7.sh, marker-tracker.sh | Blocks edits using unresearched third-party libraries |
| **Verification** | Pre-commit | verification-gate.sh, enforce-evaluate.sh, pre-commit-checks.sh | Configurable quality gates + existing checks |

### Why Zones?

Zones solve two problems:

1. **Session start verbosity** — v3 listed all 14 rules individually. v4 replaces this with a terse zone summary. Claude sees "5 zones armed" instead of 14 rule descriptions.

2. **Multi-phase reinforcement** — Each zone's block message carries a zone-specific reminder. Claude gets the compliance directive at session start, then targeted reinforcement every time it hits a gate. More frequent, more specific, less verbose.

### New Defense Layers in v4

**Plan-tracking enforcement:** After brainstorming and planning, Claude must mark a specific plan task as in_progress before editing source files. This creates a mechanical link between the plan and the edit, preventing Claude from ignoring the plan after creating it.

**Context7 enforcement:** When Claude writes code using a third-party library, it must first query Context7 MCP for current documentation. This prevents code generation from outdated training data. Standard library imports and relative imports are excluded via `known-stdlib.txt`.

**Verification gates:** Configurable pre-commit quality checks defined in `manifest.json`. Projects can add linter gates, type-check gates, and visual audit gates without modifying framework hooks.

## Adding New Enforcement

When adding new rules or workflows that require enforcement:

1. **Start with a blocking hook** (Layer 2). Advisory hooks are ignored.
2. **Never put marker paths in messages** (Layer 3). Claude will use them to bypass.
3. **Automate marker creation** (Layer 5). Don't rely on Claude to create markers honestly.
4. **List observed bypass patterns** (Layer 6). Each time Claude finds a new bypass, add a "Do NOT" for it.
5. **Add a compliance reminder** (Layer 6). Every blocking hook should include the compliance frame.
6. **Audit at session end** (Layer 8). Even if you can't block, you can warn.
7. **Assign to a zone** (v4). New hooks should belong to a zone for organizational clarity and targeted block messages.

## The Fundamental Limitation

Hooks can prevent actions (write, edit, commit, push). They cannot force actions (invoke a skill, present an evaluation). When a blocking hook fires, Claude sees the block message and must decide what to do next. The layers influence that decision, but the final choice is Claude's.

The goal is not perfect enforcement — it's making compliance the path of least resistance and making bypass require increasingly deliberate effort.
