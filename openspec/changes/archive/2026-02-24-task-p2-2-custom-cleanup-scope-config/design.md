# Design: task-p2-2-custom-cleanup-scope-config

## Approach
Create `lib/cleanup_scope.sh`:

1. Config path
   - `MDOCTOR_CLEANUP_SCOPE_FILE` default `~/.config/mdoctor/cleanup_scope.conf`
2. Config format (line-based)
   - `INCLUDE_PATH=<abs-or-~path>`
   - `EXCLUDE_GLOB=<shell-glob>`
3. Helpers
   - `ensure_cleanup_scope_file`
   - `load_cleanup_scope`
   - `cleanup_scope_get_search_dirs` (returns includes or defaults)
   - `cleanup_scope_is_excluded <path>`
4. Integration
   - source `lib/cleanup_scope.sh` in clean runtimes
   - update `cleanups/dev_caches.sh` stale node_modules search to use scope helpers

## Files Affected
- `lib/cleanup_scope.sh` (new)
- `cleanup.sh`
- `mdoctor`
- `cleanups/dev_caches.sh`

## Validation Plan
- syntax checks for modified scripts
- isolated-home tests:
  - include path scan works
  - excluded path is skipped
  - non-excluded stale node_modules removed
  - scope file auto-creates
