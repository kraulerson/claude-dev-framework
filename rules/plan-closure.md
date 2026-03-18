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

The plan closure marker is created automatically by the framework when closure is documented. Do not create it manually.

### When to Skip

- Trivial changes that didn't go through Superpowers planning
- The user explicitly says "skip closure"
- The work was straightforward with no deviations from the plan (note this in one line rather than skipping entirely)
