# CLAUDE.md

@AGENTS.md

Claude-specific project context for mdoctor (pure-Bash macOS/Linux
system-health tool). Full agent-environment rationale lives in
`docs/AGENT_ENVIRONMENT.md`; this file keeps the commands Claude needs
every session.

## Build

No compiler, no manifest. Build equivalent is the `bash -n` sweep (must
report 0 errors):

```bash
find . \( -name '*.sh' -o -name 'mdoctor' -o -name 'cleanup.sh' -o -name 'doctor.sh' -o -name 'install.sh' -o -name 'uninstall.sh' \) \
  -not -path './.git/*' \
  -not -path './openspec/*' \
  -exec bash -n {} + && echo BUILD-OK
```

## Test

Command of record: `./tests/run.sh` (bats-core suite, per-assertion
reporting, must pass 19/19 files). The runner self-provisions bats-core
v1.14.0 at a pinned SHA into `~/.cache/mdoctor/` on first use (override:
`MDOCTOR_BATS_BIN`, filter: `./tests/run.sh -f '<name>'`). Each file runs
under a 300 s watchdog (`MDOCTOR_TEST_FILE_TIMEOUT`); JUnit output lands
in `test-results/junit.xml`.

The suite is hermetic since Task 0.1: the force test
(`tests/test_force_preflight_resilience.bats`) stops after its pre-flight
summary via `MDOCTOR_PREFLIGHT_ONLY=true`, and `tests/run.sh` stubs
`docker`, `apt-get` and `sudo` on `PATH` — safe to run on a developer
machine. For a quicker signal, run a single test file directly:

```bash
./tests/run.sh tests/test_command_parsing.bats
```

## Lint

```bash
./scripts/lint_shell.sh
```

Runs `shellcheck -S error` over every tracked shell file. ShellCheck is
not vendored — install first (`brew install shellcheck` on macOS,
`sudo apt install -y shellcheck` on Debian/Ubuntu). Gate rises to
`-S warning` under Task 2.1.

Also run once per checkout: `pre-commit install` (plus
`pre-commit install --hook-type pre-push`).

## Bash 3.2 floor

Target Bash is **3.2** (macOS system Bash). The floor is deliberate (no
vendored Bash; Apple's 3.2.57 cannot be upgraded by this project;
raising it breaks the zero-dependencies promise). Bash 4+ constructs
are **banned**: `declare -A`, `declare -n` (namerefs),
`mapfile`/`readarray`, `&>>`, `coproc`, `globstar` (`**`),
`${var,,}`/`${var^^}`, newer `read` options. Canonical policy:
`docs/DEVELOPMENT.md` "Bash 3.2 compatibility floor (policy)".
Enforced by `./scripts/check_bash32.sh` (runs inside
`./scripts/lint_shell.sh`, as a pre-commit hook, and as a CI step).
See `docs/AGENT_ENVIRONMENT.md` for the full banned list and the
digest-pinned `bash:3.2` parity-check command (same digest as CI's
`image: bash@sha256:`).

## Config surface

No `.env` file exists and none is loaded. All knobs are environment
variables (`mdoctor --help` → "Environment Variables", e.g.
`DAYS_OLD_OVERRIDE`, `MDOCTOR_DEBUG`).
