RULE: Bump the project version before every commit that includes source file changes. Version file locations are project-configured.

## Version Bump

### What This Rule Requires
Every commit that includes source file changes (not doc-only commits) must also include a version bump. The specific files to update are configured in `manifest.json → projectConfig → versionFiles` (resolved per branch).

### Versioning Scheme
Use semantic versioning (MAJOR.MINOR.PATCH) unless the project specifies otherwise.

### Enforcement
The `pre-commit-checks.sh` hook blocks `git commit` if source files are staged but version files are not.
