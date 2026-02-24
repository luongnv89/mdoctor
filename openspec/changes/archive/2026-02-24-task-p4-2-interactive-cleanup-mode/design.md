# Design: task-p4-2-interactive-cleanup-mode

## Approach
1. Extend `cmd_clean` parser with `--interactive|-i`.
2. Add in-command helper flow:
   - module registry array
   - descriptions for prompt list
   - selection parser (comma-separated numbers or `all`)
   - dedup selected modules
3. Reuse existing single-module execution path for each selected module to preserve safety/logging/force behavior.
4. Add regression test:
   - dry-run interactive does not delete
   - force interactive deletes
   - invalid selection returns non-zero
5. Update README cleanup usage examples.

## Files Affected
- `mdoctor`
- `tests/test_interactive_cleanup.sh`
- `tests/test_command_parsing.sh`
- `README.md`

## Validation Plan
- `bash -n mdoctor tests/test_interactive_cleanup.sh`
- `./scripts/lint_shell.sh`
- `./tests/run.sh`
