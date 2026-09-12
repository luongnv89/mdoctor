#!/usr/bin/env bash
#
# checks/storage.sh
# Storage hogs analysis (read-only, SAFE)
# Category: System
#
# Scans and reports the largest directories consuming disk space
# across application data, dev tools, and development dependencies.
#

########################################
# INTERNAL HELPERS
########################################

# _scan_dir_for_hogs dir depth limit
# Returns top N largest subdirs (size in KB + path), sorted descending.

# Module context contract (Task 9.1): the 11 globals this module reads are
# declared by mdoctor_context_init in lib/context.sh. Fail loudly when a
# caller sources this file without the initializer instead of running on
# uncontrolled defaults.
# Required checks inputs: STEP_CURRENT, STEP_TOTAL, MDOCTOR_DEBUG, ACTIONS, WARN_COUNT, FAIL_COUNT, LOG_PATHS, LOG_DESCS, LOGFILE.
if ! is_truthy "${_MDOCTOR_CONTEXT_READY:-}"; then
  echo "${BASH_SOURCE[0]##*/}: module context not initialized (_MDOCTOR_CONTEXT_READY) — call mdoctor_context_init from lib/context.sh first" >&2
  return 1 2>/dev/null || exit 1
fi

# Shared scan machinery (Task 11.3): the combined dependency-dir scan
# reuses lib/preflight.sh's NUL+sentinel find producer and chunked
# single-pass sizer; pull it in when a standalone `source` (unit tests)
# skipped it.
if ! declare -f _preflight_find_entries >/dev/null 2>&1; then
  _MDOCTOR_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null || pwd)"
  # shellcheck source=/dev/null
  source "${_MDOCTOR_MODULE_DIR}/../lib/disk.sh"
  # shellcheck source=/dev/null
  source "${_MDOCTOR_MODULE_DIR}/../lib/preflight.sh"
  unset _MDOCTOR_MODULE_DIR
fi

_scan_dir_for_hogs() {
  local dir="$1"
  local limit="${2:-5}"

  [ -d "$dir" ] || return 0

  local sub
  local sz=""
  local sz_rc=0
  for sub in "$dir"/*/; do
    [ -e "$sub" ] || continue
    # Task 9.4: an unmeasurable subdir (rc != 0) is skipped, never ranked
    # as a 0-KB entry.
    sz_rc=0
    sz=$(du_size_kb "$sub") || sz_rc=$?
    [ "$sz_rc" -eq 0 ] || continue
    printf '%s\t%s\n' "$sz" "$sub"
  done | sort -rn | head -n "$limit"
}

# _dir_size_kb dir
# Size in KB for a single directory via the shared hardened probe. Prints
# the size only on success (rc 0); on failure prints nothing and propagates
# the distinct MDOCTOR_SIZE_ERR_* code (Task 9.4).
_dir_size_kb() {
  local kb=""
  local rc=0
  kb=$(du_size_kb "$1") || rc=$?
  [ "$rc" -ne 0 ] && return "$rc"
  printf '%s\n' "$kb"
  return 0
}

########################################
# MAIN CHECK
########################################

# Accumulators owned by check_storage and shared with the scan helpers.
STORAGE_TOTAL_KB=0
STORAGE_FOUND_ANY=false

# Combined dependency-dir scan state (Task 11.3 / issue #97): one find
# pass over the project roots resolves every node_modules/venv/.venv
# match, then each name bucket is sized once by lib/preflight.sh's
# chunked sizer — the three per-pattern traversals and the per-match
# `du` re-walks are gone. The first consumer (nodedeps or devcaches)
# triggers the scan; STORAGE_DEP_SCANNED makes every later call a no-op.
STORAGE_DEP_SCANNED=false
STORAGE_DEP_NM_KB=0
STORAGE_DEP_NM_COUNT=0
STORAGE_DEP_NM_RC=0
STORAGE_DEP_VENV_KB=0
STORAGE_DEP_VENV_COUNT=0
STORAGE_DEP_VENV_RC=0
STORAGE_DEP_DOTVENV_KB=0
STORAGE_DEP_DOTVENV_COUNT=0
STORAGE_DEP_DOTVENV_RC=0

# _storage_scan_depdirs SEARCH_DIRS... — Task 11.3 (issue #97,
# F-PERF-006/007): ONE find pass over the search roots resolves every
# dependency dir — `-type d \( -name node_modules -o -name venv -o -name
# .venv \) -prune` — so the traversal stops at each match instead of
# descending into it, and the three per-pattern passes over identical
# roots collapse into one. Sizes come from the shared chunked sizer
# (find -printf '%k' where supported, a probed stat -exec elsewhere):
# one sizing traversal per name bucket, never a `du` per match. Results
# land in the STORAGE_DEP_* globals; a failure sets the bucket's _RC
# with the distinct MDOCTOR_SIZE_ERR_* code (Task 9.4) so the report can
# warn per label. Returns the first non-zero bucket code.
_storage_scan_depdirs() {
  (( $# > 0 )) || return 0
  is_truthy "$STORAGE_DEP_SCANNED" && return 0
  STORAGE_DEP_SCANNED=true
  STORAGE_DEP_NM_KB=0
  STORAGE_DEP_NM_COUNT=0
  STORAGE_DEP_NM_RC=0
  STORAGE_DEP_VENV_KB=0
  STORAGE_DEP_VENV_COUNT=0
  STORAGE_DEP_VENV_RC=0
  STORAGE_DEP_DOTVENV_KB=0
  STORAGE_DEP_DOTVENV_COUNT=0
  STORAGE_DEP_DOTVENV_RC=0

  # Keep only roots that still exist (a vanished dir must not fail the
  # whole pass), then ONE find over all of them.
  local -a roots=()
  local d=""
  for d in "$@"; do
    [ -d "$d" ] && roots+=("$d")
  done
  (( ${#roots[@]} > 0 )) || return 0

  local -a nm_matches=() venv_matches=() dotvenv_matches=()
  local match="" base="" find_rc=0
  while IFS= read -r -d '' match; do
    case "$match" in
      _MDOCTOR_FIND_RC_*)
        find_rc="${match#_MDOCTOR_FIND_RC_}"
        ;;
      *)
        base="${match##*/}"
        case "$base" in
          node_modules) nm_matches+=("$match") ;;
          venv) venv_matches+=("$match") ;;
          .venv) dotvenv_matches+=("$match") ;;
        esac
        ;;
    esac
  done < <(_preflight_find_entries "${roots[@]}" -maxdepth 5 -type d \( -name node_modules -o -name venv -o -name .venv \) -prune)

  # A failed match pass marks every bucket failed — same outward result
  # as the three old per-pattern passes each failing (Task 9.4).
  if [ "$find_rc" -ne 0 ]; then
    local err="$MDOCTOR_SIZE_ERR_FAILED"
    case "$find_rc" in
      124) err="$MDOCTOR_SIZE_ERR_TIMEOUT" ;;
      1) err="$MDOCTOR_SIZE_ERR_DENIED" ;;
    esac
    STORAGE_DEP_NM_RC="$err"
    STORAGE_DEP_VENV_RC="$err"
    STORAGE_DEP_DOTVENV_RC="$err"
    return "$err"
  fi

  # One sizing traversal per non-empty name bucket — name and size are
  # resolved by the same scan, with no per-match du.
  local kb="" sz_rc=0
  if (( ${#nm_matches[@]} > 0 )); then
    sz_rc=0
    kb=$(preflight_size_paths_kb "${nm_matches[@]}") || sz_rc=$?
    if [ "$sz_rc" -eq 0 ]; then
      STORAGE_DEP_NM_KB="$kb"
      STORAGE_DEP_NM_COUNT="${#nm_matches[@]}"
    else
      STORAGE_DEP_NM_RC="$sz_rc"
    fi
  fi
  if (( ${#venv_matches[@]} > 0 )); then
    sz_rc=0
    kb=$(preflight_size_paths_kb "${venv_matches[@]}") || sz_rc=$?
    if [ "$sz_rc" -eq 0 ]; then
      STORAGE_DEP_VENV_KB="$kb"
      STORAGE_DEP_VENV_COUNT="${#venv_matches[@]}"
    else
      STORAGE_DEP_VENV_RC="$sz_rc"
    fi
  fi
  if (( ${#dotvenv_matches[@]} > 0 )); then
    sz_rc=0
    kb=$(preflight_size_paths_kb "${dotvenv_matches[@]}") || sz_rc=$?
    if [ "$sz_rc" -eq 0 ]; then
      STORAGE_DEP_DOTVENV_KB="$kb"
      STORAGE_DEP_DOTVENV_COUNT="${#dotvenv_matches[@]}"
    else
      STORAGE_DEP_DOTVENV_RC="$sz_rc"
    fi
  fi

  # Propagate the first bucket failure so direct callers see the same
  # distinct code the old _find_and_sum returned.
  [ "$STORAGE_DEP_NM_RC" -ne 0 ] && return "$STORAGE_DEP_NM_RC"
  [ "$STORAGE_DEP_VENV_RC" -ne 0 ] && return "$STORAGE_DEP_VENV_RC"
  return "$STORAGE_DEP_DOTVENV_RC"
}

# _storage_report LABEL KB [MIN_KB] [WARN_KB]
# The single measure-compare-classify-report helper (Task 8.6): below MIN_KB
# the entry is skipped silently, at or above WARN_KB it warns, otherwise it
# informs. Reported entries accumulate into the run totals.
_storage_report() {
  local label="$1"
  local kb="${2:-0}"
  local min_kb="${3:-$MDOCTOR_REPORT_MIN_KB}"
  local warn_kb="${4:-$MDOCTOR_REPORT_WARN_KB}"

  (( kb > min_kb )) || return 1

  local hr
  hr=$(kb_to_human "$kb")
  STORAGE_TOTAL_KB=$((STORAGE_TOTAL_KB + kb))
  STORAGE_FOUND_ANY=true
  if (( kb >= warn_kb )); then
    status_warn "${label}: ${hr}"
  else
    status_info "${label}: ${hr}"
  fi
}

# _storage_measure LABEL DIR — Task 9.4 measure-or-report wrapper: on
# success prints the KB value; on failure warns "<label>: could not
# determine" and returns the probe's distinct non-zero code.
_storage_measure() {
  local label="$1"
  local dir="$2"
  local kb=""
  local rc=0
  kb=$(_dir_size_kb "$dir") || rc=$?
  if [ "$rc" -ne 0 ]; then
    status_warn "${label}: could not determine"
    return "$rc"
  fi
  printf '%s\n' "$kb"
  return 0
}

# _storage_scan_appdata — Category 1: application data + top subdirs.
_storage_scan_appdata() {
  status_info "Scanning application data..."

  if is_macos; then
    local cat
    for cat in "Application Support" "Caches" "Containers" "Group Containers"; do
      local cat_dir="${HOME}/Library/${cat}"
      [ -d "$cat_dir" ] || continue
      local cat_size_kb
      local cat_rc=0
      # shellcheck disable=SC2088  # display label keeps the literal tilde
      cat_size_kb=$(_storage_measure "~/Library/${cat}" "$cat_dir") || cat_rc=$?
      [ "$cat_rc" -eq 0 ] || continue
      # shellcheck disable=SC2088
      if _storage_report "~/Library/${cat}" "$cat_size_kb"; then
        while IFS=$'\t' read -r sz path; do
          [ -z "$sz" ] && continue
          local sub_name
          sub_name=$(basename "$path")
          local sub_hr
          sub_hr=$(kb_to_human "$sz")
          if (( sz >= MDOCTOR_REPORT_WARN_KB )); then
            status_warn "  └─ ${sub_name}: ${sub_hr}"
          elif (( sz >= MDOCTOR_REPORT_MIN_KB )); then
            status_info "  └─ ${sub_name}: ${sub_hr}"
          fi
        done < <(_scan_dir_for_hogs "$cat_dir" 3)
      fi
    done
  else
    # Linux: XDG directories
    local xdg_dir
    for xdg_dir in "${HOME}/.cache" "${HOME}/.local/share" "${HOME}/.config"; do
      [ -d "$xdg_dir" ] || continue
      local label="${xdg_dir/#$HOME/~}"
      local xdg_kb
      local xdg_rc=0
      xdg_kb=$(_storage_measure "$label" "$xdg_dir") || xdg_rc=$?
      if [ "$xdg_rc" -eq 0 ]; then
        _storage_report "$label" "$xdg_kb" || true
      fi
    done
  fi
}

# _storage_scan_applications — Category 2: /Applications (macOS only).
_storage_scan_applications() {
  is_macos && [ -d "/Applications" ] || return 0
  status_info "Scanning /Applications..."
  local app_total=0
  while IFS=$'\t' read -r sz path; do
    [ -z "$sz" ] && continue
    local app_hr
    app_hr=$(kb_to_human "$sz")
    local app_name
    app_name=$(basename "$path")
    app_total=$((app_total + sz))
    if (( sz >= MDOCTOR_REPORT_WARN_KB )); then
      status_warn "  ${app_name}: ${app_hr}"
      STORAGE_FOUND_ANY=true
    elif (( sz >= 524288 )); then
      status_info "  ${app_name}: ${app_hr}"
      STORAGE_FOUND_ANY=true
    fi
  done < <(
    for _app in /Applications/*.app/; do
      [ -e "$_app" ] || continue
      # Task 9.4: unmeasurable entries are skipped, never ranked as 0 KB.
      _app_sz=$(du_size_kb "$_app") || continue
      printf '%s\t%s\n' "$_app_sz" "$_app"
    done | sort -rn | head -n 5)
  STORAGE_TOTAL_KB=$((STORAGE_TOTAL_KB + app_total))
}

# _storage_scan_devtools — Category 3: developer tool directories.
_storage_scan_devtools() {
  status_info "Scanning developer tools..."

  local dev_dirs=("${HOME}/.docker")
  if is_macos; then
    dev_dirs=("${HOME}/Library/Developer" "${HOME}/.docker")
  fi
  local dev_dir
  for dev_dir in "${dev_dirs[@]}"; do
    [ -d "$dev_dir" ] || continue
    local label="${dev_dir/#$HOME/~}"
    local dev_kb
    local dev_rc=0
    dev_kb=$(_storage_measure "$label" "$dev_dir") || dev_rc=$?
    if [ "$dev_rc" -eq 0 ]; then
      _storage_report "$label" "$dev_kb" || true
    fi
  done
}

# _storage_scan_cloud — Category 4: cloud storage (macOS only).
_storage_scan_cloud() {
  is_macos || return 0
  local cloud_dir="${HOME}/Library/CloudStorage"
  [ -d "$cloud_dir" ] || return 0
  # shellcheck disable=SC2088
  local cloud_kb
  local cloud_rc=0
  # shellcheck disable=SC2088  # display label keeps the literal tilde
  cloud_kb=$(_storage_measure "~/Library/CloudStorage" "$cloud_dir") || cloud_rc=$?
  if [ "$cloud_rc" -eq 0 ]; then
    # shellcheck disable=SC2088  # display label keeps the literal tilde
    _storage_report "~/Library/CloudStorage" "$cloud_kb" || true
  fi
}

# _storage_scan_nodedeps SEARCH_DIRS... — Category 5: node_modules sweep.
# Consumes the combined dependency-dir scan (Task 11.3): the first caller
# triggers the single OR-ed, pruned find pass and per-bucket sizing.
_storage_scan_nodedeps() {
  status_info "Scanning for node_modules (this may take a moment)..."
  (( $# > 0 )) || return 0

  _storage_scan_depdirs "$@" || true
  if [ "$STORAGE_DEP_NM_RC" -ne 0 ]; then
    status_warn "node_modules: could not determine"
    return 0
  fi
  (( STORAGE_DEP_NM_KB > 0 )) || return 0
  _storage_report "node_modules (${STORAGE_DEP_NM_COUNT} found)" "$STORAGE_DEP_NM_KB" 0 || true
}

# _storage_default_static_caches — single delimited label|path list for the
# static dev caches (Task 8.6): one list, no placeholders, no magic index.
_storage_default_static_caches() {
  printf '%s\n' \
    "Cargo registry|${HOME}/.cargo/registry" \
    "Go packages|${HOME}/go/pkg" \
    "Maven repository|${HOME}/.m2/repository" \
    "Gradle caches|${HOME}/.gradle/caches"
}

# _storage_scan_static_caches [ENTRIES] — size each label|path entry.
# ENTRIES defaults to _storage_default_static_caches; callers (and tests)
# may pass their own list, where position carries no meaning.
_storage_scan_static_caches() {
  local entries="${1:-$( _storage_default_static_caches )}"
  local entry
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    local clabel="${entry%%|*}"
    local cpath="${entry#*|}"
    [ -d "$cpath" ] || continue
    local cpath_label="${cpath/#$HOME/~}"
    local cpath_kb
    local cpath_rc=0
    cpath_kb=$(_storage_measure "${clabel} (${cpath_label})" "$cpath") || cpath_rc=$?
    if [ "$cpath_rc" -eq 0 ]; then
      _storage_report "${clabel} (${cpath_label})" "$cpath_kb" || true
    fi
  done <<< "$entries"
}

# _storage_scan_devcaches SEARCH_DIRS... — Category 6: venvs, conda envs and
# the static dev-cache list.
_storage_scan_devcaches() {
  status_info "Scanning development caches..."

  if (( $# > 0 )); then
    _storage_scan_depdirs "$@" || true
    local venv_name
    for venv_name in "venv" ".venv"; do
      local venv_kb venv_cnt venv_brc
      case "$venv_name" in
        venv)
          venv_kb="$STORAGE_DEP_VENV_KB"
          venv_cnt="$STORAGE_DEP_VENV_COUNT"
          venv_brc="$STORAGE_DEP_VENV_RC"
          ;;
        .venv)
          venv_kb="$STORAGE_DEP_DOTVENV_KB"
          venv_cnt="$STORAGE_DEP_DOTVENV_COUNT"
          venv_brc="$STORAGE_DEP_DOTVENV_RC"
          ;;
      esac
      if [ "$venv_brc" -ne 0 ]; then
        status_warn "Python ${venv_name}: could not determine"
        continue
      fi
      _storage_report "Python ${venv_name}/ (${venv_cnt} found)" "$venv_kb" || true
    done
  fi

  local conda_base
  for conda_base in "${HOME}/miniconda3/envs" "${HOME}/anaconda3/envs"; do
    [ -d "$conda_base" ] || continue
    local conda_label="${conda_base/#$HOME/~}"
    local conda_kb
    local conda_rc=0
    conda_kb=$(_storage_measure "$conda_label" "$conda_base") || conda_rc=$?
    if [ "$conda_rc" -eq 0 ]; then
      _storage_report "$conda_label" "$conda_kb" || true
    fi
  done

  _storage_scan_static_caches
}

# _storage_search_dirs — project roots that exist (node_modules/venv sweep).
# Each physical directory is emitted once: on a case-insensitive
# filesystem (default APFS) "${HOME}/projects" resolves to the same
# directory as "${HOME}/Projects", and a doubled root would be traversed
# once per spelling — double-counting and double-sizing every match.
# device:inode keys are spelling- and symlink-proof.
_storage_search_dirs() {
  local d key s
  local -a seen=()
  for d in "${HOME}/Projects" "${HOME}/projects" "${HOME}/code" "${HOME}/workspace" "${HOME}/dev" "${HOME}/src"; do
    [ -d "$d" ] || continue
    key="$(stat -Lc '%d:%i' "$d" 2>/dev/null || stat -Lf '%d:%i' "$d" 2>/dev/null)"
    if [ -n "$key" ]; then
      for s in ${seen[@]+"${seen[@]}"}; do
        [ "$s" = "$key" ] && continue 2
      done
      seen+=("$key")
    fi
    printf '%s\n' "$d"
  done
}

check_storage() {
  step "Storage Hogs Analysis"

  STORAGE_TOTAL_KB=0
  STORAGE_FOUND_ANY=false
  STORAGE_DEP_SCANNED=false

  _storage_scan_appdata
  _storage_scan_applications
  _storage_scan_devtools
  _storage_scan_cloud

  local -a search_dirs=()
  local d
  while IFS= read -r d; do
    [ -n "$d" ] && search_dirs+=("$d")
  done < <(_storage_search_dirs)

  _storage_scan_nodedeps "${search_dirs[@]+"${search_dirs[@]}"}"
  _storage_scan_devcaches "${search_dirs[@]+"${search_dirs[@]}"}"

  # ── Summary ──
  echo
  if is_truthy "$STORAGE_FOUND_ANY"; then
    local grand_hr
    grand_hr=$(kb_to_human "$STORAGE_TOTAL_KB")
    if (( STORAGE_TOTAL_KB >= MDOCTOR_KB_10GB )); then  # > 10 GB
      status_warn "Total scanned storage: ${grand_hr}"
      add_action "Large storage usage detected (${grand_hr}). Run 'mdoctor clean -m dev_caches' to clean developer caches, or 'mdoctor clean' for full cleanup."
    elif (( STORAGE_TOTAL_KB >= 5242880 )); then  # > 5 GB
      status_info "Total scanned storage: ${grand_hr}"
      add_action "Consider running 'mdoctor clean -m dev_caches' to reclaim space from developer caches."
    else
      status_ok "Total scanned storage: ${grand_hr} (manageable)"
    fi
  else
    status_ok "No major storage hogs found."
  fi
}
