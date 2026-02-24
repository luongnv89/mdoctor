# Design: task-p0-4-destructive-error-taxonomy

## Approach
Enhance `lib/safety.sh` with:

1. Standardized error constants and backward-compatible aliases.
2. Helper functions:
   - `safety_error_name <code>`
   - `safety_error_hint <code> [path]`
   - `_safety_error <code> <path> <detail>`
3. `safe_remove` error mapping from `rm` stderr:
   - `Permission denied` → permission category
   - `Read-only file system` / `Operation not permitted` → SIP/readonly category
   - fallback → runtime failure
4. `safe_find_delete` improved runtime error handling for `find` command execution.

## Files Affected
- `lib/safety.sh`

## Decisions
- Decision: include backward-compatible aliases for old constant names.
- Rationale: avoid breaking any external callers.
- Tradeoff: temporary duplication in constants.

## Validation Plan
- Syntax: `bash -n lib/safety.sh`
- Runtime taxonomy checks via temp paths:
  - invalid/relative path
  - protected path `/`
  - symlink blocked
  - runtime failure from malformed find predicate
- Existing cleanup dry-run command still works.
