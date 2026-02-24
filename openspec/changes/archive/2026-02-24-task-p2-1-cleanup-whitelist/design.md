# Design: task-p2-1-cleanup-whitelist

## Approach
Implement whitelist in `lib/safety.sh`:

1. Config
   - `MDOCTOR_CLEANUP_WHITELIST_FILE` (env override)
   - default path: `~/.config/mdoctor/cleanup_whitelist`
   - auto-create with comments/examples

2. Load + match
   - Load once per process.
   - Support exact path and subtree protection:
     - entry `/a/b` protects `/a/b` and `/a/b/...`
     - entry `/a/b/*` protects descendants of `/a/b`
     - `~` expansion to `$HOME`

3. Enforcement
   - In `safe_remove`, after validation and before delete:
     - if whitelisted: log skip + op_record, return success.

4. UX
   - Add help line in `mdoctor clean --help` with whitelist file location.

## Files Affected
- `lib/safety.sh`
- `mdoctor`

## Validation Plan
- Syntax checks for modified scripts.
- Isolated HOME test:
  - create `~/.Trash/protect.txt`
  - whitelist `~/.Trash`
  - run `mdoctor clean --force -m trash`
  - verify `protect.txt` remains.
- Create non-whitelisted file and verify it gets cleaned.
