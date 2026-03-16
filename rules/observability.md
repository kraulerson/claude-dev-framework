RULE: When adding features or user-facing flows, evaluate what monitoring, logging, or error reporting is needed. Never silently swallow errors.

## Observability

### What This Rule Requires
- Every caught exception should either be surfaced to the user OR logged for diagnostics — never silently swallowed
- When implementing billing, auth, or background scheduling: explicitly consider failure modes and how they will be detected in production
- New features should have appropriate error handling and logging

### Questions to Ask
For each new feature or flow:
1. What can go wrong?
2. How will I know if it goes wrong in production?
3. What does the user see when it fails?
