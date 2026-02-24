# Design: task-p0-1-safe-command-runner

## Approach
Add explicit command execution helpers in `lib/logging.sh`:

1. `run_cmd_args <cmd> [args...]`
   - Preferred API.
   - Executes command without `eval`.
   - Honors dry-run and logs full command representation.

2. `run_cmd_legacy <string>`
   - Temporary compatibility for existing callers.
   - Executes via `bash -c` with clear deprecation warning.
   - Used only until P0.3 migrates all modules.

3. `run_cmd` default behavior
   - Route to `run_cmd_args` when called with multiple args.
   - Route to `run_cmd_legacy` when passed a single string.

This enables immediate removal of `eval` while avoiding broad breakage in one change.

## Files Affected
- `lib/logging.sh`: add safe runner functions and deprecation behavior.
- `docs/ARCHITECTURE.md` or `docs/DEVELOPMENT.md`: note command runner contract (if needed).

## Decisions
- Decision: keep temporary legacy path for one phase.
- Rationale: avoid large cross-module breakage in a single task.
- Tradeoff: short-lived technical debt until P0.3 completes migration.

## Validation Plan
- Command checks:
  - `./mdoctor clean --help`
  - `./mdoctor clean` (dry-run)
  - `./mdoctor clean -m trash` (dry-run)
- Verify there is no `eval` usage in command runner path.
