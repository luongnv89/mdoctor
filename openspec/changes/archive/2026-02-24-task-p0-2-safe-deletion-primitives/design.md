# Design: task-p0-2-safe-deletion-primitives

## Approach
Create `lib/safety.sh` containing centralized primitives:

1. `validate_deletion_path <path>`
   - Enforce absolute paths.
   - Reject traversal components and control chars.
   - Reject critical system and high-risk roots.

2. `safe_remove <path> [--allow-symlink]`
   - Validate path before deletion.
   - Honor dry-run mode.
   - Return specific non-zero codes on validation or deletion failure.

3. `safe_remove_children <dir>`
   - Delete directory contents (not the directory root) via `safe_remove`.

4. `safe_find_delete <base_dir> <find-predicates...>`
   - Find candidate paths within base dir and remove via `safe_remove`.
   - Avoid inline `find ... -exec rm -rf` patterns in future module migration.

## Files Affected
- `lib/safety.sh`: new safety primitive library.
- `cleanup.sh`: source `lib/safety.sh` so cleanup modules can consume primitives.

## Decisions
- Decision: use denylist-based protected path policy now.
- Rationale: simpler initial rollout, lower chance of accidental broad breakage.
- Tradeoff: some edge cases may require iterative allowlist tuning later.

## Validation Plan
- Syntax checks:
  - `bash -n lib/safety.sh`
- Runtime checks (in temp dir):
  - `validate_deletion_path "/"` fails.
  - `safe_remove` keeps file in dry-run.
  - `safe_remove` deletes file in force mode.
  - `safe_remove_children` removes only children.
