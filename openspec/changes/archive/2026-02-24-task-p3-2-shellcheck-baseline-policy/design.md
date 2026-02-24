# Design: task-p3-2-shellcheck-baseline-policy

## Approach
1. Create `.shellcheckrc`:
   - enable external sources
   - ignore known non-actionable source include warning (`SC1091`) already tolerated in project

2. Create `scripts/lint_shell.sh`:
   - discover shell files (`*.sh` and `mdoctor`)
   - exclude meta dirs (`.specify`, `.claude`, `.codex`, `.opencode`, `openspec`)
   - run `shellcheck -S error` to enforce high-severity policy

3. Update `.github/workflows/ci.yml` shellcheck job:
   - install shellcheck
   - run `./scripts/lint_shell.sh`

4. Validate locally:
   - run lint script and confirm pass.

## Files Affected
- `.shellcheckrc` (new)
- `scripts/lint_shell.sh` (new)
- `.github/workflows/ci.yml`
- `docs/DEVELOPMENT.md`

## Decisions
- Policy enforces `-S error` for high-severity reliability first.
- Warning-level cleanup remains incremental in future tasks.

## Validation Plan
- `bash -n scripts/lint_shell.sh`
- `./scripts/lint_shell.sh`
