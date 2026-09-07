# Code Review Report

**Date**: 2026-09-05
**Scope**: Full Audit — mdoctor v3.0.0 Bash CLI (`mdoctor`, `cleanup.sh`, `doctor.sh`, `install.sh`, `uninstall.sh`, `lib/**`, `checks/**`, `cleanups/**`, `fixes/**`, `scripts/**`)
**Mode**: Mode 2 (Medium Audit — six parallel `file-reviewer` batches over the periphery, orchestrator deep-read of the destructive core)
**Files Reviewed**: 59 (7,481 LOC)
**Excluded**: `.git`, `.specify`, `.claude`, `openspec`, `assets`, `docs`. `docs/SAFETY.md` and `README.md` were consulted for contract context only, not reviewed.

> Every finding cites a line that was read. Findings marked **PROVEN** were additionally reproduced in an
> isolated scratchpad. **No script from this repository was executed** and **no source file was modified**
> (`git status` clean apart from this report).

## Summary

| Severity | Count |
|----------|-------|
| Critical | 6     |
| Major    | 15    |
| Minor    | 29    |
| Info     | 4     |

**One-line verdict:** `lib/safety.sh` is a well-designed deletion-safety layer that is bypassed or defeated
on nearly every path that matters — the Linux log target is the entire XDG data root, no confirmation
prompt exists anywhere in the codebase, all 24 deletion call sites discard the safety layer's return code,
and `fixes/**` and the installers do not use the safety layer at all.

---

# Critical Issues

## C1 — `clean_logs` deletes the entire XDG data root on Linux
**File**: `cleanups/logs.sh:13`, `lib/platform.sh:105`
**Smell**: Wrong abstraction boundary · **PROVEN**

`clean_logs` deletes every regular file older than `DAYS_OLD` (default 7), at unbounded depth, under
`platform_user_log_dir`. On Linux that returns `${HOME}/.local/share` — the XDG *data* root, not a log
directory.

Measured on the review machine: **103,440 files / 2.18 GB**, including `~/.local/share/keyrings` (GNOME
Keyring secrets), `~/.local/share/pki`, `~/.local/share/applications`, `~/.local/share/nvim` (7,935),
`~/.local/share/mise` (70,494), `~/.local/share/uv` (23,236), `~/.local/share/virtualenv` (947).

This is a **regression from the Linux port** (`4788678 feat: add Linux (Debian/Ubuntu) cross-platform
support`) and it contradicts the project's own contract: `docs/SAFETY.md:114` states the Linux "User log
dir" is `~/.local/share/mdoctor`. macOS is unaffected (`~/Library/Logs` is a genuine log directory).

Aggravating factors, each verified:
1. **The safety layer does not stop it.** `validate_deletion_path("$HOME/.local/share")` returns 0;
   `is_protected_deletion_path` has no rule for `$HOME/.local`. The default whitelist
   (`lib/safety.sh:118-131`) contains only comments.
2. **The UI mislabels it.** `cleanup.sh:217` and `mdoctor:192` present the path as `"Old logs (>7d)"`.
3. **No confirmation is possible** (see C3).
4. **It destroys its own audit trail.** `LOGFILE` is `~/.local/share/mdoctor/mdoctor_cleanup.log`
   (`cleanup.sh:51`, `lib/platform.sh:86`) — inside the delete target — so it removes the exact recovery
   artifact `docs/SAFETY.md:86` tells users to inspect.
5. The module is rated `[LOW]` (`mdoctor:981`) and `README.md:20` advertises "Safe by default".

**Before** (`lib/platform.sh:100-107`):
```bash
platform_user_log_dir() {
  if is_macos; then
    echo "${HOME}/Library/Logs"
  else
    # Linux user logs are scattered; use /var/log for system, ~/.local/share for user
    echo "${HOME}/.local/share"
  fi
}
```

**Suggested Fix**:
```bash
platform_user_log_dir() {
  if is_macos; then
    echo "${HOME}/Library/Logs"
  else
    # ~/.local/share is the XDG *data* root (keyrings, toolchains, app state).
    # Only mdoctor's own subtree is a safe recursive-delete target.
    echo "${XDG_DATA_HOME:-${HOME}/.local/share}/mdoctor"
  fi
}
```
Also add `$HOME/.local`, `$HOME/.local/share`, `$HOME/.config` to `is_protected_deletion_path`.

---

## C2 — An empty `$HOME` collapses cleanup targets onto real system directories
**File**: `lib/platform.sh:84,93,102,112`, `lib/safety.sh:209`, `cleanups/caches.sh:9`, `cleanups/logs.sh:10`, `cleanups/trash.sh:9`
**Smell**: Unvalidated environment input · **PROVEN**

`set -u` catches an *unset* `HOME` but not `HOME=""`, which occurs in cron, launchd, systemd units, `sudo`
without `-H`, and minimal containers. Every `platform_*_dir` helper interpolates `${HOME}` with no
emptiness check, so on macOS:

| Helper | `HOME=""` result | Real directory? |
|---|---|---|
| `platform_cache_dir` (`:93`) | `/Library/Caches` | yes — system-wide cache |
| `platform_user_log_dir` (`:102`) | `/Library/Logs` | yes — system log tree |

Both pass the safety layer. Verified probe results: `/Library` is blocked as an exact match
(`lib/safety.sh:201`) but there is **no `/Library/*` prefix rule** at `:204` (unlike `/etc/*`, `/var/*`,
`/usr/bin/*`), so `/Library/Caches` and `/Library/Logs` are **ALLOWED**.

Compounding it, `lib/safety.sh:209` wraps the entire home-protection block in `[ -n "${HOME:-}" ]`, so with
an empty `HOME` **all `$HOME`-based protections are skipped too**. Verified:

```
HOME=""  /Desktop     **ALLOWED**
HOME=""  /Documents   **ALLOWED**
HOME=""  /.ssh        **ALLOWED**
HOME=""  /.gnupg      **ALLOWED**
```

A related asymmetry: `is_protected_deletion_path` normalises the *input* path (`:198`) but compares against
the raw `$HOME` (`:211`), so a trailing-slash `HOME` (e.g. `HOME=/root/`) leaves `$HOME` itself unprotected
— also verified.

**Before** (`lib/safety.sh:209-215`):
```bash
  if [ -n "${HOME:-}" ]; then
    case "$path" in
      "$HOME"|"$HOME/Desktop"|"$HOME/Documents"|"$HOME/Library"|"$HOME/.ssh"|"$HOME/.gnupg")
        return 0
        ;;
    esac
  fi
```

**Suggested Fix** — fail closed, and normalise both sides:
```bash
  # An empty HOME must never mean "no home protections"; every ${HOME}-derived
  # cleanup target would collapse onto a system path.
  if [ -z "${HOME:-}" ]; then
    return 0   # treat every target as protected
  fi
  local home_norm
  home_norm="$(_normalize_path "$HOME")"
  case "$path" in
    "$home_norm"|"$home_norm"/Desktop|"$home_norm"/Documents|"$home_norm"/Library|"$home_norm"/.ssh|"$home_norm"/.gnupg)
      return 0
      ;;
  esac
```
Add `/Library/*` to the prefix list at `:204`, and have each cleanup module refuse to run on an empty `HOME`.

---

## C3 — No confirmation prompt exists anywhere; `--force` deletes immediately
**File**: `cleanup.sh:274-276`, `mdoctor:702-710`, `mdoctor:551-555`
**Smell**: Missing guard on an irreversible action · **PROVEN**

A repo-wide search for `read -p`, `read -r -p`, `[y/N]`, `(y/n)`, `Are you sure`, `confirm` across every
`.sh` file and the `mdoctor` script (excluding `tests/`) returns **zero matches**. The force path prints
`cleanup_force_preflight_summary` and falls straight through to execution. The only `read` in the CLI is the
interactive module *picker* (`mdoctor:619`), which chooses which modules run, not whether to delete.

`docs/SAFETY.md:101` states "`--force` deletions are not automatically undoable", which makes this the
highest-leverage single fix in the codebase. `cleanups/trash.sh:12` destroys real user files (not a
regenerable cache) behind this same unguarded flag.

**Before** (`cleanup.sh:274-278`):
```bash
	if [ "$DRY_RUN" = false ]; then
		cleanup_force_preflight_summary
	fi

	header "Starting cleanup (DRY_RUN=${DRY_RUN}, platform=$(platform_name))"
```

**Suggested Fix**:
```bash
	if [ "$DRY_RUN" = false ]; then
		cleanup_force_preflight_summary
		if [ "${MDOCTOR_ASSUME_YES:-false}" != true ]; then
			if [ ! -t 0 ]; then
				echo "Refusing --force non-interactively without MDOCTOR_ASSUME_YES=true." >&2
				exit 1
			fi
			printf "Delete the targets listed above? [y/N] "
			read -r reply
			case "$reply" in [yY]|[yY][eE][sS]) ;; *) echo "Aborted."; exit 0 ;; esac
		fi
	fi
```
An explicit `MDOCTOR_ASSUME_YES` also gives CI and the test suite a deliberate, auditable opt-in.

---

## C4 — The project's own test suite destroys real Docker volumes and system packages
**File**: `tests/test_force_preflight_resilience.sh:52`, `tests/run.sh:6`, `tests/run.sh:18`
**Smell**: Test with uncontained side effects · **PROVEN by static trace** (never executed — this machine has live Docker state)

`tests/run.sh:6` globs `test_*.sh` and `:18` runs each, so the force test is in the default suite. Line 52
invokes the real destructive entry point.

**Before**:
```bash
HOME="$TMPHOME" ./cleanup.sh --force >"$out_file" 2>&1 || true
```

The `HOME` override contains *filesystem* deletions, but two operations are **not `HOME`-scoped**:

| Reached code | Effect on the developer's machine |
|---|---|
| `cleanups/dev_caches.sh:84` — `docker system prune -af --volumes` | destroys **all** unused Docker volumes, images and networks |
| `cleanups/apt.sh:19,26` — `sudo apt-get clean` / `autoremove -y` | removes real system packages; blocks on a sudo password prompt mid-test |

Verified chain: `tests/run.sh:18` → `test_force_preflight_resilience.sh:52` → `cleanup.sh:59`
(`DRY_RUN=false`) → `cleanup.sh:307-313` → `cleanups/dev_caches.sh:82-84` / `cleanups/apt.sh:19-26` →
`lib/logging.sh:182` (DRY_RUN gate is false) → `lib/logging.sh:191` (`"$@"` executes).

`.github/workflows/ci.yml:51,83,112` run the same suite — acceptable on ephemeral runners, but identical on
a contributor's laptop following `CONTRIBUTING.md`.

**Suggested Fix**: the test asserts only on preflight output (`:58-68`), so it never needs the cleanup
phase. Add an early return after `cleanup.sh:276` and use it:
```bash
# cleanup.sh, after the preflight summary
	if [ "${MDOCTOR_PREFLIGHT_ONLY:-false}" = true ]; then
		exit 0
	fi
```
```bash
# tests/test_force_preflight_resilience.sh:52
HOME="$TMPHOME" MDOCTOR_PREFLIGHT_ONLY=true ./cleanup.sh --force >"$out_file" 2>&1 || true
```
Until that lands, rename the file out of the `test_*.sh` glob so `tests/run.sh` cannot pick it up.

---

## C5 — Installers `rm -rf` an unvalidated, environment-controlled path, bypassing the safety layer
**File**: `uninstall.sh:12`, `uninstall.sh:42`, `install.sh:19`, `install.sh:105-110`
**Smell**: Missing input validation on an irreversible operation

`INSTALL_DIR="${MDOCTOR_INSTALL_DIR:-${HOME}/.mdoctor}"` is taken straight from the environment in both
scripts and passed to `rm -rf`, guarded only by `[ -d ... ]`. Neither script sources `lib/safety.sh`
(verified: zero `source` lines in `uninstall.sh`), so `validate_deletion_path` never runs. Both document
`curl -fsSL … | bash` invocation (`install.sh:6`, `uninstall.sh:6`), which inherits the caller's environment.

`install.sh` is worse: `:101` tests only `[ -d "$INSTALL_DIR" ]` and never checks the directory is an
mdoctor checkout. Any `git pull --ff-only` failure — local edits, untracked files, a force-pushed remote —
triggers the `||` block and deletes the whole directory. `2>/dev/null` at `:105` hides why.

`MDOCTOR_INSTALL_DIR="$HOME" ./uninstall.sh` deletes the home directory.

**Before** (`uninstall.sh:40-43`):
```bash
if [ -d "$INSTALL_DIR" ]; then
  info "Removing ${INSTALL_DIR}"
  rm -rf "$INSTALL_DIR"
fi
```

**Suggested Fix**:
```bash
if [ -d "$INSTALL_DIR" ]; then
  case "$INSTALL_DIR" in
    "$HOME"|"$HOME/"|/|"") echo "Refusing to remove unsafe path: $INSTALL_DIR" >&2; exit 1 ;;
  esac
  if [ ! -x "${INSTALL_DIR}/mdoctor" ] || [ ! -d "${INSTALL_DIR}/.git" ]; then
    echo "Refusing: ${INSTALL_DIR} does not look like an mdoctor installation." >&2
    exit 1
  fi
  info "Removing ${INSTALL_DIR}"
  rm -rf -- "$INSTALL_DIR"
fi
```
Apply the same precondition to `install.sh:108`, and prefer clone-to-temp-then-swap over delete-then-clone
so a failed clone cannot leave the user with nothing.

Related: `REPO_URL` (`install.sh:18`) is environment-overridable and the clone is symlinked into
`/usr/local/bin` **with sudo** (`install.sh:133`), so `MDOCTOR_REPO_URL` silently controls what is installed
as the `mdoctor` binary.

---

## C6 — `fix permissions` recursively chowns `/usr/local` on every platform, unguarded
**File**: `fixes/permissions.sh:22-23`
**Smell**: Unscoped recursive ownership change

**Before**:
```bash
echo "Resetting /usr/local permissions..."
sudo chown -R "$(whoami)" /usr/local 2>/dev/null || true
```

This sits **outside** the `command -v brew` branch above it (`:13-20`) and has **no `is_macos` guard** —
verified: `fixes/permissions.sh` contains zero occurrences of `is_macos`. On macOS with Homebrew this is
conventional; on Debian/Ubuntu `/usr/local` is a real FHS tree holding locally-installed software shared
across users and services, and recursively reassigning it to a single unprivileged user is a local
privilege-escalation setup.

It is reachable on Linux today: `mdoctor`'s direct fix dispatch
(`case "$target" in homebrew|dns|disk|permissions|spotlight|bluetooth|audio|wifi|timemachine|apt)`) has
**no platform filter** — only the `register_module` registry used by `fix all` and `--help` is
`is_macos`-gated. The failure is swallowed by `2>/dev/null || true`, so a partial chown still prints
"Permissions reset complete."

**Suggested Fix**:
```bash
if is_macos && command -v brew >/dev/null 2>&1; then
  echo "Resetting /usr/local permissions..."
  if sudo chown -R "$(whoami)" /usr/local; then
    echo "${GREEN}Permissions reset complete.${RESET}"
  else
    echo "${RED}Failed to reset /usr/local permissions.${RESET}" >&2
    return 1
  fi
else
  echo "${DIM}Skipping /usr/local ownership reset (not applicable on this platform).${RESET}"
fi
```
Also add a platform check to `cmd_fix`'s dispatch `case` so macOS-only targets cannot be selected on Linux.

---

# Major Issues

### M1 — `find` without `-print0` lets a newline in a path delete the wrong directory
`cleanups/dev_caches.sh:111`, `cleanups/dev_caches.sh:135` · **PROVEN**

The stale-`node_modules` scan reads newline-delimited `find` output. A directory whose name contains a
newline splits across iterations; the first fragment is a **valid, absolute, unprotected, non-whitelisted
prefix path**, so `safe_remove` accepts it. Reproduced with `important_project/` (containing source) beside
`important_project\nX/node_modules`:

```
safe_remove <- [.../important_project]   ABSOLUTE AND EXISTS -> WOULD BE rm -rf'd
safe_remove <- [X/node_modules]          relative -> rejected
```

The safety layer cannot catch this: the fragment has no `..`, no control characters (the newline is what
split it), and is not protected. The codebase already does this correctly at `cleanup.sh:163` and
`mdoctor:138`.

**Fix**: `-print0` on the `find`, `read -r -d ''` on the loop.

### M2 — Unhardened `du -sk | awk` still aborts or silently skips cleanup (issue #9 only half-fixed)
`cleanups/dev_caches.sh:27,122`, `cleanups/xcode.sh:16,50`, `cleanups/ios_backups.sh:29`, `checks/storage.sh:33,51`, `checks/diagnose_performance.sh:364` · **PROVEN**, and self-documented at `tests/test_force_preflight_resilience.sh:13-17`

Issue #9 was fixed only inside `cleanup.sh` (`:142`, `:161`). Reproduced behaviour when `du` hits a
permission-denied subdirectory (common: a root-owned file under `~/.npm` from a past `sudo npm`):

| Entry point | `set` flags | Result |
|---|---|---|
| `cleanup.sh` | `set -euo pipefail` (`:13`) | assignment fails → **entire run aborts silently mid-cleanup**, after Trash/caches/logs are already deleted |
| `mdoctor` | `set -uo pipefail` (`:24`, no `-e`) | value empty → `(( sz > 0 ))` false → **cache silently not cleaned**, reported as success |

`cleanups/dev_caches.sh:27` is live on both platforms (`cleanup.sh:41` sources it unconditionally).
`checks/storage.sh:34,52` apply `${sz:-0}` on the *following* line, which is too late under `set -e`.

**Fix**: the shape already proven at `cleanup.sh:142` — `sz=$({ du -sk "$p" 2>/dev/null || true; } | awk '{print $1+0}')`. Extract it into `lib/disk.sh` and call it from all ten sites.

### M3 — `progress_start` clobbers the caller's EXIT trap, so the cleanup session never closes
`lib/common.sh:96`, `cleanup.sh:130` · **PROVEN** (bash EXIT traps replace, they do not stack)

`cleanup.sh:130` installs `trap _finish_cleanup_session EXIT`. The first `step` reaches `progress_start`,
which at `lib/common.sh:96` installs `trap 'progress_stop' EXIT`, silently replacing it. `op_session_end`
(`cleanup.sh:121-127`) therefore never fires on any interactive run. Invisible to tests: `progress_start`
returns early at `lib/common.sh:43` (`[ -t 1 ] || return 0`) and every test redirects to a file.
`lib/benchmark.sh:28` installs a third EXIT trap and `:123` then does `trap - EXIT`, removing whatever was
in place.

**Fix**: never install a global trap from a helper — entry points own their EXIT trap and call
`progress_stop` from it (`cleanup.sh:120` already does).

### M4 — All 24 deletion call sites discard the safety layer's error code with `|| true`
`cleanups/logs.sh:13`, `trash.sh:12`, `caches.sh:12`, `crash_reports.sh:20`, `dev_caches.sh:34,131`, `browser.sh:13,17,21,27,31,35`, `dev.sh:22,25,31,34,37,40,45,48`, `xcode.sh:27,37,61`, `ios_backups.sh:67` · **PROVEN**

`lib/safety.sh:10-15` defines a six-value error taxonomy with dedicated `safety_error_name` /
`safety_error_hint` renderers. Every call site flattens it to success, so no caller can distinguish "freed
40 GB" from "every target was blocked". Demonstrated: on Linux `platform_crash_dirs` yields `/var/crash`,
which `is_protected_deletion_path` blocks with code 22; `cleanups/crash_reports.sh:20` swallows it and the
module reports success while doing nothing.

**Fix**: replace `|| true` with `|| rc=$?` plus a `case` that distinguishes expected skips (22) from real
failures (24/26), and propagate the latter.

### M5 — `grep -c … || echo 0` double-fires and corrupts the captured count
`checks/security.sh:107`, `checks/security.sh:121`, `checks/updates.sh:36`, `checks/updates.sh:47` · **PROVEN**

`grep -c` prints `0` **and** exits 1 on zero matches, so `|| echo 0` appends a second `0`. Verified:

```
$ x=$(printf 'a\nb\nc\n' | grep -c zzz || echo 0); printf '%q\n' "$x"
0$'\n'0
$ (( x > 0 ))
bash: ((: 0
0: arithmetic syntax error in expression (error token is "0")
```

This fires on the **healthy** path (no upgradable packages, no iptables rules) and prints a raw bash error
to the user's terminal. The correct `|| true` form already sits three lines away in the same file
(`checks/security.sh:71,78`).

**Fix**: `|| true` — `grep -c` already emits `0`.

### M6 — `ping -W 1000` means 1000 **seconds** on Linux
`checks/network.sh:12`, `checks/network.sh:19` · **PROVEN** from this machine's `man ping`

> `-W timeout` — Time to wait for a response, **in seconds**.

On macOS/BSD `-W` is milliseconds, so `-W 1000` is a sane ~1 s there. Both calls run before any `is_macos`
branch, so on Linux each can block for up to 1000 s (~33 min total) when the host is unreachable or ICMP is
firewalled — precisely the situation this connectivity check exists to diagnose. The tool appears to hang.

**Fix**: `-W 1` on Linux, or `timeout 2 ping -c 1 …`.

### M7 — Nine predictable `/tmp` filenames opened with `>` (symlink clobber)
`checks/devtools.sh:47`, `checks/python.sh:24,34`, `checks/node.sh:24,34`, `checks/homebrew.sh:21,31`, `lib/logging.sh:18`, `lib/benchmark.sh:24`

Each builds a fixed or trivially-guessable path in world-writable `/tmp` and opens it with a plain `>`,
which follows symlinks (CWE-377). A local attacker can pre-create the path as a symlink and have the
victim's own run truncate the target. Without malice, a stale file owned by another user makes the redirect
fail, so `checks/devtools.sh:48` concludes the Docker daemon is unreachable and emits a false warning at
`:51`. `lib/safety.sh:379-380` already demonstrates the correct `mktemp` pattern in this codebase.

### M8 — `is_protected_deletion_path` is an incomplete denylist with inconsistent prefix coverage
`lib/safety.sh:196-228` (`:201`, `:204`) · **PROVEN** (every path below was probed)

| Path | Verdict |
|---|---|
| `/etc`, `/etc/passwd`, `/var`, `/var/lib` | protected (exact **and** `/*`) |
| `/Library` | protected — but `/Library/Logs/DiagnosticReports` **ALLOWED** |
| `/Applications` | protected — but `/Applications/Safari.app` **ALLOWED** |
| `/usr` | protected — but `/usr/local`, `/usr/local/bin`, `/usr/share` **ALLOWED** |
| `/home`, `/root`, `/opt`, `/srv`, `/mnt`, `/media` | **ALLOWED** |
| `$HOME/Desktop`, `$HOME/Documents` | protected |
| `$HOME/Downloads`, `$HOME/Pictures`, `$HOME/.config`, `$HOME/.local` | **ALLOWED** |

No current call site reaches these gaps *except* via C1 and M1 — which is why this is Major, not Critical.
But it is the last line of defence and it does not hold.

**Fix**: add a positive allowlist (`is_allowed_deletion_root`) requiring every target to sit under a known
cache/temp root, keeping the denylist as a backstop.

### M9 — `fixes/**` bypasses the DRY_RUN convention entirely — `mdoctor fix` has no dry-run at all
`fixes/*.sh` (all 10 files) · **PROVEN**

Verified counts across `fixes/`: `run_cmd_args` **0**, `run_cmd` **0**, `op_record` **0**, `safe_remove`
**0**, `validate_deletion_path` **0**. Every `sudo` call executes directly. So `mdoctor clean` defaults to
dry-run and writes an operation log, while `mdoctor fix` — which runs `chown -R`, `apt-get upgrade -y`,
`killall`, `mdutil -E /` — has neither preview nor audit trail. This asymmetry is undocumented.

### M10 — Five `fixes/` modules are macOS-only, unguarded, and report false success on Linux
`fixes/audio.sh:13`, `fixes/wifi.sh:14`, `fixes/spotlight.sh:19`, `fixes/timemachine.sh:39`, `fixes/disk.sh:39` · **PROVEN** (guard census below)

```
fixes/audio.sh         macOS-cmds=1  is_macos-guards=0   <-- UNGUARDED
fixes/disk.sh          macOS-cmds=2  is_macos-guards=0   <-- UNGUARDED
fixes/dns.sh           macOS-cmds=2  is_macos-guards=1        (correct)
fixes/spotlight.sh     macOS-cmds=3  is_macos-guards=0   <-- UNGUARDED
fixes/timemachine.sh   macOS-cmds=3  is_macos-guards=0   <-- UNGUARDED
fixes/wifi.sh          macOS-cmds=6  is_macos-guards=0   <-- UNGUARDED
```

Each swallows failure with `2>/dev/null || true` and then prints an unconditional success message —
"Core Audio daemon restarted", "Wi-Fi fix complete", "Spotlight index rebuild initiated" — for a complete
no-op. Two are worse than no-ops: `fixes/bluetooth.sh:16` `sudo pkill -HUP bluetoothd` *does* match BlueZ's
daemon on Linux, bypassing systemd supervision; `fixes/spotlight.sh` can leave Spotlight **disabled** on
macOS if the final `mdutil -a -i on` fails, while still printing success.

### M11 — `fix apt` runs an unattended whole-system upgrade with no confirmation
`fixes/apt.sh:26`, `fixes/apt.sh:29`

`sudo apt-get upgrade -y` and `sudo apt-get autoremove -y` execute immediately with no prompt, no dry-run,
and no exit-code checks on any of the six `sudo` calls — so a failed `apt-get update` (`:19`) still proceeds
against stale indices and prints "APT package manager fix complete." Without `DEBIAN_FRONTEND=noninteractive`
a modified conffile opens a debconf prompt and hangs an unattended run. Header says `Risk: LOW`.

### M12 — Browser caches are wiped with no check that the browser is running
`cleanups/browser.sh:13,17,21,27,31,35`

None of the six `safe_remove_children` calls is preceded by a process check. Running
`mdoctor clean -m browser --force` with Chrome/Firefox open deletes cache index and journal files out from
under the live process, risking profile corruption.

### M13 — `checks/security.sh` executes `sudo` inside a file whose header says "read-only, SAFE"
`checks/security.sh:96`, `checks/security.sh:107`

These are the **only** two places in the entire `checks/` tree where `sudo` is executed rather than merely
suggested via `add_action` text. This can trigger an interactive password prompt in the middle of a passive
audit, and when sudo fails silently the `iptables` branch has no non-sudo fallback — it reports
"Firewall (iptables): no rules configured" and advises configuring rules, a false negative about the
machine's security posture.

### M14 — `mdoctor history` hangs forever if any single history file is unreadable
`lib/history.sh:77`, `lib/history.sh:125` · **PROVEN**

```bash
while (( i < total )); do
  local file="${files[$i]}"
  line="$(cat "$file" 2>/dev/null)" || continue   # :77
  ...
  i=$((i + 1))                                    # :125 — the LAST statement
done
```

`continue` jumps straight back to the loop condition, **skipping the increment**, so the same index is
retried forever. Triggered by a file deleted or permission-changed between the `find` at `:54` and the read
at `:77`. Reproduced faithfully: the loop had to be killed by `timeout`.

**Fix**: increment before `continue`, or move `i=$((i + 1))` to the top of the body.

### M15 — `md_init` writes a predictable `/tmp` report path on **every** `mdoctor check`
`lib/logging.sh:18-19`

```bash
REPORT_MD="/tmp/mdoctor_report_$(date +%Y%m%d_%H%M%S).md"
: > "$REPORT_MD"   # truncating redirect, follows symlinks
```

Second-resolution timestamp in world-writable `/tmp`, truncating open, no `mktemp`. `md_init` is the first
statement of `doctor.sh:134`'s `main()`, and `doctor.sh` is what `mdoctor` execs for `check` (`mdoctor:411`)
— so this is the most-exercised path in the tool, not an edge case. This is the highest-impact instance of
M7.

---

# Minor Issues

| # | File:line | Issue |
|---|---|---|
| m1 | `lib/safety.sh:162-194`, `:93-109` | Whitelist matching is purely lexical. **PROVEN**: with entry `~/.ollama/models`, `/home/u//.ollama/models` and `/home/u/./.ollama/models` are **NOT PROTECTED**. Both pass `validate_deletion_path` (no `..`). Canonicalise `//` and `/./` in `_normalize_path`. |
| m2 | `lib/safety.sh:396` | `safe_find_delete` passes `--allow-symlink` unconditionally, contradicting the documented default at `:284-287` and `:60`. Impact is bounded and was verified: `find -type f` skips symlinks and `rm -rf` removes the link, not the target — a policy inconsistency, not a destruction vector. |
| m3 | `cleanups/downloads.sh:12-14` | Deletion is commented out; only `find … -print` runs. Yet `downloads` is an advertised module (`mdoctor:460,505`), counted in `PROGRESS_TOTAL` (`cleanup.sh:88,90`) and given a preflight size (`cleanup.sh:214`). Users believe files were removed. |
| m4 | `cleanups/crash_reports.sh:20`, `lib/platform.sh:124-125` | Linux crash cleanup is a no-op: `/var/crash` is blocked (code 22, swallowed), `~/.local/share/apport` usually absent, and the `*.crash -o *.diag -o *.ips` filter is macOS-centric. |
| m5 | `cleanups/trash.sh:12`, `lib/platform.sh:114` | Linux Trash cleanup removes `Trash/files/*` but never the matching `Trash/info/*.trashinfo`, leaving orphaned metadata and phantom entries in the desktop trash UI (freedesktop.org spec). |
| m6 | `mdoctor` `cmd_fix` dispatch `case`, and its `*)` arm | Fix-target `case` has no platform gate (root cause of C6/M10). The `*)` arm silently treats any unrecognised token — including `--typo` — as the target, unlike `cmd_clean` (`mdoctor:468-472`) which errors. |
| m7 | `checks/network.sh:158` | `net_drops` reads `awk '{print $8}'` = `Opkts` (total packet count), not a drop/error column; `$9` (`Oerrs`) was intended. Makes `(( net_drops > 0 ))` true on essentially every run. |
| m8 | `checks/network.sh:48` | Active interface parsed as `$5` of `ip route show default`; breaks for gateway-less routes (`default dev ppp0 scope link`), silently poisoning every downstream network check. |
| m9 | `checks/shell.sh:61` | Bare `source foo.sh` is resolved against `$HOME`, and embedded variables are never expanded, so `source "$HOME/.cargo/env"` becomes `$HOME/$HOME/.cargo/env` → false "sources missing file" warnings for rustup/nvm/oh-my-zsh. |
| m10 | `checks/shell.sh:46,49` | GNU-only `\s` in `grep -E`/`sed -E` while line 50 correctly uses `[[:space:]]`; not POSIX ERE, unreliable on BSD tools on the primary supported platform. |
| m11 | `checks/disk.sh:11` | `used_pct` used in interpolation and two `(( ))` comparisons with no numeric validation; an empty value coerces to 0, so the check that exists to catch a full disk silently reports OK. |
| m12 | `checks/devtools.sh:47`, `checks/git_config.sh:14`, `checks/containers.sh:25` | macOS-only remediation advice (`xcode-select --install`, `open -a Docker`) emitted unconditionally on Linux; `checks/devtools.sh:38-42` already shows the correct `is_macos` branch. |
| m13 | `checks/system.sh:49`, `checks/system.sh:60`, `checks/performance.sh:54` | Memory arithmetic with no emptiness guards, unlike `checks/performance.sh:36-38` which guards the identical computation. An empty operand coerces to 0, silently reporting "all memory free" or "100% used" instead of a parse failure. |
| m14 | `checks/hardware.sh:95` | Thermal loop `break`s unconditionally on the first glob match, which is frequently an ACPI/Wi-Fi/battery zone, not the CPU package; genuinely hot zones are never read. |
| m15 | `checks/startup.sh:75` | `systemctl list-unit-files \| wc -l` cannot distinguish "systemd unreachable" (containers, WSL) from "zero enabled services"; always prints `0`. |
| m16 | `fixes/dns.sh:27` | `"DNS cache flushed."` prints unconditionally, including on the Linux branch where neither `resolvectl` nor `systemd-resolve` exists and nothing was flushed. |
| m17 | `install.sh:130,133` | `ln -sf` clobbers any pre-existing file at `${BIN_DIR}/${BINARY_NAME}` without checking it is mdoctor's own symlink — `uninstall.sh:30` does check (`[ -L … ]`). |
| m18 | `lib/logging.sh:182`, `lib/logging.sh:212` | The DRY_RUN gate is an exact, case-sensitive match on `true`. Unset/empty correctly falls back to dry-run, but **any other value fails open and executes for real** — `DRY_RUN=1`, `yes`, `TRUE`, or a stray trailing space all disable dry-run silently on a tool that deletes files. Every current assignment (`cleanup.sh:50,59`, `fixes/disk.sh:16`) uses the exact literals, so this is latent; nothing enforces it. Normalise centrally and fail closed on anything unrecognised. |
| m19 | `lib/json.sh:20-28` | `json_escape` covers `\`, `"`, `\n`, `\r`, `\t` but not the rest of U+0000–U+001F, which RFC 8259 §7 requires. A form feed, vertical tab, or raw ANSI escape reaching a message string emits invalid JSON. |
| m20 | `lib/json.sh:44` | `json_add_check` interpolates `$risk` and `$status` **unescaped** while escaping its three siblings — and has zero callers, so `--json`'s `"checks"` array is always empty. Both a latent injection and an unshipped feature. |
| m21 | `lib/disk.sh:18`, `lib/disk.sh:41` | `kb_to_human` and `human_readable_kb` are two implementations of the same conversion, both live across 20+ call sites, and they have **already drifted**: `human_readable_kb` clamps negative input, `kb_to_human` does not, and their unset-argument defaults differ. |
| m22 | `lib/platform.sh:33` | `MDOCTOR_DISTRO_VER="${VERSION_ID%%.*}"` has no default while both neighbours do (`${ID:-unknown}`, `${PRETTY_NAME:-Linux}`). `VERSION_ID` is optional in the os-release spec, and `set -u` is active before `platform.sh` is sourced in all three entry points — so on a distro that omits it the whole CLI aborts with "unbound variable". **Not reproduced on the review machine** (Omarchy 4.0.0 defines `VERSION_ID`; `./mdoctor version` runs fine), and Debian-family targets always set it, so this is latent rather than active. |
| m23 | `lib/platform.sh:73` | `is_supported_platform` is defined but never called, so `MDOCTOR_PLATFORM="unknown"` (`:42`) is never refused — any OS falls through whatever code is not behind an `is_macos`/`is_linux` check. |
| m24 | `checks/storage.sh:23`, `checks/storage.sh:151` | These two `du` calls have **no `timeout`**, unlike their sibling helpers `_dir_size_kb` (`:33`) and `_find_and_sum` (`:51`) — whose own doc comment (`:27`) establishes hangs as a known concern. One slow or stuck mount (a network-share `.app`, a dead NFS mount) blocks the whole `check` run with nothing to kill it. |
| m25 | `checks/storage.sh:55` | `find` output read newline-delimited without `-print0`; same class as M1 but read-only, so it corrupts a size sum rather than deleting anything. |
| m26 | `lib/history.sh:24`, `lib/history.sh:15` | History filenames use second-resolution timestamps and `cat >` truncates, so two runs in the same second silently destroy one entry; and nothing ever prunes `~/.mdoctor/history/` — `history_show`'s `count` limits display only. |
| m27 | `lib/logging.sh:83`, `lib/logging.sh:79` | `~/.config/mdoctor/operations.log` is append-only with no rotation or size cap. Separately, `oplog_ensure_file`'s unchecked `mkdir -p` can abort an entire cleanup run under `cleanup.sh`'s `set -e` purely because the best-effort audit log could not be written. |
| m28 | `lib/metadata.sh:12-18` | No double-source guard (unlike `lib/platform.sh:8-12`), so re-sourcing resets the whole module registry. Not triggered today — the three `source` sites (`mdoctor:345,940,1108`) are mutually exclusive — but nothing structurally prevents it. |
| m29 | `lib/benchmark.sh:75`, `lib/benchmark.sh:85` | Network benchmark has no timeout (`curl` without `-m`, bare `nslookup`), so `mdoctor benchmark` can hang for minutes on a captive portal or firewalled network instead of reporting N/A like the disk section does. |

---

# Info

| # | File:line | Note |
|---|---|---|
| i1 | `scripts/lint_shell.sh:30` | `shellcheck -S error` cannot catch this codebase's dominant bug class. SC2086 and the `read`/`find` delimiter warnings are `info`/`warning` level and invisible to CI. Raising to `-S warning` would have caught M1, M5 and M7 mechanically. Also, `set -e` (`:2`) makes the loop abort on the first failing file instead of reporting all. |
| i2 | `cleanup.sh:13` vs `mdoctor:24`, `doctor.sh:11` | Inconsistent `errexit` posture: the same `cleanups/` and `checks/` modules are sourced by entry points with and without `-e`, so identical code has different failure semantics — the mechanism behind M2's two-row table. `doctor.sh` omitting `-e` is defensible (21 sequential checks); make it deliberate and documented. |
| i3 | `lib/logging.sh:204-232` (`:221`) | `run_cmd_legacy` executes `bash -c "$cmd"`. `run_cmd` (`:234-241`) routes any single-argument call to it. A repo-wide grep finds **zero** call sites for either — dead today, latent injection sink if revived. Recommend deleting. |
| i4 | `mdoctor:979-994` | All 11 cleanup modules are registered `LOW`, including `trash` (permanent user-file deletion), `logs` (C1), `dev`/`dev_caches` (Docker volume destruction) and `apt` (`autoremove -y`). `MED`/`HIGH` exist but are used only by `fix` modules, so the risk taxonomy `README.md:21` advertises conveys no information for the entire destructive category. |

---

# Positive Findings — verified, do not spend effort here

- **Quoting discipline is clean.** A targeted scan found **no** unquoted variable expansion reaching `rm`,
  `find`, `sudo`, or any `safe_*` primitive anywhere in the repo. The danger in this codebase is target
  *selection* and *delimiter* handling, not word splitting.
- **No `eval` anywhere**, and no dynamically-built command strings on any live path.
- **`run_cmd_args` defaults to dry-run when `DRY_RUN` is unset or empty**: `[ "${DRY_RUN:-true}" = true ]`
  (`lib/logging.sh:182`) — the important default is fail-closed, and every `cleanups/` module honours it.
  (But see m18: it fails *open* for any other value, e.g. `DRY_RUN=1`.)
- **Interactive menu input is properly validated** (`mdoctor:636-647`): non-digit tokens rejected,
  range-checked against array bounds, duplicates removed.
- **`--module` is validated against an allowlist before dispatch** (`mdoctor:669-675`) — no path traversal.
- **`json_escape` escapes in the correct order** (`lib/json.sh:20-28`): backslash first, so no
  double-escaping. (Coverage is incomplete — see m19.)
- **`safe_find_delete` uses `-print0` + `read -r -d ''`** (`lib/safety.sh:375,394`) and enumerates into a
  temp file before deleting, avoiding a live-traversal race.
- **`local var; var=$(cmd)` is split correctly throughout**, avoiding the classic exit-status masking bug.
- **`fixes/homebrew.sh` is clean**: no `sudo` (correct for Homebrew), self-guards via `command -v brew`.
- All 59 in-scope files pass `bash -n`; no merge-conflict markers present.

---

# Recommendations

**P0 — before the next release**
1. **C1** — fix `platform_user_log_dir` on Linux. Shipping data loss on the newest supported platform.
2. **C3** — add a confirmation prompt to every `--force` path, with `MDOCTOR_ASSUME_YES` for CI.
3. **C4** — stop `tests/run.sh` from reaching `docker system prune` and `sudo apt-get autoremove`.
4. **C2** — treat an empty `HOME` as fail-closed in `is_protected_deletion_path` and every `platform_*_dir`.
5. **C6** — guard the `/usr/local` chown behind `is_macos`, and platform-gate `cmd_fix`'s dispatch `case`.
6. **C5** — require an mdoctor-checkout precondition before either installer's `rm -rf`.

**P1 — next sprint**
7. **M1** — `-print0` in `cleanups/dev_caches.sh`; audit for other newline-unsafe `find` consumers.
8. **M2** — extract the hardened `du` helper into `lib/disk.sh`; replace all eight remaining sites.
9. **M3** — remove the global `trap … EXIT` from `progress_start`.
10. **M4** — replace the 24 `|| true` sites with code-aware handling.
11. **M5**, **M6** — mechanical fixes (`|| true`; `-W 1` on Linux).
12. **M9**, **M10**, **M11** — route `fixes/**` through `run_cmd_args`, add `is_macos` guards, stop printing
    unconditional success.

**P2 — hardening**
13. **M8**, **m1** — add a positive allowlist to `lib/safety.sh`; canonicalise `//` and `/./`.
14. **M7**, **M15** — move all nine `/tmp` paths to `mktemp` in one pass, starting with `lib/logging.sh:18`.
15. **M14** — fix the `history_show` increment; add a timeout to the two un-timed `du` calls (m24) and the
    network benchmark (m29).
16. **i1** — raise the lint gate to `shellcheck -S warning` and lint all files in one invocation.
17. **i4** — re-rate the cleanup modules; `LOW` for all eleven is not informative.

---

# Method and limitations

- **Six parallel `file-reviewer` subagents** covered `checks/**` (3 batches), `fixes/**` + installers,
  `lib/**` (excluding `safety.sh`/`cleanup_scope.sh`), and `doctor.sh` + `cleanups/**`. The orchestrator
  independently deep-read the destructive core: `mdoctor`, `cleanup.sh`, `lib/safety.sh`,
  `lib/cleanup_scope.sh`, `lib/platform.sh`, and the four `cleanups/` modules named in
  `tests/test_force_preflight_resilience.sh:13-17`. Overlapping claims were re-verified before inclusion.
- **`shellcheck` is not installed on this machine**, so no static-analysis pass was possible. All findings
  come from manual review plus targeted reproductions. `bash -n` was run on all 59 files (all pass). A
  `shellcheck -S warning` run would likely surface additional instances of M1, M5 and M7.
- **Nothing in the repo was executed.** `cleanup.sh`, `mdoctor clean`, `tests/run.sh` and
  `tests/test_force_preflight_resilience.sh` were deliberately never run — C4 documents why. Reproductions
  used standalone snippets in an isolated scratchpad, or sourced `lib/safety.sh` / `lib/platform.sh` with
  `MDOCTOR_CLEANUP_WHITELIST_FILE` redirected away from the user's real config.
- **The mandatory repo-sync step (`git fetch` / `git pull --rebase`) was skipped.** The audit contract
  forbids modifying tracked files, and a rebase can. The tree was verified clean and level with
  `origin/main` (0 ahead, 0 behind) before writing this report.
- **One claim could not be reproduced** and is reported as latent rather than active: m22
  (`lib/platform.sh:33` `VERSION_ID`). Stated explicitly rather than dropped or overstated.
- **Runtime behaviour was not observed** — this is a static review. Findings about what happens *during* a
  real `--force` run (M3's trap clobbering, M4's swallowed codes) are argued from code and isolated
  reproductions, not from an instrumented run.
