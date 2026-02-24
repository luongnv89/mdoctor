# Design: task-p1-2-debug-mode-structured-diagnostics

## Approach
1. Add debug primitives in `lib/logging.sh`:
   - `debug_enabled`
   - `debug_log`
2. Instrument command runners (`run_cmd_args`, `run_cmd_legacy`) with debug lifecycle logs.
3. Extend CLI option parsing in `mdoctor`:
   - `check`: add `--debug`, propagate to module/full doctor path.
   - `clean`: add `--debug`, propagate to module/full cleanup path.
   - `fix`: add `--debug`, include debug traces around fix execution.
4. Extend `cleanup.sh` parser to support `--debug` and emit startup/shutdown debug context.
5. Add lightweight debug traces in `doctor.sh` phases and summary.

## Files Affected
- `lib/logging.sh`
- `cleanup.sh`
- `doctor.sh`
- `mdoctor`

## Decisions
- Keep debug output as human-readable line logs (`[DEBUG] ...`) for minimal complexity.
- Avoid adding extra dependencies for debug formatting.

## Validation Plan
- `bash -n` on modified scripts.
- Run:
  - `mdoctor check --debug -m battery`
  - `mdoctor clean --debug -m trash`
  - `mdoctor clean --debug`
  - `mdoctor fix --debug` (usage/error path)
- Confirm `[DEBUG]` appears in logs.
