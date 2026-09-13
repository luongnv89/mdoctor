#!/usr/bin/env bash
#
# lib/timeout.sh
# Portable command time-capping (issue #101 — Task 11.7, M4).
#
# mdoctor_timeout SECONDS CMD [ARGS...] runs CMD with a hard wall-clock cap
# and propagates a distinct status: the command's own exit code on
# completion/failure, 124 when the cap fired (GNU timeout's convention,
# mirrored by MDOCTOR_SIZE_ERR_TIMEOUT).
#
# Backend resolution order (stock macOS ships no GNU timeout, so the cap
# must never silently become "run it uncapped" — that silent fallback was
# the old lib/disk.sh / lib/preflight.sh gap):
#   1. timeout   (GNU coreutils, stock on Linux)
#   2. gtimeout  (Homebrew coreutils on macOS)
#   3. builtin watchdog — pure Bash 3.2: background the command, arm a
#      watchdog subshell that TERM-kills it after SECONDS (KILL after a
#      short grace), and distinguish "killed" from "exited" via a flag
#      file so the rc is a real 124, never a guess.
#
# MDOCTOR_TIMEOUT_IMPL=watchdog forces the builtin path so tests exercise
# it on hosts that also ship GNU timeout.
#
# Bash 3.2 floor: no co-processes, no `wait -n`, no process-substitution
# reads of the deadline. Every expansion is quoted.

# TRUTHY_BOOTSTRAP (Task 9.5): is_truthy lives in constants.sh, the
# zero-dependency base lib. Source it before the guard so standalone
# sourcing of this file still sees the predicate.
_MDOCTOR_TRUTHY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null || pwd)"
# shellcheck source=/dev/null
source "${_MDOCTOR_TRUTHY_DIR}/constants.sh"
unset _MDOCTOR_TRUTHY_DIR

if is_truthy "${_MDOCTOR_TIMEOUT_LOADED:-}"; then
  return 0 2>/dev/null || true
fi
_MDOCTOR_TIMEOUT_LOADED=true

# _mdoctor_timeout_watchdog SECONDS CMD... — the no-GNU-timeout backend.
# The command runs as a background job of the *current* shell; a detached
# watchdog subshell polls a "done" flag the parent writes the instant it
# reaps the command — when the deadline passes with no flag it writes
# "fired", TERM-kills the job, then KILLs after a 1 s grace for probes
# that ignore TERM. `wait` returns the real exit code; the flag file is
# the only reliable "cap fired" signal — checking whether the watchdog
# is still alive races with its own exit.
#
# Design constraints learned the hard way (all reproduced under the
# bash:3.2 CI image):
#  * The dog is NEVER killed. A disarm-by-TERM dies *by signal*, and
#    bash prints a "PID Terminated …" job notice at the next command
#    boundary — `wait … 2>/dev/null` cannot contain it because the flush
#    lands in whatever stderr context is current then (under bats the
#    DEBUG trap flushes it into a merge-mode probe's .out file).
#    Self-termination via the done flag makes every exit a clean 0.
#  * The dog detaches EVERY inherited fd first: a watchdog child that
#    outlives the call must hold nothing the caller could block on —
#    $(tcap …) waits on pipe EOF (bats keeps its TAP pipe on fd 3 and
#    per-test output on fd 4), not on our exit.
#  * The dog only kills "$pid" after observing done-absent at the
#    deadline; the parent's reap-then-flag ordering means a live
#    same-pid stranger can only exist if the kernel recycled it inside
#    a single-builtin window — and even then the dog re-checks the flag.
# Costs one mktemp -d per call (macOS path only).
_mdoctor_timeout_watchdog() {
  local secs="$1"
  shift
  [ $# -gt 0 ] || return 2   # cap with no command — caller bug
  local dir pid dog rc=0
  dir="$(mktemp -d "${TMPDIR:-/tmp}/mdoctor-timeout.XXXXXX" 2>/dev/null)" || {
    # No scratch dir at all: run uncapped rather than drop the probe —
    # strictly better than the old behavior of skipping the cap silently,
    # and only reachable on a broken /tmp.
    "$@"
    return $?
  }
  "$@" &
  pid=$!
  (
    exec </dev/null >/dev/null 2>&1
    _wfd=3
    while [ "$_wfd" -le 63 ]; do
      eval "exec ${_wfd}>&-" 2>/dev/null || true
      _wfd=$((_wfd + 1))
    done
    unset _wfd
    _w=0
    while [ ! -f "$dir/done" ] && [ "$_w" -lt "$secs" ]; do
      sleep 1
      _w=$((_w + 1))
    done
    if [ ! -f "$dir/done" ]; then
      : >"$dir/fired" 2>/dev/null
      kill -TERM "$pid" 2>/dev/null || true
      # Grace before the guaranteed kill: TERM lets well-behaved probes
      # flush and exit; KILL bounds even a wedged call to secs + ~2.
      sleep 1
      kill -KILL "$pid" 2>/dev/null || true
    fi
  ) &
  dog=$!
  wait "$pid" 2>/dev/null || rc=$?
  # Flag the reap before checking "fired": on a deadline tie the watchdog
  # must already have committed to firing (GNU timeout's semantics — the
  # cap wins a boundary race), never kill a recycled pid.
  : >"$dir/done" 2>/dev/null || true
  if [ -f "$dir/fired" ]; then
    rc=124
    # The dog exits once its KILL follow-up lands (bounded by the 1 s
    # grace) — reap it so the child never sits as a zombie.
    wait "$dog" 2>/dev/null || true
  fi
  # Otherwise the dog self-exits on the next flag poll (≤1 s); it holds
  # no caller fd, so leaving it unwaited is invisible to every consumer.
  rm -rf "$dir"
  return "$rc"
}

# _mdoctor_timeout_gnu_ok BIN — BIN must be GNU coreutils timeout. The
# `-k` flag and the 124-on-timeout convention are GNU semantics: the
# BusyBox `timeout` applet on minimal images (Alpine — the bash:3.2 CI
# image included) accepts the argv but returns the killed child's status
# instead of 124, which would erase the "timed out" signal this file
# exists to preserve. GNU prints "(GNU coreutils)" in --version output;
# BusyBox errors on the flag entirely. One cheap probe per call — any
# doubt resolves to the builtin watchdog, correct on every host.
_mdoctor_timeout_gnu_ok() {
  local _tv=""
  _tv="$("$1" --version 2>/dev/null)" || true
  case "$_tv" in
    *coreutils*|*GNU*) return 0 ;;
  esac
  return 1
}

# mdoctor_timeout SECONDS CMD [ARGS...] — cap a blocking call.
# rc: CMD's exit code, or 124 when the cap fired. A non-numeric or
# non-positive SECONDS runs CMD directly — callers pass named constants,
# so this branch is defensive, not a reachable cap of 0.
mdoctor_timeout() {
  local secs="$1"
  shift
  case "$secs" in
    ''|*[!0-9]*) secs=0 ;;   # non-numeric → run uncapped, never instant-kill
  esac
  if [ "$secs" -le 0 ]; then   # also catches 0/00/000 after the digit check
    if [ $# -gt 0 ]; then
      "$@"
      return $?
    fi
    return 2
  fi

  local impl="${MDOCTOR_TIMEOUT_IMPL:-}"
  case "$impl" in
    watchdog)
      ;;
    timeout|gtimeout)
      command -v "$impl" >/dev/null 2>&1 || impl=""
      ;;
    *)
      impl=""
      ;;
  esac
  if [ -z "$impl" ]; then
    # `command -v` alone is not enough: a non-GNU `timeout` (BusyBox)
    # exists on minimal images but rejects `-k` — probe the flag before
    # selecting so those hosts land on the watchdog instead.
    if command -v timeout >/dev/null 2>&1 && _mdoctor_timeout_gnu_ok timeout; then
      impl="timeout"
    elif command -v gtimeout >/dev/null 2>&1 && _mdoctor_timeout_gnu_ok gtimeout; then
      impl="gtimeout"
    else
      impl="watchdog"
    fi
  fi

  case "$impl" in
    watchdog) _mdoctor_timeout_watchdog "$secs" "$@" ;;
    # -k 1 gives the GNU path the watchdog's TERM→KILL parity: a probe
    # that ignores TERM is hard-killed 1 s past the cap instead of
    # letting `timeout` wait on it indefinitely.
    *)        "$impl" -k 1 "$secs" "$@" ;;
  esac
}

########################################
# DISTINCT-TIMEOUT HELPERS (issue #101, criterion 2)
########################################
# A timed-out probe must report "timed out" — never collapse silently into
# an empty/0 result that a module then prints as "none found" or a bare
# success. Two shapes cover the call sites:
#
#   tcap SECONDS LABEL CMD...          — capture CMD's stdout (stderr
#       dropped) into _TCAP_OUT in the CURRENT shell; on 124 prints a
#       distinct "LABEL timed out (timeout Ns) — skipped." status line.
#       Returns CMD's real rc (124 on timeout) so callers can still branch.
#
#   tcap_or SECONDS FALLBACK CMD...    — for $(...) sites inside a status
#       line: prints CMD's stdout, or "timed out (timeout Ns)" on 124, or
#       FALLBACK on any other failure. The timed-out text is part of the
#       line the user sees, so the distinct state survives capture.
#
# status_info is resolved at call time (defined in lib/common.sh, which
# sources this file); the stderr printf fallback keeps tcap meaningful
# for isolated sourcers (tests, lib/benchmark.sh standalone).

_TCAP_OUT=""

tcap() {
  local secs="$1" label="$2"
  shift 2
  local rc=0
  _TCAP_OUT="$(mdoctor_timeout "$secs" "$@" 2>/dev/null)" || rc=$?
  if [ "$rc" -eq 124 ]; then
    if command -v status_info >/dev/null 2>&1; then
      status_info "${label} timed out (timeout ${secs}s) — skipped."
    else
      printf '%s\n' "i ${label} timed out (timeout ${secs}s) — skipped." >&2
    fi
  fi
  return "$rc"
}

tcap_or() {
  local secs="$1" fb="$2"
  shift 2
  local out rc=0
  out="$(mdoctor_timeout "$secs" "$@" 2>/dev/null)" || rc=$?
  if [ "$rc" -eq 124 ]; then
    printf 'timed out (timeout %ss)' "$secs"
  elif [ "$rc" -ne 0 ]; then
    printf '%s' "$fb"
  else
    printf '%s' "$out"
  fi
}
