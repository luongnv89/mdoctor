# Contributing to mdoctor

Thanks for your interest in contributing to mdoctor! This guide will help you get started.

## How to Contribute

1. **Fork** the repository
2. **Create** a feature branch from `main` (`feat/your-feature`)
3. **Make** your changes
4. **Test** your changes on macOS
5. **Submit** a pull request

## Development Setup

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/mdoctor.git
cd mdoctor

# Create a feature branch
git checkout -b feat/my-feature

# Make the CLI available locally
chmod +x mdoctor
./mdoctor help
```

No build step or dependencies required -- mdoctor is pure Bash.

## Pre-commit Hooks

Install the hooks once per checkout so trailing whitespace, YAML,
private keys, ShellCheck (`-S warning`) and `bash -n` are checked
automatically (CI runs the same hooks via `pre-commit run --all-files`):

```bash
pip install pre-commit  # or: brew install pre-commit
pre-commit install
```

Requires Python >= 3.9: `pre-commit-hooks` v6.0.0 builds each hook repo
in its own virtualenv from the interpreter it finds, so Python 3.8 or
older fails at environment-build time. Verify with
`python3 -c 'import sys; assert sys.version_info >= (3,9)'` (CI asserts
the same floor on every lane that runs the hooks).

Executable bits are enforced by the hooks
(`check-shebang-scripts-are-executable`) — never `chmod` in CI to mask
a missing bit; fix it with `git update-index --chmod=+x <file>`.

## Bash 3.2 compatibility floor

Target Bash is **3.2** (macOS system Bash) and the floor is deliberate
— see `docs/DEVELOPMENT.md` "Bash 3.2 compatibility floor (policy)"
for the rationale and the exact banned-construct list (associative
arrays, namerefs, `mapfile`/`readarray`, `${var^^}`/`${var,,}`,
`&>>`, `coproc`). Do not introduce any of them. The grep-based check:

```bash
./scripts/check_bash32.sh
```

runs inside `./scripts/lint_shell.sh`, as a pre-commit hook, and as a
CI step, and must exit 0.

## Project Structure

- `mdoctor` -- Unified CLI entry point
- `doctor.sh` -- Health audit engine
- `cleanup.sh` -- Cleanup engine
- `lib/` -- Shared libraries (colors, logging, disk utils)
- `checks/` -- Health check modules (one file per check)
- `cleanups/` -- Cleanup modules (one file per cleanup task)

## Adding a New Health Check

1. Create `checks/yourcheck.sh` with a function:

```bash
check_your_feature() {
  step "Your Feature Check"
  if command -v yourtool >/dev/null 2>&1; then
    status_ok "yourtool is installed"
  else
    status_warn "yourtool not found"
    add_action "Install yourtool: brew install yourtool"
  fi
}
```

2. Source it in `doctor.sh` and call the function from `main()`
3. Increment `STEP_TOTAL` in `doctor.sh`
4. Add the module name to `mdoctor`'s `cmd_check` case statement

## Adding a New Cleanup Module

1. Create `cleanups/yourcleanup.sh` with a function:

```bash
clean_your_cache() {
  local rc=0
  header "Cleaning Your Cache"
  if [ -d "${HOME}/.yourcache" ]; then
    # Argv form only — never pass a command string. Validate the target,
    # then run with an argument vector so nothing is ever re-parsed by a shell.
    validate_deletion_path "${HOME}/.yourcache" || return 1
    run_cmd_args rm -rf -- "${HOME}/.yourcache"/_tmp_* || rc=$?
  else
    log "No cache found."
  fi
  [ "$rc" -eq 0 ] || log "Module 'yourcache' finished with $(safety_error_name "$rc")"
  return "$rc"
}
```

> Never use a string-eval path (`bash -c`, `eval`, or a single-string command
> runner). Destructive modules route deletions through `lib/safety.sh`
> (`validate_deletion_path`, `safe_remove`) and execute commands only via
> `run_cmd_args` with separate arguments. Never swallow a deletion status
> with `|| true` — capture it into the per-module accumulator (below) so
> partial failures propagate.

2. Register it with `register_module` in `lib/registry.sh` (the single source
   of truth — help text, validation, error messages and dispatch derive from
   it; no hand-maintained case statement needs updating)
3. Derive `PROGRESS_TOTAL` coverage in `cleanup.sh` from the module list

## Return-Code Contract

One contract governs every module family (Task 9.3):

- `0` means success — including "nothing to clean" (a missing directory is
  skipped silently) and dry-run mode (nothing executes, `0` is reported).
- `21`–`26` are the safety taxonomy from `lib/safety.sh`
  (`MDOCTOR_SAFE_ERR_*`): `21` invalid target, `22` protected target
  (blocked by policy), `23` symlink blocked, `24` permission denied,
  `25` SIP/read-only, `26` runtime failure. Render them with
  `safety_error_name` / `safety_error_hint`, never with ad-hoc text.
- Any other non-zero code is an external command failure (e.g. a missing
  `docker` binary); it propagates the same way, rendered as `UNKNOWN`.

Rules for authors:

- Every deletion call site uses `|| rc=$?` on a per-module `rc` accumulator
  initialized to `0`; the function ends with `return "$rc"`. A failing
  module never aborts its siblings: `cleanup.sh` accumulates per-module
  codes across the full run and reports the first failure at the end, and
  `run_single_cleanup_module` maps a non-zero module code to an error
  session end.
- A module whose every target is blocked (exists, but outside the allowed
  roots) returns `22` and says so — "blocked" is a result, never silent
  success. A module whose targets are simply absent returns `0`.
- `cmd_check` captures each check module's exit code and `cmd_fix` captures
  each fix target's, and both return it — the same capture on both paths.

Measurement helpers (`du_size_kb` / `dir_size_kb` in `lib/disk.sh`,
`preflight_*` in `lib/preflight.sh`, `_dir_size_kb` / `_find_and_sum` /
`_scan_dir_for_hogs` in `checks/storage.sh`) echo data, so they carry a
separate error channel (Task 9.4): `0` only for a genuine measurement,
`31` (`MDOCTOR_SIZE_ERR_NOT_DIR`) for a missing target, `32`
(`MDOCTOR_SIZE_ERR_TIMEOUT`) for a timed-out probe, `33`
(`MDOCTOR_SIZE_ERR_DENIED`) for permission denied. The echo is still
always numeric (`0` on failure, so bare arithmetic stays safe) — callers
capture the status (`out=$(du_size_kb "$p") || rc=$?`) and report "could
not determine" instead of treating `0` as "nothing to report".

## Commit Conventions

We use [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` -- New feature
- `fix:` -- Bug fix
- `docs:` -- Documentation only
- `refactor:` -- Code change that neither fixes a bug nor adds a feature
- `test:` -- Adding or updating tests
- `chore:` -- Maintenance tasks

Examples:
```
feat: add battery health check module
fix: correct disk usage percentage on APFS volumes
docs: add troubleshooting section to README
```

## Pull Request Process

1. Ensure your branch is up to date with `main`
2. Write a clear PR description explaining **what** and **why**
3. Test all affected commands (`mdoctor check`, `mdoctor clean`, etc.)
4. One approval is required before merging

## Coding Standards

- Use `#!/usr/bin/env bash` shebang
- Use `set -uo pipefail` (or `set -euo pipefail` for cleanup scripts)
- Quote all variable expansions: `"$var"` not `$var`
- Use the shared library functions (`status_ok`, `status_warn`, `status_fail`, etc.)
- Keep modules small and focused on a single concern
- Add comments only where the logic isn't self-evident

## Testing

Test your changes locally before submitting:

```bash
# Test the full health check
./mdoctor check

# Test a specific module
./mdoctor check -m yourmodule

# Test cleanup in dry-run mode
./mdoctor clean

# Test system info
./mdoctor info
```

Run the regression suite explicitly (no git hook runs it automatically):

```bash
./tests/run.sh
```

The suite is hermetic: tests sandbox `HOME` to a temp dir, the force
test stops after its pre-flight summary via `MDOCTOR_PREFLIGHT_ONLY=true`,
and `tests/helpers/bin` stubs `docker`, `apt-get` and `sudo` on `PATH`
so no test can reach a real daemon. See `docs/DEVELOPMENT.md`
"Test Harness" for details.

## Questions?

Open an issue or start a discussion on GitHub. We're happy to help!
