# Modernization Plan — mdoctor

Derived from [`MODERNIZATION_REPORT.md`](./MODERNIZATION_REPORT.md) · **Baseline at audit:** AMBER
**Test command of record:** `./tests/run.sh` · **Pass rate at audit:** `8 of 9 test files pass; the 9th was not run because it is destructive`
**Build command of record:** `bash -n` across all 70 shell scripts (0 syntax errors)

## Read this before executing any task

**The test command of record is not safe to run today.** `tests/test_force_preflight_resilience.sh:52`
runs `./cleanup.sh --force`, which reaches `docker system prune -af --volumes`
(`cleanups/dev_caches.sh:84`) and `sudo apt-get autoremove -y` (`cleanups/apt.sh:26`) outside the
test's `HOME` sandbox. That is finding `F-BUG-004`; `F-TEST-002` is the `pre-push` hook that fires it
on every `git push`. **Task 0.1 is therefore the first task in the plan**, because until it lands no
other task's "baseline-green holds" acceptance criterion can honestly be executed by a developer.

The baseline assertion is substituted accordingly, once, here:

| When | The baseline assertion every P0–P4 acceptance criterion means |
|---|---|
| **Before Task 0.1 lands** | `find . \( -name '*.sh' -o -name mdoctor \) -not -path './.git/*' -print0 \| xargs -0 -n1 bash -n` reports 0 errors **and** the 8 safe test files pass: `for f in tests/test_*.sh; do [ "$f" = tests/test_force_preflight_resilience.sh ] && continue; bash "$f" \|\| exit 1; done` |
| **After Task 0.1 lands** | `./tests/run.sh` passes **9 of 9 files** |

Task 0.1 is the only P0–P4 task written against the pre-0.1 assertion; every other task depends on
0.1 directly or transitively and asserts the full suite. Pre tasks assert neither — they only require
documented install/run notes and creation of `CLAUDE.md` / `AGENTS.md`.

**The baseline is AMBER, not RED.** The build equivalent passes with 0 errors and 8 of 9 test files
pass, so Pre is not exempt from anything on RED grounds, and P0 is not "restore green" — it is
*make the suite safe to run and make the gates real*, then stop the tool destroying user data.

**ShellCheck is not installed locally and CI runs it at `-S error`, the weakest band.** Task 2.1
raises it to `-S warning`. That is a *measurement* task whose output feeds later work: the number of
findings it surfaces is unknown until it runs, so 2.1's own acceptance criteria are about producing
and triaging the inventory, not about a target count.

**Why the six data-loss defects sit in P0 with the safety work.** The normal rule is that P0 carries
only what prevents verification. It bends here: `F-BUG-001` deletes 103,440 files under the whole XDG
data root, `F-BUG-002` collapses every target onto a system directory when `HOME` is empty,
`F-BUG-003` means no confirmation prompt exists anywhere in the product, `F-BUG-005` `rm -rf`s an
environment-supplied path, `F-BUG-006` reassigns `/usr/local` to an unprivileged user on Debian, and
`F-UX-001` destroys named Docker volumes from a module badged `[LOW]`. The tool destroys user data
today. Deferring those behind a coverage or lint programme would be indefensible, so P0 carries them
alongside the suite-safety work.

**Where W0 was placed.** The report's wave table lands W0 (`F-DEP-002`, `F-DEP-003`, `F-DEP-007` —
SHA-pin the 5 Actions refs, digest-pin `bash:3.2`, add Dependabot) in P0, and this plan follows it.
The argument: mdoctor has no package manifest in any ecosystem, so those six pinned refs *are* this
repository's lockfile, and "lockfile committed" is a P0 exit condition. They are Sprint 1 tasks 1.4
and 1.5. The rest of the dependency work stays where the waves put it: W2 in P1, W3–W5 in P2.

## At a glance

| Phase | Sprints | Tasks | Closes | Milestone |
|---|---|---|---|---|
| Pre Agent environment | 1 (Pre) | 3 | 1 Low (enables ME) | ME |
| P0 Stabilize | 2 (0–1) | 14 | 9 Critical, 4 High, 8 Medium, 1 Low | M0 |
| P1 Secure & Patch | 3 (2–4) | 22 | 15 High, 19 Medium, 7 Low | M1 |
| P2 Modernize | 1 (5) | 4 | 3 Medium, 2 Low | M2 |
| P3 Clean & Harden | 5 (6–10) | 35 | 1 Critical, 17 High, 24 Medium, 14 Low | M3 |
| P4 Polish | 3 (11–13) | 26 | 17 High, 31 Medium, 16 Low | M4 |
| **Total** | **15** | **104** | **10 Critical, 53 High, 85 Medium, 41 Low** | — |

2 Medium findings are deferred with reasons (see **Deferred and out of scope**). **No Critical or
High finding is deferred** — all 63 are closed by a named task.

**Critical path:** Task Pre.1 → Pre.2 → 0.1 → 0.3 → 0.4 → 0.5 → 1.7 → 6.1 → 6.2 → 6.6 → 7.4 → 8.1 →
8.3 → 8.4 → 9.1 → 9.2 → 10.1 → 10.2 → 11.6 → 11.7 → 13.3 — **21 tasks, 38 days**. Nothing in P0
starts before `ME`. Nothing in P1–P4 starts before `M0`.

## Phase Pre — Agent environment

**Goal:** an agent can install, run, lint and test mdoctor from repository files alone, and knows the
one thing that will destroy its host if it guesses. · **Milestone ME:** `CLAUDE.md` and `AGENTS.md`
exist at the repo root (created via planned `/agent-config create`); the recorded build, test and
lint commands and the destructive-suite warning are documented in `CLAUDE.md` and the Pre.1 notes.

Neither `CLAUDE.md` nor `AGENTS.md` exists at the repo root (verified against the audited tree), so
both Pre tasks name `/agent-config create`, not `update`. This skill does not run `/agent-config`.

### Sprint Pre — Agent-runnable environment

#### Task Pre.1: Write the install, run, lint and test notes an agent cannot infer

**Description**: mdoctor has no package manifest, so nothing in the tree states how to build, lint or
test it, and the one command an agent would reach for first — `./tests/run.sh` — destroys real Docker
volumes until Task 0.1 lands. Record: the `bash -n` sweep as the build equivalent; the safe-subset
test command and the warning that the full runner is destructive until 0.1; the real lint entry point
`scripts/lint_shell.sh` and that ShellCheck must be installed separately (`command -v shellcheck`
fails on a clean machine); the `pre-commit install` step, which no tracked document currently
mentions (`F-CI-010`); the Bash 3.2 compatibility floor and its banned constructs
(`docs/DEVELOPMENT.md:6`); and that there is no `.env` surface — configuration is the environment
variables listed in `mdoctor --help`. Serves milestone ME and closes the absence-of-artifact finding.

**Closes**: `F-DOCS-022` (also milestone-enabling: ME)

**Acceptance Criteria**:
- [ ] A tracked file records all six items: build (`bash -n` sweep), test (safe subset **and** the destructive-until-0.1 warning naming `tests/test_force_preflight_resilience.sh`), lint (`scripts/lint_shell.sh` + ShellCheck install), `pre-commit install`, the Bash 3.2 floor with its banned-construct list, and the absence of any `.env`
- [ ] `grep -c 'test_force_preflight_resilience' CLAUDE.md` returns ≥ 1 once Pre.2 lands, and the surrounding text says the full runner is destructive until Task 0.1
- [ ] A reader following the notes alone can run the build equivalent and the safe test subset with no unwritten context

**Dependencies**: None

**Effort**: S

**Verify**: `bash -n` sweep and the safe-subset loop above both run to completion using only commands copied verbatim out of the notes

#### Task Pre.2: Create CLAUDE.md

**Description**: `CLAUDE.md` is absent at the repo root, so this is a create, not an update. Run
`/agent-config create` targeting `CLAUDE.md`, seeded from the Pre.1 notes plus the CI-lane mapping in
`docs/DEVELOPMENT.md`. Serves milestone ME. Do not run the skill while planning.

**Closes**: — (milestone-enabling: ME)

**Acceptance Criteria**:
- [ ] `test -f CLAUDE.md` succeeds
- [ ] `CLAUDE.md` names the recorded build command (`bash -n` sweep), the test command of record (`./tests/run.sh`) with the destructive-until-0.1 warning, and the lint command (`scripts/lint_shell.sh`)
- [ ] `CLAUDE.md` states the Bash 3.2 floor and that Bash 4+ constructs are banned

**Dependencies**: Pre.1

**Effort**: S

**Verify**: run `/agent-config create` targeting `CLAUDE.md`, then `test -f CLAUDE.md && grep -q 'tests/run.sh' CLAUDE.md`

#### Task Pre.3: Create AGENTS.md

**Description**: `AGENTS.md` is absent at the repo root, so this is a create, not an update. Run
`/agent-config create` targeting `AGENTS.md`, scoped to agent-config's own checklists (subagent
definitions and repo etiquette). The build/test/lint commands stay on the Pre.1 notes and
`CLAUDE.md`. Serves milestone ME. Do not run the skill while planning.

**Closes**: — (milestone-enabling: ME)

**Acceptance Criteria**:
- [ ] `test -f AGENTS.md` succeeds
- [ ] `AGENTS.md` content is scoped to agent-config's checklists and does not duplicate the build/test command block that lives in `CLAUDE.md`
- [ ] `AGENTS.md` records the repo etiquette an agent cannot infer: platform-branching conventions and the module registration flow (`lib/metadata.sh` `register_module`, called in two places)

**Dependencies**: Pre.1

**Effort**: S

**Verify**: run `/agent-config create` targeting `AGENTS.md`, then `test -f AGENTS.md`

## Phase P0 — Stabilize

**Goal:** make `./tests/run.sh` safe to run on a developer machine, then stop the six defects that
destroy data the user did not agree to lose, then commit this repository's lockfile-equivalent pins.
· **Milestone M0:** from a clean checkout, `./tests/run.sh` passes 9 of 9 files with no external
state destroyed (no Docker volume removed, no package autoremoved), CI reproduces that run, and every
Actions ref and container image is pinned by SHA or digest.

### Sprint 0 — Make the suite safe and stop the data loss

#### Task 0.1: Make the force test hermetic and unwire the destructive pre-push hook

**Description**: `tests/run.sh:6` globs `test_*.sh` and `:18` runs each, so the suite runs
`tests/test_force_preflight_resilience.sh:52`'s `./cleanup.sh --force`. The `HOME` override sandboxes
filesystem deletions but not `docker system prune -af --volumes` or `sudo apt-get autoremove -y`.
Add a preflight-only early exit after `cleanup.sh:276` and have the test use it, asserting only on
preflight output; then stub `docker` and `apt-get` on `PATH` for the whole suite so no future test can
reach a real daemon. Remove or re-point the `pre-push` `test-suite` hook at
`.pre-commit-config.yaml:32` (hook configuration is `devops-pipeline`'s surface). Correct
`docs/DEVELOPMENT.md:36` and the `CONTRIBUTING.md` testing section, which today are the only two
documented routes to the suite and both trigger it silently. This task unblocks the entire plan.

**Closes**: `F-BUG-004`, `F-TEST-002`, `F-DOCS-002`

**Acceptance Criteria**:
- [ ] `./tests/run.sh` runs all 9 test files and passes 9/9
- [ ] During that run, `docker volume ls -q | wc -l` is unchanged before and after, and `docker system prune` never reaches a real daemon (the stub records the argv instead)
- [ ] `grep -n 'tests/run.sh' .pre-commit-config.yaml` shows no `pre-push` stage invoking the full destructive suite
- [ ] `docs/DEVELOPMENT.md` and `CONTRIBUTING.md` both describe how the suite is sandboxed and state which stage, if any, runs it automatically
- [ ] Baseline-green (pre-0.1 form) holds: the `bash -n` sweep reports 0 errors and the 8 safe test files pass

**Dependencies**: Pre.2, Pre.3

**Effort**: L (3 days)

**Verify**: `./tests/run.sh; docker volume ls -q | wc -l` before and after, plus `pre-commit run --hook-stage pre-push --all-files`

#### Task 0.2: Scope the Linux log cleanup to mdoctor's own data directory

**Description**: `cleanups/logs.sh:13` deletes every file older than 7 days, unbounded depth, under
`platform_user_log_dir`, which `lib/platform.sh:105` defines on Linux as `${HOME}/.local/share` — the
whole XDG data root. Measured: 103,440 files / 2.18 GB including `keyrings`, `pki`, `nvim`, `mise`,
`uv`, plus mdoctor's own recovery log. `docs/SAFETY.md:114` documents the target as
`~/.local/share/mdoctor`, so the code exceeds its own contract by the whole tree. Return
`${XDG_DATA_HOME:-$HOME/.local/share}/mdoctor` on Linux and add `$HOME/.local`, `$HOME/.local/share`
and `$HOME/.config` to `is_protected_deletion_path`.

**Closes**: `F-BUG-001`

**Acceptance Criteria**:
- [ ] `platform_user_log_dir` on Linux returns a path ending in `/mdoctor`, matching `docs/SAFETY.md:114`
- [ ] `validate_deletion_path "$HOME/.local/share"` returns the protected error code, and so do `$HOME/.local` and `$HOME/.config`
- [ ] A test plants a file under `$HOME/.local/share/other-app` older than 7 days and asserts a forced `clean -m logs` leaves it in place
- [ ] `./tests/run.sh` passes 9/9 (baseline-green holds)

**Dependencies**: 0.1

**Effort**: S

**Verify**: `./tests/run.sh` and `bash -c 'source lib/safety.sh; validate_deletion_path "$HOME/.local/share"; echo $?'`

#### Task 0.3: Fail closed on an empty or denormalized `$HOME`

**Description**: `lib/safety.sh:209` wraps the whole home-protection block in `[ -n "${HOME:-}" ]`,
so `HOME` set-but-empty — legal in cron, launchd, systemd and containers, and not caught by `set -u`
— collapses every cleanup target onto a real system directory *and* disables every home protection at
the same time. With `HOME=""`, `platform_cache_dir` returns `/Library/Caches`, which `:201` allows
because it blocks only the exact string `/Library` and `:204` has no `/Library/*` prefix rule.
Separately `_normalize_path` (`lib/safety.sh:186`) trims trailing slashes only, so the whitelist is
defeated by `//` or `/./` anywhere in the path. Return protected when `HOME` is empty, normalise
`$HOME` before comparison, add a `/Library/*` prefix rule, and collapse `//` and `/./` inside
`_normalize_path`, applying it to both the candidate and every whitelist entry.

**Closes**: `F-BUG-002`, `F-BUG-020`

**Acceptance Criteria**:
- [ ] `HOME= bash -c 'source lib/safety.sh; validate_deletion_path /Library/Caches'` returns the protected error code, not success
- [ ] With `~/.ollama/models` whitelisted, all three of `$HOME/.ollama/models`, `$HOME//.ollama/models` and `$HOME/./.ollama/models` are rejected by `validate_deletion_path`
- [ ] A test asserts the empty-`HOME` case and the two denormalized whitelist forms
- [ ] `./tests/run.sh` passes 9/9 (baseline-green holds)

**Dependencies**: 0.1

**Effort**: S

**Verify**: `./tests/run.sh` and `HOME= bash -c 'source lib/safety.sh; validate_deletion_path /Library/Caches; echo $?'`

#### Task 0.4: Require every deletion target to sit under a known cache or temp root

**Description**: `is_protected_deletion_path` (`lib/safety.sh:204`) is a denylist whose exact-match
and prefix rules disagree, so coverage is arbitrary and macOS-shaped: probed, `/Library` is protected
but `/Library/Logs/DiagnosticReports` is not; `/usr` is protected but `/usr/local/bin` is not; and
`/home`, `/root`, `/opt`, `/srv`, `/mnt`, `/media`, `$HOME/Downloads`, `$HOME/.config` and
`$HOME/.local` are all allowed. The list was never extended for the Linux port. Add a positive
allowlist requiring every target to sit under a known cache or temp root, keeping the denylist as a
backstop.

**Closes**: `F-BUG-013`

**Acceptance Criteria**:
- [ ] `validate_deletion_path` rejects all of `/home`, `/root`, `/opt`, `/srv`, `/mnt`, `/media`, `/usr/local/bin`, `/Library/Logs/DiagnosticReports`, `$HOME/Downloads`, `$HOME/.config`, `$HOME/.local`
- [ ] `validate_deletion_path` still accepts every path the 11 cleanup modules legitimately target, proven by a test that enumerates them from the module list
- [ ] The allowlist roots are enumerated in one place and referenced by both the validator and `docs/SAFETY.md`
- [ ] `./tests/run.sh` passes 9/9 (baseline-green holds)

**Dependencies**: 0.3

**Effort**: M

**Verify**: `./tests/run.sh` and `bash tests/test_safety_validation.sh`

#### Task 0.5: Add a confirmation gate before any destructive execution

**Description**: No confirmation prompt exists anywhere in the product — a repo-wide search for
`read -p`, `[y/N]`, `Are you sure` or `confirm` across every shell file returns zero matches. The
force path (`cleanup.sh:274`) prints the pre-flight summary and falls straight through to execution;
the only `read` in the CLI (`mdoctor:619`) is the module picker, which chooses *which* modules run,
not *whether* to delete. Meanwhile `docs/SAFETY.md:9` describes the summary as a review step. Add a
y/N prompt after the pre-flight summary, gated on an assume-yes variable, and refuse `--force` on a
non-tty unless that variable is set. Amend `docs/SAFETY.md`'s second layer, its safe-operating
checklist and the README cleanup section to state what actually happens.

**Closes**: `F-BUG-003`, `F-DOCS-003`

**Acceptance Criteria**:
- [ ] `printf 'n\n' | ./cleanup.sh --force` exits without deleting and says so; `printf 'y\n' | ./cleanup.sh --force` proceeds
- [ ] `./cleanup.sh --force < /dev/null` on a non-tty refuses unless the assume-yes variable is set, and names the variable in the refusal
- [ ] `grep -n 'no confirmation\|deletes immediately' docs/SAFETY.md README.md` returns a match in each, and neither still describes the summary as a review-then-approve step
- [ ] A test covers the yes, no and non-tty paths
- [ ] `./tests/run.sh` passes 9/9 (baseline-green holds)

**Dependencies**: 0.4

**Effort**: M

**Verify**: `./tests/run.sh` and `printf 'n\n' | ./cleanup.sh --force; echo $?`

#### Task 0.6: Put the Docker volume prune behind an explicit opt-in and re-rate the badges

**Description**: `docker system prune -af --volumes` deletes named volumes — database data, not
caches — and runs from `cleanups/dev.sh:55` and `cleanups/dev_caches.sh:84`, both badged `[LOW]`,
which `README.md:231` defines as "Easily reversible, minimal impact". In the pre-flight it appears as
one unadorned line, "Docker prune (size estimate: n/a)"; the source comment at `cleanups/dev.sh:52`
warning that it "removes ALL unused containers/images/volumes" never reaches the user. Separately all
11 cleanup modules are registered `LOW` at `mdoctor:981`, including `trash`, `logs`, `dev`,
`dev_caches` and `apt` — so the risk badge conveys no information for the entire destructive
category. Put the prune behind an explicit opt-in flag, print the full command and the `--volumes`
consequence in both pre-flight summaries, and re-rate the cleanup modules against actual blast radius.

**Closes**: `F-UX-001`, `F-BUG-023`

**Acceptance Criteria**:
- [ ] `docker system prune` does not execute on any path without the new opt-in flag, proven by a stub-`PATH` test that records argv
- [ ] Both pre-flight summaries print the literal command string including `--volumes` and a one-line consequence statement
- [ ] `./mdoctor list` shows `trash`, `logs`, `dev` and `dev_caches` at a risk level above `LOW`, and no cleanup module that deletes user files is still `LOW`
- [ ] `./tests/run.sh` passes 9/9 (baseline-green holds)

**Dependencies**: 0.1

**Effort**: S

**Verify**: `./tests/run.sh` and `./mdoctor list | grep -E 'trash|logs|dev_caches'`

#### Task 0.7: Document the operations the safety layer does not cover

**Description**: `docs/SAFETY.md:20` presents the whitelist as blanket protection inside a
defense-in-depth model whose third layer claims "cleanup modules route through guarded helpers". Two
operations reached by a forced clean do not route through them and the whitelist cannot stop them:
`docker system prune -af --volumes`, and three `sudo apt-get` calls including an unattended
`autoremove`. Neither `docker` nor `sudo apt-get` appears anywhere in the document and the
known-limitations section does not mention the gap. Have `doc-manager` add an explicit "operations
outside the safety primitives" section naming both commands with their source lines, stating plainly
that the whitelist and protected-path checks do not apply, and add both to known limitations —
updated to reflect the opt-in and confirmation gates that Tasks 0.5 and 0.6 introduce.

**Closes**: `F-DOCS-001`

**Acceptance Criteria**:
- [ ] `docs/SAFETY.md` contains a section naming `docker system prune -af --volumes` (`cleanups/dev.sh:55`, `cleanups/dev_caches.sh:84`) and the three `sudo apt-get` calls (`cleanups/apt.sh`) with their source lines
- [ ] That section states that `validate_deletion_path` and the whitelist do not apply to either, and points at the opt-in flag from Task 0.6 and the confirmation gate from Task 0.5
- [ ] Both commands appear in the known-limitations section
- [ ] `./tests/run.sh` passes 9/9 (baseline-green holds)

**Dependencies**: 0.5, 0.6

**Effort**: S

**Verify**: run `doc-manager` on `docs/SAFETY.md`, then `grep -c 'docker system prune\|apt-get autoremove' docs/SAFETY.md`

### Sprint 1 — Privileged entry points and the lockfile-equivalent pins

#### Task 1.1: Validate the install directory before `rm -rf`, and confirm uninstall

**Description**: `uninstall.sh:42` `rm -rf`s an unvalidated environment-controlled path:
`INSTALL_DIR="${MDOCTOR_INSTALL_DIR:-…}"` comes from the environment, `uninstall.sh` sources nothing,
so `validate_deletion_path` never runs — and both scripts document `curl … | bash` invocation, which
inherits the caller's environment. `install.sh:101` tests only `[ -d ]` and never checks the
directory is an mdoctor checkout before `rm -rf` at `:108`. Uninstall is additionally unprompted and
its completion claim is untrue: `~/.config/mdoctor` — holding the whitelist, the operations log, the
scope file and the score history — is neither removed nor mentioned. Source `lib/safety.sh`, require
`${INSTALL_DIR}/mdoctor` and `.git` to exist, reject `$HOME` and `/`, call `validate_deletion_path`
before any `rm`, prompt when stdin is a tty with a flag to skip, and print the retained config path.

**Closes**: `F-BUG-005`, `F-UX-016`

**Acceptance Criteria**:
- [ ] `MDOCTOR_INSTALL_DIR="$HOME" ./uninstall.sh` refuses and removes nothing; the same with `/` refuses
- [ ] `MDOCTOR_INSTALL_DIR=<empty dir> ./uninstall.sh` refuses because `mdoctor` and `.git` are absent
- [ ] `./uninstall.sh` on a tty prompts before deleting and honours a documented skip flag
- [ ] `./uninstall.sh` output names `~/.config/mdoctor` and the command to remove it
- [ ] `./tests/run.sh` passes 9/9 (baseline-green holds)

**Dependencies**: 0.1

**Effort**: S

**Verify**: `./tests/run.sh` and `MDOCTOR_INSTALL_DIR="$HOME" ./uninstall.sh; echo $?`

#### Task 1.2: Platform-gate the fix dispatch and stop the unconditional `chown -R /usr/local`

**Description**: `fixes/permissions.sh:23` runs `sudo chown -R "$(whoami)" /usr/local` on every
platform — it sits outside the `command -v brew` branch above it and the file has zero `is_macos`
guards. On Debian `/usr/local/bin` is the first entry of root's sudo `secure_path`, so recursively
reassigning the tree to one unprivileged user is a local privilege-escalation setup. It is reachable
on Linux only because `cmd_fix`'s dispatch case (`mdoctor:778`) lists all ten fix targets with no
platform gate — only the registry used by `fix all` and `--help` is gated. That dispatch case is the
routing root cause of this finding and of `F-BUG-015`. Its argument loop's `*)` arm also silently
treats any unrecognised token, including a mistyped flag, as the target, unlike `cmd_clean`.

**Closes**: `F-BUG-006`, `F-BUG-024`

**Acceptance Criteria**:
- [ ] On Linux, `./mdoctor fix permissions` exits non-zero with a platform message and `chown` is never invoked, proven by a stub-`PATH` argv recorder
- [ ] `sudo chown -R … /usr/local` executes only inside a branch guarded by both `is_macos` and `command -v brew`, and its exit status is checked before any success message
- [ ] `./mdoctor fix --nosuchflag` errors on the unknown option instead of treating it as a target, matching `cmd_clean`
- [ ] `./tests/run.sh` passes 9/9 (baseline-green holds)

**Dependencies**: 0.1

**Effort**: S

**Verify**: `./tests/run.sh` and `./mdoctor fix --nosuchflag; echo $?`

#### Task 1.3: Add macOS guards to the five ungated fix modules

**Description**: Five fix modules are built from macOS-only commands with no platform guard and print
unconditional success on Linux. Guard census: `audio` (1 macOS command, 0 guards), `disk` (2, 0),
`spotlight` (3, 0), `timemachine` (3, 0), `wifi` (6, 0); only `dns` guards correctly. Two are worse
than no-ops: `fixes/bluetooth.sh:16`'s `sudo pkill -HUP bluetoothd` does match BlueZ's daemon on
Linux, bypassing systemd supervision. Separately `fixes/disk.sh:17` hardcodes the macOS log path
although the module is registered cross-platform and included unconditionally in `fix all`, and its
final step invokes a macOS-only binary whose `|| true` masks a command that can never succeed on
Linux — so step 4 of 4 prints progress for work that never happens. Add an `is_macos` early return
to each module, stop printing unconditional success, and route the log path through the existing
platform helper.

**Closes**: `F-BUG-015`, `F-DEAD-018`

**Acceptance Criteria**:
- [ ] On Linux, each of `audio`, `disk`, `spotlight`, `timemachine`, `wifi` and `bluetooth` returns non-zero with a platform message and executes zero macOS-only binaries, proven by a stub-`PATH` argv recorder
- [ ] `sudo pkill -HUP bluetoothd` is unreachable on Linux
- [ ] `fixes/disk.sh` obtains its log path from the platform helper, with no hardcoded `/Library` or `/private/var` literal remaining (`grep -c '/Library\|/private/var' fixes/disk.sh` returns 0)
- [ ] `./tests/run.sh` passes 9/9 (baseline-green holds)

**Dependencies**: 1.2

**Effort**: S

**Verify**: `./tests/run.sh` and `for t in audio disk spotlight timemachine wifi bluetooth; do ./mdoctor fix "$t"; echo "$t=$?"; done`

#### Task 1.4: Pin the five Actions refs to SHAs and the container image to its digest

**Description**: mdoctor has no package manifest in any ecosystem — `scripts/dep_scan.sh` reports
"Ecosystems detected: none" — so the six pinned refs in CI are this repository's lockfile. Today
`actions/checkout` is referenced as the float tag `@v4` at five sites (`.github/workflows/ci.yml:15`)
and the test container as the mutable tag `bash:3.2` (`:112`, currently digest
`sha256:3a13e5da…`). Pin all five Actions refs to full commit SHAs with the version as a trailing
comment, and pin the image by digest. This is wave W0 and it is the P0 lockfile step.

**Closes**: `F-DEP-002`, `F-DEP-003`

**Acceptance Criteria**:
- [ ] `grep -c 'uses: .*@[0-9a-f]\{40\}' .github/workflows/ci.yml` equals the number of `uses:` lines in the file
- [ ] `grep -c 'image: bash@sha256:' .github/workflows/ci.yml` returns 1 and no `image: bash:3.2` tag reference remains
- [ ] A CI run on the pinned refs is green across all five jobs
- [ ] `./tests/run.sh` passes 9/9 (baseline-green holds)

**Dependencies**: 0.1

**Effort**: S

**Verify**: `grep -n 'uses:\|image:' .github/workflows/ci.yml` and `gh run list --limit 1`

#### Task 1.5: Add automated dependency updates for Actions and pre-commit

**Description**: There is no dependency update automation of any kind, so the three pin groups
(Actions refs, container image, pre-commit hook revisions) drift with nothing to detect it — the
finding the report records at `.github/workflows/ci.yml:15`. Now that Task 1.4 has pinned them by
SHA, a bot is the only thing that will ever unpin them safely. Add Dependabot covering the
`github-actions` and `pre-commit` ecosystems.

**Closes**: `F-DEP-007`

**Acceptance Criteria**:
- [ ] `.github/dependabot.yml` exists and declares both the `github-actions` and `pre-commit` package ecosystems
- [ ] Dependabot's first run opens or reports zero PRs without erroring, visible in the repository's Dependabot logs
- [ ] `./tests/run.sh` passes 9/9 (baseline-green holds)

**Dependencies**: 1.4

**Effort**: S

**Verify**: `test -f .github/dependabot.yml && gh api repos/:owner/:repo/dependabot/alerts --silent`

#### Task 1.6: Add a central fail-closed dry-run predicate

**Description**: `lib/logging.sh:182`'s dry-run gate is an exact case-sensitive string match on
`true`. Unset or empty correctly falls back to dry-run, so the important default is fail-closed, but
any other value fails *open* and executes for real: `DRY_RUN=1`, `yes`, `TRUE` or a trailing space all
silently disable dry-run on a tool that deletes files. Latent today only because every current
assignment uses the exact literals. Add a central `is_dry_run()` normalising `true/1/yes` and
`false/0/no`, warning and then failing closed on anything unrecognised. This predicate is the helper
Task 9.5 later rolls out across the other 36 string-boolean sites.

**Closes**: `F-BUG-021`

**Acceptance Criteria**:
- [ ] `DRY_RUN=1`, `DRY_RUN=yes`, `DRY_RUN=TRUE` and `DRY_RUN='true '` all resolve to dry-run enabled
- [ ] `DRY_RUN=banana` warns on stderr and resolves to dry-run enabled (fail closed), exit status non-zero from the predicate
- [ ] Every site that previously compared the variable to the literal `true` calls `is_dry_run` instead (`grep -c '= *"\?true"\?' lib/logging.sh` shows no remaining dry-run comparison)
- [ ] `./tests/run.sh` passes 9/9 (baseline-green holds)

**Dependencies**: 0.1

**Effort**: S

**Verify**: `./tests/run.sh` and `for v in 1 yes TRUE banana; do DRY_RUN=$v bash -c 'source lib/logging.sh; is_dry_run; echo "$v -> $?"'; done`

#### Task 1.7: Reproduce baseline-green in CI from a clean checkout and record it

**Description**: Milestone-enabling task for `M0`. With Task 0.1 landed the suite is hermetic, but
nothing yet asserts that a *clean checkout* reproduces 9/9 in CI rather than only on a developer
machine with warm state. Add or adjust the CI step so the suite runs from a fresh clone with the
stubs in place, and record the observed pass count as the plan's standing baseline. Every subsequent
P1–P4 task's baseline-green criterion is checked against this recorded run. Serves milestone M0.

**Closes**: — (milestone-enabling: M0)

**Acceptance Criteria**:
- [ ] A CI job clones the repository fresh and runs `./tests/run.sh`, reporting 9 of 9 files passed
- [ ] The same job asserts no Docker volume was removed and no package autoremoved during the run
- [ ] The recorded pass count appears in the job summary so a reviewer can read it without opening logs
- [ ] `./tests/run.sh` passes 9/9 locally (baseline-green holds)

**Dependencies**: 0.5

**Effort**: S

**Verify**: `gh run list --limit 1 --json conclusion,name` shows the clean-checkout suite job succeeding

## Phase P1 — Secure & Patch

**Goal:** make the declared quality gates real, then close the security findings that let a deletion
resolve to a target the user never named. · **Milestone M1:** zero known High or Critical advisories
against any pinned dependency (already true at audit — see W1 below), the lint gate runs at
`-S warning` with every remaining suppression individually justified, `main` is protected by a
ruleset requiring all five checks, and every deletion path is canonicalized before validation.

**Wave W1 is empty.** No vulnerability advisory affects any pinned dependency: mdoctor has no package
manifest in any ecosystem, and the report checked `actions/checkout` security advisories and found
none. There is nothing to patch. That is a real result, not a gap — this phase is therefore carried
entirely by wave W2 (ShellCheck version alignment, runner label pins and host-binary guards, 8
findings), the CI gate findings, and the security-hardening findings. `M1`'s advisory clause is
satisfied at entry and must be *re-checked at exit* via Dependabot (Task 1.5), not assumed.

### Sprint 2 — Make the declared gates real

#### Task 2.1: Raise the lint gate to `-S warning` and inventory the backlog

**Description**: `scripts/lint_shell.sh:30` runs `shellcheck -S error`, the weakest threshold, which
excludes exactly the warning and info checks that matter for this codebase — SC2086, SC2115 and the
read/find delimiter warnings are invisible to CI. A `-S warning` run is expected to surface that
SC2086/SC2115 class, but which specific findings it catches is unknown until it runs — and ShellCheck
has no rule for predictable temp-file naming, so `F-BUG-012` is not diagnosable by it at any band.
`set -e` additionally aborts the loop on the first failing
file, and files are passed one per invocation. **This is a measurement task: the number of findings
`-S warning` surfaces is unknown until it runs**, because ShellCheck was not installed on the audit
machine and the report's claim is argued from the lint policy line alone, not from a
measured backlog. Its output feeds Sprints 3, 4 and 12. Raise the band, pass all files to a single
invocation, drop the `set -e` abort, and record every remaining violation as either a fix or an
explicit per-line `# shellcheck disable=` with a one-line reason.

**Closes**: `F-BUG-037`

**Acceptance Criteria**:
- [ ] `scripts/lint_shell.sh` invokes `shellcheck -S warning` once with all discovered files as arguments, and does not abort on the first failing file
- [ ] `scripts/lint_shell.sh` exits 0, with the full violation inventory recorded: every remaining warning has either been fixed or carries a per-line disable comment naming the reason
- [ ] The inventory count is written into the task's PR description so later sprints can reference it
- [ ] `./tests/run.sh` passes 9/9 (baseline-green holds)

**Dependencies**: 1.7

**Effort**: S

**Verify**: `scripts/lint_shell.sh; echo $?` and `grep -c 'shellcheck disable' -r . --include='*.sh' --include=mdoctor`

#### Task 2.2: Make the lint script the single source of shell-file discovery

**Description**: The shell-file discovery and exclusion list is maintained in three parallel copies
that must be kept in sync by hand — `scripts/lint_shell.sh:11`, a verbatim `find` duplicate in the
workflow, and the same set as a regex in `.pre-commit-config.yaml`. They already differ in mechanism:
the two `find` copies match by name while the hooks rely on content detection, so a new extensionless
script is covered by a different subset of the three gates. The lists are also vestigial — the
`*-old.sh` pattern excludes two files deleted in February 2026, and two agent-tool directories are
excluded that have never appeared in any of the repo's 65 commits. Drop the three dead patterns from
all three files and have CI and the hooks derive discovery from the lint script.

**Closes**: `F-CI-018`, `F-DEAD-023`

**Acceptance Criteria**:
- [ ] `grep -rn '\-old\.sh' .pre-commit-config.yaml .github/workflows/ci.yml scripts/lint_shell.sh` returns nothing
- [ ] The workflow's syntax sweep invokes `scripts/lint_shell.sh` rather than duplicating its `find`
- [ ] Adding a new extensionless executable shell file under the repo root causes all three gates to pick it up, proven by a temporary file in a test run
- [ ] `./tests/run.sh` passes 9/9 (baseline-green holds)

**Dependencies**: 2.1

**Effort**: S

**Verify**: `scripts/lint_shell.sh` and `grep -n 'find\|lint_shell' .github/workflows/ci.yml`

#### Task 2.3: Align the ShellCheck versions and move the lint job to Ubuntu

**Description**: CI and the local hooks run different linter versions: the hook pins
`shellcheck-py/shellcheck-py` v0.10.0.1 (`.pre-commit-config.yaml:16`, latest v0.11.0.1-1) while CI
installs ShellCheck unpinned via Homebrew (`.github/workflows/ci.yml:18`), currently resolving to
0.11.0 by accident. So a contributor's hook and CI can disagree about the same file. Separately the
lint job runs on macOS and spends a step on `brew install shellcheck` — a slow formula install on the
most expensive runner class — although nothing in the job is macOS-specific and Ubuntu ships
ShellCheck preinstalled. Because lint is a prerequisite for all four other jobs, its latency gates
the whole pipeline.

**Closes**: `F-DEP-005`, `F-DEP-006`, `F-CI-014`

**Acceptance Criteria**:
- [ ] The hook revision and the CI ShellCheck version are the same explicit version string, greppable from both files
- [ ] The lint job's `runs-on` is Ubuntu and the `brew install shellcheck` step is deleted
- [ ] A CI run shows the lint job completing faster than the recorded macOS baseline, and all five jobs green
- [ ] `./tests/run.sh` passes 9/9 (baseline-green holds)

**Dependencies**: 2.1

**Effort**: S

**Verify**: `grep -n 'shellcheck' .pre-commit-config.yaml .github/workflows/ci.yml` and `gh run list --limit 1`

#### Task 2.4: Pin the runner images

**Description**: Both runner labels are floating. `macos-latest` (`.github/workflows/ci.yml:12`,
3 jobs) currently resolves to macOS 26 arm64 and moved silently from macOS 15 mid-2026;
`ubuntu-latest` (`:73`, 2 jobs) resolves to Ubuntu 24.04. Neither is deprecated, so this is pinning
for reproducibility rather than a forced migration — which is why it sits in W2 alongside the other
alignment work rather than in a major-upgrade wave. Pin both to explicit images.

**Closes**: `F-DEP-013`, `F-DEP-014`

**Acceptance Criteria**:
- [ ] `grep -c 'runs-on: .*-latest' .github/workflows/ci.yml` returns 0
- [ ] Every `runs-on:` names an explicit image (e.g. `macos-26`, `ubuntu-24.04`)
- [ ] A CI run on the pinned images is green across all five jobs
- [ ] `./tests/run.sh` passes 9/9 (baseline-green holds)

**Dependencies**: 1.4

**Effort**: S

**Verify**: `grep -n 'runs-on:' .github/workflows/ci.yml` and `gh run list --limit 1`

#### Task 2.5: Guard the host binaries and fix the inverted `ping -W` unit

**Description**: Four host binaries are used unguarded, and one is used incorrectly. `ping`
(`checks/network.sh:12`) passes `-W` with macOS milliseconds semantics, which on Linux iputils means
*seconds* — the unit is inverted, so the timeout is off by three orders of magnitude on the platform
v3.0.0 just added. `ss` (`checks/security.sh:152`, 3 sites), `ps` procps-ng long options
(`checks/performance.sh:66`, 7 sites) and `nslookup` (`checks/network.sh:30`, 2 sites) are all used
with no `command -v` guard, so a minimal container or a Debian install without `iproute2`,
`bind9-dnsutils` or full `procps` produces an error rather than a skip. This is wave W2.

**Closes**: `F-DEP-009`, `F-DEP-008`, `F-DEP-010`, `F-DEP-011`

**Acceptance Criteria**:
- [ ] `ping`'s `-W` argument is branched on platform, with the Linux branch expressed in seconds; a test asserts the constructed argv per platform
- [ ] Each of `ss`, `ps` (long options), `nslookup` and `ping` is preceded by a `command -v` guard whose absent branch reports a skip rather than an error
- [ ] With those four binaries removed from `PATH` in a stub environment, `./mdoctor check` exits 0 and reports skips for exactly those probes
- [ ] `./tests/run.sh` passes 9/9 (baseline-green holds)

**Dependencies**: 2.1

**Effort**: S

**Verify**: `./tests/run.sh` and a stub-`PATH` run of `./mdoctor check -m network -m security -m performance`

#### Task 2.6: Harden the workflow — permissions, timeouts, concurrency

**Description**: Three CI hygiene gaps in one file. The workflow declares no `permissions` block at
any level (`.github/workflows/ci.yml:9`), so all five jobs receive the repository's default token
scope — read/write across contents, issues and packages — including the job that executes the test
suite inside a third-party container pulled from a floating tag. No job declares a `timeout-minutes`
(`:51`), so each inherits the 6-hour default; the macOS test job's suite invocation has no per-step
timeout at all and that suite shells out to `docker system prune`, which can block on an unreachable
daemon, burning up to 6 hours of macOS runner time at roughly 10x the Linux rate against observed
healthy runs under 9 minutes. And there is no concurrency group (`:3`), so pushing twice to an open
PR leaves both runs executing — the history shows four consecutive superseded runs on one branch.

**Closes**: `F-CI-007`, `F-CI-009`, `F-CI-016`

**Acceptance Criteria**:
- [ ] A workflow-level `permissions: contents: read` block exists, with any per-job widening explicit and commented
- [ ] Every job declares `timeout-minutes: 15` or lower, and the macOS suite step declares a per-step timeout
- [ ] A `concurrency` group keyed on workflow and ref with `cancel-in-progress: true` exists
- [ ] Two pushes in quick succession to a branch leave exactly one run executing
- [ ] `./tests/run.sh` passes 9/9 (baseline-green holds)

**Dependencies**: 1.7

**Effort**: S

**Verify**: `grep -n 'permissions:\|timeout-minutes:\|concurrency:' .github/workflows/ci.yml` and `gh run list --limit 3`

#### Task 2.7: Protect `main`

**Description**: `main` has no branch protection — the protection API returns 404. Combined with the
workflow triggering on push to main, CI runs *after* a commit already lands: nothing requires the
five jobs to pass before merge, nothing requires review, nothing blocks a direct push. This compounds
with the installer cloning HEAD of main (`F-CI-012`), so any red commit is immediately live for every
curl-pipe user with no gate in between. Enable a ruleset requiring all five checks plus one approving
review, and block direct pushes.

**Closes**: `F-CI-003`

**Acceptance Criteria**:
- [ ] `gh api repos/:owner/:repo/rulesets` returns a ruleset targeting `main` (no longer 404 on protection)
- [ ] The ruleset requires all five CI jobs as status checks and one approving review, and blocks direct pushes
- [ ] A direct `git push` to `main` from a clean clone is rejected
- [ ] `./tests/run.sh` passes 9/9 (baseline-green holds)

**Dependencies**: 1.7

**Effort**: S

**Verify**: `gh api repos/:owner/:repo/rulesets --jq '.[].name'` and an attempted direct push

#### Task 2.8: Run the hooks in CI and delete the masking `chmod` steps

**Description**: `pre-commit run --all-files` is never executed in CI, and the config file is the
only tracked file in the repository that mentions pre-commit at all — neither the contributor guide
nor the development docs tell a contributor to install the hooks, so they are dormant for anyone who
does not discover them: the hook revisions drift undetected, the private-key detector (the repo's
only secret gate) never fires, and the CI syntax sweep silently duplicates the local hook. Separately
four `chmod +x` steps (`.github/workflows/ci.yml:48`) are dead work that masks a real regression —
every target is already mode 100755 in the index, and the hook pair already enforces the invariant, so
a lost mode bit would be papered over and reach users through the installer. Add a CI job running the
hooks over all files, which subsumes the ad-hoc sweep, and delete the `chmod` steps. Schedule via
`devops-pipeline`, which owns hook configuration. Sequenced after Task 0.1 by design — the report is
explicit that the hooks must not be run in CI until the destructive pre-push hook is fixed.

**Closes**: `F-CI-010`, `F-CI-017`

**Acceptance Criteria**:
- [ ] A CI job runs `pre-commit run --all-files` and is green
- [ ] `grep -c 'chmod +x' .github/workflows/ci.yml` returns 0
- [ ] Removing the executable bit from a tracked script causes CI to fail loudly rather than silently re-chmod
- [ ] `pre-commit install` appears in `CONTRIBUTING.md` and `docs/DEVELOPMENT.md`
- [ ] `./tests/run.sh` passes 9/9 (baseline-green holds)

**Dependencies**: 2.2, 2.3

**Effort**: S

**Verify**: run `devops-pipeline`, then `pre-commit run --all-files` and `gh run list --limit 1`

#### Task 2.9: Fix the `grep -c … || echo 0` double-fire

**Description**: `grep -c PATTERN || echo 0` double-fires: `grep -c` prints `0` *and* exits 1 on zero
matches, so the fallback appends a second `0` and the substitution captures `0\n0`. `(( x > 0 ))` on
that value prints an arithmetic syntax error to the user's terminal — and this fires on the *healthy*
path, which is the common case. Sites: `checks/security.sh:107,121`, `checks/updates.sh:36,47`.
Replace with `|| true`, since `grep -c` already emits 0 on no matches. Scheduled directly after Task
2.1 because it triages output from the same raised lint band, so the two share a working context. The
report makes no claim that this defect is mechanically catchable by ShellCheck.

**Closes**: `F-BUG-011`

**Acceptance Criteria**:
- [ ] All four sites use `|| true` and none uses `|| echo 0`; `grep -rn '|| echo 0' checks/` returns nothing
- [ ] `./mdoctor check -m security` and `./mdoctor check -m updates` on a healthy machine produce no arithmetic syntax error on stderr
- [ ] A test asserts stderr is empty for both modules on a zero-match input
- [ ] `./tests/run.sh` passes 9/9 (baseline-green holds)

**Dependencies**: 2.1

**Effort**: S

**Verify**: `./mdoctor check -m security 2>&1 >/dev/null | wc -c` returns 0, and `./tests/run.sh`

### Sprint 3 — Deletion-path integrity

#### Task 3.1: Reject symlinked arguments in `safe_remove_children`

**Description**: `lib/safety.sh:344`'s `safe_remove_children` validates only the literal string of its
argument, then tests `-d` (which follows symlinks) and globs the directory. If the argument is itself
a symlink to a protected directory, the glob expands *through* it and each child is passed as a path
whose final component is not a symlink and whose literal string is not in the protected list — so
both guards pass. Replacing a cache directory with a symlink to `Documents` makes a forced clean
delete the target's contents while reporting success. This is the classic cleanup-tool symlink escape
and it bypasses the entire protected-path list.

**Closes**: `F-SEC-004`

**Acceptance Criteria**:
- [ ] `safe_remove_children` returns the symlink rejection code when its argument is a symlink, before any glob expansion
- [ ] The function canonicalizes before validation and re-validates the canonical result
- [ ] A test plants a symlinked cache directory pointing at a protected path, runs a forced clean, and asserts the target's contents survive and the rejection code was returned
- [ ] `./tests/run.sh` passes 9/9 (baseline-green holds)

**Dependencies**: 0.4

**Effort**: M

**Verify**: `./tests/run.sh` and `bash tests/test_safety_validation.sh`

#### Task 3.2: Canonicalize every deletion path and make symlink allowance opt-in

**Description**: No deletion path is ever canonicalized — `realpath` and `readlink` appear nowhere
outside script-directory resolution (`lib/safety.sh:284`), so every protection operates on an
unresolved string, and there is a time-of-check-to-time-of-use window between the symlink test and
the removal in which a concurrent process can swap a parent component for a symlink to a protected
directory. Compounding it, `safe_find_delete` (`lib/safety.sh:396`) passes `--allow-symlink`
*unconditionally*, opting every find-based deletion into the flow that `:284-287` makes the guarded
default — while `docs/SAFETY.md:16` advertises symlink blocking as a safety layer and
`tests/test_safety_validation.sh:38` asserts it only against `safe_remove` called directly. Two of
the three deletion primitives never enforce the documented guarantee. Canonicalize before validation,
validate the canonical path, make symlink allowance a parameter defaulting to blocked, and where
possible delete relative to an opened directory handle rather than re-resolving an absolute path.

**Closes**: `F-SEC-005`, `F-BUG-036`

**Acceptance Criteria**:
- [ ] Every entry into `validate_deletion_path` canonicalizes first; `grep -c 'realpath\|readlink -f' lib/safety.sh` is ≥ 3 and covers all three deletion primitives
- [ ] `safe_find_delete` no longer passes `--allow-symlink` unconditionally; symlink allowance is an explicit parameter defaulting to blocked
- [ ] `tests/test_safety_validation.sh` asserts symlink blocking through all three primitives — `safe_remove`, `safe_remove_children` and `safe_find_delete` — not just the first
- [ ] `./tests/run.sh` passes 9/9 (baseline-green holds)

**Dependencies**: 3.1

**Effort**: M

**Verify**: `./tests/run.sh` and `bash tests/test_safety_validation.sh`

#### Task 3.3: Allowlist check-module names before sourcing

**Description**: `cmd_check` (`mdoctor:331`) builds the module file path straight from the CLI
argument with no allowlist, tests only that the file exists, and then *sources* it — executing its
top-level code. `./mdoctor check -m ../../../../tmp/payload` sources an arbitrary script. The two
sibling dispatchers already do this correctly, validating against a list and a literal case
respectively; only the check path was left unvalidated. The same file-existence validation also
produces a dead dispatch path (`mdoctor:371`): `check -m diagnose_performance` passes validation,
sources the file, then falls through a case with no matching arm — running nothing and exiting 0
silently — and the same case handles `apt` while both the help list and the unknown-module error omit
it. Replacing file-existence validation with membership in an explicit list fixes both.

**Closes**: `F-SEC-006`, `F-DEAD-027`

**Acceptance Criteria**:
- [ ] `./mdoctor check -m ../../../../tmp/payload` exits non-zero without sourcing anything, proven by a canary script that would leave a marker file
- [ ] Any module name containing `/` or `..` is rejected before the path is constructed
- [ ] `./mdoctor check -m diagnose_performance` either runs the module or exits non-zero with an unknown-module message — it never exits 0 having run nothing
- [ ] `./mdoctor check -m apt` on Linux is accepted and appears in both the help list and the unknown-module error text
- [ ] `./tests/run.sh` passes 9/9 (baseline-green holds)

**Dependencies**: 1.7

**Effort**: S

**Verify**: `./tests/run.sh` and `./mdoctor check -m ../../../../tmp/payload; echo $?`

#### Task 3.4: Validate history fields before arithmetic and tighten state-file modes

**Description**: `history_show` (`lib/history.sh:108`) parses score, warning and failure counts out of
stored JSON with parameter expansion and no numeric validation, then feeds them to Bash arithmetic —
and Bash arithmetic evaluates array subscripts, so a stored value shaped like `a[$(command)]` executes
that command when `mdoctor history` runs. Separately the config directory and operation log
(`lib/logging.sh:79`, plus three other creation sites) are created with a bare `mkdir -p` and a
truncating redirect, taking the ambient umask — typically world-readable — while the log records the
absolute path of every file removed and the full command line of every privileged command. On a
shared host any local user can read the victim's full home layout and privileged-command history.
There is no `umask` call anywhere in the codebase.

**Closes**: `F-SEC-012`, `F-SEC-016`

**Acceptance Criteria**:
- [ ] Each parsed history field is validated against `^[0-9]+$` before any arithmetic or format use, and a non-conforming entry is rejected with a message
- [ ] A test writes a history entry containing `a[$(touch /tmp/mdoctor_canary)]`, runs `./mdoctor history`, and asserts `/tmp/mdoctor_canary` does not exist
- [ ] The config directory is created mode 0700 and the operation log mode 0600 at all four creation sites; `stat -c %a` confirms both after a fresh run
- [ ] `./tests/run.sh` passes 9/9 (baseline-green holds)

**Dependencies**: 1.7

**Effort**: S

**Verify**: `./tests/run.sh` and `stat -c '%a %n' ~/.config/mdoctor ~/.config/mdoctor/*.log`

#### Task 3.5: Add secret scanning as a hook and a CI job

**Description**: There is no secret scanning and no static application security testing anywhere in
the pipeline. CI runs only ShellCheck, a syntax sweep and functional smoke tests; the hook config has
a private-key detector, which matches PEM headers only — it catches no API keys, cloud credentials,
bearer tokens or webhook URLs, and being a hook it guards only future commits on machines where hooks
are installed, never history. A manual scan of all 65 commits found no committed credentials and no
environment file ever added, so the history is currently clean; the gap is the absence of an enforced
gate, not an existing leak. Add a scanner as both a hook and a CI job, run it once over full history
to establish the clean baseline, and register the result as a required check on the Task 2.7 ruleset.

**Closes**: `F-SEC-018`

**Acceptance Criteria**:
- [ ] A secret scanner runs as a pre-commit hook and as a CI job, both green
- [ ] A full-history scan is run once and its clean result recorded in the PR description
- [ ] Committing a fake AWS-shaped key is blocked by the hook and, if pushed, fails the CI job
- [ ] The scanner job is listed as a required check in the `main` ruleset
- [ ] `./tests/run.sh` passes 9/9 (baseline-green holds)

**Dependencies**: 2.8

**Effort**: S

**Verify**: run `security-setup`, then `pre-commit run --all-files` and `gh api repos/:owner/:repo/rulesets --jq '.[].name'`

#### Task 3.6: Use NUL-delimited find in the stale-`node_modules` scan

**Description**: `cleanups/dev_caches.sh:135` reads `find` output newline-delimited with no
`-print0`. A directory whose name contains a newline splits across iterations and the first fragment
is a valid absolute unprotected path, so `safe_remove` accepts it. Reproduced: with
`important_project/` beside `important_project\nX/node_modules`, `safe_remove` received
`.../important_project`. The codebase already does this correctly at `cleanup.sh:163`. Add `-print0`
to the find and `read -r -d ''` to the loop, matching the existing correct site.

**Closes**: `F-BUG-007`

**Acceptance Criteria**:
- [ ] `cleanups/dev_caches.sh` uses `-print0` and `read -r -d ''`, matching `cleanup.sh:163`
- [ ] A test creates `important_project/` beside a sibling whose name contains a newline, runs the scan, and asserts `important_project` is never passed to `safe_remove`
- [ ] `grep -c 'find .* -print0' cleanups/dev_caches.sh` returns ≥ 1 and no bare newline-delimited `find | while read` loop feeding a delete remains in `cleanups/`
- [ ] `./tests/run.sh` passes 9/9 (baseline-green holds)

**Dependencies**: 3.2

**Effort**: S

**Verify**: `./tests/run.sh` and the newline-directory regression test

### Sprint 4 — Privileged surface and supply chain

#### Task 4.1: Install and self-update from signed release tags

**Description**: `install.sh:113` passes no branch to the clone, so every install takes the default
branch HEAD, and the update path pulls `main` explicitly — the four published release tags and their
GitHub releases are decorative, no user ever installs a tagged version, and every merge to main is
instantly the shipped version. There is no checksum, signature or tag pin, so a single malicious
commit is fetched and symlinked into a PATH directory with sudo. The self-update (`mdoctor:1250`) has
the same integrity gap on the path users hit repeatedly: no tag pinning, no signature, no checksum,
and the remote and branch come from environment variables — git accepts a URL wherever a remote name
is expected, so a URL-valued remote fetches attacker objects into the install directory before the
merge aborts. Clone the latest release tag by default with an opt-in channel for tracking main,
verify the tag against a published signing key, publish a checksum for the installer itself, and
validate the remote against configured remote names only.

**Closes**: `F-CI-012`, `F-SEC-020`

**Acceptance Criteria**:
- [ ] A default `./install.sh` run checks out the latest release tag, verified by `git -C "$INSTALL_DIR" describe --tags --exact-match` succeeding
- [ ] An opt-in channel flag or variable is required to track `main`, and is named in `--help`
- [ ] The self-update rejects a remote value that is a URL rather than a configured remote name, before any `git fetch` runs
- [ ] The release tag's signature is verified before merge, and the run fails closed if verification fails
- [ ] `./tests/run.sh` passes 9/9 (baseline-green holds)

**Dependencies**: 1.1

**Effort**: M

**Verify**: `./tests/run.sh` and a sandboxed `MDOCTOR_INSTALL_DIR=$(mktemp -d) ./install.sh` followed by `git -C "$MDOCTOR_INSTALL_DIR" describe --tags --exact-match`

#### Task 4.2: Validate the installer's environment overrides and refuse to clobber a non-symlink

**Description**: `install.sh:133` creates the symlink using the bin directory and binary name
verbatim from environment variables with no validation — no basename constraint, no charset
restriction, no check that the destination is a legitimate bin path. Anything that can seed the
installing shell's environment turns the installer's sudo into an arbitrary root-owned symlink write:
a binary name of `git` shadows a system binary on PATH, and a bin directory under the profile drop-in
path gets mdoctor executed for every login shell. The CI workflow shows setting these variables is
the supported invocation pattern, so the surface is intentional and unguarded. Separately
`install.sh:130`'s `ln -sf` clobbers whatever already exists at the bin path — a regular file,
another package's binary — with no check that it is mdoctor's own symlink, while `uninstall.sh:30`
*does* check.

**Closes**: `F-SEC-009`, `F-BUG-035`

**Acceptance Criteria**:
- [ ] The binary name is validated against a strict charset and any value containing `/` is rejected
- [ ] The bin directory is restricted to an allowlist or required to exist and end in `/bin`; a value outside that is rejected with a message
- [ ] When either override is set, the installer prints the exact `ln` command and requires confirmation
- [ ] `ln -sf` is replaced by a check that refuses to overwrite anything at the bin path that is not mdoctor's own symlink; a test plants a regular file there and asserts the install refuses
- [ ] `./tests/run.sh` passes 9/9 (baseline-green holds)

**Dependencies**: 1.1

**Effort**: S

**Verify**: `./tests/run.sh` and `MDOCTOR_BIN_NAME=git ./install.sh; echo $?` in a sandbox

#### Task 4.3: Replace the nine fixed `/tmp` filenames with `mktemp`

**Description**: Nine predictable `/tmp` filenames are opened with a plain `>` redirect
(`lib/logging.sh:18` and eight siblings), which follows symlinks. The highest-impact is `md_init`,
which truncates `/tmp/mdoctor_report_<timestamp>.md` and is the first statement of `doctor.sh`'s
main, so it runs on the tool's most-used command. Even without an attacker, a stale file owned by
another user makes `checks/devtools.sh:48` wrongly conclude the Docker daemon is unreachable.
`lib/safety.sh:379` already shows the correct `mktemp` pattern. Switch all nine to `mktemp` under a
per-user 0700 directory in one pass.

**Closes**: `F-BUG-012`

**Acceptance Criteria**:
- [ ] `grep -rn '> */tmp/mdoctor' . --include='*.sh' --include=mdoctor` returns nothing
- [ ] All nine sites obtain their path from `mktemp` under a per-user directory created mode 0700
- [ ] A test plants a root-owned-style stale file at the old predictable path and asserts `./mdoctor check -m devtools` is unaffected
- [ ] `./tests/run.sh` passes 9/9 (baseline-green holds)

**Dependencies**: 1.7

**Effort**: S

**Verify**: `./tests/run.sh` and `grep -rn '/tmp/mdoctor' . --include='*.sh' --include=mdoctor`

#### Task 4.4: Route every `fixes/` command through `run_cmd_args`

**Description**: `mdoctor fix` has no dry-run and no audit trail. A census across all ten
`fixes/*.sh` returns zero uses of `run_cmd_args`, `run_cmd`, `op_record`, `safe_remove` or
`validate_deletion_path` (`fixes/apt.sh:26`) — every sudo call executes directly, and none of
`fixes/apt.sh`'s six sudo calls checks exit status. So `clean` defaults to dry-run and writes an
operations log while `fix` — which runs `chown -R`, `apt-get upgrade -y`, `killall` and `mdutil -E /`
— offers neither preview nor record. The same family follows none of the conventions the other 33
modules follow (`fixes/disk.sh:16`): zero of 10 call `log`, `header` or `status_*`, they print raw
escape sequences, and `fix_disk` sets `DRY_RUN=false` unconditionally and then deletes, so
`mdoctor fix disk` deletes for real with no force flag while `mdoctor clean -m trash` is dry-run by
default. This is the single largest gap in the safety model and the reason the `fixes/` test lane
(Tasks 6.3–6.4) is worth writing.

**Closes**: `F-BUG-014`, `F-CLEAN-006`

**Acceptance Criteria**:
- [ ] `grep -rc 'run_cmd_args' fixes/ | grep -c ':0'` returns 0 — every fix module uses the wrapper
- [ ] `grep -rn 'DRY_RUN=false' fixes/` returns nothing
- [ ] With dry-run active, `./mdoctor fix all` executes zero privileged commands, proven by a stub-`PATH` argv recorder, and every intended command appears in the operations log
- [ ] Every fix module's success message is emitted only after a checked non-zero exit status test
- [ ] Every fix module uses `status_*`/`header` rather than raw escape sequences (`grep -rc $'\033' fixes/` returns 0)
- [ ] `./tests/run.sh` passes 9/9 (baseline-green holds)

**Dependencies**: 1.2, 1.6

**Effort**: M

**Verify**: `./tests/run.sh` and a stub-`PATH` `./mdoctor fix all` with the recorded argv compared against the operations log

#### Task 4.5: Delete the `bash -c` string-eval path

**Description**: `run_cmd_legacy` (`lib/logging.sh:221`) executes `bash -c "$cmd"`, an
eval-equivalent injection primitive, and `run_cmd` (`:234`) routes any single-argument call into it —
so `run_cmd docker` is an eval and `run_cmd docker prune` is not, from the same call-site shape, and
the names invert the intended default. `run_cmd` itself is never called, which makes `run_cmd_legacy`
transitively dead — a path the project's own P0.1 milestone declared eliminated. `CONTRIBUTING.md:67`
still instructs new contributors to write `run_cmd "rm -rf …"`, i.e. straight back into the dead eval
branch. Delete both functions and have `doc-manager` fix the contributor guide to show the argv form
and the safe primitives. Sequenced after Task 4.4 so no `fixes/` caller is stranded.

**Closes**: `F-BUG-033`, `F-DEAD-005`, `F-CLEAN-013`

**Acceptance Criteria**:
- [ ] `grep -rn 'run_cmd_legacy\|bash -c' lib/ cleanups/ fixes/ checks/ mdoctor cleanup.sh doctor.sh` returns no eval-shaped call
- [ ] `run_cmd` either does not exist or is a direct alias for the argv form with no argument-count overload
- [ ] `CONTRIBUTING.md:67` shows the argv form; `grep -c 'run_cmd "' CONTRIBUTING.md` returns 0
- [ ] `./tests/run.sh` passes 9/9 (baseline-green holds)

**Dependencies**: 4.4

**Effort**: S

**Verify**: run `doc-manager` on `CONTRIBUTING.md`, then `grep -rn 'run_cmd_legacy' .` and `./tests/run.sh`

#### Task 4.6: Stop running sudo inside read-only checks

**Description**: `checks/security.sh:96` runs `sudo ufw status` and `sudo iptables -L -n` in a file
whose header says "read-only, SAFE" — the only two places in the entire `checks/` tree where sudo
runs rather than being suggested. This can trigger a password prompt in the middle of a passive
audit, and when sudo fails the iptables branch has no fallback: it reports "no rules configured" and
advises the user to configure rules, a false negative about security posture. Use unprivileged status
where possible, or gate on `sudo -n true` and report "requires sudo to verify".

**Closes**: `F-BUG-019`

**Acceptance Criteria**:
- [ ] `grep -rn '^\s*sudo ' checks/` returns nothing that executes; any remaining occurrence is inside a suggestion string
- [ ] With sudo unavailable, `./mdoctor check -m security` reports "requires sudo to verify" rather than "no rules configured"
- [ ] `./mdoctor check -m security` never prompts for a password, proven by running with a stub `sudo` that would record an invocation
- [ ] `./tests/run.sh` passes 9/9 (baseline-green holds)

**Dependencies**: 1.7

**Effort**: S

**Verify**: `./tests/run.sh` and a stub-`sudo` run of `./mdoctor check -m security`

#### Task 4.7: Fix the EXIT-trap clobber and the history-command hang

**Description**: Two shared-library defects that silently break the audit trail and the history
command. `progress_start` (`lib/common.sh:96`) installs `trap 'progress_stop' EXIT`, silently
replacing the caller's EXIT trap — bash traps replace, they do not stack — so `cleanup.sh:130`'s
`trap _finish_cleanup_session EXIT` is clobbered by the first `step` call, `op_session_end` never
fires on any interactive run, and the operations log loses its session-end record. It is invisible to
tests because `progress_start` returns early when stdout is not a tty. Separately `lib/history.sh:77`
hangs forever if any single history file becomes unreadable: `line="$(cat "$file" …)" || continue`
jumps back to the loop *condition*, skipping the `i=$((i + 1))` at `:125` — the last statement in the
body — so the same index is retried indefinitely (reproduced in isolation; the loop had to be killed
by timeout).

**Closes**: `F-BUG-009`, `F-BUG-017`

**Acceptance Criteria**:
- [ ] `progress_start` installs no global EXIT trap; either a shared ordered exit-hook list installed once at top level exists, or the trap is removed
- [ ] A tty-simulating test (e.g. under `script`) asserts the operations log contains a session-end record after an interactive cleanup run
- [ ] `chmod 000` on one history file, then `timeout 10 ./mdoctor history` exits 0 within the timeout and skips that entry
- [ ] `./tests/run.sh` passes 9/9 (baseline-green holds)

**Dependencies**: 1.7

**Effort**: S

**Verify**: `./tests/run.sh` and `timeout 10 ./mdoctor history; echo $?` with one unreadable history file

## Phase P2 — Modernize

**Goal:** document the runtime floor as policy (W3), then take the two available majors one per task
(W4, W5), and remove the manual release ritual that makes any version bump a six-file edit.
· **Milestone M2:** every major current or deferred with written rationale — `actions/checkout` at
v7, `pre-commit-hooks` at v6, and the Bash 3.2 floor documented as a deliberate, enforced constraint
rather than neglect.

**P2 is deliberately small.** mdoctor has no package manifest, so there are only two majors in the
entire dependency surface and one runtime decision. Both majors have migration sources already
recorded in the report's dependency section — neither needs a spike.

### Sprint 5 — Runtime policy, the two majors, and release automation

#### Task 5.1: Document the Bash 3.2 floor and its banned-construct list (W3)

**Description**: Wave W3, and **no code change**. The Bash 3.2 floor (`docs/DEVELOPMENT.md:6`) is
deliberate and genuinely honoured: a full-text sweep of all 70 shell files found zero uses of any
Bash 4+ construct — no associative arrays, namerefs, `mapfile`, `${var^^}`, `&>>` or `coproc`. It is
not reported as an EOL-runtime Critical because the project ships no Bash of its own, the 3.2 path
executes only on macOS where Apple's vendored 3.2.57 cannot be upgraded by this project, and raising
the floor would break the zero-dependencies promise on the primary platform. Write that reasoning
down as policy with the explicit banned-construct list, so the constraint survives a contributor who
did not read the report.

**Closes**: `F-DEP-012`

**Acceptance Criteria**:
- [ ] A tracked policy section states the 3.2 floor, why it is deliberate, and enumerates the banned constructs: associative arrays, namerefs, `mapfile`/`readarray`, `${var^^}`/`${var,,}`, `&>>`, `coproc`
- [ ] The same list is referenced from `CLAUDE.md` and `CONTRIBUTING.md`
- [ ] A grep-based check for those constructs runs in CI or as a hook and passes on the current tree
- [ ] `./tests/run.sh` passes 9/9 (baseline-green holds)

**Dependencies**: 2.3

**Effort**: S

**Verify**: `./tests/run.sh` and the banned-construct grep check exiting 0

#### Task 5.2: Upgrade `actions/checkout` v4 → v7 (W4)

**Description**: Wave W4, one major per task. `actions/checkout` is at v4.4.0 across five refs
(`.github/workflows/ci.yml:15`); latest is v7.0.1 — three majors. Blast radius is low: five refs in
one workflow, no other consumer. **Migration source**: the `actions/checkout` release notes and
CHANGELOG for v5.0.0, v6.0.0 and v7.0.1, resolved live during the audit (the report's dependency
section records both the installed and latest versions from that lookup). No spike needed. Take the
three majors in one task because they are one action with one ref site pattern, but keep it isolated
from every other dependency change. Re-pin to the v7 commit SHA, preserving the Task 1.4 policy.

**Closes**: `F-DEP-001`

**Acceptance Criteria**:
- [ ] All five `actions/checkout` refs are pinned to the v7.0.1 commit SHA with `# v7.0.1` as a trailing comment
- [ ] Any input renamed or removed across v5/v6/v7 is accounted for — the workflow uses no input that the v7 release notes list as removed
- [ ] The one hard requirement in the v4→v7 span is recorded: v5.0.0's release notes set a **minimum compatible runner version of v2.327.1**. It is immaterial here because every job uses a GitHub-hosted runner, which is always at or above that version — assert `grep -c 'self-hosted' .github/workflows/ci.yml` returns 0, and record the floor in a workflow comment for whoever adds a self-hosted runner later
- [ ] A CI run on v7 is green across all five jobs, including the container job and release-sanity
- [ ] `./tests/run.sh` passes 9/9 (baseline-green holds)

**Dependencies**: 2.4

**Effort**: S

**Verify**: `grep -n 'actions/checkout' .github/workflows/ci.yml` and `gh run list --limit 1`

#### Task 5.3: Upgrade `pre-commit/pre-commit-hooks` v5 → v6 (W5)

**Description**: Wave W5, one major per task, ordered after W4 by blast radius: this touches 7 hooks
that every contributor runs locally, so it lands after the CI-only change. `.pre-commit-config.yaml:5`
pins v5.0.0; latest is v6.0.0. **Migration source**: the `pre-commit-hooks` v6.0.0 release notes,
resolved live during the audit. No spike needed. The live constraint in this bump is not a removed
hook — none of the 7 configured hook ids is among v6's removals — it is that **v6.0.0 raises the
Python floor to ≥ 3.9**. `pre-commit` builds each hook repo in its own virtualenv from the
interpreter it finds, so a contributor or a runner on Python 3.8 or older gets an environment-build
failure rather than a clear message. Check the floor explicitly rather than discovering it in
someone's first `git commit`. Sequenced after Task 1.5 so Dependabot is already watching this file,
after Task 2.3 so the hook and CI linter versions are already aligned, and after Task 2.8 so the CI
job that must go green on v6 exists before the bump.

**Closes**: `F-DEP-004`

**Acceptance Criteria**:
- [ ] `.pre-commit-config.yaml` pins `pre-commit/pre-commit-hooks` at `v6.0.0`
- [ ] Every one of the 7 configured hook ids still exists in v6, or its replacement is configured — no hook silently stops running
- [ ] The **Python ≥ 3.9** floor is satisfied and stated: `python3 -c 'import sys; assert sys.version_info >= (3,9)'` passes on every CI lane that runs the hooks, the floor is named in `CONTRIBUTING.md`'s hook-install step, and `.pre-commit-config.yaml` records it via `default_language_version` or an equivalent comment
- [ ] `pre-commit run --all-files` is green locally and in the Task 2.8 CI job
- [ ] `./tests/run.sh` passes 9/9 (baseline-green holds)

**Dependencies**: 1.5, 2.3, 2.8

**Effort**: S

**Verify**: `pre-commit run --all-files; echo $?` and `grep -n 'rev:' .pre-commit-config.yaml`

#### Task 5.4: Add a tag-triggered release workflow with one version source of truth

**Description**: There is no release workflow — cutting a release is a documented manual ritual, and
a version bump requires touching at least six sites by hand: the constant, a fallback literal in the
JSON library, the changelog, two places in the release notes, and a worked example in the deployment
doc. Nothing verifies these agree, so a partial bump ships a binary that misreports its own version.
Compounding it, `lib/json.sh:66` hardcodes the version as a fallback — a second copy of the constant
— so if the library is ever sourced without the dispatcher having set the variable, the output
silently reports a fabricated version, and the fallback keeps saying the old number after the constant
is bumped. Add a tag-triggered workflow reading the version from the constant as the single source of
truth, asserting every other site matches, and failing the build otherwise; drop the JSON fallback in
favour of failing loudly on an unset variable.

**Closes**: `F-CI-011`, `F-CI-019`

**Acceptance Criteria**:
- [ ] A tag-triggered workflow exists and fails when any of the six version sites disagrees with the constant, proven by a deliberate mismatch on a scratch branch
- [ ] `grep -c '3\.0\.0' lib/json.sh` returns 0 — the literal fallback is gone and an unset variable emits null or fails loudly
- [ ] Pushing a tag produces a GitHub release without any manual file edit beyond the constant and the changelog
- [ ] `./tests/run.sh` passes 9/9 (baseline-green holds)

**Dependencies**: 2.7

**Effort**: M

**Verify**: `gh workflow list` shows the release workflow, and a scratch-branch mismatch run fails

## Phase P3 — Clean & Harden

**Goal:** measure coverage for the first time, cover the 14 modules that never execute in any test,
then refactor the duplication and the implicit contracts that let all of this drift — each refactor
sitting on top of the tests that cover it.

**Milestone M3 — bound to evidence, no placeholders:**

| Clause | Bound value | Verified by |
|---|---|---|
| **Coverage** | Baseline coverage is **Not Assessed** (`kcov`/`bashcov` absent, repo-wide grep returns prose only), so per the plan rule the target is *"a coverage tool is configured and reports a number"*. Bound to **`kcov`** per `F-TEST-004`, wired into the Linux CI job with the HTML report published as an artifact and a no-fail baseline recorded. Task 6.1 establishes the number; the number itself is the milestone, and the ratchet minimum is set from it. | `kcov` artifact present on the latest CI run and a percentage printed in the job summary |
| **Duplication** | No tool measured duplication, so the threshold is: **no logic block identified in the `DEAD` findings survives at 3 or more sites.** Specifically — the **size formatter**: 1 implementation, not 9 (`F-CLEAN-009`); the **`du` probe**: 1 hardened helper, not 15 sites with 3 different error behaviours (`F-DEAD-012`, `F-BUG-008`); the **module list**: declared in 1 place, not 13 (`F-CLEAN-004`). | `grep -rc` counts for each of the three, from Tasks 8.1 and 8.2 |
| **Weak types** | The Bash analogue of `any` is `F-DEAD-020` (helpers returning data via `echo` with no error channel, so "not a directory", "timed out", "permission denied" and "genuinely empty" are indistinguishable) and `F-DEAD-021` (36 string-boolean comparison sites across 22 variables, tested three inconsistent ways). **Scope — these directories and files: `lib/`, `checks/storage.sh`, `mdoctor`, `cleanup.sh`.** Exit: zero echo-only-return helpers without a distinct failure return code in that scope, and one truthy predicate across all 36 sites. | Tasks 9.4 and 9.5; `grep -rc` for the old comparison forms returns 0 in the named scope |

### Sprint 6 — Measure coverage, and cover the most dangerous modules

#### Task 6.1: Configure `kcov` in CI and publish the first coverage number

**Description**: There is no coverage tooling of any kind — a repo-wide grep for `kcov`, `bashcov`,
`bats` or `shunit` returns only prose and two test message strings: no configuration, no dependency,
no CI step. The result is 778 lines of test against 7,481 lines of source with no mechanical way to
know which of the 53 modules a change touches; every coverage number in the audit had to be
reconstructed by hand from call graphs, and nothing prevents that picture from silently regressing.
Add `kcov` to the Linux CI job, publish the HTML report as an artifact, record a no-fail baseline,
then ratchet a minimum from it. **This task binds M3's coverage clause** — it establishes the number
that every later coverage claim is measured against.

**Closes**: `F-TEST-004`

**Acceptance Criteria**:
- [ ] The Linux CI job runs the suite under `kcov` and uploads the HTML report as a build artifact
- [ ] The job summary prints a coverage percentage; that number is recorded in the PR description as the M3 baseline
- [ ] A minimum threshold is configured at or just below the recorded baseline so the number cannot silently regress
- [ ] `./tests/run.sh` passes 9/9 (baseline-green holds)

**Dependencies**: 1.7

**Effort**: M

**Verify**: `gh run download --name coverage` on the latest run, then open the report; `gh run view --log | grep -i 'covered'`

#### Task 6.2: Migrate the runner to bats-core

**Description**: There is no test framework — `tests/run.sh:15` is a 30-line loop counting files, not
assertions. Costs: file-level granularity only, so 32 assertions report as one pass/fail; eight of
nine files use errexit so the first failing assertion aborts the file and hides every later one; no
filter, so iterating on one assertion requires running the whole suite; no TAP or JUnit output, so CI
can show no per-test annotation; no per-test timeout; and two incompatible failure semantics coexist
because one file sets different shell options from the other eight. Migrate to bats-core for
per-assertion reporting, filtering, JUnit output, fixtures and per-test timeouts, keeping the
existing `tests/helpers/assert.sh` as a shim during migration. Every task in Sprints 7–10 depends on
this, because per-assertion granularity is what makes the refactors verifiable.

**Closes**: `F-TEST-007`

**Acceptance Criteria**:
- [ ] `./tests/run.sh` delegates to bats-core and reports per-assertion results, not per-file
- [ ] The suite emits JUnit XML that CI renders as per-test annotations
- [ ] A named filter runs a single test without executing the rest of the suite
- [ ] Every test has a per-test timeout; a deliberately hanging test fails within it rather than blocking the run
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline — all assertions from the 9 files pass (baseline-green holds)

**Dependencies**: 6.1

**Effort**: M

**Verify**: `./tests/run.sh` and `./tests/run.sh --filter '<one test name>'`

#### Task 6.3: `fixes/` test lane, part 1 of 2 — harness and the five macOS-only targets

**Description**: All 10 modules in `fixes/` have zero test coverage
(`tests/test_e2e_safe_mode.sh:222` — the only fix invocations in the suite are two negative cases and
a help check; no test ever executes a real fix target). These are simultaneously the least covered
and most dangerous modules: they call sudo directly to chown `/usr/local`, erase the Spotlight index,
upgrade and autoremove packages, and cycle the Wi-Fi interface, and three are rated MED, the highest
risk grade in the project. **This is the plan's second Critical finding and it sits in early P3
rather than P0 deliberately.** The behavioural hazard is already neutralized by then: Task 1.2
platform-gates the dispatch, Task 1.3 guards the five macOS-only modules, and Task 4.4 routes every
fix through `run_cmd_args` so dry-run and the operations log apply. Writing the lane in P0 would also
have duplicated the stub-`PATH` harness that Task 0.1 builds and Task 6.2 makes per-assertion. Part 1
builds the harness — stub `PATH` with argv recorders — and covers `audio`, `disk`, `spotlight`,
`timemachine` and `wifi`.

**Closes**: `F-TEST-003` (part 1 of 2)

**Acceptance Criteria**:
- [ ] A reusable stub-`PATH` harness with argv recorders exists under `tests/helpers/` and is used by the new lane
- [ ] Each of `audio`, `disk`, `spotlight`, `timemachine` and `wifi` has a test asserting the exact command sequence it issues, per platform
- [ ] No test in the lane executes a real privileged command — the harness records argv and the recorded set is asserted to contain zero real `sudo` invocations
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 6.2

**Effort**: L (3 days)

**Verify**: run `test-coverage` on `fixes/`, then `./tests/run.sh --filter fixes`

#### Task 6.4: `fixes/` test lane, part 2 of 2 — remaining targets and the dry-run honour guard

**Description**: Part 2 of `F-TEST-003`. Covers the remaining five fix modules — `apt`, `bluetooth`,
`dns`, `permissions` and the tenth target — with the same argv-recording harness, and adds the guard
test the report asks for: **every** fix module honours dry-run. That guard is what stops the
`fixes/` family drifting back out of the safety layer after Task 4.4 puts it in, and it is the test
that would have caught `fixes/disk.sh`'s unconditional `DRY_RUN=false`.

**Closes**: `F-TEST-003` (part 2 of 2)

**Acceptance Criteria**:
- [ ] Each of the remaining five fix targets has a test asserting its exact command sequence per platform
- [ ] A parameterised guard test iterates every module in `fixes/` and asserts that with dry-run active it issues zero executing commands — adding an eleventh module with no dry-run support fails the suite
- [ ] `./mdoctor fix permissions` on Linux is asserted to issue no `chown`, closing the loop on Task 1.2
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 6.3

**Effort**: M

**Verify**: run `test-coverage` on `fixes/`, then `./tests/run.sh --filter fixes` and add a throwaway eleventh module to confirm the guard fails

#### Task 6.5: Make the whitelist test assert the rejection code, not file survival

**Description**: The whitelist-protection test passes for the wrong reason
(`tests/test_safety_validation.sh:49`): the call discards the return code entirely and the assertion
checks only that the file still exists, so it passes under any failure mode — a mistyped path, an
unloaded whitelist, a renamed function, an abort inside the function. The correct pattern is used
three times in the same file and was deliberately not used here. Compounding it, the test pokes a
private internal flag to force a cache reload, so renaming that variable turns the test into a silent
no-op. **This is the only test guarding the primary data-loss safeguard.** Capture the return code,
assert the exact whitelist rejection code, and expose a public reload entry point.

**Closes**: `F-TEST-008`

**Acceptance Criteria**:
- [ ] The test captures the return code and asserts the exact whitelist rejection value, not file existence
- [ ] Renaming the whitelist function causes the test to fail rather than pass
- [ ] A public reload entry point exists and the test uses it; `grep -c '_[A-Z_]*CACHE_LOADED' tests/` returns 0
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 6.2, 3.2

**Effort**: S

**Verify**: `./tests/run.sh --filter whitelist`, then rename the function on a scratch branch and confirm the test fails

#### Task 6.6: Assert per-module check behaviour and drop the macOS gate

**Description**: 20 of 22 check modules are covered only by a macOS-gated aggregate assertion whose
sole check is that the output contains "Health score" (`tests/test_e2e_safe_mode.sh:139`) — a single
summary string that would still match if 19 of the 20 sourced modules produced nothing. On Linux —
two of the three CI jobs and the platform this repo is developed on — 21 of 22 check modules never
execute, since the Linux job runs one module and the Bash 3.2 job runs no check command at all.
`checks/` is the largest body of code in the repo and is effectively untested off macOS. Replace the
aggregate assertion with a per-module loop asserting each module emits its own header and a parseable
status line, and drop the macOS gate by stubbing platform tools rather than skipping.

**Closes**: `F-TEST-006`

**Acceptance Criteria**:
- [ ] A per-module loop asserts every registered check module emits its own header and a parseable status line
- [ ] The macOS gate is removed; the loop runs on Linux with platform tools stubbed, and the Linux CI job exercises all platform-applicable check modules
- [ ] Making one check module produce no output causes the suite to fail naming that module
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 6.2

**Effort**: M

**Verify**: `./tests/run.sh --filter checks` and the coverage report from Task 6.1 showing `checks/` reached on Linux

### Sprint 7 — Cover the untested modules, the installer, and the fix history

`F-TEST-005` is effort `L` and the report asks for at least four tasks; it is split across 7.1–7.4.

#### Task 7.1: Untested modules, part 1 of 4 — the browser and dev cleanups

**Description**: 14 of 53 modules never execute in any test, on any platform. Two of them are the
`browser` and `dev` cleanup modules, reachable only via `clean -m` and the interactive menu, which no
test invokes — and `dev` is one of the two modules that reach `docker system prune -af --volumes`.
Add smoke and behaviour tests for both against the Task 6.3 stub harness.

**Closes**: `F-TEST-005` (part 1 of 4)

**Acceptance Criteria**:
- [ ] `clean -m browser` and `clean -m dev` each have a test asserting the module runs, emits its header, and issues the expected target set
- [ ] The `dev` test asserts `docker system prune` is not issued without the Task 0.6 opt-in flag
- [ ] The Task 6.1 coverage report shows both modules reached
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 6.2, 6.3

**Effort**: S

**Verify**: run `test-coverage` on `cleanups/browser.sh cleanups/dev.sh`, then `./tests/run.sh --filter cleanups`

#### Task 7.2: Untested modules, part 2 of 4 — the apt check and the benchmark library

**Description**: Part 2 of `F-TEST-005`. The `apt` check is sourced only under Linux while the only
full check run is macOS-gated, so it never executes in any test; `lib/benchmark.sh` is likewise never
exercised. Add coverage for both, using the Task 6.6 de-gated Linux path.

**Closes**: `F-TEST-005` (part 2 of 4)

**Acceptance Criteria**:
- [ ] `check -m apt` has a behavioural test running on the Linux CI lane, asserting its header and a parseable status line
- [ ] `lib/benchmark.sh` has a test exercising the disk and network benchmark entry points against stubs, asserting the reported units
- [ ] The Task 6.1 coverage report shows both reached
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 6.2, 6.6

**Effort**: S

**Verify**: run `test-coverage` on `checks/apt.sh lib/benchmark.sh`, then `./tests/run.sh --filter apt`

#### Task 7.3: Untested modules, part 3 of 4 — the two untested CLI commands

**Description**: Part 3 of `F-TEST-005`. Two CLI commands are entirely untested. Add smoke and
behaviour coverage for both, asserting exit status *and* an output assertion, so they do not join the
33 modules that run only as a side effect of an exit-status check.

**Closes**: `F-TEST-005` (part 3 of 4)

**Acceptance Criteria**:
- [ ] Each of the two commands has a test asserting exit status and at least one content assertion on its output
- [ ] The Task 6.1 coverage report shows both command paths reached
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 6.2

**Effort**: S

**Verify**: run `test-coverage` on `mdoctor`, then `./tests/run.sh` and the coverage artifact

#### Task 7.4: Untested modules, part 4 of 4 — behavioural assertions for the 33 exit-status-only modules

**Description**: Part 4 of `F-TEST-005`, and the task every P3 refactor depends on. Of the 39 modules
that do execute in the suite, only 6 have any behavioural assertion attached — the other 33 run as a
side effect of an exit-status check, so a module could produce nothing and stay green. Attach at
least one content assertion per module. **This is the "tests covering the code it touches"
precondition for Sprints 8–10**: the registry, disk-library, god-module, `check_storage` and context
refactors all depend on it.

**Closes**: `F-TEST-005` (part 4 of 4)

**Acceptance Criteria**:
- [ ] Every one of the 33 modules has at least one assertion on its output content, not only its exit status
- [ ] A parameterised guard fails the suite if any registered module has no content assertion, so a new module cannot be added without one
- [ ] The Task 6.1 coverage number increases against the recorded baseline, and the new value is recorded
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 6.6

**Effort**: M

**Verify**: run `test-coverage` on `checks/ cleanups/`, then `./tests/run.sh` and compare the coverage artifact against the Task 6.1 baseline

#### Task 7.5: Port the installer CI block into a real test file and matrix release-sanity

**Description**: `install.sh` and `uninstall.sh` have no test file. Their only coverage is 22 lines
of inline shell in the CI workflow, which cannot be run locally, lives outside the test directory, is
gated behind three other jobs so it never runs when an earlier one fails, and duplicates its recipe
in the development docs. This is the surface that produced three separate symlink-resolution fixes,
and it remains the one code path a user hits before anything else works. Separately release-sanity
runs only on macOS (`.github/workflows/ci.yml:116`), so the install/uninstall round trip is never
verified on Linux — although v3.0.0 is explicitly the cross-platform release, and the uninstaller
contains a platform-sensitive sudo fallback targeting a path that is standard on macOS but root-owned
on Debian. Port the block into a real test file using the same environment overrides, have CI call
it, matrix it across Ubuntu and macOS, and add cases for re-install over an existing install and
uninstall of a broken symlink.

**Closes**: `F-TEST-016`, `F-CI-004`

**Acceptance Criteria**:
- [ ] `tests/test_installer.sh` (or its bats equivalent) exists, runs locally, and covers fresh install, re-install over an existing install, uninstall, and uninstall of a broken symlink
- [ ] The workflow's inline 22-line block is deleted and the job invokes the test file instead
- [ ] Release-sanity runs on both `ubuntu-*` and `macos-*` in a matrix, both green
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 6.2, 4.2

**Effort**: S

**Verify**: `./tests/run.sh --filter installer` and `gh run view --json jobs --jq '.jobs[].name'`

#### Task 7.6: Cover the curl-pipe, remote-clone and update-in-place installer paths

**Description**: The release-sanity job sets the repo URL to the working directory
(`.github/workflows/ci.yml:134`), so it only ever exercises a local-path install. The installer
defaults to cloning the public HTTPS URL, and the documented distribution channel is a curl-pipe
one-liner. None of that is covered: not the remote clone, not the curl-pipe entry point where the
script runs with no argv and a non-tty stdin, and not the update-in-place branch with its re-clone
fallback. The installer is the product's only delivery mechanism, so a break there ships silently
while CI stays green. Add a job piping the committed installer through bash against a locally served
git repo over HTTP, covering fresh install, update and re-clone fallback plus a non-tty invocation.
Sequenced after Task 4.1 so the tag-pinning behaviour is what gets covered.

**Closes**: `F-CI-002`

**Acceptance Criteria**:
- [ ] A CI job serves the repository over HTTP locally and runs `curl … | bash` against the committed installer, asserting a working install
- [ ] The job covers update-in-place and the re-clone fallback branch, each asserted separately
- [ ] The curl-pipe case runs with a non-tty stdin and no argv, and is asserted not to hang on the Task 4.2 confirmation prompt
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 7.5, 4.1

**Effort**: M

**Verify**: `gh run view --json jobs --jq '.jobs[].name'` shows the curl-pipe job, green

#### Task 7.7: Backfill regression tests for the 11 untested bug fixes

**Description**: 11 of 13 behavioural bug fixes in the history landed with no regression test. Only
two have one, and both are the two that carried GitHub issue numbers — and one of those covers only
half its commit, because the test exports dry-run so the second half never executes. The 11 untested
fixes include two Bash 3.2 empty-array fixes, two spinner lifecycle fixes, and three separate
symlink-resolution fixes — the last being exactly what an absent regression test produces. Backfill a
test per commit, starting with the three symlink fixes as one shared test and the two empty-array
fixes, and add a checklist item requiring a test reference for any fix commit.

**Closes**: `F-TEST-014`

**Acceptance Criteria**:
- [ ] Each of the 11 fix commits has a named regression test referencing its commit SHA in a comment
- [ ] The three symlink fixes are covered by one shared test, and the two empty-array fixes each have a Bash 3.2-compatible test that runs in the container job
- [ ] The existing half-covered test no longer exports dry-run, so its second half executes
- [ ] The PR checklist requires a test reference for any fix commit
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 6.2

**Effort**: M

**Verify**: `./tests/run.sh` and `grep -c 'regression for' tests/` returning ≥ 11

#### Task 7.8: Move every test sandbox to a shared home-scoped fixture root

**Description**: Four of nine test files build their sandbox inside the developer's real home rather
than under a temp directory (`tests/test_dry_run_semantics.sh:9`); the other four use `mktemp -d`, so
the suite is internally inconsistent. The choice is deliberate — the protected-path check rejects any
target under the macOS temp root — but the cost is unmitigated: cleanup depends solely on an EXIT
trap, which bash does not run for an untrapped SIGTERM, so the CI timeout wrappers and any interrupt
leave test directories behind in the real home with nothing to sweep them. Separately
`tests/test_cleanup_scope_empty_excludes.sh:12` writes into the repository working tree, and
`git check-ignore` confirms the pattern is matched by no rule, so an interrupted run leaves an
untracked directory that `git add -A` can sweep into a commit. And the Bash 3.2 job's skip guard does
not fire (`tests/test_e2e_safe_mode.sh:19`) because it probes two utilities busybox provides in that
image — so the end-to-end test does not skip there despite the comment naming that image as the
reason the guard exists.

**Closes**: `F-TEST-012`, `F-TEST-013`, `F-TEST-017`

**Acceptance Criteria**:
- [ ] A shared fixture helper sets one home-scoped temp root and every test file uses `mktemp -d` under it; `grep -rc 'mktemp -d' tests/` covers all files and no file writes into the repo working tree
- [ ] Traps cover INT and TERM as well as EXIT, and a startup sweep removes stale fixture directories
- [ ] `kill -TERM` on a running test leaves no directory behind under the real home or the working tree; `git status --porcelain` is clean after an interrupted run
- [ ] The Bash 3.2 skip guard is an explicit capability check or job-set flag, not a utility probe, and the Bash 3.2 job asserts on output rather than exit status
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 6.2

**Effort**: S

**Verify**: `./tests/run.sh`, then interrupt a run with `kill -TERM` and check `git status --porcelain` and `ls ~/`

#### Task 7.9: Replace the tautological, conditional and warning-only assertions

**Description**: Four related test-quality defects. Eight of the twenty end-to-end sub-tests assert
nothing beyond exit status (`tests/test_e2e_safe_mode.sh:167`); the JSON test is the only one in the
repo and never parses the output, so the entire JSON emitter could emit malformed JSON and the suite
would stay green; two negative cases assert only a non-zero exit, never that the right error was
reported; and two assertions are tautological, checking for a file the preceding redirection just
created. The report-generation check (`:147`) is downgraded to a warning that can never fail — it
prints to stderr and never increments the failure counter, so "a markdown report is written" is
permanently unasserted. `tests/test_diagnose.sh:133` wraps its recommendation check in a guard that
is false on a healthy idle machine, so the block never runs while the pass line fires having asserted
nothing, and its status-indicator check accepts a five-way alternation where one branch matches
essentially any output. `tests/test_interactive_cleanup.sh:28` pipes `1` to the menu, depending on
position 1 of an array literal being `trash` — reordering that array silently repoints a force
cleanup at a different module, and if `dev_caches` moved to position 1 this test would run
`docker system prune -af --volumes` on the developer's machine.

**Closes**: `F-TEST-009`, `F-TEST-010`, `F-TEST-011`, `F-TEST-015`

**Acceptance Criteria**:
- [ ] The JSON output is piped through a real parser and the schema asserted; malformed JSON fails the suite
- [ ] Both negative cases assert the specific error text, and the two tautological checks are replaced with content assertions
- [ ] The report-generation check asserts on a deterministic path supplied by an environment override; the warning branch is deleted and the failure counter increments on failure
- [ ] `tests/test_diagnose.sh` feeds fixed inputs via injectable metric sources so both branches are asserted, and the five-way alternation is narrowed
- [ ] `tests/test_interactive_cleanup.sh` derives the menu index from the rendered output and asserts the selected module name appears in the run output
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 6.2

**Effort**: M

**Verify**: `./tests/run.sh`, then reorder the module array on a scratch branch and confirm the interactive test still selects `trash`

### Sprint 8 — One source of truth

Every task in this sprint is a refactor and depends on Task 7.4, the behavioural assertions covering
the code it touches.

#### Task 8.1: Make the module registry the single source of truth

**Description**: The cleanup module list is maintained by hand in seven places and the check list in
six — array, descriptions, dispatch case, help text, two error messages, pre-flight case, plus the
source list and call sequence in `cleanup.sh`, plus two separate registries: 13 places in total. They
have already drifted — `apt` is registered as a cleanup module but absent from the help list and from
both "Available modules" error messages (`mdoctor:483`). Move the registry into one library file as
the single source of truth and derive the source list, dispatch, call sequence, help and error text
from it via the lookup function that already exists and is unused. **This closes M3's duplication
clause for the module list: 1 declaration, not 13.**

**Closes**: `F-CLEAN-004`

**Acceptance Criteria**:
- [ ] The cleanup and check module lists are declared in exactly one library file; `grep -rc '\btrash\b.*\blogs\b' --include='*.sh' --include=mdoctor .` shows one declaration site, not 13
- [ ] `apt` appears in the help list and both "Available modules" error messages, derived rather than typed
- [ ] Adding a module to the registry alone makes it appear in `./mdoctor list`, the help text, both error messages and the dispatch, proven by a throwaway module
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 7.4

**Effort**: M

**Verify**: `./tests/run.sh` and adding a throwaway module, then `./mdoctor list && ./mdoctor clean --help`

#### Task 8.2: Extract one disk library — one formatter, one hardened `du` probe

**Description**: One concept, several names and several definitions (`lib/disk.sh:18`): two
near-identical size formatters in the same file differing only in negative-input handling, a third
name wrapping the second, and the same ladder re-inlined four more times — 9 implementations with 3
different precisions. Two pre-flight sizing helpers are duplicated under different names, and two
timestamp functions are byte-identical. The `du` probe is worse: issue #9 was fixed only inside
`cleanup.sh`, so the unhardened `du -sk … | awk` pattern survives at eight sites
(`cleanups/dev_caches.sh:27,122`, `cleanups/xcode.sh:16,50`, `cleanups/ios_backups.sh:29`,
`checks/storage.sh:33,51`, `checks/diagnose_performance.sh:364`), and the two size helpers in
`mdoctor` (`mdoctor:120`) are copies of the `cleanup.sh` pair that never received the fix — under
`cleanup.sh`'s `set -e` a permission-denied subdirectory aborts the run mid-cleanup after Trash and
caches are already deleted, while under `mdoctor`'s `set -uo pipefail` the value is empty so the
cache is silently skipped and success is reported. `mdoctor:149` adds an unreachable defensive branch
guarding a function that is always defined, which is also the third copy of the formatter. **This
closes two of M3's three duplication clauses.**

**Closes**: `F-CLEAN-009`, `F-DEAD-012`, `F-BUG-008`, `F-DEAD-016`

**Acceptance Criteria**:
- [ ] Exactly one size-formatter ladder exists and it lives in `lib/disk.sh`: no other file re-inlines the GB/MB/KB ladder, verified by `grep -rln '1048576\|MDOCTOR_KB_PER_GB' --include='*.sh' --include=mdoctor . | grep -v 'lib/disk.sh'` listing only files where the value is a bare threshold, never a formatter. 1 implementation, not 9. (Stated against either the literal or the named constant so this holds whether or not Task 8.7 has already replaced the literals; the global count-to-1 assertion belongs to 8.7)
- [ ] Exactly one hardened `du` helper exists in `lib/disk.sh` and all 10 former call sites call it; `grep -rn 'du -sk' . --include='*.sh' --include=mdoctor` shows only that helper
- [ ] One timestamp function remains, and the unreachable guard and fallback at `mdoctor:149` are deleted
- [ ] A regression test covers the single-module pre-flight path with a permission-denied subdirectory, under both `cleanup.sh` and `mdoctor`, asserting a numeric result and no abort
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 7.4

**Effort**: M

**Verify**: `./tests/run.sh` and `grep -rn 'du -sk' . --include='*.sh' --include=mdoctor`

#### Task 8.3: Split the `mdoctor` god module, part 1 of 2 — registry and pre-flight out

**Description**: `mdoctor` is a 1379-line dispatcher holding four unrelated concerns
(`mdoctor:939`): a 43-call module registry, 76 lines of hand-maintained help copy, a 111-line disk-size
estimator that re-implements `cleanup.sh:168-250`, and 27 lines of actual dispatch. The registry and
renderer being fused already produces a wrong number on screen. Part 1 extracts the registry into the
module Task 8.1 created and the pre-flight estimator into a shared module both entry points source,
retiring the `mdoctor`-local duplicate of `cleanup.sh`'s estimator.

**Closes**: `F-CLEAN-001` (part 1 of 2)

**Acceptance Criteria**:
- [ ] The registry and the pre-flight estimator live in sourced library files; `wc -l mdoctor` is reduced by at least the 111 estimator lines plus the registry block
- [ ] `cleanup.sh` and `mdoctor` produce byte-identical pre-flight estimates for the same target set, asserted by a test
- [ ] No estimator logic remains duplicated between `mdoctor` and `cleanup.sh`
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 8.1

**Effort**: M

**Verify**: run `code-review mode:clean` on `mdoctor`, then `./tests/run.sh` and `wc -l mdoctor`

#### Task 8.4: Split the `mdoctor` god module, part 2 of 2 — help rendered from the registry

**Description**: Part 2 of `F-CLEAN-001`. Extracts the 76 lines of hand-maintained help copy into a
help module rendered from the registry, leaving `mdoctor` as dispatch. That also closes two findings
the fusion causes. `mdoctor:279` holds five copies of the same parse-plus-inline-help block — five
identical option loops, five identical debug-flag blocks, and 176 lines of help copy embedded in
those parsers, whose hand-typed counts are wrong on Linux. And `mdoctor:1016` prints three different
user-facing counts for the same thing, none correct: "Check Modules (${_MOD_COUNT} — all read-only)"
uses a counter incremented for every module of every type, observed as "Check Modules (30 …)" above a
list of 17; `:1277` says "21 checks"; `:1279` says "fix (9 targets)" while the Linux branch lists 3.
Actual: 17 on Linux, 20 on macOS. Derive every count from the platform-filtered registry at render
time, per type.

**Closes**: `F-CLEAN-001` (part 2 of 2), `F-CLEAN-012`, `F-UX-007`

**Acceptance Criteria**:
- [ ] Help copy lives in per-command usage functions outside the parse loops, and a single shared common-flag parser replaces the five duplicated option loops
- [ ] Every user-facing count is computed from the platform-filtered registry; on Linux `./mdoctor list` reports 17 check modules and the number above the list equals the number of rows listed
- [ ] `./mdoctor help`, `check --help` and `clean --help` report counts that match `./mdoctor list` on the running platform, asserted by a test that compares them
- [ ] `grep -c '21 checks\|9 targets' mdoctor` returns 0
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 8.3

**Effort**: M

**Verify**: run `code-review mode:clean` on `mdoctor`, then `./mdoctor list | tail -n +2 | wc -l` compared against the printed count

#### Task 8.5: Hoist `cmd_clean`'s nested helpers to library scope

**Description**: `cmd_clean` (`mdoctor:422`) is 290 lines and defines four functions inside its own
body, one of them 83 lines, with a fifth closure nested inside the pre-flight function. These are
file-scope helpers scoped inside a command handler purely to reach the module array as a closure
variable, so none is unit-testable or reusable. Hoist all four to file or library scope and pass the
module list explicitly; `cmd_clean` then reduces to argument parsing plus three dispatch branches.

**Closes**: `F-CLEAN-002`

**Acceptance Criteria**:
- [ ] Zero function definitions remain inside `cmd_clean`'s body; `awk` over the function's line range finds no nested `()` definition
- [ ] Each hoisted helper takes the module list as an explicit parameter and has at least one unit test calling it directly
- [ ] `cmd_clean` is under 60 lines
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 8.4

**Effort**: M

**Verify**: run `code-review mode:clean` on `mdoctor`, then `./tests/run.sh`

#### Task 8.6: Break `check_storage` into six scans and one reporter

**Description**: `check_storage` (`checks/storage.sh:65`) is 255 lines at 5 levels of nesting. It
repeats the same measure-compare-classify-report block eight times and carries an index-alignment
hack: parallel label and path arrays with three empty placeholder slots
(`checks/storage.sh:234`), walked from a magic starting index — so adding a cache to the front of
either array silently mislabels every row. Extract one report helper carrying the threshold logic,
replace the parallel arrays with a single delimited list, split the six scan categories into six
functions, and drop the placeholders and the offset.

**Closes**: `F-CLEAN-003`, `F-DEAD-019`

**Acceptance Criteria**:
- [ ] `check_storage` is under 60 lines and delegates to six named scan functions plus one report helper
- [ ] The parallel arrays are replaced by a single delimited list with no empty placeholder entries and no magic starting index
- [ ] Inserting a new cache entry at the front of the list produces correctly labelled output, asserted by a test
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 7.4, 8.2

**Effort**: M

**Verify**: run `code-review mode:clean` on `checks/storage.sh`, then `./tests/run.sh --filter storage`

#### Task 8.7: Add a named-constants library

**Description**: Size and threshold constants are bare literals throughout
(`checks/diagnose_performance.sh:129`): `1048576` appears 34 times across 8 files, `1024` 27 times,
`102400` 8 times in one file. The diagnose module carries roughly 30 untunable thresholds inline in
conditionals with no named constant and no config surface. `lib/benchmark.sh` states the same
constant twice, so changing one silently corrupts the reported throughput. `lib/safety.sh` shows the
codebase can do this right, yet its own renderers then match on raw numbers instead of the constants
defined ten lines above. Add a constants library with named size, threshold and timeout values, make
the safety renderers switch on the named constants, and derive the benchmark size from its count.

**Closes**: `F-CLEAN-008`

**Acceptance Criteria**:
- [ ] A constants library declares the size, threshold and timeout values; `grep -rc '1048576' --include='*.sh' --include=mdoctor .` returns 1 (the definition)
- [ ] `lib/safety.sh`'s name and hint renderers reference the named error constants, not numeric literals
- [ ] The benchmark size is derived from its block count and appears once, not twice
- [ ] Diagnose thresholds are named constants overridable by documented environment variables
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 7.4

**Effort**: M

**Verify**: `./tests/run.sh` and `grep -rn '1048576\|102400' . --include='*.sh' --include=mdoctor`

### Sprint 9 — Explicit contracts

#### Task 9.1: Introduce an explicit module context initializer, part 1 of 2

**Description**: Hidden global variables are the de-facto parameter list for all 53 modules, which
take zero arguments (`mdoctor:341`): callers must pre-seed 11 globals before sourcing, with no
declared contract — the coupling is visible only as 28 `# shellcheck disable=SC2034` suppressions,
each marking a variable the linter cannot see being consumed in another file. Omitting any one
produces a silent wrong result rather than an error. Part 1 defines and documents the contract as an
explicit initializer and wires all three entry points (`mdoctor`, `cleanup.sh`, `doctor.sh`) through
it, failing loudly when a required input is unset.

**Closes**: `F-CLEAN-007` (part 1 of 2)

**Acceptance Criteria**:
- [ ] A documented context initializer declares all 11 inputs with their types and defaults, and is called by all three entry points
- [ ] Sourcing a module without the initializer having run fails with a named-variable error rather than producing a wrong result, asserted by a test
- [ ] The contract is greppable: one file lists every required input
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 8.4

**Effort**: M

**Verify**: `./tests/run.sh` and `bash -c 'source cleanups/trash.sh; clean_trash'` failing with a named-variable error

#### Task 9.2: Introduce an explicit module context initializer, part 2 of 2

**Description**: Part 2 of `F-CLEAN-007`. With the contract declared, remove all 28
`# shellcheck disable=SC2034` suppressions — each of which exists only because the linter cannot see
a variable consumed in another file — and add a header comment to each module directory naming its
required inputs. That makes the coupling greppable rather than implicit, and it is what lets the
raised lint band from Task 2.1 actually see this code.

**Closes**: `F-CLEAN-007` (part 2 of 2)

**Acceptance Criteria**:
- [ ] `grep -rc 'shellcheck disable=SC2034' . --include='*.sh' --include=mdoctor` returns 0
- [ ] `scripts/lint_shell.sh` at `-S warning` still exits 0 with those suppressions removed
- [ ] Each of `checks/`, `cleanups/` and `fixes/` carries a header comment naming the context inputs its modules require
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 9.1

**Effort**: M

**Verify**: `scripts/lint_shell.sh; echo $?` and `grep -rc 'SC2034' .`

#### Task 9.3: Define one return-code contract and replace the 24 `|| true`

**Description**: Three different return-code contracts exist across the three module families and the
cleanup one is inert (`mdoctor:575`): the cleanup dispatcher builds a per-module return code and maps
non-zero to an error session end, but 9 of 11 cleanup modules terminate every destructive call with
`|| true` and so always return 0; `cmd_check` discards check exit codes entirely; `cmd_fix` captures
and returns them. All 24 deletion call sites (`cleanups/crash_reports.sh:20` and siblings) discard
the safety layer's six-value error taxonomy and its `safety_error_name`/`safety_error_hint`
renderers, so no caller can distinguish "freed 40 GB" from "every target was blocked" — on Linux
`platform_crash_dirs` yields `/var/crash`, which is blocked with code 22, and the module swallows it
and reports success while cleaning nothing. Define one contract in the contributor guide, replace
`|| true` with `|| rc=$?` plus a case distinguishing expected skips from real failures, use a
per-module accumulator so partial failures propagate, and apply the capture `cmd_fix` already does to
`cmd_check`.

**Closes**: `F-CLEAN-014`, `F-BUG-010`

**Acceptance Criteria**:
- [ ] `grep -rc '|| true' cleanups/` returns 0 for deletion call sites; each uses `|| rc=$?` with a case over the error taxonomy
- [ ] On Linux, `clean -m crash_reports` where every target is blocked exits non-zero and reports "blocked" rather than success, asserted by a test
- [ ] `cmd_check` captures and returns module exit codes, matching `cmd_fix`
- [ ] The single return-code contract is documented in `CONTRIBUTING.md`
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 7.4, 4.4

**Effort**: M

**Verify**: `./tests/run.sh` and `./mdoctor clean -m crash_reports --force; echo $?` in a sandbox where every target is protected

#### Task 9.4: Give the echo-returning helpers a real error channel

**Description**: The Bash analogue of `any` (`checks/storage.sh:28`): functions that return data
through `echo` with no error channel, so failure is indistinguishable from an empty result. The
directory-size helper returns `0` for "not a directory", "timed out", "permission denied" and
"genuinely empty" alike, and every caller treats `0` as "nothing to report". The same shape appears
at five more helpers. One function in the codebase does it correctly, with distinct return codes.
**This is half of M3's weak-type clause, scoped to `lib/`, `checks/storage.sh`, `mdoctor` and
`cleanup.sh`.** Give each size and lookup helper a non-zero return on failure and have callers
distinguish it, following the one correct example.

**Closes**: `F-DEAD-020`

**Acceptance Criteria**:
- [ ] All six helpers in the named scope return a distinct non-zero code for each of "not a directory", "timed out" and "permission denied", and 0 only for a genuine measurement
- [ ] Every caller distinguishes failure from an empty result and reports "could not determine" rather than 0
- [ ] A test exercises all four outcomes for the directory-size helper and asserts the distinct codes
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 8.2, 7.4

**Effort**: M

**Verify**: `./tests/run.sh --filter storage` and `bash -c 'source lib/disk.sh; dir_size_kb /nonexistent; echo $?'`

#### Task 9.5: Normalise the 36 string-boolean comparison sites onto one predicate

**Description**: The debug flag is a string-typed boolean tested three inconsistent ways
(`lib/logging.sh:41`) — one site accepts both `true` and `1`, another accepts only `"true"` — so
setting it to `1` enables debug logging but not the update command's debug branch. There are 36 such
string-boolean comparison sites across 22 variables. **This is the other half of M3's weak-type
clause, in the same scope: `lib/`, `checks/storage.sh`, `mdoctor`, `cleanup.sh`.** Roll out the
`is_dry_run`-style predicate created in Task 1.6 across all 36, with one accepted truthy set.

**Closes**: `F-DEAD-021`

**Acceptance Criteria**:
- [ ] One truthy predicate is used at all 36 sites; `grep -rEc '= *"?(true|1|yes)"?' lib/ checks/storage.sh mdoctor cleanup.sh` shows no remaining ad-hoc boolean comparison
- [ ] Setting any of the 22 variables to `1`, `yes` or `TRUE` produces identical behaviour to `true`, asserted by a parameterised test
- [ ] An unrecognised value warns and fails closed for every one of the 22
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 1.6, 7.4

**Effort**: S

**Verify**: `./tests/run.sh` and `for v in 1 yes TRUE; do MDOCTOR_DEBUG=$v ./mdoctor update --help >/dev/null && echo "$v ok"; done`

### Sprint 10 — Retire duplication and dead code

#### Task 10.1: Extract the shared performance probes, part 1 of 2 — load, CPU, memory

**Description**: The 702-line diagnose module re-implements five checks the 167-line performance
module already performs (`checks/diagnose_performance.sh:394`) — load average, top CPU consumers,
memory pressure, swap and zombie processes. One five-line block is byte-identical between the two
files; the surrounding routines differ only by a sort flag and which action-collector they call. Both
run in the same process on a full check plus diagnose session. Part 1 extracts the load-average,
top-CPU and memory-pressure probes into one module both check functions call, with the reporting sink
passed in.

**Closes**: `F-DEAD-015` (part 1 of 2)

**Acceptance Criteria**:
- [ ] Load average, top CPU consumers and memory pressure are each implemented once, in a shared probe module, with the reporting sink passed as a parameter
- [ ] Both `check_performance` and the diagnose module call the shared probes; the byte-identical five-line block exists once
- [ ] Output of `./mdoctor check -m performance` and `./mdoctor diagnose` is unchanged for those three probes, asserted against captured fixtures
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 9.2

**Effort**: M

**Verify**: `./tests/run.sh` and a fixture diff of `./mdoctor diagnose` before and after

#### Task 10.2: Extract the shared performance probes, part 2 of 2 — swap, zombies, retire the duplicates

**Description**: Part 2 of `F-DEAD-015`. Extracts the swap and zombie-process probes on the same
pattern, then deletes the now-unreachable duplicate routines from
`checks/diagnose_performance.sh`, bringing the 702-line module down to the diagnosis logic that is
genuinely its own.

**Closes**: `F-DEAD-015` (part 2 of 2)

**Acceptance Criteria**:
- [ ] Swap and zombie-process probes are implemented once in the shared module and called from both check functions
- [ ] The duplicate routines are deleted; `wc -l checks/diagnose_performance.sh` is reduced by at least 150 lines against the audited 702
- [ ] Output of both commands is unchanged for those probes, asserted against captured fixtures
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 10.1

**Effort**: M

**Verify**: `./tests/run.sh` and `wc -l checks/diagnose_performance.sh`

#### Task 10.3: Retire `dev` into `dev_caches` and resolve the commented-out steps

**Description**: `clean_dev_stuff` (`cleanups/dev.sh:7`) is roughly 90% subsumed by
`clean_dev_caches` — both clear the same npm, pip and pnpm paths and both end with the identical
`docker system prune -af --volumes`, so selecting "all" in interactive mode runs the prune twice. The
only unique work is two Homebrew commands and one Linux yarn path. Separately `cleanup.sh:316`
carries commented-out step calls for the browser and dev modules while still sourcing both files, so
a full `mdoctor clean` runs 8 of 10 modules on macOS and 7 of 9 on Linux while the docs claim all 10.
`cleanup.sh:99` defines `step()` a second time, shadowing the library definition after sourcing it,
maintaining a second counter pair mirrored back into the first, with a hand-maintained literal total
the commented block asks future editors to bump. `cleanup.sh:353` passes already-shifted arguments to
`main`, and `cleanup.sh` is the only tab-indented file in the repo — 208 tab-indented lines against
2-space indentation in the other 58 files, plus 58 comments restating the next line.

**Closes**: `F-DEAD-011`, `F-DEAD-009`, `F-DEAD-029`, `F-DEAD-030`, `F-CLEAN-016`

**Acceptance Criteria**:
- [ ] The three unique `dev` targets are folded into `clean_dev_caches` and the `dev` module, its registry entry, dispatch arm, pre-flight case and source line are deleted
- [ ] Interactive "all" issues `docker system prune` at most once, asserted by the argv recorder
- [ ] The commented-out step calls are resolved — either re-enabled with the progress total derived from the module list, or deleted along with their now-pointless source lines — and no commented-out code remains in `cleanup.sh`
- [ ] `step()` is defined once with one counter pair; the hand-maintained literal total is gone
- [ ] `main` is called with no arguments in both `cleanup.sh` and `doctor.sh`; `cleanup.sh` is reindented to 2 spaces in an isolated commit (`grep -Pc '^\t' cleanup.sh` returns 0)
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 8.1, 7.1

**Effort**: M

**Verify**: `./tests/run.sh` and `grep -Pc '^\t' cleanup.sh; grep -c '^# *step ' cleanup.sh`

#### Task 10.4: Wire or drop `json_add_check`, and complete `json_escape`

**Description**: `json_add_check` (`lib/json.sh:32`) is never called from anywhere, so the checks
accumulator is always empty and the JSON builder always emits `"checks": []` — `mdoctor check --json`,
advertised as "JSON output for automation", ships a permanently empty checks array. Separately
`json_escape` (`lib/json.sh:20`) covers backslash, quote, newline, carriage return and tab but not
the rest of U+0000–U+001F, which RFC 8259 §7 requires, so a form feed or raw ANSI escape reaching a
message string emits invalid JSON; and `:44` interpolates `$risk` and `$status` unescaped while
escaping its three siblings. Decide: wire the accumulator into the status helpers or delete it and
the array from the schema — do not leave a documented-but-empty field. Sequenced after Task 7.9,
which makes the JSON output actually parsed by a test.

**Closes**: `F-DEAD-004`, `F-BUG-025`

**Acceptance Criteria**:
- [ ] `./mdoctor check --json` either emits a populated `checks` array or the field is absent from the schema and the docs; it is never present and empty
- [ ] `json_escape` escapes or strips all of U+0000–U+001F, and `risk` and `status` are escaped like their siblings
- [ ] A test feeds a message containing a form feed and a raw ANSI escape and asserts the output parses as valid JSON
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 7.9

**Effort**: M

**Verify**: `./mdoctor check --json | python3 -m json.tool > /dev/null; echo $?` and `./tests/run.sh`

#### Task 10.5: Delete the unreferenced functions, constants and unreachable guards

**Description**: Nine dead-code findings that share one commit shape — delete the definition, delete
the last reference, confirm nothing else reaches it. `get_module_func` (`lib/metadata.sh:56`) is
never called and is the sole reader of the function-name column, so the 5th argument of every one of
the ~40 `register_module` calls is dead data. `get_module_risk` (`:64`) and `list_modules` (`:84`)
are never called. `is_supported_platform` (`lib/platform.sh:73`) is never called, which makes
`is_debian` transitively dead — the actual platform gate is a byte-identical inline duplicate of the
same distro list in `install.sh`. `assert_dir_exists` (`tests/helpers/assert.sh:36`) is used by none
of the 9 test files. Three "backward-compat aliases" (`lib/safety.sh:18`) have zero callers anywhere.
`cleanups/dev_caches.sh:100` carries a function-existence guard whose library is sourced before it on
every path, with a dead else-branch duplicating six default project directories the library already
defines, plus a paired always-true guard. The destructive-error taxonomy (`lib/safety.sh:37`) is
restated three times — named constants, then bare literals in the name renderer, then the same
literals in the hint renderer, which have already drifted. And `cmd_check` accepts `--json` and
exports the flag while the single-module branch never calls the JSON builder (`mdoctor:318`), so
`check -m network --json` silently emits plain text and the JSON library is sourced on that path for
functions never reached.

**Closes**: `F-DEAD-001`, `F-DEAD-002`, `F-DEAD-003`, `F-DEAD-006`, `F-DEAD-007`, `F-DEAD-008`, `F-DEAD-017`, `F-DEAD-022`, `F-DEAD-028`

**Acceptance Criteria**:
- [ ] `grep -rn 'get_module_func\|get_module_risk\|list_modules\|is_supported_platform\|is_debian\|assert_dir_exists' . --include='*.sh' --include=mdoctor` returns only intentional retentions, each with a call site
- [ ] The function-name column is either deleted from all ~40 `register_module` calls or read by the dispatchers; the three backward-compat aliases and both always-true guards in `cleanups/dev_caches.sh` are gone
- [ ] The error taxonomy's name and hint renderers are driven from one table keyed by the named constants; the drifted name is corrected
- [ ] `./mdoctor check -m network --json` either emits JSON or rejects the flag combination, and the unused `lib/json.sh` source on that path is dropped
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 9.2

**Effort**: S

**Verify**: run `code-review mode:cleanup` on `lib/ tests/helpers/ cleanups/dev_caches.sh`, then `./tests/run.sh` and `scripts/lint_shell.sh`

#### Task 10.6: Untrack `.specify/` and resolve the ignore-rule contradictions

**Description**: `.specify/scripts/bash/update-agent-context.sh:1` heads abandoned spec-kit
scaffolding: 11 tracked files including 1,475 lines of Bash across five scripts, plus 9 command
definitions. Both trees were last touched 2026-02-15, one commit before the openspec workflow began.
Nothing references them except the exclusion lists, and three config files explicitly exempt them
from ShellCheck and syntax checking — so 1,475 lines of shell are tracked and validated by no gate,
the worst of both. Separately `.gitignore:17` reserves three directories that have never existed in
the repo's history, and two directories are ignored while 19–20 files under them are tracked
(`.gitignore:29`): ignore rules do not apply to already-tracked paths, so those entries are inert but
read as intentional exclusions — a contributor who removes and re-adds those trees finds staging
silently refusing, and the tracked content can be dropped from a commit without warning. Untrack
`.specify/` (already listed in the ignore file), drop the never-used ignores, and resolve each
ignored-yet-tracked directory in one direction or the other. The `openspec/` tree is deferred — see
**Deferred and out of scope**.

**Closes**: `F-DEAD-026`, `F-DEAD-024`, `F-CI-020`

**Acceptance Criteria**:
- [ ] `git ls-files .specify/ | wc -l` returns 0, and the `.specify` exclusion entries are removed from the lint script, workflow and hook config
- [ ] `git check-ignore -v` on each remaining `.gitignore` entry resolves to a path that exists or has existed; the three never-used entries are gone
- [ ] No directory is both ignored and tracked: `comm` of `git ls-files` against `git check-ignore` output is empty
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 2.2

**Effort**: S

**Verify**: `git ls-files .specify/ | wc -l` and `git ls-files | git check-ignore --stdin | wc -l` returning 0

#### Task 10.7: Give both entry points one check registry

**Description**: `doctor.sh:68` re-registers all 21 check modules — a near-verbatim duplicate of the
block in `mdoctor`, including the same platform guards, categories, risks, function names and
descriptions. Nothing in `doctor.sh` reads the registry except one integer, so 33 lines of registry
exist solely to produce a count, and its hardcoded fallback must be kept in sync by hand. Move the
registry to the single sourced file Task 8.1 created and have `doctor.sh` read the count from it.

**Closes**: `F-DEAD-014`

**Acceptance Criteria**:
- [ ] `grep -c 'register_module' doctor.sh` returns 0; `doctor.sh` sources the shared registry
- [ ] The hardcoded count fallback in `doctor.sh` is deleted; the count is derived
- [ ] Adding a check module to the registry changes `doctor.sh`'s denominator with no edit to `doctor.sh`, proven by a throwaway module
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 8.1, 7.4

**Effort**: S

**Verify**: `./tests/run.sh` and `grep -c 'register_module' doctor.sh`

#### Task 10.8: Honour or delete the per-module staleness thresholds

**Description**: The days-old global has five different documented defaults that never take effect —
7, 30 and 90 across five modules (`cleanups/ios_backups.sh:9`). Both callers set the variable
unconditionally before sourcing, so 30 and 90 are unreachable and iOS backups are deleted at 7 days
despite the module stating 90. A second, differently-named threshold defaults to 30 and is not listed
in the help's environment-variable section. Either honour the per-module thresholds by setting the
global only when an override is present, or delete the misleading fallbacks; fold the second
threshold into the same naming scheme and document both. Task 13.5 documents whatever is decided
here, so this task must land first.

**Closes**: `F-CLEAN-015`

**Acceptance Criteria**:
- [ ] Either every per-module default is reachable (the global is set only when an override is present, asserted by a test per module) or the unreachable fallbacks are deleted so no module states a threshold it does not use
- [ ] `./mdoctor clean -m ios_backups` uses the threshold the module documents, asserted by a test
- [ ] Both thresholds follow one naming scheme and both appear in the help's environment-variable section
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 8.7

**Effort**: S

**Verify**: `./tests/run.sh --filter ios_backups` and `./mdoctor clean --help | grep -c DAYS`

## Phase P4 — Polish

**Goal:** pay back the measured performance debt, make the terminal interface tell the truth about
what it is about to do, and bring the documentation back level with the code after the cross-platform
release.

**Milestone M4 — bound to the report's measured numbers, no invented budget:**

| Clause | Bound ceiling | Verified by |
|---|---|---|
| **UX findings closed** | All 14 `UX` findings closed (`F-UX-001` in P0; `F-UX-003`–`F-UX-016` here and in P3) | every `UX` ID appears in a completed task's `Closes:` |
| **Pre-flight sizing** | Sizing 500 files costs **≤ 1 `find … -printf '%k\n'` pass**, not a `du -sk` per entry. The measured ratio to beat is **210x** (843 ms vs 4 ms over 500 files, `F-PERF-004`) | timed run of the pre-flight over a 500-file fixture |
| **Find traversal** | On a workspace with 81 `node_modules`, directories visited is **≤ 835**, not 3,986 — the measured **4.8x** un-pruned factor (`F-PERF-006`) | `find … -D stat` or a counted traversal over the fixture |
| **Field extraction** | Extracting fields from 200 lines costs **≤ 3 ms**, not 943 ms — the measured **314x** ratio (`F-PERF-010`) | timed microbenchmark over a 200-line `ps` fixture |
| **Blocking calls** | **Every network or daemon call has a timeout** (`F-PERF-008`): the count of uncapped blocking external calls is **0**, down from roughly 15 with exactly 1 capped at audit | `grep` census of the ~15 named call sites, each preceded by `timeout` |
| **Docs match code** | Every hand-maintained count is derived from the registry (`F-DOCS-009`); the guidebook covers both platforms (`F-DOCS-007`) | Task 13.2's comparison test and Task 13.1 |

### Sprint 11 — Performance

#### Task 11.1: Replace the per-entry `du` loop with one `find -printf` pass

**Description**: `cleanup_preflight_find_kb` (`cleanup.sh:161`) spawns a `du -sk` plus an `awk`
*inside* the per-file read loop; `md_find_size_kb` (`mdoctor:136`) is a near-identical copy. Measured
over 500 files: **843 ms versus 4 ms** for `find -printf '%k\n' | awk` — 210x slower for an identical
result. It is called on the log dir, Downloads, every crash dir and two more macOS trees. Replace the
loop with one `find` pass and collapse the duplicate pair into the shared helper Task 8.2 created.
**This binds M4's pre-flight sizing ceiling.**

**Closes**: `F-PERF-004`

**Acceptance Criteria**:
- [ ] One shared helper computes find-based sizes with a single `find … -printf '%k\n'` pass; `grep -c 'du -sk' cleanup.sh mdoctor` returns 0 for the pre-flight path
- [ ] Timed over a 500-file fixture, the pre-flight sizing completes in under 50 ms (against the measured 843 ms baseline), with the timing recorded in the PR
- [ ] The computed total matches the old implementation's total on the same fixture
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 8.2

**Effort**: S

**Verify**: `time ./cleanup.sh --dry-run` over a 500-file fixture, compared against the recorded 843 ms

#### Task 11.2: Stop walking the same tree twice with a keyed size cache

**Description**: The force-mode pre-flight (`cleanup.sh:188`) `du`-walks the exact trees the cleanup
modules re-walk seconds later in the same process — `~/.npm`, `~/.cache/pip`, `~/.m2/repository`,
`~/.gradle/caches`, `~/go/pkg/mod/cache`, `~/.cargo/registry/cache`. On macOS `DerivedData` is walked
three times. Measured `du -sk ~/.cache` = 112 ms over 105,703 inodes warm on NVMe. There is a
correctness side-effect too: nested paths are double-counted in the estimate. Compute each path's
size once into a keyed cache the cleanup modules read, and drop paths nested inside an
already-measured parent.

**Closes**: `F-PERF-005`

**Acceptance Criteria**:
- [ ] Each path is sized at most once per process, asserted by a counter the cache increments and a test that runs a full force pre-flight plus clean and asserts one measurement per distinct root
- [ ] Paths nested inside an already-measured parent are excluded from the estimate; a fixture with a nested cache produces a total equal to the parent, not parent + child
- [ ] On macOS, `DerivedData` is walked once, not three times
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 8.2, 11.1

**Effort**: M

**Verify**: `./tests/run.sh` and the measurement-counter test

#### Task 11.3: Prune the find traversals and collapse the three storage passes

**Description**: `_find_and_sum` (`checks/storage.sh:55`) runs
`find -maxdepth 5 -type d -name node_modules` with no `-prune`, so find descends *into* every match
looking for nested ones. Measured on a real workspace with 81 `node_modules`: **3,986 directories
visited without prune versus 835 with it** — 4.8x wasted traversal, far worse on a monorepo.
`cleanups/dev_caches.sh:135` has the same defect. Separately `check_storage` (`checks/storage.sh:211`)
runs three full `find` passes over identical project roots for `node_modules`, `venv` and `.venv`:
measured 3 passes 44 ms, 1 combined pass 15 ms, combined plus prune 5 ms — **8.8x** end to end — and
each match then gets its own `timeout 30 du -sk`, re-walking the tree find just traversed. Use one
`find` pass with an OR-ed `-name` set plus `-prune`, emitting name and size together. **This binds
M4's find-traversal ceiling.**

**Closes**: `F-PERF-006`, `F-PERF-007`

**Acceptance Criteria**:
- [ ] Both sites use `-name … -prune -print` so find stops at the match; on the 81-`node_modules` fixture the traversal visits ≤ 835 directories, recorded in the PR
- [ ] `check_storage` performs one `find` pass with an OR-ed `-name` set, not three
- [ ] The pass emits name and size together so no per-match `du` runs; `grep -c 'du -sk' checks/storage.sh` returns 0 for the scan path
- [ ] Reported sizes match the previous implementation on the fixture
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 8.6

**Effort**: S

**Verify**: `time ./mdoctor check -m storage` over the fixture, and a counted traversal against the 835 ceiling

#### Task 11.4: Replace the forked string pipelines with Bash builtins

**Description**: The single largest fork source in the codebase — 49 sites, measured 314x slower.
Whitespace fields are extracted with `$(echo "$line" | awk '{print $N}')`, three processes per field
(`checks/performance.sh:73`): measured **943 ms versus 3 ms for 200 lines**, and `check_performance`
alone burns 100–150 forks parsing 10 lines of `ps` output it already holds in a variable. Inside the
per-line loop over each shell rc file (`checks/shell.sh:46`), every non-comment line runs
`echo "$line" | grep -qE` — 2 processes per line — and matched lines add three more `echo | sed`
pipelines; four files are scanned and a typical oh-my-zsh `.zshrc` is 100–200 lines, so a normal
machine pays ~1,000 `grep` processes for a prefix test `case` performs with zero forks. Inside the
loop over every `.plist` in three LaunchAgents/LaunchDaemons directories (`checks/startup.sh:38`),
each file costs a `basename` subshell plus an `echo | grep -q` — 4 processes per plist, several
hundred on a stock macOS install. `checks/apps.sh:37` uses `xargs -I{} basename {}`, disabling
argument batching so one process is forked per crash file. `checks/network.sh:157` invokes
`netstat -I <if> -b` twice for two columns of the same row, `networksetup` twice, and runs three
`echo | awk` pipelines over an already-captured variable, while `lib/disk.sh` calls `_disk_root`
three times for a value constant for the life of the process. **This binds M4's field-extraction
ceiling.**

**Closes**: `F-PERF-010`, `F-PERF-009`, `F-PERF-016`, `F-PERF-020`, `F-PERF-021`

**Acceptance Criteria**:
- [ ] `grep -rc 'echo "\$[a-z_]*" *| *awk' checks/ lib/` returns 0 — every field-extraction group uses `read -r f1 f2 rest <<< "$line"` and Bash arithmetic
- [ ] `grep -rc 'echo .* | *grep -q' checks/` returns 0 — prefix tests use `case` or `[[ =~ ]]`
- [ ] `${f##*/}` replaces `basename` in the plist loop and `sed 's|.*/||'` replaces `xargs -I{} basename {}`
- [ ] Timed over a 200-line `ps` fixture, field extraction completes in under 10 ms (against the measured 943 ms baseline), recorded in the PR
- [ ] `netstat` and `networksetup` are each invoked once and `_disk_root` computed once per process
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 7.4

**Effort**: M

**Verify**: run `code-review mode:perf` on `checks/`, then the timed 200-line microbenchmark and `./tests/run.sh`

#### Task 11.5: Cheapen `log()` and the per-file cost of `safe_remove`

**Description**: `log()` (`lib/logging.sh:37`) spawns 4 processes per line — a command-substitution
subshell, a `date` exec, a pipeline subshell and a `tee` exec — and reopens the log file each call:
measured **177 ms per 200 calls versus 7 ms** for `printf '%(…)T'` plus a plain append, 25x. It is on
the hot path of every cleanup action via `_safety_log`. `safe_find_delete` (`lib/safety.sh:396`)
calls `safe_remove` per matched file and `safe_remove` forks ~12 processes per file — three are
command substitutions around `_normalize_path`, a function whose entire body is parameter expansion
and needs no subshell — while `op_record` re-runs `dirname` plus `mkdir -p` on every action. Measured
on 300 files with dry-run: 1431 ms = 4.77 ms/file; a crash directory with 10,000 stale files costs
~50 s of pure fork overhead. Have `_normalize_path` assign to a caller-named variable, hoist
`oplog_ensure_file` to session start, and batch oplog appends behind one file descriptor.

**Closes**: `F-PERF-003`, `F-PERF-002`

**Acceptance Criteria**:
- [ ] `log()` uses `printf '%(…)T'` and a plain append or a held file descriptor; timed over 200 calls it completes in under 20 ms (against the measured 177 ms baseline)
- [ ] `_normalize_path` assigns to a caller-named variable with no command substitution at its three call sites in `safe_remove`
- [ ] `oplog_ensure_file` runs once per session, not per action; `dirname`/`mkdir -p` do not appear in `op_record`'s per-action path
- [ ] Timed over a 300-file dry-run deletion, per-file cost is under 1.5 ms (against the measured 4.77 ms baseline), recorded in the PR
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 9.3

**Effort**: M

**Verify**: run `code-review mode:perf` on `lib/safety.sh lib/logging.sh`, then the 300-file timed dry-run

#### Task 11.6: Capture each slow command's output once

**Description**: Three modules invoke the same slow binary repeatedly to read fields of one report.
`check_battery` (`checks/battery.sh:13`) invokes `system_profiler SPPowerDataType` three times for
three fields of one report, `ioreg` twice for two fields of one dump, and `pmset -g batt` three times
for three fields of one line — 8 invocations of 3 slow macOS binaries where 3 captures would serve,
and the project's own sibling comment records `system_profiler` as "very slow (~30s)". One `diagnose`
run parses `/proc/meminfo` with 8 separate `awk` forks within about a second
(`checks/diagnose_performance.sh:175`), never memoizing, recomputes the identical swap value twice,
awks `/proc/loadavg` 4 times for three fields of one line, runs `nproc` twice, and forks `vm_stat` 5
times on macOS — while the correct pattern already exists in the same file, where
`get_linux_iowait_pct` memoizes and is called 3 times for the cost of one. `dpkg -l`
(`checks/apt.sh:20`) executes three times per `mdoctor check` on Debian, two of them byte-identical
queries from different modules, each formatting 2,000–4,000 rows.

**Closes**: `F-PERF-011`, `F-PERF-013`, `F-PERF-017`

**Acceptance Criteria**:
- [ ] Each of `system_profiler`, `ioreg`, `pmset`, `dpkg -l`, `nproc` and `vm_stat` is invoked at most once per `mdoctor check` run, asserted by a stub-`PATH` invocation counter
- [ ] `/proc/meminfo` and `/proc/loadavg` are each read once into shell variables that the sub-checks consume, following the existing memoization pattern
- [ ] The swap value is computed once, not twice
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 10.2

**Effort**: S

**Verify**: run `code-review mode:perf` on `checks/`, then a stub-`PATH` `./mdoctor check` with the invocation counts asserted

#### Task 11.7: Time-cap every network and daemon call, and parallelize the independent probes

**Description**: Exactly one external call in the codebase is time-capped (`checks/node.sh:25`).
Every network- or daemon-bound call in `mdoctor check` is uncapped: `npm doctor`, `npm outdated -g`,
`pip3 list --outdated`, `brew doctor`, `brew outdated`, `softwareupdate -l`, `apt list --upgradable`,
`docker info`, `nslookup` — and `doctor.sh:141-181` runs all modules strictly sequentially, so 6–8
independent network round trips execute back to back. `docker info` runs twice per check from two
different modules, neither capped, and `check_containers` spawns 6 separate `docker` CLI processes
(`checks/containers.sh:23`). `check_disk_hotspots` (`checks/diagnose_performance.sh:364`) runs
`du -sk` over `/tmp`, `/var/log` and `/var/tmp` with no timeout in a block whose own comment states
deep scans are "too slow for a diagnostic check", while `checks/storage.sh:33` wraps the identical
call in `timeout 30` — and `diagnose` is the command a user runs precisely when the machine is
already slow. `check_open_connections` (`:477`) runs the socket enumerator twice, once for
ESTABLISHED and once for LISTEN, neither capped despite enumerating tens of thousands of sockets.
Two `du` calls in `checks/storage.sh:23` have no timeout at all, and `lib/benchmark.sh:75,85` has the
same gap for the network benchmark. **This binds M4's blocking-call clause: the count of uncapped
blocking external calls must reach 0.**

**Closes**: `F-PERF-008`, `F-PERF-012`, `F-PERF-018`, `F-PERF-019`, `F-BUG-028`

**Acceptance Criteria**:
- [ ] A census of the ~15 named blocking call sites shows every one preceded by `timeout` (and `curl -m 10` for the benchmark); the count of uncapped sites is 0
- [ ] Each timed-out call reports a distinct "timed out" status rather than silently returning 0
- [ ] `docker info` is probed once behind `timeout 5` and cached for the second module; the socket enumerator runs once piped into one `awk`
- [ ] The mutually independent registry probes run concurrently; a stub-`PATH` run with each probe sleeping 2 s completes in well under the sequential sum, recorded in the PR
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 11.6

**Effort**: M

**Verify**: run `code-review mode:perf` on `checks/ lib/benchmark.sh`, then `grep -rn 'npm \|brew \|docker info\|nslookup\|apt list\|softwareupdate\|du -sk' checks/ lib/ | grep -vc timeout` returning 0

#### Task 11.8: Cut the spinner and startup fork overhead

**Description**: The four `status_*` functions (`lib/common.sh:150`) each call `progress_stop` then
`progress_start` around every printed line, and each cycle forks a background subshell plus two
`tput` execs — measured ~1.3 ms per status line. A full `mdoctor check` emits 100–150 status lines,
so several hundred process spawns exist purely to tear down and re-erect the spinner, whose body also
forks a `sleep` every 0.1 s. Separately every invocation, including `mdoctor help` and
`mdoctor version` (`mdoctor:35`), runs `git rev-parse --short HEAD` purely to decorate the version
banner, plus `realpath`/`dirname` resolution and 8 `tput` execs when stdout is a tty — measured:
`mdoctor help` forks 11 processes non-interactively, about 19 with the tput block active, all before
argument parsing. Hoist the `tput el` capture into a variable computed once, keep one long-lived
spinner signalled rather than re-forked per line, use `read -t` instead of forking `sleep`, and
resolve the git commit lazily.

**Closes**: `F-PERF-014`, `F-PERF-022`

**Acceptance Criteria**:
- [ ] `git rev-parse` is not invoked by `./mdoctor help` or `./mdoctor version` unless the version string is actually printed, proven by a stub-`PATH` counter
- [ ] `tput` is invoked at most once per process; `./mdoctor help` forks fewer than 6 processes non-interactively, measured and recorded in the PR against the audited 11
- [ ] The spinner is started once per run and signalled per line, not re-forked; `sleep` is not forked in its loop
- [ ] Per-status-line cost is under 0.3 ms, timed over 150 lines against the measured 1.3 ms baseline
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 7.4

**Effort**: M

**Verify**: run `code-review mode:perf` on `lib/common.sh mdoctor`, then `strace -f -c -e trace=clone ./mdoctor help` or an equivalent fork count

#### Task 11.9: Benchmark real disk, over HTTPS

**Description**: The disk benchmark writes its 256 MB test file into `/tmp`
(`lib/benchmark.sh:24`), which is tmpfs — RAM — on systemd Linux, confirmed on the audit host. The
headline "Disk Write" and "Disk Read" figures therefore measure RAM bandwidth on the platform the
project just added; the page cache is dropped only on macOS, `dd` lacks `conv=fdatasync`, and the
bare `sync` flushes every process's dirty pages. Separately the network benchmark
(`lib/benchmark.sh:83`) fetches a third-party host over cleartext HTTP: it measures nothing that
requires plaintext, it leaks the fact that the machine is running mdoctor to any on-path observer,
and it is trivially redirectable by a captive portal into content that skews the result — and a
sibling line hardcodes the same third-party host for a DNS lookup inside a local-diagnostics tool.

**Closes**: `F-PERF-015`, `F-SEC-023`

**Acceptance Criteria**:
- [ ] The disk benchmark writes under a real on-disk path and refuses to report if the target filesystem is tmpfs, asserted by a test that forces a tmpfs target
- [ ] `dd` uses `conv=fdatasync`, and the read pass drops caches or uses `iflag=direct` on Linux; the bare `sync` is gone
- [ ] `grep -c 'http://' lib/benchmark.sh` returns 0
- [ ] Any external host is configurable via a documented environment variable, and the default is documented
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 7.2

**Effort**: S

**Verify**: `./tests/run.sh --filter benchmark` and `grep -n 'http' lib/benchmark.sh`

### Sprint 12 — UX and the remaining correctness debt

#### Task 12.1: Build the help and error module lists from the platform-filtered registry

**Description**: Error and help copy names the wrong platform's modules and omits valid ones
(`mdoctor:332`). On Linux an unknown check module lists `battery, bluetooth, usb, homebrew` — all
macOS-only — and omits `apt`; `check --help` and `clean --help` hardcode the macOS lists with no
platform branch. Observed contradiction in one session: `clean --help` lists `ios_backups`/`xcode`
while `clean -i`, run seconds later, shows `[9] apt`. Krug's rule for error copy is inverted — it
names invalid options and hides a valid one. Build all four lists from the platform-filtered array
`cmd_clean` already computes and the branch `cmd_help` already has, now derived from the Task 8.1
registry.

**Closes**: `F-UX-005`

**Acceptance Criteria**:
- [ ] On Linux, no help or error list names `battery`, `bluetooth`, `usb` or `homebrew`, and every list includes `apt`
- [ ] All four lists (`check --help`, `clean --help`, and both unknown-module error messages) are derived from the platform-filtered registry, not typed
- [ ] A test asserts `clean --help`'s module list and `clean -i`'s menu contain the same set on the running platform
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 8.4

**Effort**: S

**Verify**: `./tests/run.sh` and `diff <(./mdoctor clean --help | grep -oE '^\s+[a-z_]+') <(./mdoctor clean -i </dev/null | grep -oE '[a-z_]+$')`

#### Task 12.2: Guard the `-m`/`--module` arity

**Description**: `-m`/`--module` with a missing value crashes with a raw interpreter error
(`mdoctor:282`). Observed: `./mdoctor check -m` → `./mdoctor: line 282: $2: unbound variable`;
`./mdoctor clean -m` → the same at line 435. The user sees a line number and a shell internals term,
with no mention of the flag and no valid values. Guard the arity before consuming `$2` and emit
"Error: -m/--module requires a module name" plus the platform-correct module list from Task 12.1.

**Closes**: `F-UX-004`

**Acceptance Criteria**:
- [ ] `./mdoctor check -m` and `./mdoctor clean -m` each exit non-zero with a message naming the flag and listing valid module names
- [ ] Neither emits `unbound variable` or a line number; `./mdoctor check -m 2>&1 | grep -c 'unbound variable'` returns 0
- [ ] A test covers both commands with the flag and no value
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 8.4

**Effort**: S

**Verify**: `./mdoctor check -m; echo $?` and `./tests/run.sh`

#### Task 12.3: Name the mode, accept `--dry-run`, and terminate every run with a summary

**Description**: Four related UX defects around the safe mode. The interactive cleanup menu
(`mdoctor:601`) never states whether the run is dry-run or destructive — `select_interactive_modules`
prints the numbered list and the force flag is not consulted until after selection, so
`mdoctor clean -i` and `mdoctor clean -i --force` render an identical menu and `[1] trash  Empty
Trash` reads as an action in both. The safe mode has no name and leaves no trace (`mdoctor:513`):
`mdoctor clean --dry-run` is rejected with "Error: Unknown option: --dry-run", so the default safe
mode cannot be stated explicitly while the destructive mode can, and `run_single_cleanup_module`
prints no mode banner and no closing summary. The whitelist — the only mechanism a user has to
protect a path — appears only inside `clean --help` and the environment-variable list, never in
either pre-flight summary, the exact screen that enumerates paths about to be deleted
(`mdoctor:464`), and `ensure_cleanup_whitelist_file` creates the file silently. And the single-module
check path (`mdoctor:393`) prints only an "Actions:" list with no terminator, so the user cannot tell
whether it finished or was cut off.

**Closes**: `F-UX-003`, `F-UX-008`, `F-UX-009`, `F-UX-014`

**Acceptance Criteria**:
- [ ] The interactive menu heading states the mode, and the resolved selection is restated with the mode before the first module runs; `clean -i` and `clean -i --force` render visibly different headings
- [ ] `./mdoctor clean --dry-run` and `-n` are accepted as explicit affirmations of the default and exit 0
- [ ] Every cleanup run, including the single-module path, prints a mode banner at the top and a deleted/would-free summary at the end
- [ ] Both pre-flight summaries name the whitelist file path and what it is for
- [ ] `./mdoctor check -m network` ends with the same counts and terminator the full run emits
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 8.4, 0.5

**Effort**: M

**Verify**: `./mdoctor clean --dry-run; echo $?` and `diff <(./mdoctor clean -i </dev/null) <(./mdoctor clean -i --force </dev/null)`

#### Task 12.4: Make the badges honest and orient the user on bare invocation

**Description**: `diagnose` is badged `[HIGH]` though it only reads (`mdoctor:962`) — `cmd_diagnose`
sources the module and calls a function that reads and appends advice strings, never running the
`kill` commands it suggests — while `README.md:233` defines `[HIGH]` as "Destructive or hard to
reverse". Observed: `mdoctor list` shows `diagnose [HIGH]` while `mdoctor help` describes it with no
badge. Since the badge is the only destructive/read-only signal in `mdoctor list`, mis-badging a
read-only command as the most dangerous level trains users to discount the badges — which matters
because Task 0.6 just re-rated the cleanup modules. Separately bare `mdoctor` prints the full help
and exits 0 (`mdoctor:1372`), with no recommended next step and no visual separation of safe from
destructive commands: all 11 command names are colored identically, so `check` and `clean` are
typographically indistinguishable and only the parenthetical prose separates them.

**Closes**: `F-UX-012`, `F-UX-013`

**Acceptance Criteria**:
- [ ] `./mdoctor list` shows `diagnose` at a read-only badge level, and `./mdoctor help` renders the badge in its command table too
- [ ] Bare `./mdoctor` prints an orientation block ending in a recommended first command
- [ ] Every command entry is marked read-only / modifies / deletes from the registry data, and the three classes are visually distinguishable in a `cat -v` capture (not by color alone)
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 8.4

**Effort**: S

**Verify**: `./mdoctor | cat -v | head -20` and `./mdoctor list | grep diagnose`

#### Task 12.5: Honour `NO_COLOR` and the tty guard in `init_colors`

**Description**: ANSI escapes leak into piped and redirected output and `NO_COLOR` is ignored
(`lib/common.sh:12`). `init_colors` gates on `command -v tput` alone with no `[ -t 1 ]` test, unlike
every entry point, and is called *after* the tty-safe block so it overwrites the empty strings.
Observed: `./mdoctor check -m network | cat -v` emits raw escapes, and so does
`NO_COLOR=1 ./mdoctor check -m network`. This affects the documented JSON pipeline. Add the `[ -t 1 ]`
guard and a `NO_COLOR`/`MDOCTOR_NO_COLOR` check, and make `init_colors` the single implementation.

**Closes**: `F-UX-010`

**Acceptance Criteria**:
- [ ] `./mdoctor check -m network | cat -v` emits no `^[[` sequences
- [ ] `NO_COLOR=1 ./mdoctor check -m network` on a tty emits no escapes; `MDOCTOR_NO_COLOR=1` behaves identically
- [ ] `init_colors` is the single color implementation and is called before, not after, the tty-safe block
- [ ] `./mdoctor check --json | python3 -m json.tool` succeeds when piped
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 7.4

**Effort**: S

**Verify**: `./mdoctor check -m network | cat -v | grep -c '\^\[\['` returning 0

#### Task 12.6: Make the check copy and remediation advice platform-correct

**Description**: Platform-wrong copy inside check output, in one case contradicting the hardware.
Observed on a Linux laptop with a battery: "No battery detected (desktop Mac). Skipping battery
checks." (`checks/battery.sh:16`). `checks/containers.sh:25` tells Linux users to "Start Docker
Desktop or run: open -a Docker" — `open -a` does not exist on Linux — and `checks/git_config.sh:14`
emits `xcode-select --install` unconditionally on Linux; both modules are registered without a
platform gate, so Debian users are told to run commands that do not exist, while
`checks/devtools.sh:38-42` already implements the correct branch one file over. Two cleanup modules
are also effectively no-ops on Linux while reporting success (`cleanups/crash_reports.sh:20`): crash
reports resolve to `/var/crash`, blocked as protected, plus a macOS-centric filter; and trash removes
`Trash/files/*` but never the matching `Trash/info/*.trashinfo`, leaving phantom entries in the
desktop trash UI contrary to the freedesktop.org spec. The shell-config source checker
(`checks/shell.sh:61`) generates false warnings on common dotfiles: bare relative `source foo.sh` is
resolved against `$HOME` although the shell resolves it against the runtime CWD, and embedded
variables are never expanded, so rustup's, nvm's and oh-my-zsh's source lines become paths containing
a literal `$` that can never exist.

**Closes**: `F-UX-011`, `F-BUG-039`, `F-BUG-029`, `F-BUG-030`

**Acceptance Criteria**:
- [ ] `grep -rn 'desktop Mac\|open -a Docker\|xcode-select' checks/` shows every occurrence inside an `is_macos` branch, with a Linux alternative (`systemctl start docker`) in the else branch
- [ ] On Linux with a battery present, `./mdoctor check -m battery` reports the battery rather than "desktop Mac"
- [ ] Crash reports use apport and systemd-coredump paths with Linux filters, and trash deletes the matching `.trashinfo` entry alongside each trashed file, asserted by a test
- [ ] `checks/shell.sh` expands variables before matching, skips bare relative targets, and uses `[[:space:]]` instead of GNU-only `\s`; a fixture `.zshrc` with rustup, nvm and oh-my-zsh lines produces zero false warnings
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 7.4

**Effort**: M

**Verify**: `./tests/run.sh` and `./mdoctor check -m battery -m containers -m git_config -m shell` on Linux

#### Task 12.7: Fix the installer's first-screen copy

**Description**: The first screen a new user sees recommends a system-modifying batch command as a
peer of read-only ones (`install.sh:150`): the "Get started" block lists `mdoctor fix all` alongside
`help`, `check` and `info` with no risk marker — on macOS `fix all` runs two `[MED]` targets.
Separately `install.sh:112` prints "Cloning mac-doctor to …" while the product is `mdoctor`.

**Closes**: `F-UX-015`

**Acceptance Criteria**:
- [ ] The getting-started block either omits `fix all` or marks it with its risk level; `check`, `help` and `info` are presented as the read-only starting points
- [ ] `grep -c 'mac-doctor' install.sh` returns 0
- [ ] The Task 7.5 installer test asserts both
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 4.2, 7.5

**Effort**: S

**Verify**: `MDOCTOR_INSTALL_DIR=$(mktemp -d) ./install.sh | tail -20` and `grep -c 'mac-doctor' install.sh`

#### Task 12.8: Validate numeric readings and report failure honestly

**Description**: Numeric values from external commands are used in arithmetic with no validation, so
an empty value silently coerces to 0 and the check reports a healthy system instead of a parse
failure (`checks/disk.sh:11`) — the disk check, whose entire job is catching a full disk, silently
reports OK. Same at `checks/system.sh:49,60` and `checks/performance.sh:54`, while
`checks/performance.sh:36-38` guards the identical computation correctly. `net_drops`
(`checks/network.sh:158`) reads `awk 'NR==2 {print $8}'` from `netstat -I <if> -b`, which is the
Opkts column — total output packets — not a drop or error column; `$9` (Oerrs) was intended, matching
the correct `$6` used one line above, so a meaningless huge "Network drops" figure is reported on
essentially every macOS run. `fixes/dns.sh:27` prints "DNS cache flushed." unconditionally, outside
the branch structure, so on a Linux system with neither `resolvectl` nor `systemd-resolve` the user
is told the cache was flushed when it was not — reproducible 100% of the time. The thermal check
(`checks/hardware.sh:95`) breaks unconditionally on the first `thermal_zone` glob match, frequently
an ACPI or Wi-Fi sensor rather than the CPU package, so hot zones are never read;
`checks/startup.sh:75` cannot distinguish "systemd unreachable" from "zero enabled services" and
always prints 0; and `lib/metadata.sh:12-18` has no double-source guard, so re-sourcing resets the
module registry. Finally `MDOCTOR_DISTRO_VER="${VERSION_ID%%.*}"` (`lib/platform.sh:33`) has no
default while both neighbours do, and `VERSION_ID` is optional in the os-release spec with `set -u`
active, so on a distro omitting it the whole CLI aborts before any command runs.

**Closes**: `F-BUG-027`, `F-BUG-026`, `F-BUG-031`, `F-BUG-040`, `F-BUG-034`

**Acceptance Criteria**:
- [ ] Every numeric value from an external command is validated against `^[0-9]+$` before arithmetic; an unparseable value reports "could not determine" rather than 0, asserted by a stub that returns empty output for `checks/disk.sh`, `checks/system.sh` and `checks/performance.sh`
- [ ] `net_drops` reads the Oerrs column and parses the interface by name rather than a fixed field position
- [ ] `fixes/dns.sh` returns non-zero from the no-tool branch and prints success only after a flush actually ran
- [ ] The thermal zone is selected by its `type` file; systemd reachability is probed before counting enabled services; `lib/metadata.sh` has a double-source guard asserted by a test that sources it twice
- [ ] `VERSION_ID` is defaulted before the suffix strip; a stub `os-release` without `VERSION_ID` lets `./mdoctor help` run
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 11.6

**Effort**: M

**Verify**: `./tests/run.sh` and a stub `os-release` without `VERSION_ID`, then `./mdoctor help; echo $?`

#### Task 12.9: Make the `downloads` module honest and skip caches of running browsers

**Description**: The `downloads` module never deletes anything (`cleanups/downloads.sh:13`) — the
`safe_find_delete` call is commented out and only `find … -print` runs — yet it is an advertised
cleanup module, counted in `PROGRESS_TOTAL`, and given a pre-flight size estimate, so a user running
`--force` reasonably believes large downloads were removed. Separately none of the six
`safe_remove_children` calls in `cleanups/browser.sh:13` is preceded by a process check, so
`mdoctor clean -m browser --force` deletes cache index and journal files out from under a running
browser; it is scoped to Caches rather than the profile proper, so the result is misbehaviour and
cache corruption rather than lost bookmarks. Either enable the downloads deletion behind an explicit
opt-in plus the Task 0.5 confirmation, or relabel the module as report-only and drop it from the
destructive pre-flight; and skip each browser's cache when `pgrep` finds it running, saying so in the
log.

**Closes**: `F-BUG-022`, `F-BUG-018`

**Acceptance Criteria**:
- [ ] `downloads` either deletes behind an explicit opt-in flag, or is labelled report-only, excluded from `PROGRESS_TOTAL` and given no destructive pre-flight size estimate — never both advertised and inert
- [ ] A test asserts the chosen behaviour: a forced run either removes the fixture file or reports it as report-only
- [ ] Each of the six browser cache targets is skipped when `pgrep` finds that browser running, and the skip is logged; a test with a stub `pgrep` asserts all six skips
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 0.5, 0.6, 6.2

**Effort**: S

**Verify**: `./tests/run.sh --filter 'downloads|browser'` and a stub-`pgrep` forced browser clean

#### Task 12.10: Bound the persistent state and settle the errexit posture

**Description**: Persistent state grows without bound and can collide (`lib/history.sh:24`): history
filenames use second-resolution timestamps and `cat >` truncates, so two runs in the same second
silently destroy one entry, and nothing ever prunes the history directory; the operations log is
append-only with no rotation; and an unchecked `mkdir -p` can abort an entire cleanup run because the
best-effort audit log could not be written. Separately the errexit posture is inconsistent across
entry points (`mdoctor:24`): `cleanup.sh:13` uses `set -euo pipefail` while `mdoctor:24` and
`doctor.sh:11` use `set -uo pipefail`, so the same modules sourced by both have different failure
semantics depending on invocation — the mechanism behind `F-BUG-008`'s two distinct failure modes.
Decide the posture per entry point deliberately, document it, and make modules robust under both.

**Closes**: `F-BUG-032`, `F-BUG-038`

**Acceptance Criteria**:
- [ ] History filenames carry a PID or random suffix; two runs in the same second produce two entries, asserted by a test
- [ ] The history directory is pruned to a documented retention cap and the operations log rotates by size; both caps are named constants from Task 8.7
- [ ] A failing `mkdir -p` for the oplog disables logging with a warning rather than aborting the run, asserted by a test with an unwritable config directory
- [ ] The errexit posture of each entry point is stated in a header comment and in `CONTRIBUTING.md`, and the suite runs each of the shared modules under both postures
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 3.4, 8.7

**Effort**: S

**Verify**: `./tests/run.sh` and two `./mdoctor check` runs in the same second, then `ls ~/.config/mdoctor/history | wc -l`

### Sprint 13 — Documentation alignment

#### Task 13.1: Rewrite the guidebook for two platforms

**Description**: The guidebook (`docs/GUIDEBOOK.md:1`) was not updated for the cross-platform release
and is still an entirely macOS document, while the README presents it as the primary
problem-to-command entry point for all users. It is titled for the old product name, gives the macOS
cache path, and contains no apt rows despite all three apt modules shipping. Worse, it prescribes
seven macOS-only fix targets with no platform label — and two documented cleanup examples are
rejected outright on Linux. Rewrite it with the two-platform table treatment the README already uses:
retitle, split or label every macOS-only row, add the Linux rows, correct the cache path. Sequenced
after Tasks 1.2, 1.3, 12.1 and 12.6, which actually gate the unguarded fix targets — the report is
explicit that documenting them is not a substitute for gating them.

**Closes**: `F-DOCS-007`

**Acceptance Criteria**:
- [ ] Every fix and cleanup row in the guidebook carries a platform label or sits under a platform-specific heading; `grep -c 'macOS only\|Linux only' docs/GUIDEBOOK.md` covers all platform-specific rows
- [ ] apt rows exist for all three apt modules; the cache path shown for Linux is the XDG path
- [ ] `grep -c 'mac-doctor' docs/GUIDEBOOK.md` returns 0
- [ ] Every command example in the guidebook is executed by a doc-example test on both platforms and none is rejected
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 12.1, 12.6

**Effort**: M

**Verify**: run `doc-manager` on `docs/GUIDEBOOK.md`, then the doc-example test on both CI lanes

#### Task 13.2: Derive every count from the registry and correct the inventories

**Description**: The literals "21 checks", "10 modules" and "9 targets" are hand-maintained in at
least 15 places (`README.md:19`) and are wrong on both platforms: the registry yields 20 checks on
macOS and 17 on Linux, cleanups are 10 and 9 of which only 8 and 7 run in a full clean, and fix
targets are 9 on macOS but 3 on Linux; the project-structure tree labels three directories with
counts that disagree with the entries it lists. A full clean does not execute every cleanup module
but the docs say it does (`docs/GUIDEBOOK.md:125`): two step calls are commented out and the progress
total set accordingly to 8 on macOS and 7 on Linux, while the guidebook says "dry-run all 10 modules"
and the README repeats the figure. And the README's inventories have two omissions
(`README.md:281`): the project-structure tree enumerates 21 files under `checks/` and omits the 22nd
(the diagnose module), and the documentation index lists nine entries, omitting the release notes and
the code of conduct. Replace every fixed count with per-platform figures or a pointer to
`mdoctor list`, now that Task 8.4 derives them from the registry.

**Closes**: `F-DOCS-009`, `F-DOCS-006`, `F-DOCS-021`

**Acceptance Criteria**:
- [ ] `grep -rc '21 checks\|10 modules\|9 targets' README.md docs/` returns 0
- [ ] Every remaining count in the docs is either per-platform or a pointer to `mdoctor list`
- [ ] Both documents state the real per-platform full-clean counts (8 macOS / 7 Linux) and that the two modules are opt-in via `-m`, or the counts are corrected to whatever Task 10.3 decided
- [ ] The project-structure tree lists all 22 `checks/` files and the documentation index lists all 11 root documents
- [ ] A test compares the counts printed by `./mdoctor list` against any count still appearing in the docs and fails on a mismatch
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 8.4, 12.1

**Effort**: M

**Verify**: run `doc-manager` on `README.md docs/`, then the count-comparison test

#### Task 13.3: Document `diagnose` everywhere it is missing

**Description**: The `diagnose` command is implemented, registered, tested and advertised by the
CLI's own help, yet appears in no documentation (`README.md:53`): the README command table lists 11
commands and omits it; the guidebook's other-commands block omits it and its performance table still
routes "machine feels slow" to the older module; the architecture document omits it; and the
changelog's unreleased section records only the two bugfixes, not the commit that shipped it after
v3.0.0. The only occurrence of the word in any document is the README tagline. The architecture
document has the same shape of drift (`docs/ARCHITECTURE.md:17`): it describes no component that is
absent, but its component diagram has no diagnose node, its inline-commands box omits the command,
the module is undescribed in the module-layer section, and the runtime-flows section documents check,
cleanup and update but not diagnose. Sequenced after Tasks 10.2 and 11.7 so the documented runtime
flow describes the shared probes and the timeout behaviour rather than the pre-refactor shape.

**Closes**: `F-DOCS-005`, `F-DOCS-010`

**Acceptance Criteria**:
- [ ] `diagnose` appears in the README command table with a usage section, in the guidebook's other-commands block and cheat sheet, and the guidebook's performance row for "machine feels slow" routes to it
- [ ] `docs/ARCHITECTURE.md` has a diagnose node and edge in the component diagram, a module-layer description, and a diagnose runtime flow alongside the existing three
- [ ] The changelog has an entry for the diagnose feature citing its commit
- [ ] `grep -rc 'diagnose' README.md docs/GUIDEBOOK.md docs/ARCHITECTURE.md` returns ≥ 1 for each
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 10.2, 11.7

**Effort**: M

**Verify**: run `doc-manager` on `README.md docs/GUIDEBOOK.md docs/ARCHITECTURE.md`, then the grep counts

#### Task 13.4: Rewrite the contributor guide against the real gates

**Description**: The contributor guide names none of the project's actual quality gates
(`CONTRIBUTING.md:10`): its testing section tells contributors to run four CLI commands and never
mentions the regression suite CI runs on three lanes, the ShellCheck gate CI enforces, or the hook
config and how to install it — a grep for "pre-commit" across the README, the contributor guide, the
docs directory and the workflow directory returns zero hits. It still says to test changes on macOS
although CI has run a Linux lane since the cross-platform release, so a contributor who follows this
guide exactly will open a PR that fails lint. The step-by-step guides for adding modules
(`CONTRIBUTING.md:55`) are also stale: one step says to increment a total in the audit script, but
that value is now derived from the registry; neither guide mentions `register_module`, which must be
called in two places, so a module added by following the guide would never appear in `list`, never
count toward the score denominator, and carry no category or risk level; and neither mentions the
platform-gating conditionals or the module array.

**Closes**: `F-DOCS-008`, `F-DOCS-015`

**Acceptance Criteria**:
- [ ] `CONTRIBUTING.md` names `./tests/run.sh`, `scripts/lint_shell.sh` and `pre-commit install`, and maps each to the CI lane that enforces it
- [ ] The macOS-only testing instruction is replaced by the real cross-platform expectation
- [ ] The add-a-module guides describe the current flow — the registry file from Task 8.1, the platform conditionals and the dispatch — and the obsolete increment instruction is deleted
- [ ] A new module added by following the guide verbatim appears in `./mdoctor list` and counts toward the score denominator, verified once by hand and recorded in the PR
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 2.8, 6.2, 8.1

**Effort**: S

**Verify**: run `doc-manager` on `CONTRIBUTING.md`, then follow the add-a-module guide verbatim and run `./mdoctor list`

#### Task 13.5: Correct the safety document's scope and whitelist rules

**Description**: The scope-file format is documented correctly but the deletion criteria that apply
when the file is empty are omitted (`docs/SAFETY.md:59`) — which is the *default* state, since the
generated file has every rule line commented out. The document says only that "default scan behavior
is preserved" without naming it; the actual defaults are six project directories scanned to depth 5
with a staleness threshold from an undocumented variable, so a user cannot tell that a forced clean
will recursively delete `node_modules` under six of their project directories by default. Separately
the whitelist format rules (`docs/SAFETY.md:53`) omit the tilde-expansion rule even though all three
examples rely on it — and expansion applies only to a *leading* tilde, so a mid-path one silently
fails, a rule the tool's own generated template documents, making the safety document less accurate
than the generated file — and the trailing-glob rule is described as protecting descendants when the
implementation also matches the base path itself. Sequenced after Task 10.8, which decides what the
thresholds actually are.

**Closes**: `F-DOCS-004`, `F-DOCS-018`

**Acceptance Criteria**:
- [ ] `docs/SAFETY.md`'s scope section lists the six default roots, the depth bound and the threshold variable as decided by Task 10.8, and that variable also appears in the README's configuration section
- [ ] The whitelist rules state that tilde expansion applies to a leading tilde only, matching the generated template's wording
- [ ] The trailing-glob rule states that it matches the base path as well as descendants
- [ ] A test asserts the documented defaults match the code's actual defaults, so the two cannot drift again
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 10.8

**Effort**: S

**Verify**: run `doc-manager` on `docs/SAFETY.md`, then the defaults-comparison test

#### Task 13.6: Pick one authoritative changelog and complete the release checklist

**Description**: Two changelog-shaped files exist with no statement of which is authoritative
(`RELEASE_NOTES.md:30`), and each is wrong in a different way: the documented release process feeds
only one of them to the release command and never mentions the other, making it an orphan of the
process meant to produce it; that orphan claims Linux milestones sit under "unreleased" when the
shipped file has them under the version heading, and claims a test count that disagrees with the
directory — while the file the process actually consumes omits the diagnose feature entirely, so a
release cut today would ship notes missing a headline feature. The release checklist
(`docs/DEPLOYMENT.md:45`) lists five steps and misses every other file a release has to touch by
hand: not the release-notes file, which is version-titled and carries per-release statistics, nor the
module counts hardcoded across four documents and two scripts. And `docs/LINUX_DEBIAN_PLAN.md:3`
still reads "Status: Planning" for work that shipped in v3.0.0 — every one of its seven phases is
done except the guidebook update, which Task 13.1 completes — while the README lists it in the
documentation index as a phased roadmap with no completion marker. Sequenced after Task 5.4, which
makes the version constant the single source of truth and lets the checklist shrink.

**Closes**: `F-DOCS-011`, `F-DOCS-016`, `F-DOCS-012`

**Acceptance Criteria**:
- [ ] One changelog is declared authoritative in `docs/DEPLOYMENT.md`; the other is deleted or reduced to a pointer, and the decision is recorded in the deployment checklist
- [ ] The authoritative changelog has an entry for the diagnose feature and its per-release statistics match the repository
- [ ] The release checklist enumerates every file a release touches, marking which literals Task 5.4 now derives automatically
- [ ] `docs/LINUX_DEBIAN_PLAN.md` is archived or stamped shipped with per-phase completion markers, and the README index entry no longer reads as a live roadmap
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 5.4

**Effort**: S

**Verify**: run `doc-manager` on `RELEASE_NOTES.md docs/DEPLOYMENT.md docs/LINUX_DEBIAN_PLAN.md`, then a dry-run of the release checklist

#### Task 13.7: Document the global options, installer variables, and the rest of the small gaps

**Description**: Five small documentation gaps that share one editing pass. Implemented flags are
missing from the user docs (`README.md:53`): the debug flag exists on five commands and is advertised
in five help examples and the environment-variable block, yet a grep across the README, contributor
guide and docs directory finds it only in passing twice, never in a usage section; the update
command's channel option is undocumented outside a changelog parenthetical; the short version aliases
are undocumented; and the environment variable the debug flag sets and exports is documented nowhere.
The install and uninstall instructions are correct for the default path but two environment variables
are documented nowhere in the repo and four more appear only inside a CI-only sanity recipe
(`install.sh:21`), so a user who installed to a custom prefix gets uninstall instructions that
silently remove nothing. The bug report template's environment block predates cross-platform support
(`.github/ISSUE_TEMPLATE/bug_report.md:32`) and collects no Linux information — it asks for a macOS
version and an Apple Silicon or Intel architecture, with no distribution, kernel or os-release field.
The development document lists five coverage areas for the regression suite
(`docs/DEVELOPMENT.md:40`) but the test directory now holds nine files. And `SECURITY.md:7` lists a
single supported-versions row against a repo that ships four tagged releases, states no policy for
older majors, and says nothing about the tool's threat model — now fixable because Task 4.1 makes the
installer pin tags.

**Closes**: `F-DOCS-013`, `F-DOCS-017`, `F-DOCS-019`, `F-DOCS-020`, `F-SEC-022`

**Acceptance Criteria**:
- [ ] A global-options section documents the debug flag with its environment variable, the update channel option, and the short version aliases; the debug flag also appears in the guidebook's tips block
- [ ] `docs/DEPLOYMENT.md` carries an installer environment-variable table covering all six variables, cross-linked from the README's configuration and uninstall sections
- [ ] The bug report template asks for OS and version covering both platforms plus a distribution line, and requests `mdoctor info` output
- [ ] `docs/DEVELOPMENT.md`'s coverage list matches the test directory contents, or is replaced by a pointer
- [ ] `SECURITY.md` states the supported tag range that Task 4.1's tag-pinning makes meaningful, and adds a threat-model section naming the privileged and destructive surfaces as in scope
- [ ] `./tests/run.sh` passes at ≥ the recorded baseline (baseline-green holds)

**Dependencies**: 4.2, 12.4

**Effort**: S

**Verify**: run `doc-manager` on `README.md docs/ SECURITY.md .github/ISSUE_TEMPLATE/`, then `grep -c 'MDOCTOR_' docs/DEPLOYMENT.md` returning ≥ 6

## Dependency table

| Task | Depends on | Blocks | Wave |
|---|---|---|---|
| Pre.1 | — | Pre.2, Pre.3 | 1 |
| Pre.2 | Pre.1 | 0.1 | 2 |
| Pre.3 | Pre.1 | 0.1 | 2 |
| 0.1 | Pre.2, Pre.3 | 0.2, 0.3, 0.6, 1.1, 1.2, 1.4, 1.6 | 3 |
| 0.2 | 0.1 | — | 4 |
| 0.3 | 0.1 | 0.4 | 4 |
| 0.4 | 0.3 | 0.5, 3.1 | 5 |
| 0.5 | 0.4 | 0.7, 1.7, 12.3, 12.9 | 6 |
| 0.6 | 0.1 | 0.7, 12.9 | 4 |
| 0.7 | 0.5, 0.6 | — | 7 |
| 1.1 | 0.1 | 4.1, 4.2 | 4 |
| 1.2 | 0.1 | 1.3, 4.4 | 4 |
| 1.3 | 1.2 | — | 5 |
| 1.4 | 0.1 | 1.5, 2.4 | 4 |
| 1.5 | 1.4 | 5.3 | 5 |
| 1.6 | 0.1 | 4.4, 9.5 | 4 |
| 1.7 | 0.5 | 2.1, 2.6, 2.7, 3.3, 3.4, 4.3, 4.6, 4.7, 6.1 | 7 |
| 2.1 | 1.7 | 2.2, 2.3, 2.5, 2.9 | 8 |
| 2.2 | 2.1 | 2.8, 10.6 | 9 |
| 2.3 | 2.1 | 2.8, 5.1, 5.3 | 9 |
| 2.4 | 1.4 | 5.2 | 5 |
| 2.5 | 2.1 | — | 9 |
| 2.6 | 1.7 | — | 8 |
| 2.7 | 1.7 | 5.4 | 8 |
| 2.8 | 2.2, 2.3 | 3.5, 5.3, 13.4 | 10 |
| 2.9 | 2.1 | — | 9 |
| 3.1 | 0.4 | 3.2 | 6 |
| 3.2 | 3.1 | 3.6, 6.5 | 7 |
| 3.3 | 1.7 | — | 8 |
| 3.4 | 1.7 | 12.10 | 8 |
| 3.5 | 2.8 | — | 11 |
| 3.6 | 3.2 | — | 8 |
| 4.1 | 1.1 | 7.6 | 5 |
| 4.2 | 1.1 | 7.5, 12.7, 13.7 | 5 |
| 4.3 | 1.7 | — | 8 |
| 4.4 | 1.2, 1.6 | 4.5, 9.3 | 5 |
| 4.5 | 4.4 | — | 6 |
| 4.6 | 1.7 | — | 8 |
| 4.7 | 1.7 | — | 8 |
| 5.1 | 2.3 | — | 10 |
| 5.2 | 2.4 | — | 6 |
| 5.3 | 1.5, 2.3, 2.8 | — | 11 |
| 5.4 | 2.7 | 13.6 | 9 |
| 6.1 | 1.7 | 6.2 | 8 |
| 6.2 | 6.1 | 6.3, 6.5, 6.6, 7.1, 7.2, 7.3, 7.5, 7.7, 7.8, 7.9, 12.9, 13.4 | 9 |
| 6.3 | 6.2 | 6.4, 7.1 | 10 |
| 6.4 | 6.3 | — | 11 |
| 6.5 | 3.2, 6.2 | — | 10 |
| 6.6 | 6.2 | 7.2, 7.4 | 10 |
| 7.1 | 6.2, 6.3 | 10.3 | 11 |
| 7.2 | 6.2, 6.6 | 11.9 | 11 |
| 7.3 | 6.2 | — | 10 |
| 7.4 | 6.6 | 8.1, 8.2, 8.6, 8.7, 9.3, 9.4, 9.5, 10.7, 11.4, 11.8, 12.5, 12.6 | 11 |
| 7.5 | 4.2, 6.2 | 7.6, 12.7 | 10 |
| 7.6 | 4.1, 7.5 | — | 11 |
| 7.7 | 6.2 | — | 10 |
| 7.8 | 6.2 | — | 10 |
| 7.9 | 6.2 | 10.4 | 10 |
| 8.1 | 7.4 | 8.3, 10.3, 10.7, 13.4 | 12 |
| 8.2 | 7.4 | 8.6, 9.4, 11.1, 11.2 | 12 |
| 8.3 | 8.1 | 8.4 | 13 |
| 8.4 | 8.3 | 8.5, 9.1, 12.1, 12.2, 12.3, 12.4, 13.2 | 14 |
| 8.5 | 8.4 | — | 15 |
| 8.6 | 7.4, 8.2 | 11.3 | 13 |
| 8.7 | 7.4 | 10.8, 12.10 | 12 |
| 9.1 | 8.4 | 9.2 | 15 |
| 9.2 | 9.1 | 10.1, 10.5 | 16 |
| 9.3 | 4.4, 7.4 | 11.5 | 12 |
| 9.4 | 7.4, 8.2 | — | 13 |
| 9.5 | 1.6, 7.4 | — | 12 |
| 10.1 | 9.2 | 10.2 | 17 |
| 10.2 | 10.1 | 11.6, 13.3 | 18 |
| 10.3 | 7.1, 8.1 | — | 13 |
| 10.4 | 7.9 | — | 11 |
| 10.5 | 9.2 | — | 17 |
| 10.6 | 2.2 | — | 10 |
| 10.7 | 7.4, 8.1 | — | 13 |
| 10.8 | 8.7 | 13.5 | 13 |
| 11.1 | 8.2 | 11.2 | 13 |
| 11.2 | 8.2, 11.1 | — | 14 |
| 11.3 | 8.6 | — | 14 |
| 11.4 | 7.4 | — | 12 |
| 11.5 | 9.3 | — | 13 |
| 11.6 | 10.2 | 11.7, 12.8 | 19 |
| 11.7 | 11.6 | 13.3 | 20 |
| 11.8 | 7.4 | — | 12 |
| 11.9 | 7.2 | — | 12 |
| 12.1 | 8.4 | 13.1, 13.2 | 15 |
| 12.2 | 8.4 | — | 15 |
| 12.3 | 0.5, 8.4 | — | 15 |
| 12.4 | 8.4 | 13.7 | 15 |
| 12.5 | 7.4 | — | 12 |
| 12.6 | 7.4 | 13.1 | 12 |
| 12.7 | 4.2, 7.5 | — | 11 |
| 12.8 | 11.6 | — | 20 |
| 12.9 | 0.5, 0.6, 6.2 | — | 10 |
| 12.10 | 3.4, 8.7 | — | 13 |
| 13.1 | 12.1, 12.6 | — | 16 |
| 13.2 | 8.4, 12.1 | — | 16 |
| 13.3 | 10.2, 11.7 | — | 21 |
| 13.4 | 2.8, 6.2, 8.1 | — | 13 |
| 13.5 | 10.8 | — | 14 |
| 13.6 | 5.4 | — | 10 |
| 13.7 | 4.2, 12.4 | — | 16 |

The graph is a DAG: every edge runs from a lower wave number to a strictly higher one, and every
referenced task ID exists in the plan.

## Execution waves

Tasks with no unmet dependencies, grouped by the round they can start in. Everything in a wave can
run in parallel — with `team_size: 1` this is the *permission* order, not a schedule; a single
developer walks the waves in order and picks any task within one.

| Wave | Tasks |
|---|---|
| 1 | Pre.1 |
| 2 | Pre.2, Pre.3 |
| 3 | 0.1 |
| 4 | 0.2, 0.3, 0.6, 1.1, 1.2, 1.4, 1.6 |
| 5 | 0.4, 1.3, 1.5, 2.4, 4.1, 4.2, 4.4 |
| 6 | 0.5, 3.1, 4.5, 5.2 |
| 7 | 0.7, 1.7, 3.2 |
| 8 | 2.1, 2.6, 2.7, 3.3, 3.4, 3.6, 4.3, 4.6, 4.7, 6.1 |
| 9 | 2.2, 2.3, 2.5, 2.9, 5.4, 6.2 |
| 10 | 2.8, 5.1, 6.3, 6.5, 6.6, 7.3, 7.5, 7.7, 7.8, 7.9, 10.6, 12.9, 13.6 |
| 11 | 3.5, 5.3, 6.4, 7.1, 7.2, 7.4, 7.6, 10.4, 12.7 |
| 12 | 8.1, 8.2, 8.7, 9.3, 9.5, 11.4, 11.8, 11.9, 12.5, 12.6 |
| 13 | 8.3, 8.6, 9.4, 10.3, 10.7, 10.8, 11.1, 11.5, 12.10, 13.4 |
| 14 | 8.4, 11.2, 11.3, 13.5 |
| 15 | 8.5, 9.1, 12.1, 12.2, 12.3, 12.4 |
| 16 | 9.2, 13.1, 13.2, 13.7 |
| 17 | 10.1, 10.5 |
| 18 | 10.2 |
| 19 | 11.6 |
| 20 | 11.7, 12.8 |
| 21 | 13.3 |

**Critical path** — the longest chain in the graph, one task per wave:

`Pre.1 (1d) → Pre.2 (1d) → 0.1 (3d) → 0.3 (1d) → 0.4 (2d) → 0.5 (2d) → 1.7 (1d) → 6.1 (2d) →
6.2 (2d) → 6.6 (2d) → 7.4 (2d) → 8.1 (2d) → 8.3 (2d) → 8.4 (2d) → 9.1 (2d) → 9.2 (2d) → 10.1 (2d) →
10.2 (2d) → 11.6 (1d) → 11.7 (2d) → 13.3 (2d)`

**21 tasks, 38 days.** The shape of it is the argument: nothing can be verified until the suite is
safe (0.1), nothing can be refactored until it is covered (6.1 → 7.4), and the god-module split (8.1
→ 8.4) gates the context contract, the diagnose extraction, and every count the documentation prints.

## Milestones

| ID | Phase | Exit condition (measurable) | Verify with |
|---|---|---|---|
| **ME** | Pre | `CLAUDE.md` and `AGENTS.md` exist at the repo root (created via planned `/agent-config create`); the recorded build (`bash -n` sweep), test (`./tests/run.sh`) and lint (`scripts/lint_shell.sh`) commands, the destructive-suite warning, the `pre-commit install` step and the Bash 3.2 floor are documented in `CLAUDE.md` and the Pre.1 notes | `test -f CLAUDE.md && test -f AGENTS.md && grep -q 'tests/run.sh' CLAUDE.md && grep -q '3\.2' CLAUDE.md` |
| **M0** | P0 | From a clean checkout, `./tests/run.sh` passes 9 of 9 files with no external state destroyed (no Docker volume removed, no package autoremoved); CI reproduces that run; every Actions ref is SHA-pinned and the container image digest-pinned; the six data-loss Criticals are closed | `gh run list --limit 1` on the clean-checkout job + `grep -c 'uses: .*@[0-9a-f]\{40\}' .github/workflows/ci.yml` equals the `uses:` count |
| **M1** | P1 | Zero known High/Critical advisories against any pinned dependency (W1 was empty at audit; Dependabot from Task 1.5 re-checks it continuously); `scripts/lint_shell.sh` exits 0 at `-S warning` with every remaining suppression individually justified; `main` protected by a ruleset requiring all five checks; every deletion path canonicalized before validation | `scripts/lint_shell.sh; echo $?` + `gh api repos/:owner/:repo/rulesets --jq '.[].name'` + `gh api repos/:owner/:repo/dependabot/alerts --jq 'length'` returning 0 |
| **M2** | P2 | `actions/checkout` at v7.0.1 (SHA-pinned), `pre-commit-hooks` at v6.0.0, and the Bash 3.2 floor documented as a deliberate enforced constraint with its banned-construct list — no major left undeclared | `grep -n 'actions/checkout\|pre-commit-hooks' .github/workflows/ci.yml .pre-commit-config.yaml` + the banned-construct check exiting 0 |
| **M3** | P3 | **Coverage:** `kcov` configured in the Linux CI job, publishing an HTML artifact and a percentage in the job summary, with a ratchet minimum set from it (baseline was Not Assessed, so the target is a configured tool reporting a number). **Duplication:** the size formatter exists once not 9 times, the `du` probe once not at 15 sites, the module list declared once not in 13 places. **Weak types:** in `lib/`, `checks/storage.sh`, `mdoctor` and `cleanup.sh` — zero echo-only-return helpers without a distinct failure code, and one truthy predicate across all 36 string-boolean sites | `gh run download --name coverage` + `grep -rc '1048576' --include='*.sh' --include=mdoctor .` returning 1 + `grep -rn 'du -sk' . --include='*.sh' --include=mdoctor` showing one helper + `grep -rEc '= *"?(true\|1\|yes)"?' lib/ checks/storage.sh mdoctor cleanup.sh` returning 0 |
| **M4** | P4 | All 14 `UX` findings closed. **Perf ceilings met, using the report's measured values:** pre-flight sizing of 500 files < 50 ms (was 843 ms, 210x over one `find -printf` pass); traversal of an 81-`node_modules` workspace ≤ 835 directories (was 3,986, 4.8x); field extraction over 200 lines < 10 ms (was 943 ms, 314x); and **zero uncapped blocking network or daemon calls** (was ~15 with 1 capped). **Docs:** every hand-maintained count derived from the registry and the guidebook covering both platforms | the four timed/counted checks recorded in Tasks 11.1, 11.3, 11.4 and 11.7 + `grep -rc '21 checks\|10 modules\|9 targets' README.md docs/` returning 0 + the Task 13.2 count-comparison test |

## Deferred and out of scope

**No Critical or High finding is deferred.** All 10 Critical and all 53 High findings are closed by a
named task above. Two Medium findings are deliberately deferred:

| ID | Severity | Why deferred | Revisit when |
|---|---|---|---|
| `F-DEAD-025` | Medium | The `openspec/` tree is 109 of the repo's 226 tracked files — 48% of the repository. All 18 change folders are archived (90 tracked files between them), there are zero active ones, the last commit touching it is 2026-02-24, and the 13 commits since (all of Linux support, the v3.0.0 release, the diagnose command and two bugfix PRs) bypassed the workflow. But the report's own fix direction begins "Confirm with the owner": untracking half a repository, or restarting an abandoned process, is a maintainer decision this plan cannot make on evidence alone. Task 10.6 handles the independent `.specify/` tree and the ignore-rule contradictions; the exclusion entries `openspec/` forced into four config files stay until this is settled | the maintainer confirms whether the openspec workflow is abandoned or being restarted. If abandoned, this becomes a one-task `git rm -r --cached` plus the four exclusion removals; if restarted, it becomes a documentation task recording the four post-February releases |
| `F-CLEAN-005` | Medium | Renaming 10 module entry points so dispatch can be by convention (5 of 22 check modules and 5 of 11 cleanup modules break it; all 10 fix modules follow it, which is why `cmd_fix` dispatches in one line while `cmd_check` needs a 22-arm case) is churn across 10 files with an aliasing period, and it competes directly with Task 8.1, which makes the registry the single source of truth and removes most of the pain by other means. Doing both at once would make Task 8.1's diff unreviewable. Task 10.7 closes the related `F-DEAD-014` (the duplicate registry in `doctor.sh`) without the renames | Task 8.1's registry has shipped and one release has gone out on it. If the dispatch cases are then still hand-written, do the renames with one release of aliases; if the registry has already made them dead, delete the cases instead and this finding closes for free |

## Risks

| Risk | Affects | Mitigation |
|---|---|---|
| **Task 0.1 is the plan's single point of failure.** Every other task's baseline-green criterion is unexecutable until the suite is hermetic, and 0.1 is the plan's only 3-day P0 task | every task | 0.1 is wave 3, immediately after Pre. Until it lands the substituted pre-0.1 assertion (the `bash -n` sweep plus the 8 safe files) is the contract, stated at the top of the plan so nobody silently weakens a criterion |
| **Task 2.1's ShellCheck backlog is an unknown quantity.** ShellCheck was not installed on the audit machine, so the claim that `-S warning` surfaces real findings is argued from the lint policy line alone, not from a measured backlog. It could surface 5 findings or 500 | 2.1, 2.9, and any P1/P4 task that inherits a warning | 2.1 is explicitly a measurement task whose acceptance is producing and triaging the inventory, not hitting a count. If the backlog is large, the per-line disable inventory absorbs it and the fixes distribute into later sprints rather than blocking the sprint |
| **All macOS-only code paths in this plan were verified by reading source, never on a real macOS system.** The audit ran on Arch Linux; the Xcode and iOS-backup cleanups, the battery/Bluetooth/USB/Homebrew checks, seven of the ten fix modules and the `/Library` probes in `F-BUG-002` were never executed | 0.3, 1.3, 6.3, 11.6, 12.6 and every macOS assertion | Every one of those tasks carries a stub-`PATH` argv-recorder criterion that runs on Linux, and Task 7.5 matrixes release-sanity onto macOS. Land the macOS-facing tasks only after a green run on a macOS runner, not on local Linux evidence alone |
| **Coverage figures in the report were reconstructed by hand from call graphs, not measured.** A module reachable through a mis-read branch could be more or less covered than reported, so the Sprint 7 backfill list (14 modules, 33 exit-status-only modules) may be wrong at the edges | 7.1–7.4, and M3's coverage clause | Task 6.1 lands `kcov` *before* any backfill task, so the real picture replaces the reconstructed one. If 6.1 contradicts the report's module list, re-scope 7.1–7.4 from the measurement rather than from the report |
| **The P3 refactors are large and the tests that make them safe land immediately before them.** 8.1–8.7 and 9.1–9.5 touch the registry, the god module, `check_storage`, the module contract and all 24 deletion call sites | Sprint 8, Sprint 9, Sprint 10 | Every task in those sprints depends on Task 7.4 (behavioural assertions for the 33 exit-status-only modules), which is the plan's "tests covering the code it touches" precondition. Do not start Sprint 8 with 7.4 incomplete |
| **`F-BUG-016` was deduplicated at the source — do not go looking for it.** An earlier reading of the report flagged it as cited in the cross-cutting pattern "External commands that can block are uncapped" while having no row in the `BUG` findings table. That is resolved: `F-BUG-016` was one of 29 IDs removed by the report's deduplication step, merged into **`F-DEP-009`** (the `ping -W` unit inversion at `checks/network.sh:12`), which carries the higher severity of the two. The cross-cutting pattern now names `F-DEP-009` and the report documents the deduplication explicitly. There is no missing row and nothing to restore | Task 2.5 closes `F-DEP-009`; Task 11.7 covers the uncapped-call pattern | No action. Task 11.7's acceptance is a *census* — the count of uncapped blocking external calls must reach 0 across the ~15 named sites — so the pattern is covered whole regardless of how its constituent IDs were merged. An executor who finds a stale `F-BUG-016` reference in an older copy of the report should read `F-DEP-009` instead |
| **Two Critical findings are closed by tasks that change user-visible behaviour on the destructive path.** Task 0.5 adds a confirmation prompt where none existed and Task 0.6 puts `docker system prune --volumes` behind an opt-in — both will break anyone scripting `mdoctor clean --force` today | 0.5, 0.6, and any downstream automation | Both tasks require the non-tty behaviour to be explicit (0.5 refuses without an assume-yes variable, and names it in the refusal). Ship them together in one release with a changelog breaking-change entry, and Task 13.6 makes that changelog the authoritative one |
| **Task 4.1 changes what every user installs.** Pinning the installer to signed release tags means the four decorative tags become load-bearing overnight, and any user tracking `main` today silently stops receiving commits | 4.1, 7.6, 13.7 | 4.1 requires an opt-in channel for tracking `main`, named in `--help`; Task 7.6 covers the curl-pipe, remote-clone and update-in-place paths in CI before it ships; Task 13.7 updates `SECURITY.md`'s supported-versions row to the tag range this makes meaningful |
| **`openspec/` stays excluded from every gate while `F-DEAD-025` is deferred.** 109 tracked files, including whatever shell lives under them, remain outside ShellCheck and the syntax sweep | Task 10.6, and the completeness of M1's lint clause | Task 10.6 closes the `.specify/` half of the same problem so the exclusion list shrinks to one entry, making the remaining gap explicit rather than buried among four. Escalate the owner decision during Sprint 2, so it can land inside Sprint 10 if answered |
