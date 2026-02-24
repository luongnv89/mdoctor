# Design: task-p1-3-preflight-safety-summary

## Approach
Implement lightweight preflight estimators:

1. In `mdoctor` (module force path)
   - Add module preflight helper functions.
   - For selected module, print target paths and rough estimate.
   - Include notes for command-based cleanup (docker prune, xcrun, brew cleanup) where exact size is unknown.

2. In `cleanup.sh` (full force path)
   - Add full-run preflight summary function with modules + key targets.
   - Print aggregated estimate before destructive steps begin.

3. Keep behavior unchanged in dry-run mode and non-force module invocations.

## Files Affected
- `mdoctor`
- `cleanup.sh`

## Decisions
- Use approximate estimates based on known target directory sizes and filtered find scans.
- Do not add prompt/confirmation gate in this task.

## Validation Plan
- `bash -n` for modified scripts.
- Validate module force summary with isolated HOME:
  - `mdoctor clean --force -m trash`
- Validate full force summary using isolated HOME + stub docker binary to avoid real prune side effects.
