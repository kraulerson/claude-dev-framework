RULE: Every bug fix MUST include a regression test that fails before the fix and passes after.

## Test Per Bug Fix

### What This Rule Requires
When fixing a bug, write a test FIRST that reproduces the bug (fails), then implement the fix (test passes). This ensures:
1. The bug is actually fixed (not just masked)
2. The bug cannot regress silently in the future

### Test Framework Selection
Use the project's native test framework. Check the manifest or project structure:
- Python: pytest
- JavaScript/TypeScript: jest, vitest, or mocha
- Swift: XCTest
- Kotlin/Java: JUnit + MockK
- Rust: cargo test
- Go: go test

### When This Rule Blocks
The stop-checklist hook checks all commits made during the session for bug fix patterns (fix/bug/patch/hotfix/repair/resolve) and blocks stopping if any lack a corresponding test file.
