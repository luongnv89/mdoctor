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

# _find_and_sum pattern dirs...
# Finds all matching dirs and sums their sizes (KB). Timeout 30s per search
# dir. Prints "<total> <count>" only on success (rc 0); a timed-out find
# returns MDOCTOR_SIZE_ERR_TIMEOUT and prints nothing; matches whose own
# size probe fails are skipped, never counted as 0 (Task 9.4).
_find_and_sum() {
  local pattern="$1"
  shift

  local total=0
  local count=0
  local dir
  local match=""
  local find_rc=0
  local seen_rc=""
  local sz=""
  local sz_rc=0

  for dir in "$@"; do
    [ -d "$dir" ] || continue
    while IFS= read -r -d '' match; do
      case "$match" in
        _MDOCTOR_FIND_RC_*)
          seen_rc="${match#_MDOCTOR_FIND_RC_}"
          if [ "$find_rc" -eq 0 ]; then
            find_rc="$seen_rc"
          fi
          ;;
        *)
          sz_rc=0
          sz=$(du_size_kb "$match") || sz_rc=$?
          if [ "$sz_rc" -eq 0 ]; then
            total=$((total + sz))
            count=$((count + 1))
          fi
          ;;
      esac
    done < <( _find_entries_with_rc "$MDOCTOR_FIND_TIMEOUT_S" "$dir" -maxdepth 5 -type d -name "$pattern" )
  done

  case "$find_rc" in
    0) ;;
    124) return "$MDOCTOR_SIZE_ERR_TIMEOUT" ;;
    1) return "$MDOCTOR_SIZE_ERR_DENIED" ;;
    *) return "$MDOCTOR_SIZE_ERR_FAILED" ;;
  esac

  echo "${total} ${count}"
  return 0
}

# _find_entries_with_rc TIMEOUT ARGS... — producer for _find_and_sum:
# NUL-separated entries plus a final NUL-terminated
# _MDOCTOR_FIND_RC_<n> sentinel carrying the find exit code (a process
# substitution's rc is lost). Wraps the find in a timeout where available
# (GNU-only).
_find_entries_with_rc() {
  local t="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$t" find "$@" -print0 2>/dev/null
    printf '%s\0' "_MDOCTOR_FIND_RC_$?"
  else
    find "$@" -print0 2>/dev/null
    printf '%s\0' "_MDOCTOR_FIND_RC_$?"
  fi
}

########################################
# MAIN CHECK
########################################

# Accumulators owned by check_storage and shared with the scan helpers.
STORAGE_TOTAL_KB=0
STORAGE_FOUND_ANY=false

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
_storage_scan_nodedeps() {
  status_info "Scanning for node_modules (this may take a moment)..."
  (( $# > 0 )) || return 0

  local nm_result nm_total_kb nm_count
  local nm_rc=0
  nm_result=$(_find_and_sum "node_modules" "$@") || nm_rc=$?
  if [ "$nm_rc" -ne 0 ]; then
    status_warn "node_modules: could not determine"
    return 0
  fi
  nm_total_kb=$(echo "$nm_result" | awk '{print $1}')
  nm_count=$(echo "$nm_result" | awk '{print $2}')
  (( nm_total_kb > 0 )) || return 0
  _storage_report "node_modules (${nm_count} found)" "$nm_total_kb" 0 || true
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
    local venv_name
    for venv_name in "venv" ".venv"; do
      local venv_result venv_kb venv_cnt
      local venv_rc=0
      venv_result=$(_find_and_sum "$venv_name" "$@") || venv_rc=$?
      if [ "$venv_rc" -ne 0 ]; then
        status_warn "Python ${venv_name}: could not determine"
        continue
      fi
      venv_kb=$(echo "$venv_result" | awk '{print $1}')
      venv_cnt=$(echo "$venv_result" | awk '{print $2}')
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
_storage_search_dirs() {
  local d
  for d in "${HOME}/Projects" "${HOME}/projects" "${HOME}/code" "${HOME}/workspace" "${HOME}/dev" "${HOME}/src"; do
    [ -d "$d" ] && printf '%s\n' "$d"
  done
}

check_storage() {
  step "Storage Hogs Analysis"

  STORAGE_TOTAL_KB=0
  STORAGE_FOUND_ANY=false

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
