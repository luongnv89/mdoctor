#!/usr/bin/env bash
#
# lib/common.sh
# Common utilities: colors, icons, UI helpers
#

########################################
# COLORS & ICONS
########################################


# TRUTHY_BOOTSTRAP (Task 9.5): is_truthy lives in constants.sh, the
# zero-dependency base lib. Source it before the guard so standalone
# sourcing of this file still sees the predicate. Zero-fork (issue #102):
# the lib dir is the literal directory part of ${BASH_SOURCE[0]} — the
# source line just reached this file through it — so parameter expansion
# replaces the old $(cd "$(dirname …)" && pwd) probe, and the declare -f
# guards skip even that once the base libs are loaded.
_mdoctor_lib_dir="${BASH_SOURCE[0]%/*}"
if [ "$_mdoctor_lib_dir" = "${BASH_SOURCE[0]}" ]; then
  _mdoctor_lib_dir="."
fi
if ! declare -f is_truthy >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "${_mdoctor_lib_dir}/constants.sh"
fi
# mdoctor_timeout (issue #101): every check module gets the portable cap
# through this file, the one lib all entry points source first.
if ! declare -f mdoctor_timeout >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "${_mdoctor_lib_dir}/timeout.sh"
fi
unset _mdoctor_lib_dir

# Guard against double-sourcing (the is_dry_run loader in logging.sh and
# lib/safety.sh pull this file in when is_dry_run is otherwise unavailable).
if is_truthy "${_MDOCTOR_COMMON_LOADED:-}"; then
  return 0 2>/dev/null || true
fi
_MDOCTOR_COMMON_LOADED=true

init_colors() {
  # The single color implementation every entry point calls (issue #108).
  # All terminal sequences come from the memoized `tput -S` batch in
  # mdoctor_term_init (issue #102): at most one tput exec per process,
  # zero when stdout is not a tty or NO_COLOR/MDOCTOR_NO_COLOR is set
  # (the previous per-capability calls ran tput six times even on pipes,
  # where colors are never wanted).
  mdoctor_term_init

  CHECK="✅"
  WARN="⚠️"
  CROSS="❌"
  INFO="ℹ️"
}

########################################
# ORDERED EXIT HOOKS (Task 4.7)
########################################
# Bash traps replace rather than stack: every `trap ... EXIT` silently
# discards the previously installed handler. So EXIT-time actions register
# here and the single runner trap runs them in order with the script's exit
# status. Never install a bare `trap ... EXIT` anywhere else — use
# register_exit_hook / unregister_exit_hook instead.
# The runner trap is installed lazily by register_exit_hook, never at
# source time: sourcing this library must not discard an EXIT handler the
# host process installed earlier (e.g. a test harness's result reporter).
_EXIT_HOOKS=""
_EXIT_TRAP_INSTALLED=""

register_exit_hook() {
  local hook="${1-}"
  [ -n "$hook" ] || return 1
  case " ${_EXIT_HOOKS} " in
    *" ${hook} "*) return 0 ;;
  esac
  _EXIT_HOOKS="${_EXIT_HOOKS} ${hook}"
  if [ -z "${_EXIT_TRAP_INSTALLED}" ]; then
    trap _run_exit_hooks EXIT
    _EXIT_TRAP_INSTALLED="true"
  fi
}

unregister_exit_hook() {
  local hook="${1-}"
  [ -n "$hook" ] || return 1
  _EXIT_HOOKS=" ${_EXIT_HOOKS} "
  _EXIT_HOOKS="${_EXIT_HOOKS// ${hook} / }"
  _EXIT_HOOKS="${_EXIT_HOOKS# }"
  _EXIT_HOOKS="${_EXIT_HOOKS% }"
}

_run_exit_hooks() {
  local _rc=$?
  local hook
  for hook in ${_EXIT_HOOKS}; do
    "$hook" "$_rc" || true
  done
  return "$_rc"
}

########################################
# VALUE HELPERS
########################################

# to_int VALUE
# Normalizes potentially messy numeric command output into a safe integer.
# Handles cases like "0\n0" from `grep -c ... || echo 0` patterns.
to_int() {
  local raw="${1:-0}"
  local first

  # head -n1 + tr -cd '0-9' inlined: first line of $raw, digits only
  # (issue #98 — zero-fork normalization).
  local _first_line
  IFS= read -r _first_line <<< "$raw"
  first="${_first_line//[!0-9]/}"
  if [ -z "$first" ]; then
    echo 0
  else
    # 10# forces base-10: a value like "008" must never reach (( ))
    # with a leading zero (bash would read it as octal and fail).
    printf '%d\n' "$((10#$first))"
  fi
}

########################################
# SPINNER / PROGRESS BAR (issue #102 rework)
########################################
# One long-lived spinner per run, driven over a two-fifo control channel
# instead of a kill+respawn per status line: the parent writes one-letter
# commands to `ctl` ('r<TAB>label<TAB>cur<TAB>tot' resume/redraw,
# 's<TAB>line' print a status line between frames, 'p' pause, 'q' quit)
# and the worker acknowledges 'p'/'q' with 'a' on `ack`, so a parent's own
# direct print never races a queued line. Status lines are handed to the
# worker whole — the fifo serializes them between frames, so a per-line
# status costs ONE builtin write: no ack round-trip, no collision window.
# The old design forked a background subshell plus two `tput el` execs
# around EVERY printed line (~1.3 ms each) and forked `sleep` every 0.1 s
# inside the loop; the tick is now a builtin `read -t 1` (integer — Bash
# 3.2 rejects fractional -t) and the per-line signal is one printf.
#
# Background-job discipline mirrors lib/timeout.sh's watchdog (the PR #210
# review family):
#  * never signal-killed on the normal path — 'q' makes the worker
#    `exit 0`, so no "Terminated" job notice can leak into a stream; TERM
#    is trapped to `exit 0` for the same reason on the forced path;
#  * the worker detaches every inherited fd it does not draw on (stdin ←
#    /dev/null, stderr → /dev/null, fds 3-63 closed) so an orphan can
#    never hold a caller pipe open — exactly the bats-TAP-hang fix;
#  * it polls `kill -0` on the spawning shell each tick and self-exits on
#    parent death, so a leaked worker releases stdout within ~1 s;
#  * 'p' is acknowledged before the parent prints — the synchronous point
#    replacing the old kill+wait barrier;
#  * the parent holds both fifos open RDWR, so a dead worker can never
#    turn a control write into a SIGPIPE against this shell;
#  * stop consumes the pid list once (SPINNER_PID cleared before the
#    signal/wait phase) so an exit-hook second pass can never TERM a
#    recycled pid.

SPINNER_PID=""
_PROGRESS_LABEL=""
_SPINNER_DIR=""
# Worker-side only: the fifo dir the worker's own exit hook removes.
# Set inside _mdoctor_spinner; in the parent it always stays empty.
_SPINNER_WORKER_DIR=""

# MDOCTOR_SPINNER_FORCE=1 — test seam: drive the real protocol with stdout
# on a pipe (the suite is hermetic, no real ttys). Unset by default.
_spinner_wanted() {
  if is_truthy "${MDOCTOR_SPINNER_FORCE:-}"; then
    return 0
  fi
  [ -t 1 ]
}

# _spinner_on — a live worker is attached (pid set + still running) and
# THIS context may signal it. The BASHPID clause protects $() captures on
# Bash 4+: inside a command substitution BASHPID differs from $$, so a
# status_* helper invoked in a capture falls back to a plain echo (its
# output is captured by the caller, matching the old semantics) instead
# of signalling a worker it does not own. BASHPID does not exist on Bash
# 3.2 — there a capture is detectable ONLY by its pipe stdout, so the
# MDOCTOR_SPINNER_FORCE seam may not stand in for [ -t 1 ]: when BASHPID
# is absent and stdout is not a tty we cannot rule out a capture, and
# echoing is the only safe emit (a stolen capture is the failure the
# guard exists to prevent — test_spinner_startup.bats exercises this on
# the Bash 3.2/macOS lanes).
_spinner_on() {
  [ -n "$SPINNER_PID" ] || return 1
  [ "${BASHPID:-$$}" = "$$" ] || return 1
  if [ -z "${BASHPID:-}" ] && [ ! -t 1 ]; then
    return 1
  fi
  is_truthy "${MDOCTOR_SPINNER_FORCE:-}" || [ -t 1 ] || return 1
  kill -0 "$SPINNER_PID" 2>/dev/null || return 1
  return 0
}

# _spinner_signal LETTER — fire-and-forget command to the worker. Returns
# 1 (and drops the handle) when the worker is already gone so callers can
# fall through to a fresh spawn.
_spinner_signal() {
  kill -0 "$SPINNER_PID" 2>/dev/null || return 1
  printf '%s\n' "$1" >&9 2>/dev/null || return 1
  return 0
}

# _spinner_worker_exit — worker-side exit hook (registered inside the
# worker subshell only): removes the fifo dir so a parent that died
# first leaves nothing stale. The parent's own teardown removes it too;
# a double `rm -rf` is a no-op.
_spinner_worker_exit() {
  [ -n "${_SPINNER_WORKER_DIR:-}" ] && rm -rf "$_SPINNER_WORKER_DIR" 2>/dev/null
  return 0
}

# _mdoctor_spinner DIR PARENT_PID — the worker loop (backgrounded by
# _spinner_spawn). Pure builtins: no fork anywhere in the loop.
_mdoctor_spinner() {
  local dir="$1" parent="$2"

  # A backgrounded subshell clones the parent's exit-hook list: left in
  # place, the inherited _run_exit_hooks runner would fire on EVERY worker
  # exit below and re-run hooks like _finish_cleanup_session inside the
  # wrong process (a duplicated session-end record mid-run). Clearing the
  # list disarms the runner — the inherited `trap _run_exit_hooks EXIT`
  # line stays but iterates over nothing; the worker's own cleanup is
  # registered through the same hook list once it owns the fifo dir.
  _EXIT_HOOKS=""

  # Detach every fd we do not draw on (watchdog discipline): stdin and
  # stderr to /dev/null, then sweep 3-63 so nothing inherited stays open
  # behind our back — a caller pipe held past exit is the bats-TAP hang.
  exec </dev/null 2>/dev/null
  local _fd=3
  while [ "$_fd" -le 63 ]; do
    eval "exec ${_fd}>&-" 2>/dev/null || true
    _fd=$((_fd + 1))
  done
  # Both channel opens are RDWR: a plain 7< / 8> blocks until the other
  # end appears, and a parent that died between fork and open (and left
  # no fd-9/8 inheritor) would park the worker in open() forever — before
  # even the TERM trap exists. RDWR never blocks; the kill -0 poll below
  # is the authoritative parent-death detector either way.
  exec 7<>"$dir/ctl" 2>/dev/null || exit 0
  exec 8<>"$dir/ack" 2>/dev/null || exit 0

  # The worker owns its fifo dir on the way out: the parent also rm's it
  # in _spinner_teardown_channel, but a parent that dies first (SIGKILL)
  # never gets there — without this the tmpdir outlives both processes.
  _SPINNER_WORKER_DIR="$dir"
  register_exit_hook _spinner_worker_exit

  # Trapped TERM => clean exit 0: a signal death would print a
  # "Terminated" job notice at the caller's next command boundary.
  trap 'exit 0' TERM

  # Ready-ack: the spawn blocks on this byte, so by the time
  # progress_start returns the trap is installed and both fifos are
  # attached — a TERM sent immediately after start can never slip into
  # the pre-trap window and kill the worker as a signal death.
  printf 'a\n' >&8 2>/dev/null

  local frames="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
  local el="${_MDOCTOR_EL:-}"
  local i=0 paused=1 rc=0
  local msg="" label="" bar="" pct=0
  local _code _l _c _t _filled _empty _j

  while :; do
    # One 1 s read tick in every state: an untimed read would only end on
    # a command or EOF — and the worker holds ctl RDWR, so ctl can NEVER
    # reach EOF at all (it is itself a writer). The tick is what runs the
    # orphan poll below every second, paused or running — a paused worker
    # can never outlive its parent either. Commands are one atomic fifo
    # write each (well under PIPE_BUF), so the timeout can never consume
    # a partial line. rc 1 (read error; EOF is impossible here) is still
    # a safe bail.
    if [ "$paused" -eq 1 ]; then
      msg=""
      IFS= read -r -t 1 -u 7 msg || rc=$?
      if [ "$rc" -eq 1 ]; then
        exit 0        # read error — channel unusable, bail
      fi
      if [ "$rc" -ne 0 ]; then
        msg=""        # tick timeout (>128) — fall through to the poll
      fi
      rc=0
    else
      msg=""
      IFS= read -r -t 1 -u 7 msg || rc=$?
      if [ "$rc" -eq 1 ]; then
        exit 0        # read error — channel unusable, bail
      fi
      if [ "$rc" -ne 0 ]; then
        msg=""
      fi
      rc=0
    fi

    case "$msg" in
      p)
        paused=1
        printf 'a\n' >&8 2>/dev/null
        ;;
      q)
        printf 'a\n' >&8 2>/dev/null
        exit 0
        ;;
      r*)
        IFS=$'\t' read -r _code _l _c _t <<< "$msg"
        label="$_l"
        case "$_c" in ''|*[!0-9]*) _c=0 ;; esac
        case "$_t" in ''|*[!0-9]*) _t=1 ;; esac
        [ "$_t" -gt 0 ] || _t=1
        _filled=$(( _c * 20 / _t ))
        _empty=$(( 20 - _filled ))
        pct=$(( _c * 100 / _t ))
        bar=""
        _j=0
        while [ "$_j" -lt "$_filled" ]; do bar="${bar}█"; _j=$((_j + 1)); done
        _j=0
        while [ "$_j" -lt "$_empty" ]; do bar="${bar}░"; _j=$((_j + 1)); done
        paused=0
        ;;
      s*)
        # A status line: \r + erase-to-eol clears the frame, then the line
        # and its newline commit it. Queued on the same fifo as commands,
        # so it can never interleave with a frame byte-wise.
        printf '\r%s%s\n' "$el" "${msg#??}" 2>/dev/null
        ;;
      "")
        ;;
    esac

    # Draw a frame whenever running (fresh 'r' or a 1 s tick).
    if [ "$paused" -eq 0 ]; then
      printf '\r  %s [%s] %3d%% %s%s' \
        "${frames:$((i % 10)):1}" "$bar" "$pct" "$label" "$el" 2>/dev/null
      i=$((i + 1))
    fi

    # Orphan check: $$ is the top-level shell's pid even inside this
    # subshell — the argument is the spawning pid captured at fork time.
    kill -0 "$parent" 2>/dev/null || exit 0
  done
}

# _spinner_spawn — create the fifo pair + worker once per run.
_spinner_spawn() {
  local dir
  dir="$(mktemp -d "${TMPDIR:-/tmp}/mdoctor-spin.XXXXXX" 2>/dev/null)" || return 1
  if ! mkfifo "$dir/ctl" "$dir/ack" 2>/dev/null; then
    rm -rf "$dir"
    return 1
  fi
  # RDWR opens never block, and they make every later writer-side open in
  # the worker succeed immediately — no open-ordering deadlock, and no
  # SIGPIPE if the worker dies (the parent itself is still a reader).
  if ! exec 9<>"$dir/ctl" 2>/dev/null; then
    rm -rf "$dir"
    return 1
  fi
  if ! exec 8<>"$dir/ack" 2>/dev/null; then
    exec 9>&-
    rm -rf "$dir"
    return 1
  fi
  _SPINNER_DIR="$dir"
  _mdoctor_spinner "$dir" "$$" &
  SPINNER_PID=$!
  # Spinner cleanup runs as an ordered exit hook — never a bare
  # `trap ... EXIT` here, which would clobber other handlers (Task 4.7).
  register_exit_hook progress_stop
  # Wait for the worker's ready-ack (bounded — a failed spawn still lets
  # the run continue, the next signal just finds a dead pid).
  _spinner_await_ack || true
  # First frame: announce label + step counters (worker starts paused).
  _spinner_resume
  return 0
}

# _spinner_resume — signal 'r': label + step counters, worker unpauses and
# draws. Fire-and-forget (no ack needed — ordering with parent output is
# only required on pause/quit, which do ack).
_spinner_resume() {
  printf 'r\t%s\t%s\t%s\n' \
    "$_PROGRESS_LABEL" "${STEP_CURRENT:-0}" "${STEP_TOTAL:-1}" >&9 2>/dev/null
}

# _spinner_await_ack — block (≤1 s, bash 3.2 integer read -t) until the
# worker confirms it has gone silent / exited. Returns 0 on the ack.
_spinner_await_ack() {
  local _ack=""
  IFS= read -r -t 1 _ack <&8 2>/dev/null
}

progress_start() {
  [ -n "${1:-}" ] || return 0
  _spinner_wanted || return 0

  # The control protocol is one line per command, tab-delimited — strip
  # both characters out of a label before it can corrupt a message.
  _PROGRESS_LABEL="${1//$'\t'/ }"
  _PROGRESS_LABEL="${_PROGRESS_LABEL//$'\n'/ }"
  if [ -n "$SPINNER_PID" ]; then
    if kill -0 "$SPINNER_PID" 2>/dev/null; then
      _spinner_resume
      return 0
    fi
    # Worker gone — reap the zombie, drop the stale handle, respawn below.
    wait "$SPINNER_PID" 2>/dev/null || true
    SPINNER_PID=""
    _spinner_teardown_channel
  fi
  _spinner_spawn || true
  return 0
}

# progress_pause — signal the worker silent + ack-wait, then clear the
# spinner line so a status line never shares the row with a frame. This is
# the per-line barrier that replaced the old kill+respawn.
progress_pause() {
  _spinner_on || return 0
  if ! _spinner_signal p; then
    SPINNER_PID=""
    _spinner_teardown_channel
    return 0
  fi
  if ! _spinner_await_ack; then
    # No ack — wedged or dead. Drop the handle so per-line work never
    # stalls again; the next progress_start respawns a fresh worker.
    if ! kill -0 "$SPINNER_PID" 2>/dev/null; then
      SPINNER_PID=""
      _spinner_teardown_channel
    fi
    return 0
  fi
  printf '\r%s' "$_MDOCTOR_EL" 2>/dev/null
  return 0
}

# _spinner_teardown_channel — close the parent-side fds and drop the fifo
# dir. Safe when the worker is already gone; never signals anything.
# The closes are gated on _SPINNER_DIR (set only after both channel opens
# in _spinner_spawn succeeded): a bare `exec N>&-` on a never-opened fd
# aborts Bash 3.2 in some redirection states — silently, since the failing
# command's own 2>/dev/null swallows the diagnostic. progress_stop calls
# this unconditionally, so the single-module path died here with empty
# output on the bash:3.2 lane (issue #114 doc-example run).
_spinner_teardown_channel() {
  if [ -n "$_SPINNER_DIR" ]; then
    exec 9>&- 2>/dev/null || true
    exec 8>&- 2>/dev/null || true
    rm -rf "$_SPINNER_DIR" 2>/dev/null || true
    _SPINNER_DIR=""
  fi
  return 0
}

progress_stop() {
  local pid="$SPINNER_PID"
  # Consume the handle first: a second pass (ordered exit hook after an
  # explicit stop) must not TERM a pid the kernel may have recycled.
  SPINNER_PID=""
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    # 'q' asks the worker to exit 0 — it acks, then exits, so the ack
    # read is the bounded wait and `wait` below is a pure zombie reap.
    printf 'q\n' >&9 2>/dev/null || true
    _spinner_await_ack || true
    if kill -0 "$pid" 2>/dev/null; then
      kill -TERM "$pid" 2>/dev/null || true
    fi
  fi
  if [ -n "$pid" ]; then
    wait "$pid" 2>/dev/null || true
  fi
  _spinner_teardown_channel
  # Clear the spinner line if stdout is a terminal
  if [ -t 1 ] || is_truthy "${MDOCTOR_SPINNER_FORCE:-}"; then
    printf '\r%s' "$_MDOCTOR_EL" 2>/dev/null
  fi
  return 0
}

########################################
# UI HELPERS
########################################

step() {
  progress_pause

  STEP_CURRENT=$((STEP_CURRENT + 1))
  local title="$1"
  echo
  echo "${BOLD}➤ [${STEP_CURRENT}/${STEP_TOTAL}] ${title}${RESET}"
  echo "----------------------------------------"

  md_append ""
  md_append "## [${STEP_CURRENT}/${STEP_TOTAL}] ${title}"
  md_append ""

  progress_start "$title"
}

section_title() {
  local title="$1"
  echo
  echo "${BOLD}${BLUE}== ${title} ==${RESET}"

  md_append ""
  md_append "## ${title}"
  md_append ""
}

# _status_emit LINE — the per-status-line output path (issue #102). When
# the long-lived spinner owns stdout, the fully rendered line is handed to
# the worker over the control fifo as one builtin write ('s<TAB>line') —
# the worker prints it serially between frames, so no ack round-trip is
# needed and a frame can never collide mid-line. Without a live worker
# (non-tty, capture, dead channel) the line is echoed directly, exactly
# where the old synchronous path put it.
_status_emit() {
  local line="${1//$'\t'/ }"
  line="${line//$'\n'/ }"
  if _spinner_on; then
    printf 's\t%s\n' "$line" >&9 2>/dev/null && return 0
    # Write failed (wedged channel) — drop the handle so later lines take
    # the cheap direct path, then fall through to the plain echo.
    SPINNER_PID=""
    _spinner_teardown_channel
  fi
  printf '%s\n' "$line"
}

# The four status_* helpers: emit the line, append to the report, record
# for --json. No more progress_stop/progress_start sandwich around every
# line — the spinner worker stays up for the whole run.
status_ok() {
  local msg="$1"
  _status_emit "  ${CHECK} ${GREEN}${msg}${RESET}"
  md_append "- ✅ ${msg}"
  _json_record_status "ok" "$msg"
}

status_warn() {
  local msg="$1"
  WARN_COUNT=$((WARN_COUNT + 1))
  _status_emit "  ${WARN} ${YELLOW}${msg}${RESET}"
  md_append "- ⚠️ ${msg}"
  _json_record_status "warn" "$msg"
}

status_fail() {
  local msg="$1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  _status_emit "  ${CROSS} ${RED}${msg}${RESET}"
  md_append "- ❌ ${msg}"
  _json_record_status "fail" "$msg"
}

status_info() {
  local msg="$1"
  _status_emit "  ${INFO} ${msg}"
  md_append "- ℹ️ ${msg}"
  _json_record_status "info" "$msg"
}

# _json_record_status STATUS MESSAGE — appends a check result to the JSON
# accumulator behind `mdoctor check --json` (issue #90). Every status line
# is recorded (ok/warn/fail/info): info lines are findings too, and
# recording all four keeps the "checks" array populated for every module,
# including info-only ones like `system`.
# No-op unless JSON output is enabled AND lib/json.sh is loaded — this
# library is also sourced by engines that never load it, so the recorder
# resolves lazily instead of a hard call.
_json_record_status() {
  is_truthy "${JSON_ENABLED:-false}" || return 0
  if ! declare -f json_add_check >/dev/null 2>&1; then
    return 0
  fi
  json_add_check "${_JSON_MODULE:-}" "${_JSON_CATEGORY:-}" "${_JSON_RISK:-}" "$1" "$2"
}

add_action() {
  local msg="${1-}"
  [ -n "${msg}" ] && ACTIONS+=("$msg")
}

add_log_file() {
  local path="${1-}"
  local desc="${2-}"
  if [ -n "${path}" ]; then
    LOG_PATHS+=("$path")
    LOG_DESCS+=("$desc")
  fi
}

########################################
# DRY-RUN PREDICATE (Task 1.6)
########################################

# is_dry_run — central fail-closed dry-run predicate. Never compare
# $DRY_RUN to a literal again; call this instead.
#
# Return codes:
#   0 — dry-run ENABLED (unset/empty default, or truthy: true/1/yes/y
#       in any letter case, surrounding whitespace ignored)
#   1 — dry-run EXPLICITLY DISABLED (force): false/0/no/n, the ONLY
#       code that may proceed to deletion
#   2 — value INVALID: warns on stderr and dry-run stays enabled
#       (fail closed)
#
# Call sites MUST branch on rc==1 explicitly so invalid values fail
# closed (plain `if is_dry_run` would take the force branch on rc 2):
#
#   local _dry_rc=0
#   is_dry_run || _dry_rc=$?
#   if [ "$_dry_rc" -eq 1 ]; then
#     <force path — explicit opt-out only>
#   else
#     <dry path — default, truthy, and invalid values>
#   fi
#
# (The `||` keeps the call safe under `set -e`.)
is_dry_run() {
  local raw="${DRY_RUN:-true}"
  local norm="$raw"

  # Trim leading/trailing whitespace (Bash 3.2-safe; no extglob).
  norm="${norm#"${norm%%[![:space:]]*}"}"
  norm="${norm%"${norm##*[![:space:]]}"}"

  case "$norm" in
    ""|[tT][rR][uU][eE]|1|[yY][eE][sS]|[yY])
      return 0
      ;;
    [fF][aA][lL][sS][eE]|0|[nN][oO]|[nN])
      return 1
      ;;
    *)
      echo "warning: ignoring invalid DRY_RUN='${raw}' — failing closed to dry-run enabled" >&2
      return 2
      ;;
  esac
}

# cleanup_mode_name FORCE — the canonical cleanup mode label (issue
# #106): "force" when the flag is truthy, "dry-run" otherwise. The CLI
# names cleanup modes with exactly these two strings — the safe default
# and the explicit destructive opt-in, the same words --help and the
# pre-flight summaries use — so menus, banners and closing summaries can
# never drift into a third spelling.
cleanup_mode_name() {
  if is_truthy "${1:-false}"; then
    echo "force"
  else
    echo "dry-run"
  fi
}

########################################
# SECURE TEMP FILES (Task 4.3)
########################################

# mdoctor_tmpdir — per-user scratch dir (${TMPDIR:-/tmp}/mdoctor-$UID),
# created mode 0700. All temp files live under it via mktemp below.
mdoctor_tmpdir() {
  local dir="${TMPDIR:-/tmp}/mdoctor-${UID}"
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir" 2>/dev/null || true
    chmod 700 "$dir" 2>/dev/null || true
  fi
  printf '%s' "$dir"
}

# mdoctor_mktemp_file PREFIX — secure temp file path (created empty).
mdoctor_mktemp_file() {
  mktemp "$(mdoctor_tmpdir)/${1:-tmp}.XXXXXX"
}

# mdoctor_mktemp_dir PREFIX — secure temp directory path (created).
mdoctor_mktemp_dir() {
  mktemp -d "$(mdoctor_tmpdir)/${1:-tmp}.XXXXXX"
}

########################################
# DESTRUCTIVE-EXECUTION CONFIRMATION GATE (Task 0.5)
########################################

# confirm_destructive_execution [context]
# Returns 0 when deletion may proceed, 1 otherwise. Behavior:
# - MDOCTOR_ASSUME_YES=true  -> proceed with no prompt (automation/CI).
# - otherwise a y/N prompt is read from stdin; only an explicit
#   y/Y/yes proceeds. Anything else (n, empty, EOF) aborts.
# - on a non-tty stdin without an affirmative answer the refusal names
#   MDOCTOR_ASSUME_YES, so `--force < /dev/null` fails with a pointer
#   instead of hanging or deleting.
confirm_destructive_execution() {
  local context="${1:-cleanup}"

  if is_truthy "${MDOCTOR_ASSUME_YES:-false}"; then
    return 0
  fi

  local answer=""
  printf 'Proceed with deletion (%s)? [y/N] ' "$context" >&2
  IFS= read -r answer || answer=""

  case "$answer" in
    [yY]|[yY][eE][sS])
      return 0
      ;;
  esac

  if [ ! -t 0 ]; then
    echo "Refusing --force on a non-tty without MDOCTOR_ASSUME_YES=true: no confirmation received, nothing was deleted." >&2
  else
    echo "Aborted: nothing was deleted." >&2
  fi
  return 1
}
