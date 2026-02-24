# Design: task-p5-2-docs-sync

## Approach
1. Update README:
   - Expand config section (whitelist/scope/update env vars).
   - Sync project tree with new libraries/scripts/tests.
2. Rewrite architecture doc to current state:
   - include safety and quality gates.
3. Update development/deployment/guidebook with current workflows:
   - test count, CI lanes, release command examples, update tips.
4. Add `Unreleased` changelog section for CI/Bash3.2 fixes.

## Validation
- sanity-read docs for broken references
- `./scripts/lint_shell.sh`
- `./tests/run.sh`
