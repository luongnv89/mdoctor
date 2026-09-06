# AGENTS.md

## Project

mdoctor is a pure-Bash system-health tool for macOS and Debian Linux:
`mdoctor` (unified CLI) drives `doctor.sh` (audit), `cleanup.sh`
(cleanup), `checks/` + `cleanups/` + `fixes/` modules, `lib/` shared
libraries. No build step, no vendored dependencies. Invariants: dry-run
is the default for every destructive path; every deletion routes through
`lib/safety.sh` validators; Bash 3.2 compatibility is never broken.

## Commands

Canonical build / test / lint commands live in `CLAUDE.md` (and the
rationale in `docs/AGENT_ENVIRONMENT.md`) — use those, not this file.
CI lane mapping (`docs/DEVELOPMENT.md`): Lint → `lint_shell.sh` +
`bash -n`; Test macOS/Linux → `./tests/run.sh` + smoke commands;
Test Bash 3.2 → `bash:3.2` docker run; Release Sanity → env-overridden
installer flow.

## Layout

- `mdoctor`, `doctor.sh`, `cleanup.sh`, `install.sh`, `uninstall.sh` —
  entry points (never rename; referenced by tests and docs).
- `lib/` — shared libs (`platform.sh` first, then `common.sh`,
  `logging.sh`, `disk.sh`, `safety.sh`, `metadata.sh`, `json.sh`).
- `checks/`, `cleanups/`, `fixes/` — one file per module/target.
- `tests/` — `run.sh` runner + `test_*.sh` files + `helpers/`.
- `docs/` — user/developer docs; `docs/AGENT_ENVIRONMENT.md` is the
  agent-runbook source of truth.
- `.specify/`, `openspec/` — excluded from lint and build sweep.

## Conventions

- **Platform branching:** every platform-specific code path gates on
  `lib/platform.sh` predicates — `is_macos`, `is_linux`, `is_debian`
  (Debian-family only). Never branch on `uname` output directly, never
  assume a macOS-only binary exists on Linux (guard with `is_macos`
  AND `command -v`). New modules follow the same shape: shared logic
  first, `if is_macos ... elif is_linux` arms after.
- **Module registration flow:** check/cleanup modules do not
  self-register. `mdoctor` calls `register_module` from
  `lib/metadata.sh` (`register_module TYPE NAME CATEGORY RISK FUNCTION
  DESCRIPTION`) in exactly two places — the check-registration block
  and the cleanup-registration block. Adding a module means: create the
  file, source it from the owning engine (`doctor.sh`/`cleanup.sh`),
  add one `register_module` line in the matching block, bump the
  corresponding `STEP_TOTAL`/`PROGRESS_TOTAL`.
- Commit style: Conventional Commits (`feat:`, `fix:`, `docs:`,
  `refactor:`, `test:`, `chore:`); feature branches off `main`.
- Quote every expansion (`"$var"`), `set -uo pipefail` minimum
  (`-e` added for cleanup scripts).

## Constraints

- Never run the full `./tests/run.sh` on a real machine until Task 0.1
  lands (destructive force test) — safe subset only.
- Never push to `main` except through a reviewed PR.
- Never create or read a `.env` file — env vars only.
- Never break the Bash 3.2 floor.

## Done when

`bash -n` sweep reports 0 errors; safe test subset passes (full
`./tests/run.sh` 9/9 once 0.1 lands); `./scripts/lint_shell.sh` exits
0; `git status` shows only intended files.

## Read when needed

- Commands/quirks → `CLAUDE.md`, `docs/AGENT_ENVIRONMENT.md`
- Test/CI lanes → `docs/DEVELOPMENT.md`
- Safety model → `docs/SAFETY.md`
- Contributing flow → `CONTRIBUTING.md`

## Token Efficiency

- Never re-read files you just wrote or edited. You know the contents.
- Prefer `grep`/`glob` over full-file reads for locating code.
- Batch independent tool calls in one block; keep responses concise.
- Verify only uncertain outcomes — do not re-run green commands.
