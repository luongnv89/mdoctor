#!/usr/bin/env bash
#
# lib/benchmark.sh
# System benchmark: Disk I/O, Network, CPU
# Risk: SAFE (uses temp files, no system modification)
#
# Issue #103 (Task 11.9): the disk benchmark measures a REAL disk — the
# scratch file is staged under the per-user cache dir (never /tmp, which
# is tmpfs/RAM on systemd Linux), the backing filesystem type is verified
# and RAM-backed or unverifiable targets refuse to report, and dd flushes
# via conv=fdatasync instead of a system-wide `sync`. The network probes
# run over HTTPS against MDOCTOR_BENCH_HOST (default example.com).
#

# Benchmark sizes (Task 8.7); guarded so isolated sourcing works.
# Zero-fork (issue #102): the lib dir is the literal directory part of
# ${BASH_SOURCE[0]} — parameter expansion replaces the old
# $(cd "$(dirname …)" && pwd) probe, and the declare -f guards skip the
# sources entirely once the base libs are loaded.
_mdoctor_lib_dir="${BASH_SOURCE[0]%/*}"
if [ "$_mdoctor_lib_dir" = "${BASH_SOURCE[0]}" ]; then
  _mdoctor_lib_dir="."
fi
if ! declare -f is_truthy >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "${_mdoctor_lib_dir}/constants.sh"
fi
if ! declare -f is_linux >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "${_mdoctor_lib_dir}/platform.sh"
fi
if ! declare -f register_exit_hook >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "${_mdoctor_lib_dir}/common.sh"
fi
# safety.sh validators (_normalize_path / _canonical_path /
# is_protected_deletion_path) gate the scratch dir: every path this file
# creates or removes is safety.sh-validated first (issue #103).
if ! declare -f is_protected_deletion_path >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "${_mdoctor_lib_dir}/safety.sh"
fi
# mdoctor_timeout (issue #101): the DNS + HTTPS probes are capped even
# without GNU timeout.
if ! declare -f mdoctor_timeout >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "${_mdoctor_lib_dir}/timeout.sh"
fi
unset _mdoctor_lib_dir

_BENCH_TMP_DIR=""

# _bench_time → high-resolution timestamp in seconds (uses Perl's Time::HiRes)
_bench_time() {
  perl -MTime::HiRes=time -e 'printf "%.6f\n", time()' 2>/dev/null || date +%s
}

# _bench_elapsed START END → prints elapsed time in seconds
_bench_elapsed() {
  awk -v s="$1" -v e="$2" 'BEGIN {printf "%.3f", e - s}'
}

# _bench_fs_type DIR — print the filesystem type backing DIR, nothing
# when it cannot be determined.
#   Linux: `df -PT` (one-line POSIX output with the Type column), then a
#     /proc/mounts longest-prefix fallback for dd-flavoured environments
#     without a -T flag (BusyBox).
#   macOS: `mount` prints "dev on /mp (type, opts)" — walk DIR's
#     ancestors until one matches a mountpoint exactly.
_bench_fs_type() {
  local target="${1-}"
  local fstype=""
  [ -n "$target" ] || return 1
  if is_linux; then
    fstype="$(df -PT "$target" 2>/dev/null | awk 'NR==2 && NF>=2 {print $2; exit}')"
    if [ -z "$fstype" ] && [ -r /proc/mounts ]; then
      fstype="$(awk -v t="$target" '
        {
          mp = $2
          # "/" is the ancestor of every path but never prefixes one as
          # "//"; the other mountpoints match exactly or as a parent.
          if (mp == "/" || t == mp || index(t, mp "/") == 1) {
            if (length(mp) > best) { best = length(mp); ft = $3 }
          }
        }
        END { if (best) print ft }
      ' /proc/mounts)"
    fi
  elif is_macos; then
    local dir="$target" line="" rest="" mtab=""
    mtab="$(mount 2>/dev/null)"
    while [ -n "$dir" ]; do
      line="$(printf '%s\n' "$mtab" | awk -v d="$dir" 'index($0, " on " d " (") {print; exit}')"
      [ -n "$line" ] && break
      [ "$dir" = "/" ] && break
      dir="${dir%/*}"
      [ -n "$dir" ] || dir="/"
    done
    case "$line" in
      *"("*)
        rest="${line#*(}"
        fstype="${rest%%,*}"
        ;;
    esac
  fi
  [ -n "$fstype" ] || return 1
  printf '%s\n' "$fstype"
}

# _bench_scratch_dir — print a fresh canonical scratch dir for the
# benchmark's real file writes; rc 1 when no acceptable base exists.
# The base is $MDOCTOR_BENCH_DIR when set (must already exist), else the
# per-user cache dir — never ${TMPDIR:-/tmp}: on systemd Linux that is
# tmpfs and the "disk" numbers would be RAM bandwidth (issue #103). The
# base passes the lib/safety.sh validators (normalize → absolute → no
# traversal → no control characters → canonical → not a protected
# deletion path → existing writable dir); the dir returned is a
# `mdoctor-bench.*` mktemp child of that validated base, canonicalized
# again so the removal target is provably the dir this process created.
_bench_scratch_dir() {
  local base="${MDOCTOR_BENCH_DIR:-}"
  if [ -z "$base" ]; then
    base="$(platform_cache_dir)/mdoctor"
    mkdir -p "$base" 2>/dev/null || true
    chmod 700 "$base" 2>/dev/null || true
  fi

  local canon=""
  _normalize_path "$base" canon
  case "$canon" in
    /*) ;;
    *) return 1 ;;
  esac
  if [[ "$canon" =~ (^|/)\.\.(/|$) ]]; then
    return 1
  fi
  case "$canon" in
    *$'\n'*|*$'\r'*|*$'\t'*) return 1 ;;
  esac
  _canonical_path "$canon" canon
  _normalize_path "$canon" canon
  if is_protected_deletion_path "$canon"; then
    return 1
  fi
  [ -d "$canon" ] && [ -w "$canon" ] || return 1

  local dir="" canon_dir=""
  dir="$(mktemp -d "${canon%/}/mdoctor-bench.XXXXXX" 2>/dev/null)" || return 1
  _canonical_path "$dir" canon_dir
  _normalize_path "$canon_dir" canon_dir
  printf '%s\n' "$canon_dir"
}

# _bench_cleanup_tmp — ordered-exit-hook cleanup for the scratch dir.
# Only paths matching the `mdoctor-bench.*` mktemp shape are ever
# removed: the guard keeps a corrupted _BENCH_TMP_DIR from widening rm.
_bench_cleanup_tmp() {
  case "${_BENCH_TMP_DIR-}" in
    */mdoctor-bench.*)
      rm -rf -- "${_BENCH_TMP_DIR}" 2>/dev/null || true
      ;;
  esac
}

# _bench_dd_conv_sync DIR — probe which end-of-write flush conv this dd
# supports and print it: fdatasync (GNU coreutils, Linux) → fsync →
# osync (BSD). The flag makes dd sync THIS file to media before exiting,
# so the write number covers the real commit — replacing the old bare
# `sync` that flushed every process's dirty pages into our timing
# (issue #103). Empty output = no conv support; the caller then writes
# without one. The probe file sits in the benchmark's own dir so the
# answer describes the same filesystem.
_bench_dd_conv_sync() {
  local dir="${1-}" probe="" c=""
  probe="${dir%/}/.dd-sync-probe.$$"
  for c in fdatasync fsync osync; do
    if dd if=/dev/zero of="$probe" bs=1 count=1 conv="$c" 2>/dev/null; then
      rm -f "$probe" 2>/dev/null
      printf '%s\n' "$c"
      return 0
    fi
  done
  rm -f "$probe" 2>/dev/null
  return 1
}

# _bench_dd_iflag_direct FILE BS — true when this dd can read FILE with
# iflag=direct: O_DIRECT bypasses the page cache so the read number is
# the media's, not a cache hit (issue #103). The probe performs the
# flagged one-block read itself; dd flavours without the flag (BSD/macOS
# builds vary) fail at argv parse, before any I/O, so the rc is a pure
# capability answer.
_bench_dd_iflag_direct() {
  dd if="${1-}" of=/dev/null bs="${2:-1M}" count=1 iflag=direct 2>/dev/null
}

run_benchmark() {
  echo "${BOLD}${BLUE}== System Benchmark ==${RESET}"
  echo
  echo "Running disk, network, and CPU benchmarks..."
  echo

  local bs
  # macOS dd uses lowercase 'm' for megabytes; Linux uses uppercase 'M'
  if is_macos 2>/dev/null; then bs="1m"; else bs="1M"; fi
  local count="$MDOCTOR_BENCH_DISK_MB"  # block count IS the MiB size (bs=1M); the MiB value below derives from it

  # Real-disk scratch dir (issue #103). A tmpfs/ramfs/devtmpfs target —
  # or one whose filesystem type cannot be verified — refuses to report:
  # a number that might be RAM bandwidth is never presented as disk I/O.
  local tmp_dir=""
  tmp_dir="$(_bench_scratch_dir)"
  local disk_skip=""
  if [ -n "$tmp_dir" ]; then
    _BENCH_TMP_DIR="$tmp_dir"
    # Ensure cleanup via the ordered exit-hook list (Task 4.7): a bare
    # `trap ... EXIT` here would clobber the session/spinner handlers,
    # and the old `trap - EXIT` disarm would have cleared them too.
    register_exit_hook _bench_cleanup_tmp
    local _bench_fs=""
    _bench_fs="$(_bench_fs_type "$tmp_dir")"
    case "$_bench_fs" in
      tmpfs|ramfs|devtmpfs)
        disk_skip="${tmp_dir} is ${_bench_fs} (RAM-backed) — results would measure memory, not disk"
        ;;
      "")
        disk_skip="filesystem type of ${tmp_dir} could not be determined — results would be unverifiable"
        ;;
    esac
  else
    disk_skip="no writable scratch directory (see MDOCTOR_BENCH_DIR)"
  fi

  ########################################
  # DISK I/O
  ########################################
  echo "${BOLD}1. Disk I/O${RESET}"

  local w_start w_end w_elapsed w_speed r_start r_end r_elapsed r_speed
  if [ -n "$disk_skip" ]; then
    w_speed="skipped"
    r_speed="skipped"
    printf "  %-20s %s\n" "Write/Read:" "skipped — $disk_skip"
  else
    local disk_file="${tmp_dir}/bench_disk"

    # Write test — dd flushes the file to media itself via the probed
    # conv (fdatasync/fsync/osync); no system-wide `sync` is run.
    local conv=""
    conv="$(_bench_dd_conv_sync "$tmp_dir")"
    w_start=$(_bench_time)
    if [ -n "$conv" ]; then
      dd if=/dev/zero of="$disk_file" bs="$bs" count="$count" conv="$conv" 2>/dev/null
    else
      dd if=/dev/zero of="$disk_file" bs="$bs" count="$count" 2>/dev/null
    fi
    w_end=$(_bench_time)
    w_elapsed=$(_bench_elapsed "$w_start" "$w_end")
    w_speed=$(awk -v sz="$count" -v t="$w_elapsed" 'BEGIN {if(t>0) printf "%.1f", sz/t; else print "N/A"}')

    # Read test — bypass the page cache (iflag=direct where dd supports
    # it) or drop it (purge on macOS) so the number is the media's.
    if is_macos 2>/dev/null; then
      purge 2>/dev/null || true
    fi
    local iflag=""
    if _bench_dd_iflag_direct "$disk_file" "$bs"; then
      iflag="direct"
    fi
    r_start=$(_bench_time)
    if [ -n "$iflag" ]; then
      dd if="$disk_file" of=/dev/null bs="$bs" iflag="$iflag" 2>/dev/null
    else
      dd if="$disk_file" of=/dev/null bs="$bs" 2>/dev/null
    fi
    r_end=$(_bench_time)
    r_elapsed=$(_bench_elapsed "$r_start" "$r_end")
    r_speed=$(awk -v sz="$count" -v t="$r_elapsed" 'BEGIN {if(t>0) printf "%.1f", sz/t; else print "N/A"}')

    rm -f "$disk_file"

    printf "  %-20s %s\n" "Write (${MDOCTOR_BENCH_DISK_MB} MB):" "${w_speed} MB/s (${w_elapsed}s)"
    printf "  %-20s %s\n" "Read (${MDOCTOR_BENCH_DISK_MB} MB):" "${r_speed} MB/s (${r_elapsed}s)"
  fi
  echo

  ########################################
  # NETWORK
  ########################################
  echo "${BOLD}2. Network${RESET}"

  # One documented, configurable external host for both probes
  # (issue #103): MDOCTOR_BENCH_HOST, default example.com. The fetch
  # runs over HTTPS — no cleartext request leaks that this machine is
  # running mdoctor, and a captive portal cannot redirect the probe.
  local bench_host="${MDOCTOR_BENCH_HOST:-example.com}"

  # DNS resolution latency — timeout-capped (issue #101)
  local dns_start dns_end dns_ms _dns_rc=0
  dns_start=$(_bench_time)
  mdoctor_timeout "$MDOCTOR_DNS_TIMEOUT_S" nslookup "$bench_host" >/dev/null 2>&1 || _dns_rc=$?
  dns_end=$(_bench_time)
  dns_ms=$(awk -v s="$dns_start" -v e="$dns_end" 'BEGIN {printf "%.0f", (e-s)*1000}')
  if [ "$_dns_rc" -eq 124 ]; then
    printf "  %-20s %s\n" "DNS resolution:" "timed out (timeout ${MDOCTOR_DNS_TIMEOUT_S}s)"
  else
    printf "  %-20s %s\n" "DNS resolution:" "${dns_ms}ms"
  fi

  # Small file download speed — `curl -m 10` hard cap (issue #101): the
  # fetch can never outlast 10s.
  if command -v curl >/dev/null 2>&1; then
    local dl_start dl_end dl_elapsed _dl_rc=0
    local dl_url="https://${bench_host}"
    dl_start=$(_bench_time)
    curl -m 10 -sS -o /dev/null -w '' "$dl_url" 2>/dev/null || _dl_rc=$?
    dl_end=$(_bench_time)
    dl_elapsed=$(_bench_elapsed "$dl_start" "$dl_end")
    if [ "$_dl_rc" -eq 28 ]; then
      printf "  %-20s %s\n" "HTTPS fetch:" "timed out (curl -m 10)"
    else
      printf "  %-20s %s\n" "HTTPS fetch:" "${dl_elapsed}s (${bench_host})"
    fi
  fi
  echo

  ########################################
  # CPU
  ########################################
  echo "${BOLD}3. CPU${RESET}"

  # Compress 10MB random data via gzip — staged in the same scratch dir
  # (the file is input data, not the measurement target, so a
  # RAM-backed scratch is acceptable here; only the disk numbers refuse).
  local c_start c_end c_elapsed
  if [ -z "$tmp_dir" ]; then
    c_elapsed="skipped"
    printf "  %-20s %s\n" "gzip 10 MB:" "skipped — no scratch dir"
  else
    local cpu_file="${tmp_dir}/bench_cpu"
    dd if=/dev/urandom of="$cpu_file" bs="$bs" count=10 2>/dev/null

    c_start=$(_bench_time)
    gzip -c "$cpu_file" > /dev/null
    c_end=$(_bench_time)
    c_elapsed=$(_bench_elapsed "$c_start" "$c_end")
    printf "  %-20s %s\n" "gzip 10 MB:" "${c_elapsed}s"

    rm -f "$cpu_file"
  fi

  echo
  echo "${BOLD}Results Summary${RESET}"
  echo "  ┌──────────────────────┬──────────────────┐"
  printf "  │ %-20s │ %-16s │\n" "Test" "Result"
  echo "  ├──────────────────────┼──────────────────┤"
  if [ -n "$disk_skip" ]; then
    printf "  │ %-20s │ %-16s │\n" "Disk Write (${MDOCTOR_BENCH_DISK_MB}MB)" "$w_speed"
    printf "  │ %-20s │ %-16s │\n" "Disk Read (${MDOCTOR_BENCH_DISK_MB}MB)" "$r_speed"
  else
    printf "  │ %-20s │ %13s MB/s │\n" "Disk Write (${MDOCTOR_BENCH_DISK_MB}MB)" "$w_speed"
    printf "  │ %-20s │ %13s MB/s │\n" "Disk Read (${MDOCTOR_BENCH_DISK_MB}MB)" "$r_speed"
  fi
  printf "  │ %-20s │ %15s ms │\n" "DNS Resolution" "$dns_ms"
  if [ "$c_elapsed" = "skipped" ]; then
    printf "  │ %-20s │ %-16s │\n" "CPU gzip (10MB)" "$c_elapsed"
  else
    printf "  │ %-20s │ %16ss │\n" "CPU gzip (10MB)" "$c_elapsed"
  fi
  echo "  └──────────────────────┴──────────────────┘"
  echo

  _bench_cleanup_tmp
  _BENCH_TMP_DIR=""
  unregister_exit_hook _bench_cleanup_tmp
}
