#!/usr/bin/env bash
#
# lib/constants.sh
# Named size, threshold and timeout values (Task 8.7). This is the single
# definition site for every bare literal the codebase compares against:
# the KB-per-GB literal occurs exactly once in all shell sources, here.
#
#
# Diagnose thresholds are overridable by documented environment variables so
# the diagnose module is tunable without editing code; everything else is a
# fixed named value. No dependencies — source this file before every other
# lib file. Several lib files also source it themselves (guarded) so unit
# tests that source one lib in isolation still see the values.
#

########################################
# TRUTHY PREDICATE (Task 9.5)
########################################

# is_truthy VALUE — the single truthy predicate (issue #86). Every
# string-boolean comparison routes through here; never compare a flag to a
# literal again. One accepted truthy set: true/1/yes/y in any letter case,
# surrounding whitespace ignored.
#
# Return codes:
#   0 — truthy (true/1/yes/y, any case, whitespace-trimmed)
#   1 — explicitly falsy: false/0/no/n, empty/unset
#   2 — value UNRECOGNIZED: warns on stderr and fails closed (rc 2, i.e.
#       non-zero — a plain `if is_truthy` treats it as "not enabled", the
#       conservative direction for enable-flags)
#
# (Bash 3.2-safe: no extglob, no [[ =~ ]].)
is_truthy() {
  local raw="${1-}"
  local norm="$raw"

  # Trim leading/trailing whitespace (same idiom as is_dry_run).
  norm="${norm#"${norm%%[![:space:]]*}"}"
  norm="${norm%"${norm##*[![:space:]]}"}"

  case "$norm" in
    [tT][rR][uU][eE]|1|[yY][eE][sS]|[yY])
      return 0
      ;;
    ""|[fF][aA][lL][sS][eE]|0|[nN][oO]|[nN])
      return 1
      ;;
    *)
      echo "warning: ignoring unrecognized boolean value '${raw}' — failing closed (treated as false)" >&2
      return 2
      ;;
  esac
}

# is_uint VALUE — the single unsigned-integer gate (issue #111). Every
# numeric reading taken from an external command passes here before any
# arithmetic: an empty or non-numeric value must never reach (( )), where
# it silently coerces to 0 and a failed probe reports a healthy zero.
# rc 0 iff VALUE is non-empty and all digits (^[0-9]+$). For signed
# readings validate "${v#-}" instead (one leading minus stripped).
is_uint() {
  case "${1-}" in
    ""|*[!0-9]*) return 1 ;;
  esac
  return 0
}

########################################
# TERMINAL CAPABILITIES (issue #102)
########################################

# mdoctor_term_init — fill RED GREEN YELLOW BLUE CYAN BOLD DIM RESET and
# _MDOCTOR_EL in ONE `tput` exec, memoized per process. Every consumer
# previously ran its own per-capability tput (8 execs in mdoctor's startup
# block, 6 in init_colors, 2 per spinner cycle — the issue's "8 tput execs
# when tty" audit line).
#
# `tput -S` concatenates capability output with no separator, so each
# request is followed by `cr` — carriage return is a literal \r on every
# terminfo entry — giving the blob a delimiter to split on. If the blob
# carries no \r (a tput without -S support, an exotic entry) everything
# stays empty, which is the same plain output a dumb terminal gets today.
#
# Gated on `[ -t 1 ]` plus the NO_COLOR / MDOCTOR_NO_COLOR kill switches
# (issue #108): colors serve interactive output only, so a piped, hermetic
# or explicitly uncolored run never execs tput at all. A second call in the
# same process (mdoctor's startup block, then init_colors inside a command)
# refills the variables without another exec — "tput at most once per
# process".
_MDOCTOR_EL="${_MDOCTOR_EL:-}"

mdoctor_term_init() {
  # Refill from the per-process cache on repeat calls — never a second exec.
  RED="$_MDOCTOR_TC_RED" GREEN="$_MDOCTOR_TC_GREEN" YELLOW="$_MDOCTOR_TC_YELLOW"
  BLUE="$_MDOCTOR_TC_BLUE" CYAN="$_MDOCTOR_TC_CYAN" BOLD="$_MDOCTOR_TC_BOLD"
  DIM="$_MDOCTOR_TC_DIM" RESET="$_MDOCTOR_TC_RESET"
  _MDOCTOR_EL="$_MDOCTOR_TC_EL"
  # Referenced here so the published globals are not write-only in this file.
  : "${RED}${GREEN}${YELLOW}${BLUE}${CYAN}${BOLD}${DIM}${RESET}"
  if is_truthy "${_MDOCTOR_TPUT_DONE:-}"; then
    return 0
  fi
  _MDOCTOR_TPUT_DONE=true
  # NO_COLOR / MDOCTOR_NO_COLOR (issue #108): either variable set to a
  # non-empty value disables color — the no-color.org convention, applied
  # identically to both names. The capability cache stays empty, so every
  # consumer prints plain text and the spinner's erase-line never arms.
  if [ -n "${NO_COLOR:-}" ] || [ -n "${MDOCTOR_NO_COLOR:-}" ]; then
    return 0
  fi
  command -v tput >/dev/null 2>&1 || return 0
  [ -t 1 ] || return 0

  local _cr _blob
  _cr=$'\r'
  _blob="$(printf '%s\n' \
    'setaf 1' 'cr' 'setaf 2' 'cr' 'setaf 3' 'cr' 'setaf 4' 'cr' \
    'setaf 6' 'cr' 'bold' 'cr' 'dim' 'cr' 'sgr0' 'cr' 'el' 'cr' \
    | tput -S 2>/dev/null)"
  case "$_blob" in
    *"$_cr"*) ;;      # delimiter present — split below
    *) return 0 ;;    # no -S support / no caps — stay empty
  esac
  local _i=0 _v
  while IFS= read -r -d "$_cr" _v || [ -n "$_v" ]; do
    case "$_i" in
      0) _MDOCTOR_TC_RED="$_v" ;;
      1) _MDOCTOR_TC_GREEN="$_v" ;;
      2) _MDOCTOR_TC_YELLOW="$_v" ;;
      3) _MDOCTOR_TC_BLUE="$_v" ;;
      4) _MDOCTOR_TC_CYAN="$_v" ;;
      5) _MDOCTOR_TC_BOLD="$_v" ;;
      6) _MDOCTOR_TC_DIM="$_v" ;;
      7) _MDOCTOR_TC_RESET="$_v" ;;
      8) _MDOCTOR_TC_EL="$_v" ;;
    esac
    _i=$((_i + 1))
  done <<< "$_blob"
  # Publish to the public variables.
  RED="$_MDOCTOR_TC_RED" GREEN="$_MDOCTOR_TC_GREEN" YELLOW="$_MDOCTOR_TC_YELLOW"
  BLUE="$_MDOCTOR_TC_BLUE" CYAN="$_MDOCTOR_TC_CYAN" BOLD="$_MDOCTOR_TC_BOLD"
  DIM="$_MDOCTOR_TC_DIM" RESET="$_MDOCTOR_TC_RESET"
  _MDOCTOR_EL="$_MDOCTOR_TC_EL"
  # Referenced here so the published globals are not write-only in this file.
  : "${RED}${GREEN}${YELLOW}${BLUE}${CYAN}${BOLD}${DIM}${RESET}"
  return 0
}

# Guard against double-sourcing.
if is_truthy "${_MDOCTOR_CONSTANTS_LOADED:-}"; then
  return 0 2>/dev/null || true
fi
_MDOCTOR_CONSTANTS_LOADED=true

# Terminal-capability cache (mdoctor_term_init above): initialized after
# the guard so re-sourcing constants.sh can never reset the memoization
# and cause a second tput exec.
_MDOCTOR_TPUT_DONE=""
_MDOCTOR_TC_RED="" _MDOCTOR_TC_GREEN="" _MDOCTOR_TC_YELLOW="" _MDOCTOR_TC_BLUE=""
_MDOCTOR_TC_CYAN="" _MDOCTOR_TC_BOLD="" _MDOCTOR_TC_DIM="" _MDOCTOR_TC_RESET=""
_MDOCTOR_TC_EL=""

########################################
# SIZE UNITS (KB-based)
########################################

export MDOCTOR_BYTES_PER_KB=1024
export MDOCTOR_KB_PER_MB=1024
export MDOCTOR_KB_PER_GB=1048576
export MDOCTOR_KB_10GB=$(( MDOCTOR_KB_PER_GB * 10 ))

########################################
# REPORT THRESHOLDS (storage-style scans)
########################################

# Below MIN_KB an entry is skipped silently; at/above WARN_KB it warns.
export MDOCTOR_REPORT_MIN_KB=102400
export MDOCTOR_REPORT_WARN_KB="$MDOCTOR_KB_PER_GB"

########################################
# TIMEOUTS (seconds)
########################################
# Every blocking external call runs behind mdoctor_timeout (lib/timeout.sh):
# GNU timeout where available, else gtimeout, else a pure-Bash watchdog that
# still kills the probe and still reports 124 — so these caps hold on stock
# macOS too. The *_TIMEOUT_S values are env-overridable (same convention as
# the MDOCTOR_DIAG_* thresholds) so tests can shrink them without stubs
# racing real timeouts.

export MDOCTOR_DU_TIMEOUT_S=30
export MDOCTOR_FIND_TIMEOUT_S=30
export MDOCTOR_DEV_FIND_TIMEOUT_S=60

# Issue #101 — time-capped network/daemon probes. Any call that can block
# on a network round trip, a package registry, or a daemon socket gets one
# of these caps; the default bucket is MDOCTOR_CMD_TIMEOUT_S.
#
#   MDOCTOR_REGISTRY_TIMEOUT_S .. timeout for package-registry probes that
#                                 can stall on the network (timeout-capped
#                                 at every call site): 'npm' 'doctor',
#                                 'npm' 'outdated' '-g', 'pip3' 'check',
#                                 'pip3' 'list' '--outdated', 'brew'
#                                 'doctor', 'brew' 'outdated'
#   MDOCTOR_UPDATE_TIMEOUT_S .... timeout for OS update listings (each
#                                 timeout-capped): 'softwareupdate' '-l',
#                                 'apt' 'list' '--upgradable',
#                                 'apt-get' '-s' 'upgrade'
#   MDOCTOR_DOCKER_TIMEOUT_S .... timeout for the 'docker' 'info' probe +
#                                 the docker CLI calls in check_containers
#                                 (per the issue: the daemon liveness
#                                 probe is `timeout 5`)
#   MDOCTOR_DNS_TIMEOUT_S ....... timeout for the nslookup DNS probes
#                                 (check + benchmark)
#   MDOCTOR_NET_TIMEOUT_S ....... timeout for network enumerators:
#                                 netstat/ss/lsof, scutil, mdfind
#   MDOCTOR_CMD_TIMEOUT_S ....... default cap for other daemon/IPC calls:
#                                 systemctl, osascript, mdutil, ufw, the
#                                 macOS security IPC tools, ioreg/pmset
#   MDOCTOR_SYSINFO_TIMEOUT_S ... system_profiler (documented ~30s slow)
export MDOCTOR_REGISTRY_TIMEOUT_S="${MDOCTOR_REGISTRY_TIMEOUT_S:-30}"
export MDOCTOR_UPDATE_TIMEOUT_S="${MDOCTOR_UPDATE_TIMEOUT_S:-60}"
export MDOCTOR_DOCKER_TIMEOUT_S="${MDOCTOR_DOCKER_TIMEOUT_S:-5}"
export MDOCTOR_DNS_TIMEOUT_S="${MDOCTOR_DNS_TIMEOUT_S:-5}"
export MDOCTOR_NET_TIMEOUT_S="${MDOCTOR_NET_TIMEOUT_S:-15}"
export MDOCTOR_CMD_TIMEOUT_S="${MDOCTOR_CMD_TIMEOUT_S:-10}"
export MDOCTOR_SYSINFO_TIMEOUT_S="${MDOCTOR_SYSINFO_TIMEOUT_S:-45}"

# mdoctor_timeout backend override (issue #101): unset/empty = auto
# (timeout → gtimeout → builtin watchdog); "watchdog" forces the builtin
# path (tests exercise it on hosts that do ship GNU timeout).
export MDOCTOR_TIMEOUT_IMPL="${MDOCTOR_TIMEOUT_IMPL:-}"

# Parallel probe prefetch (issue #101): doctor.sh launches the independent
# slow registry/daemon captures in background jobs before the module loop
# and each consumer joins lazily, so module registration and output order
# are unchanged. MDOCTOR_PREFETCH=false runs every probe inline (still
# time-capped) — the kill switch exists so the PR can record both numbers.
export MDOCTOR_PREFETCH="${MDOCTOR_PREFETCH:-true}"

# Max paths handed to one sizing find invocation in preflight_find_kb
# (Task 11.1) — bounds exec argv so a huge match set can never hit
# ARG_MAX (tightest on macOS, ~256 KB).
export MDOCTOR_FIND_ARGV_CHUNK=2000

########################################
# SIZE-PROBE ERROR CODES (Task 9.4)
########################################
#
# Every size/lookup helper (du_size_kb, preflight_path_kb, preflight_find_kb,
# disk_used_*) returns 0 ONLY for a genuine measurement and one of these
# distinct codes otherwise; it prints its value only on success, so a caller
# can never mistake a failure for an empty result.

# Path missing/empty/not measurable target ("not a directory").
export MDOCTOR_SIZE_ERR_NO_TARGET=2
# Permission denied (top-level target unreadable/untraversable).
export MDOCTOR_SIZE_ERR_DENIED=3
# Probe timed out (timeout(1) exit code, mirrored here).
export MDOCTOR_SIZE_ERR_TIMEOUT=124
# Any other measurement failure (could not determine).
export MDOCTOR_SIZE_ERR_FAILED=1

# is_truthy unrecognized-value code (issue #86): warns and fails closed.
export MDOCTOR_TRUTHY_RC_UNSET=2

########################################
# DIAGNOSE THRESHOLDS (env-overridable)
########################################
#
# Each threshold honours an MDOCTOR_DIAG_* override, e.g.
#   MDOCTOR_DIAG_CPU_HIGH=90 ./mdoctor diagnose
# warns on per-process CPU only above 90%.

# Load average: warn when load exceeds CORES * 100 by this multiple.
export MDOCTOR_DIAG_LOAD_OVER_MULT="${MDOCTOR_DIAG_LOAD_OVER_MULT:-2}"

# Per-process CPU %.
export MDOCTOR_DIAG_CPU_HIGH="${MDOCTOR_DIAG_CPU_HIGH:-80}"
export MDOCTOR_DIAG_CPU_MED="${MDOCTOR_DIAG_CPU_MED:-50}"

# Memory pressure %.
export MDOCTOR_DIAG_MEM_CRIT="${MDOCTOR_DIAG_MEM_CRIT:-95}"
export MDOCTOR_DIAG_MEM_WARN="${MDOCTOR_DIAG_MEM_WARN:-85}"

# Free-memory %.
export MDOCTOR_DIAG_MEM_FREE_CRIT="${MDOCTOR_DIAG_MEM_FREE_CRIT:-5}"
export MDOCTOR_DIAG_MEM_FREE_WARN="${MDOCTOR_DIAG_MEM_FREE_WARN:-15}"

# Swap usage %.
export MDOCTOR_DIAG_SWAP_HIGH="${MDOCTOR_DIAG_SWAP_HIGH:-80}"
export MDOCTOR_DIAG_SWAP_MED="${MDOCTOR_DIAG_SWAP_MED:-50}"

# I/O wait %.
export MDOCTOR_DIAG_IOWAIT_HIGH="${MDOCTOR_DIAG_IOWAIT_HIGH:-30}"
export MDOCTOR_DIAG_IOWAIT_MED="${MDOCTOR_DIAG_IOWAIT_MED:-15}"

# Disk usage %.
export MDOCTOR_DIAG_DISK_CRIT="${MDOCTOR_DIAG_DISK_CRIT:-95}"
export MDOCTOR_DIAG_DISK_WARN="${MDOCTOR_DIAG_DISK_WARN:-85}"

# Single-directory size (KB) worth flagging in diagnostics.
export MDOCTOR_DIAG_DIR_WARN_KB="${MDOCTOR_DIAG_DIR_WARN_KB:-$MDOCTOR_KB_PER_GB}"

# Open-file-descriptor usage %.
export MDOCTOR_DIAG_FD_HIGH="${MDOCTOR_DIAG_FD_HIGH:-80}"
export MDOCTOR_DIAG_FD_MED="${MDOCTOR_DIAG_FD_MED:-50}"

# Connection counts.
export MDOCTOR_DIAG_CONN_HIGH="${MDOCTOR_DIAG_CONN_HIGH:-5000}"
export MDOCTOR_DIAG_CONN_MED="${MDOCTOR_DIAG_CONN_MED:-1000}"

# Swap-pressure diagnosis bands (%).
export MDOCTOR_DIAG_PRESSURE_SWAP="${MDOCTOR_DIAG_PRESSURE_SWAP:-20}"
export MDOCTOR_DIAG_THRASH_SWAP="${MDOCTOR_DIAG_THRASH_SWAP:-50}"
export MDOCTOR_DIAG_THRASH_IO="${MDOCTOR_DIAG_THRASH_IO:-10}"
export MDOCTOR_DIAG_HEAVY_SWAP="${MDOCTOR_DIAG_HEAVY_SWAP:-30}"
export MDOCTOR_DIAG_HEAVY_IO="${MDOCTOR_DIAG_HEAVY_IO:-20}"

# Load/I-O correlation bands (%).
export MDOCTOR_DIAG_LOAD_IO="${MDOCTOR_DIAG_LOAD_IO:-15}"
export MDOCTOR_DIAG_IO_ALONE="${MDOCTOR_DIAG_IO_ALONE:-20}"

# System CPU share %.
export MDOCTOR_DIAG_SYS_HIGH="${MDOCTOR_DIAG_SYS_HIGH:-40}"

# sysctl hw.pagesize fallback when the probe fails.
export MDOCTOR_PAGE_SIZE_FALLBACK=4096

########################################
# BENCHMARK SIZES
########################################

# Disk benchmark payload in MiB (bs=1M, count derived below).
export MDOCTOR_BENCH_DISK_MB=256

# External host the network benchmark resolves (DNS probe) and fetches
# over HTTPS (issue #103). Env-overridable; default example.com — the
# IANA documentation domain: stable, operated for exactly this kind of
# probe, and reachable over HTTPS on every supported platform.
export MDOCTOR_BENCH_HOST="${MDOCTOR_BENCH_HOST:-example.com}"

# Directory the disk benchmark stages its test file in (issue #103).
# Empty/unset = the per-user cache dir (platform_cache_dir()/mdoctor);
# an override must be an existing writable directory that passes the
# lib/safety.sh validators (absolute, non-traversal, non-protected).
# The filesystem type is checked at run time either way — a RAM-backed
# target (tmpfs/ramfs) is refused, never reported as disk I/O.
export MDOCTOR_BENCH_DIR="${MDOCTOR_BENCH_DIR:-}"

# sysfs power-supply root the Linux battery probe reads (issue #109).
# Overridable so tests can stage a fixture tree instead of touching real
# /sys/class/power_supply.
export MDOCTOR_POWER_SUPPLY_ROOT="${MDOCTOR_POWER_SUPPLY_ROOT:-/sys/class/power_supply}"

# sysfs thermal root the Linux temperature probe reads (issue #111).
# Overridable so tests can stage a fixture tree instead of touching real
# /sys/class/thermal.
export MDOCTOR_THERMAL_ROOT="${MDOCTOR_THERMAL_ROOT:-/sys/class/thermal}"

# os-release file sourced during Linux platform detection (issue #111).
# Overridable so tests can stage a fixture file instead of reading the
# host's real /etc/os-release.
export MDOCTOR_OS_RELEASE="${MDOCTOR_OS_RELEASE:-/etc/os-release}"
