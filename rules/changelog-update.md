RULE: Update the project changelog alongside every source file commit. Changelog file location is project-configured.

## Changelog Update

### What This Rule Requires
Every commit that includes source file changes must also update the changelog file. The specific file is configured in `manifest.json → projectConfig → changelogFile`.

### Before Editing
If the project has a sync command configured (`manifest.json → projectConfig → syncCommand`), run it first to merge any upstream changes.

### Enforcement
The `pre-commit-checks.sh` hook blocks `git commit` if source files are staged but the changelog file is not.
