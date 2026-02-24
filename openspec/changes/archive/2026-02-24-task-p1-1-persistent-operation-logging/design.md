# Design: task-p1-1-persistent-operation-logging

## Approach
Enhance `lib/logging.sh` with persistent operation log subsystem:

1. File/config
   - `OPLOGFILE="${HOME}/.config/mdoctor/operations.log"`
   - ensure directory/file creation.

2. Session lifecycle
   - `op_session_start <name>`
   - `op_session_end <status>` with duration, action count, error count

3. Event APIs
   - `op_record <action> <target> [detail]`
   - `op_error <category> <target> [detail]`

4. Integration points
   - command runners (`run_cmd_args`, `run_cmd_legacy`) record dry-run/run/fail
   - safety layer emits operation records and categorized errors
   - cleanup entry points start/end operation sessions

## Files Affected
- `lib/logging.sh`
- `lib/safety.sh`
- `cleanup.sh`
- `mdoctor`

## Decisions
- Decision: append-only human-readable log lines (not JSON) for now.
- Rationale: minimal overhead and fast implementation.
- Tradeoff: machine parsing is possible but less structured than JSON.

## Validation Plan
- Run `mdoctor clean -m trash` and verify session + action lines in operations log.
- Run `mdoctor clean` (dry-run) and verify another session block.
- Validate scripts with `bash -n`.
