#!/usr/bin/env bash
#
# lib/preflight.sh
# Shared pre-flight size estimators (Task 8.3, part 1 of the god-module split).
# Both entry points (`mdoctor` single-module pre-flight and `cleanup.sh` full
# pre-flight) source this module so the estimate logic exists once and both
# produce byte-identical numbers for the same target set.
#
# Sourcing contract: lib/disk.sh must be sourced first (du_size_kb,
# human_readable_kb).
#


# TRUTHY_BOOTSTRAP (Task 9.5): is_truthy lives in constants.sh, the
# zero-dependency base lib. Source it before the guard so standalone
# sourcing of this file still sees the predicate.
_MDOCTOR_TRUTHY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null || pwd)"
# shellcheck source=/dev/null
source "${_MDOCTOR_TRUTHY_DIR}/constants.sh"
unset _MDOCTOR_TRUTHY_DIR

if is_truthy "${_MDOCTOR_PREFLIGHT_LOADED:-}"; then
  return 0 2>/dev/null || true
fi
_MDOCTOR_PREFLIGHT_LOADED=true

# ---------------------------------------------------------------------------
# Keyed per-process size cache (Task 11.2 / issue #96, F-PERF-005)
# ---------------------------------------------------------------------------
#
# The force-mode pre-flight sizes a fixed set of cache roots; the cleanup
# modules then re-measure the same paths seconds later in the same process
# (on macOS DerivedData was walked three times). The cache stores one KB
# figure per normalized path so every path is measured at most once per
# process; preflight_size_path additionally drops a path nested inside an
# already-measured parent from the estimate (its bytes are already inside
# the parent's total).
#
# Bash 3.2 has no associative arrays, so the store is one newline-separated
# list of "key<TAB>kb" records (~a dozen entries — a linear scan is cheap
# and portable). Keys are normalized by _size_cache_key; a path containing
# a tab or newline can never be a key and is measured without caching (the
# deletion validators reject those characters anyway).
#
# Call contract — mutating entry points MUST be invoked as plain commands,
# never inside $(...): a command substitution runs in a subshell whose
# writes die with it, so `x=$(size_cache_kb p)` would silently bypass the
# store (the value would still be returned via MDOCTOR_SIZE_KB inside the
# subshell only — use the read-only print API size_cache_lookup there).
# Mutating calls return their result in globals instead of stdout:
#   MDOCTOR_SIZE_KB   — KB printed-equivalent of the last size_cache_kb /
#                       preflight_size_path call ("" on failure)
#   MDOCTOR_SIZE_ADD  — KB the last preflight_size_path contributes to an
#                       estimate total (0 for cache hits and covered paths)
#   MDOCTOR_SIZE_COVER — cached ancestor covering the last queried path
#                       ("" when none)
# MDOCTOR_SIZE_CACHE_MEASUREMENTS counts real disk probes — it is
# incremented only on a fresh successful measurement, never on a cache hit
# or a failed probe.
_MDOCTOR_SIZE_CACHE=""
# The MDOCTOR_SIZE_* result globals are exported: cleanup.sh, mdoctor and
# the cleanup modules consume them cross-file — same convention as the
# module-context scalars in lib/context.sh. The private store
# (_MDOCTOR_SIZE_CACHE) stays unexported on purpose: it is per-process
# state and must never leak into a child's environment.
export MDOCTOR_SIZE_CACHE_MEASUREMENTS=0
export MDOCTOR_SIZE_KB=""
export MDOCTOR_SIZE_ADD=0
export MDOCTOR_SIZE_COVER=""

# _size_cache_key PATH — normalized cache identity for a path: collapses
# repeated slashes and strips trailing ones ("/" survives). Deliberately
# textual — no symlink resolution: the cache dedupes one spelling of a
# path per process, and callers pass canonical absolute paths.
_size_cache_key() {
  local p="${1-}"
  while [[ "$p" == *"//"* ]]; do
    p="${p//\/\//\/}"
  done
  while [ "$p" != "/" ] && [ "${p%/}" != "$p" ]; do
    p="${p%/}"
  done
  [ -z "$p" ] && p="/"
  printf '%s\n' "$p"
}

# _size_cache_key_cacheable PATH — rc 0 when the normalized key can be
# stored (no tab/newline, which would corrupt the line-based records).
_size_cache_key_cacheable() {
  case "${1-}" in
    ''|*$'\t'*|*$'\n'*) return 1 ;;
  esac
  return 0
}

# size_cache_lookup PATH — read-only lookup. Prints the cached KB and
# returns 0 on a hit; prints nothing and returns 1 on a miss. Never
# measures, never mutates — safe to call inside $(...).
size_cache_lookup() {
  local key line k
  key="$(_size_cache_key "${1-}")"
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    k="${line%%$'\t'*}"
    if [ "$k" = "$key" ]; then
      printf '%s\n' "${line#*$'\t'}"
      return 0
    fi
  done <<EOF
$_MDOCTOR_SIZE_CACHE
EOF
  return 1
}

# size_cache_covering_root PATH — read-only ancestor check. When a stored
# key is a strict ancestor of PATH (its measurement already includes this
# subtree), prints the LONGEST such key and returns 0; returns 1 when no
# cached root covers PATH. A path does not cover itself. Safe for $(...).
size_cache_covering_root() {
  local key line k best=""
  key="$(_size_cache_key "${1-}")"
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    k="${line%%$'\t'*}"
    [ "$k" = "$key" ] && continue
    if [ "$k" = "/" ]; then
      # "/" is a strict ancestor of every other absolute path.
      best="/"
      continue
    fi
    # Literal-prefix test (quoted RHS of ${var#...} is literal): removing
    # "$k/" from the front changes the string iff $k is a strict ancestor.
    if [ "${key#"$k"/}" != "$key" ]; then
      if [ "${#k}" -gt "${#best}" ]; then
        best="$k"
      fi
    fi
  done <<EOF
$_MDOCTOR_SIZE_CACHE
EOF
  if [ -n "$best" ]; then
    printf '%s\n' "$best"
    return 0
  fi
  return 1
}

# size_cache_kb PATH — cached whole-path size in KB. On a hit returns 0
# with MDOCTOR_SIZE_KB set and no disk access; on a miss runs du_size_kb
# once, stores the result and bumps MDOCTOR_SIZE_CACHE_MEASUREMENTS.
# Probe failures propagate the MDOCTOR_SIZE_ERR_* code unchanged and are
# never cached (a later caller may retry). DIRECT CALL ONLY — see the
# call-contract note above; MDOCTOR_SIZE_KB carries the result.
size_cache_kb() {
  MDOCTOR_SIZE_KB=""
  local path="${1-}"
  local key kb rc=0
  key="$(_size_cache_key "$path")"
  if _size_cache_key_cacheable "$key"; then
    if kb="$(size_cache_lookup "$path")"; then
      MDOCTOR_SIZE_KB="$kb"
      if declare -f debug_log >/dev/null 2>&1; then
        debug_log "size-cache hit ${key} ${kb}KB"
      fi
      return 0
    fi
  fi
  kb="$(du_size_kb "$path")" || rc=$?
  if [ "$rc" -ne 0 ]; then
    return "$rc"
  fi
  MDOCTOR_SIZE_KB="$kb"
  if _size_cache_key_cacheable "$key"; then
    _MDOCTOR_SIZE_CACHE="${_MDOCTOR_SIZE_CACHE}${key}"$'\t'"${kb}"$'\n'
  fi
  MDOCTOR_SIZE_CACHE_MEASUREMENTS=$((MDOCTOR_SIZE_CACHE_MEASUREMENTS + 1))
  if declare -f debug_log >/dev/null 2>&1; then
    debug_log "size-cache measured ${key} ${kb}KB (measurements=${MDOCTOR_SIZE_CACHE_MEASUREMENTS})"
  fi
  return 0
}

# preflight_size_path PATH — the estimate-time path sizer. Wraps
# size_cache_kb with the two estimate policies of Task 11.2: a path that
# was already measured contributes its size to the display but 0 KB to
# the total (MDOCTOR_SIZE_ADD), and a path nested inside an already-
# measured parent is neither measured nor counted — MDOCTOR_SIZE_COVER
# names the covering ancestor so the caller can print "included in …".
# Always returns 0; an unmeasurable path leaves MDOCTOR_SIZE_KB empty.
preflight_size_path() {
  MDOCTOR_SIZE_KB=""
  MDOCTOR_SIZE_ADD=0
  MDOCTOR_SIZE_COVER=""
  local path="${1-}"
  local anc
  if MDOCTOR_SIZE_KB="$(size_cache_lookup "$path")"; then
    # Exact repeat: display the cached size, add nothing a second time.
    return 0
  fi
  if anc="$(size_cache_covering_root "$path")"; then
    MDOCTOR_SIZE_COVER="$anc"
    return 0
  fi
  if size_cache_kb "$path"; then
    MDOCTOR_SIZE_ADD="$MDOCTOR_SIZE_KB"
  fi
  return 0
}

# size_cache_reset — test/debug hook: drop every entry and the counter.
size_cache_reset() {
  _MDOCTOR_SIZE_CACHE=""
  MDOCTOR_SIZE_CACHE_MEASUREMENTS=0
  MDOCTOR_SIZE_KB=""
  MDOCTOR_SIZE_ADD=0
  MDOCTOR_SIZE_COVER=""
}

# size_cache_keys — read-only dump: prints each cached key, one per line.
size_cache_keys() {
  local line
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    printf '%s\n' "${line%%$'\t'*}"
  done <<EOF
$_MDOCTOR_SIZE_CACHE
EOF
}

# preflight_path_kb PATH — size of one path in KB. Prints the size only on
# success (rc 0); on failure prints nothing and propagates the distinct
# MDOCTOR_SIZE_ERR_* code. Thin printing wrapper over size_cache_kb
# (Task 11.2): called directly it populates the cache; called inside
# $(...) the store cannot persist, which degrades to a plain probe —
# correct either way, only the dedup is lost.
preflight_path_kb() {
  local rc=0
  size_cache_kb "${1-}" || rc=$?
  if [ "$rc" -ne 0 ]; then
    return "$rc"
  fi
  printf '%s\n' "$MDOCTOR_SIZE_KB"
}

# _preflight_find_entries BASE [FIND ARGS...] — matcher producer for
# preflight_find_kb: streams NUL-separated entry paths, then a final
# _MDOCTOR_FIND_RC_<n> sentinel carrying the find exit code (the rc of a
# process substitution is lost, and command substitution would drop the
# NUL separators, Task 3.6). Wraps the find in a timeout where available
# (GNU-only; macOS runs it directly). A path literally named
# "_MDOCTOR_FIND_RC_<n>" would be mistaken for the sentinel.
_preflight_find_entries() {
  if command -v timeout >/dev/null 2>&1; then
    timeout "$MDOCTOR_FIND_TIMEOUT_S" find "$@" -print0 2>/dev/null
    printf '%s\0' "_MDOCTOR_FIND_RC_$?"
  else
    find "$@" -print0 2>/dev/null
    printf '%s\0' "_MDOCTOR_FIND_RC_$?"
  fi
}

# _preflight_find_printf_ok — memoized capability probe for
# _preflight_find_size_kb. GNU find prints each entry's allocated size in
# the sizing pass itself (-printf '%k\n'); BSD find (macOS) has no
# -printf, so the sizer falls back to one batched `stat -f %b` exec pass.
# Probed once per process under the same timeout as the scan so a wedged
# find can never stall it, then memoized for the remaining call sites.
_MDOCTOR_FIND_PRINTF_OK=""
_preflight_find_printf_ok() {
  local rc=0
  if [ -n "$_MDOCTOR_FIND_PRINTF_OK" ]; then
    is_truthy "$_MDOCTOR_FIND_PRINTF_OK"
    return $?
  fi
  if command -v timeout >/dev/null 2>&1; then
    timeout "$MDOCTOR_FIND_TIMEOUT_S" find . -maxdepth 0 -printf '%k\n' >/dev/null 2>&1 || rc=$?
  else
    find . -maxdepth 0 -printf '%k\n' >/dev/null 2>&1 || rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    _MDOCTOR_FIND_PRINTF_OK=true
  else
    _MDOCTOR_FIND_PRINTF_OK=false
  fi
  is_truthy "$_MDOCTOR_FIND_PRINTF_OK"
}

# _preflight_stat_blocks_flag — memoized stat-flavor probe for the
# non-printf sizing arm of _preflight_find_size_kb. BSD stat (macOS)
# takes the per-file 512-byte block count as `stat -f %b`; GNU and
# busybox stat take `stat -c %b` — on both of those `-f` means
# "filesystem status" (statfs) and swallows %b as a filename operand,
# printing host-wide block totals instead of the file's. Probes each
# spelling once per process on '.', keeps the flag letter that returns
# a bare block count, and records "none" when neither does so the sizer
# can fail closed rather than print a wrong total.
_MDOCTOR_STAT_BLOCKS_FLAG=""
_preflight_stat_blocks_flag() {
  local out
  case "$_MDOCTOR_STAT_BLOCKS_FLAG" in
    f|c) return 0 ;;
    none) return 1 ;;
  esac
  out="$(stat -f %b . 2>/dev/null)"
  case "$out" in
    ''|*[!0-9]*) ;;
    *) _MDOCTOR_STAT_BLOCKS_FLAG=f; return 0 ;;
  esac
  out="$(stat -c %b . 2>/dev/null)"
  case "$out" in
    ''|*[!0-9]*) ;;
    *) _MDOCTOR_STAT_BLOCKS_FLAG=c; return 0 ;;
  esac
  _MDOCTOR_STAT_BLOCKS_FLAG=none
  return 1
}

# _preflight_find_size_kb PATH... — the sizing pass (Task 11.1): one find
# invocation over the already-resolved match set, never a du per entry.
# GNU find emits each entry's %k — allocated 1K blocks, the same figure
# du_size_kb reported per entry; for a directory match the traversal
# sums the whole subtree exactly like a recursive du did. Without
# -printf (BSD/macOS find, busybox) it batches one `stat` exec pass —
# `stat -f %b` on BSD, `stat -c %b` on GNU/busybox, picked by the
# _preflight_stat_blocks_flag probe — over allocated 512-byte blocks,
# and awk applies the same per-entry round-up to KB that du uses.
# Prints the KB total on rc 0; a pass that measured nothing propagates
# the find exit code and a timed-out pass the timeout code, while a
# partially measured stream still prints its (genuine) total — entries
# whose own probe failed were always skipped.
_preflight_find_size_kb() {
  local stream="" rc=0
  if _preflight_find_printf_ok; then
    if command -v timeout >/dev/null 2>&1; then
      stream=$(timeout "$MDOCTOR_FIND_TIMEOUT_S" find "$@" -printf '%k\n' 2>/dev/null) || rc=$?
    else
      stream=$(find "$@" -printf '%k\n' 2>/dev/null) || rc=$?
    fi
    if [ "$rc" -eq 124 ]; then
      return "$MDOCTOR_SIZE_ERR_TIMEOUT"
    fi
    if [ -z "$stream" ]; then
      [ "$rc" -eq 0 ] || return "$rc"
      printf '0\n'
      return 0
    fi
    # In-shell sum of field 1 across the stream — replaces printf|awk
    # (issue #98). Non-numeric fields coerce to 0 like awk's $1+0.
    local _pf_sum=0 _pf_line _pf_v
    while IFS= read -r _pf_line; do
      read -r _pf_v _ <<< "$_pf_line"
      case "$_pf_v" in
        ''|*[!0-9]*) _pf_v=0 ;;
      esac
      _pf_sum=$((_pf_sum + _pf_v))
    done <<< "$stream"
    printf '%s\n' "$_pf_sum"
    return 0
  fi
  if ! _preflight_stat_blocks_flag; then
    # Neither -printf find nor a known stat flavour: fail closed rather
    # than print a wrong total (MDOCTOR_SIZE_ERR_FAILED).
    return "$MDOCTOR_SIZE_ERR_FAILED"
  fi
  if command -v timeout >/dev/null 2>&1; then
    stream=$(timeout "$MDOCTOR_FIND_TIMEOUT_S" find "$@" -exec stat "-${_MDOCTOR_STAT_BLOCKS_FLAG}" %b {} + 2>/dev/null) || rc=$?
  else
    stream=$(find "$@" -exec stat "-${_MDOCTOR_STAT_BLOCKS_FLAG}" %b {} + 2>/dev/null) || rc=$?
  fi
  if [ "$rc" -eq 124 ]; then
    return "$MDOCTOR_SIZE_ERR_TIMEOUT"
  fi
  if [ -z "$stream" ]; then
    [ "$rc" -eq 0 ] || return "$rc"
    printf '0\n'
    return 0
  fi
  # In-shell equivalent of the retired awk 'NF { s += int(($1+1)/2) }':
  # blank lines (NF==0) are skipped; stat %b 512-blocks convert to KB by
  # integer division (issue #98).
  local _pf_sum=0 _pf_line _pf_v
  while IFS= read -r _pf_line; do
    if [ -z "${_pf_line//[[:space:]]/}" ]; then
      continue
    fi
    read -r _pf_v _ <<< "$_pf_line"
    case "$_pf_v" in
      ''|*[!0-9]*) _pf_v=0 ;;
    esac
    _pf_sum=$((_pf_sum + (_pf_v + 1) / 2))
  done <<< "$stream"
  printf '%s\n' "$_pf_sum"
  return 0
}

# preflight_find_kb BASE [FIND ARGS...] — summed size in KB of all entries
# under BASE matching the given find arguments; a matched directory
# contributes its whole subtree, exactly as the retired per-entry du
# loop measured it. Prints the total only on success (rc 0); distinct
# failure codes (Task 9.4): a missing base returns
# MDOCTOR_SIZE_ERR_NO_TARGET, an untraversable one MDOCTOR_SIZE_ERR_DENIED,
# a timed-out find MDOCTOR_SIZE_ERR_TIMEOUT; a partially measured match
# set keeps its (genuine) total.
preflight_find_kb() {
  local base="${1-}"
  shift || true

  if [ -z "$base" ] || [ ! -d "$base" ]; then
    return "$MDOCTOR_SIZE_ERR_NO_TARGET"
  fi
  if [ ! -r "$base" ] || [ ! -x "$base" ]; then
    return "$MDOCTOR_SIZE_ERR_DENIED"
  fi

  # Pass 1 (Task 11.1): resolve the match set once — NUL-separated, so
  # newline-bearing paths stay safe — keeping the find exit code via the
  # _MDOCTOR_FIND_RC_<n> sentinel.
  local -a matches=()
  local p=""
  local find_rc=0
  while IFS= read -r -d '' p; do
    case "$p" in
      _MDOCTOR_FIND_RC_*)
        find_rc="${p#_MDOCTOR_FIND_RC_}"
        ;;
      *)
        matches+=("$p")
        ;;
    esac
  done < <(_preflight_find_entries "$base" "$@")

  case "$find_rc" in
    0) ;;
    124) return "$MDOCTOR_SIZE_ERR_TIMEOUT" ;;
    1) return "$MDOCTOR_SIZE_ERR_DENIED" ;;
    *) return "$MDOCTOR_SIZE_ERR_FAILED" ;;
  esac

  local n="${#matches[@]}"
  if [ "$n" -eq 0 ]; then
    printf '0\n'
    return 0
  fi

  # Pass 2: one chunked sizing traversal over the match set — the
  # per-entry du + awk spawn that made this 210x slower is gone
  # (F-PERF-004). Shared with callers that resolved their own match set
  # (Task 11.3).
  preflight_size_paths_kb "${matches[@]}"
}

# preflight_size_paths_kb PATH... — summed size in KB of an already-
# resolved path set: each path contributes its whole subtree, exactly as
# a per-path du in kilobytes reported it. One chunked sizing traversal
# per MDOCTOR_FIND_ARGV_CHUNK paths (find -printf '%k' on GNU, a probed
# stat -exec elsewhere) — never a du per path. Prints the total on rc 0;
# the MDOCTOR_SIZE_ERR_* codes propagate per chunk.
preflight_size_paths_kb() {
  local -a paths=("$@")
  local n="${#paths[@]}"
  if [ "$n" -eq 0 ]; then
    printf '0\n'
    return 0
  fi

  # Chunked so a very large path set can never overflow exec argv.
  local total=0
  local i=0
  local chunk_kb=""
  local chunk_rc=0
  while [ "$i" -lt "$n" ]; do
    chunk_rc=0
    chunk_kb=$(_preflight_find_size_kb "${paths[@]:$i:$MDOCTOR_FIND_ARGV_CHUNK}") || chunk_rc=$?
    case "$chunk_rc" in
      0) ;;
      124) return "$MDOCTOR_SIZE_ERR_TIMEOUT" ;;
      1) return "$MDOCTOR_SIZE_ERR_DENIED" ;;
      *) return "$MDOCTOR_SIZE_ERR_FAILED" ;;
    esac
    total=$((total + ${chunk_kb:-0}))
    i=$((i + MDOCTOR_FIND_ARGV_CHUNK))
  done

  printf '%s\n' "$total"
  return 0
}
