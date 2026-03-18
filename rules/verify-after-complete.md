RULE: After completing a planned feature or significant change, guide the user through verifying the work matches acceptance criteria before moving to the next task.

## Verify After Complete

### What This Rule Requires

When a planned feature or significant change is finished, walk the user through verification before proceeding:

1. Review the acceptance criteria from the plan
2. For each AC item, ask the user to confirm it works or describe what's wrong
3. If issues are found, create a fix plan before moving on
4. Only mark the work as complete after all AC items pass

### Why This Matters

Automated tests verify that code is correct. This rule verifies that the *feature* is correct — that what was built matches what was intended. The gap between "tests pass" and "this actually works as the user expects" is where subtle issues hide.

### How It Relates to Other Rules

- **plan-before-code** defines acceptance criteria before implementation
- **test-strategy** drives risk-proportional automated testing
- **verify-after-complete** (this rule) closes the loop with human verification

### When to Trigger

- After completing all tasks in a Superpowers-planned implementation
- After a significant feature is committed and tests pass
- Before starting the next unrelated task in the same session

### When to Skip

- Trivial changes (typo fixes, config updates, version bumps)
- The user explicitly says "skip verification"
- Changes where the user has already tested interactively during development
