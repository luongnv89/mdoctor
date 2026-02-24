# Design: task-p4-1-update-command

## Approach
1. Add `cmd_update` in `mdoctor`:
   - options: `--check`, `--channel <stable>`, `--debug`, `--help`
   - validate running inside git checkout (`$MDOCTOR_DIR/.git`)
   - fetch remote + compare `HEAD` vs `origin/main`
   - check mode prints status only
   - update mode runs `git pull --ff-only origin main`
   - print before/after commit and resulting version

2. Keep channels explicit:
   - `stable` only for now
   - reject unsupported channels with actionable message

3. Update docs/help:
   - `mdoctor` top usage comments + `cmd_help`
   - README command table and examples
   - docs/DEPLOYMENT update section

## Files Affected
- `mdoctor`
- `README.md`
- `docs/DEPLOYMENT.md`

## Validation Plan
- `bash -n mdoctor`
- `./mdoctor update --help`
- `./mdoctor update --check`
