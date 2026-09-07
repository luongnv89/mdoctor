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

Executable bits are enforced by the hooks
(`check-shebang-scripts-are-executable`) — never `chmod` in CI to mask
a missing bit; fix it with `git update-index --chmod=+x <file>`.

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
  header "Cleaning Your Cache"
  if [ -d "${HOME}/.yourcache" ]; then
    run_cmd "rm -rf \"${HOME}/.yourcache\"/*"
  else
    log "No cache found."
  fi
}
```

2. Source it in `cleanup.sh` and call the function
3. Increment `PROGRESS_TOTAL` in `cleanup.sh`
4. Add the module name to `mdoctor`'s `cmd_clean` case statement

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
