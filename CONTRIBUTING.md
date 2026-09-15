# Contributing to mdoctor

Thanks for your interest in contributing to mdoctor! This guide will help you get started.

## How to Contribute

1. **Fork** the repository
2. **Create** a feature branch from `main` (`feat/your-feature`)
3. **Make** your changes
4. **Test** your changes — run the gates CI enforces on macOS, Linux
   and Bash 3.2 (see [Testing](#testing)); macOS alone is not enough
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
- `lib/` -- Shared libraries (platform, logging, disk, safety, metadata)
- `lib/registry.sh` -- Module registry, the single source of truth for
  `mdoctor list`, `mdoctor help`, validation and dispatch
- `checks/` -- Health check modules (one file per check)
- `cleanups/` -- Cleanup modules (one file per cleanup task)
- `fixes/` -- Fix modules (`mdoctor fix` targets)
- `tests/` -- bats regression suite, run with `./tests/run.sh`

## Adding a New Health Check

1. Create `checks/yourcheck.sh` with a function. Every module file
   opens with the module context contract (Task 9.1) — a
   `Required checks inputs:` header naming the globals
   `lib/context.sh` provides, plus the `_MDOCTOR_CONTEXT_READY` guard
   that fails loudly when the file is sourced without
   `mdoctor_context_init`. `test_module_context.bats` rejects any
   module file missing either:

```bash
# Required checks inputs: STEP_CURRENT, STEP_TOTAL, MDOCTOR_DEBUG, ACTIONS, WARN_COUNT, FAIL_COUNT, LOG_PATHS, LOG_DESCS, LOGFILE.
if [ "${_MDOCTOR_CONTEXT_READY:-false}" != true ]; then
  echo "${BASH_SOURCE[0]##*/}: module context not initialized (_MDOCTOR_CONTEXT_READY) — call mdoctor_context_init from lib/context.sh first" >&2
  return 1 2>/dev/null || exit 1
fi

check_your_feature() {
  step "Your Feature Check"
  if command -v yourtool >/dev/null 2>&1; then
    status_ok "yourtool is installed"
  else
    status_warn "yourtool not found"
    add_action "Install yourtool with your package manager"
  fi
}
```

   Any probe call that can block — `npm`, `brew`, `docker info`,
   `nslookup`, `apt list`, `softwareupdate`, `du -sk` — runs under
   `mdoctor_timeout` or carries a `timeout` note on the same line:
   `test_timeout_prefetch.bats` keeps a zero-uncapped census over
   `checks/` and `lib/` (issue #101).

Module names are lowercase letters, digits and underscores only —
`check -m` rejects anything else before it ever reaches a file.

2. Source it in `doctor.sh`, in the matching `checks/` category block.
   A platform-specific module goes inside the existing `if is_macos` /
   `if is_linux` guard (or self-gates inside the function, like
   `checks/battery.sh` — still registered unconditionally).

3. Register it in `lib/registry.sh`: add one `register_module` line to
   `register_all_modules()`, in the matching category group and inside
   the same platform conditional as the source line:

```bash
  register_module check yourcheck Software SAFE check_your_feature "One-line description"
```

   The signature is
   `register_module TYPE NAME CATEGORY RISK FUNCTION DESCRIPTION`
   (`lib/metadata.sh`); categories are `Hardware`, `System`, `Software`
   and check modules are `SAFE` (read-only). Registration is what puts
   the module in `mdoctor list` and `mdoctor help` and makes
   `mdoctor check -m yourcheck` dispatch to it — an unregistered file
   under `checks/` is invisible to all three.

4. Call it from `main()` in `doctor.sh`, in the matching phase block:

```bash
  _set_check_context yourcheck
  check_your_feature
```

   `_set_check_context` feeds the module's category/risk to the `--json`
   report; wrap both lines in `if is_macos` / `if is_linux` when the
   module is platform-specific. This is the line that makes the module
   run inside the full `mdoctor check` audit.

There is no total to bump and no dispatch table to edit: `doctor.sh`
derives `STEP_TOTAL` from the registry, and `check -m` resolves the
function name through `get_module_func`. Verify with:

```bash
./mdoctor list                # module listed, Check Modules count +1
./mdoctor check -m yourcheck  # runs via registry dispatch
```

## Adding a New Cleanup Module

1. Create `cleanups/yourcleanup.sh` with a function. Same context
   contract as check modules (above) — a `Required cleanups inputs:`
   header plus the `_MDOCTOR_CONTEXT_READY` guard:

```bash
# Required cleanups inputs: DRY_RUN, DAYS_OLD, LOGFILE, STEP_CURRENT, STEP_TOTAL, MDOCTOR_DEBUG.
if [ "${_MDOCTOR_CONTEXT_READY:-false}" != true ]; then
  echo "${BASH_SOURCE[0]##*/}: module context not initialized (_MDOCTOR_CONTEXT_READY) — call mdoctor_context_init from lib/context.sh first" >&2
  return 1 2>/dev/null || exit 1
fi

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

2. Register it in `lib/registry.sh`: one `register_module` line in
   `register_all_modules()`, inside the same `is_macos`/`is_linux`
   conditional when the module is platform-specific:

```bash
  register_module cleanup yourcleanup System MED clean_your_cache "One-line description"
```

   Risk is `SAFE` (report-only — never deletes), `LOW`, `MED` or `HIGH`;
   the badge in `mdoctor list`/`help` comes from this declaration, and
   `mdoctor clean -m yourcleanup` plus the `--interactive` picker
   resolve the function through the registry — no dispatch case to edit.

3. To include a destructive module in a full `mdoctor clean` run, wire
   it into `cleanup.sh` in three spots, all inside the matching
   platform conditional:

   - `source "${SCRIPT_DIR}/cleanups/yourcleanup.sh"` next to the other
     `cleanups/` sources
   - a `step "..."` + `clean_your_cache || _cleanup_rc=$?` pair in
     `main()`
   - add the module name to `CLEANUP_STEPS` — the hand-maintained
     list of modules the full run executes, with platform-gated `+=`
     entries (`if is_macos` / `if is_linux`); `STEP_TOTAL` derives
     from the list, so add the module only under the gate(s) it runs
     in and keep it mirrored with the `main()` step calls

   A report-only module (`SAFE`, like `downloads`) skips all three: the
   engine neither sources it nor counts it — it only ever runs via
   `mdoctor clean -m`.

4. For a destructive module, also add a `case` arm in
   `cmd_clean_preflight_summary_module` (in `mdoctor`) listing its
   touched targets, so the `--force` pre-flight summary can size them.

Verify with `./mdoctor list` (the module and the Cleanup Modules count
rise) and `./mdoctor clean -m yourcleanup` — dry-run is the default.

Fix targets follow the same shape — a file under `fixes/`, a
`register_module fix …` line — except `cmd_fix` still dispatches through
hand-maintained `case` blocks and a `fix all` array in `mdoctor` (the
platform gate and the dispatch itself), so those need the new target
added too.

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
- Follow the errexit posture table below — each entry point's `set` line
  is a deliberate decision, stated in its header comment
- Quote all variable expansions: `"$var"` not `$var`
- Use the shared library functions (`status_ok`, `status_warn`, `status_fail`, etc.)
- Keep modules small and focused on a single concern
- Add comments only where the logic isn't self-evident

### Errexit posture

Each entry point picks its `set` flags deliberately; the posture is
stated in the file's header comment and must not be changed casually.
`set -uo pipefail` is the minimum everywhere.

| Entry point | Flags | Why |
|-------------|-------|-----|
| `mdoctor` | `set -uo pipefail` | The dispatcher runs independent commands and reports each exit code itself; one failing command must not kill the CLI. |
| `doctor.sh` | `set -uo pipefail` | A read-only audit of 20+ sequential checks — one check's failure must not abort the rest of the report. |
| `cleanup.sh` | `set -euo pipefail` | Destructive engine — an unexpected failure aborts the run before further deletions. |
| `install.sh`, `uninstall.sh` | `set -euo pipefail` | A half-completed install/uninstall is worse than none; fail fast. |
| `tests/run.sh` | `set -uo pipefail` | The runner aggregates per-file failures; aborting on the first would hide later results. |

Because the same `lib/` modules are sourced by entry points with and
without `-e`, shared code must be **posture-agnostic** (issue #113):

- Never rely on `set -e` to abort on failure — check return codes and
  `return` explicitly.
- Guard best-effort writes (operations log, `~/.mdoctor/history`,
  `~/.config/mdoctor` config files, `$LOGFILE`) so a failure warns and
  continues instead of tripping `-e`: `if ! cmd; then …`, `cmd || true`,
  or `2>/dev/null` as appropriate.
- Capture a command that may fail inside `if var="$(cmd)"; then … else
  rc=$?; fi` — never toggle `set +e`/`set -e` mid-script (that also leaks
  the flag into the rest of the process).

## Testing

Run the same gates CI runs — every lane below lives in
`.github/workflows/ci.yml`:

| Local command | CI lane that enforces it |
|---------------|--------------------------|
| `./scripts/lint_shell.sh` | **Lint** — ShellCheck `-S warning` plus a `bash -n` syntax pass over every shell file (the lane also runs `./scripts/check_bash32.sh`) |
| `pre-commit install`, then the hooks fire per commit | **Hooks (pre-commit)** — runs `pre-commit run --all-files` |
| `./tests/run.sh` | **Test (macOS)** (two `--shard I/2` legs) and **Test (Linux/Ubuntu)** — the bats suite plus `mdoctor` smoke commands |
| `./tests/run.sh` under Bash 3.2 | **Test (Bash 3.2 compat)** — the suite inside the digest-pinned `bash:3.2` container |
| `./tests/run.sh` under kcov | **Coverage (kcov)** — enforces the `COVERAGE_MIN` floor |

Two lanes have no local equivalent: **Release Sanity** (installer
round trip on Ubuntu + macOS) and **Installer (curl-pipe)**. See
`docs/DEVELOPMENT.md` "CI lanes map to local commands" for the full
list, including the `bash:3.2` and Ubuntu `docker run` recipes for
reproducing the other-platform lanes locally.

The cross-platform expectation: `./tests/run.sh` and
`./scripts/lint_shell.sh` must pass on every platform your change
touches — a Linux-only or macOS-only change still has to pass both
suites, because the suite itself is platform-aware. If you cannot run
the other platform, say so in the PR; CI runs both.

Smoke-test the commands your change touches (the test lanes run this
same set):

```bash
# Full health audit (read-only)
./mdoctor check

# A single check module
./mdoctor check -m system

# Cleanup in dry-run mode (the default — safe)
./mdoctor clean

# System info
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
