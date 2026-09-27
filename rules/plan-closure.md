RULE: After completing work planned through the Superpowers workflow, document the outcome — what was planned vs. what was built, decisions made, and issues deferred.

## Plan Closure

### What This Rule Requires

When Superpowers-planned work is complete and committed, document the outcome before ending the session or moving to unrelated work:

1. **Planned vs. actual** — what was in the plan? What actually got built? Were any tasks dropped or added?
2. **Decisions made** — what choices came up during implementation that weren't in the original plan? Why were they made?
3. **Issues deferred** — what was discovered but not addressed? What should be revisited later?
4. **Next steps** — if this is part of a larger effort, what comes next?

### Where to Document

Save the closure summary to the context history file (configured in `manifest.json -> projectConfig -> contextHistoryFile`) or include it in the final commit message. The goal is that a future session can understand what happened without re-reading all the code.

### Marker

Once closure is documented, record it with the sanctioned script, run as a lone command from the project root:

```
bash .claude/framework/hooks/mark-plan-closed.sh "one-line closure summary"
bash .claude/framework/hooks/mark-plan-closed.sh --note path/to/closure-note.md
```

The summary is plain text, no shell punctuation. The script refuses an empty summary and a note that is missing or empty, then creates the plan closure marker, which stops the end-of-session closure advisory for the rest of the session. It is the only way to create the marker: `touch`, redirects and file tools aimed at it are blocked by `marker-guard.sh`. If closure is skipped for one of the reasons below, say so in the summary.

### When to Skip

- Trivial changes that didn't go through Superpowers planning
- The user explicitly says "skip closure"
- The work was straightforward with no deviations from the plan (note this in one line rather than skipping entirely)
