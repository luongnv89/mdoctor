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
_scan_dir_for_hogs() {
  local dir="$1"
  local limit="${2:-5}"

  [ -d "$dir" ] || return 0

  local sub
  for sub in "$dir"/*/; do
    [ -e "$sub" ] || continue
    printf '%s\t%s\n' "$(du_size_kb "$sub")" "$sub"
  done | sort -rn | head -n "$limit"
}

# _dir_size_kb dir
# Returns size in KB for a single directory via the shared hardened probe.
_dir_size_kb() {
  du_size_kb "$1"
}

# _find_and_sum pattern dirs...
# Finds all matching dirs and sums their sizes (KB). Timeout 30s per search dir.
_find_and_sum() {
  local pattern="$1"
  shift

  local total=0
  local count=0
  local dir

  for dir in "$@"; do
    [ -d "$dir" ] || continue
    while IFS= read -r match; do
      local sz
      sz=$(du_size_kb "$match")
      sz="${sz:-0}"
      total=$((total + sz))
      count=$((count + 1))
    done < <(timeout 30 find "$dir" -maxdepth 5 -type d -name "$pattern" 2>/dev/null)
  done

  echo "${total} ${count}"
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
  local min_kb="${3:-102400}"
  local warn_kb="${4:-1048576}"

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

# _storage_scan_appdata — Category 1: application data + top subdirs.
_storage_scan_appdata() {
  status_info "Scanning application data..."

  if is_macos; then
    local cat
    for cat in "Application Support" "Caches" "Containers" "Group Containers"; do
      local cat_dir="${HOME}/Library/${cat}"
      [ -d "$cat_dir" ] || continue
      local cat_size_kb
      cat_size_kb=$(_dir_size_kb "$cat_dir")
      # shellcheck disable=SC2088
      if _storage_report "~/Library/${cat}" "$cat_size_kb"; then
        while IFS=$'\t' read -r sz path; do
          [ -z "$sz" ] && continue
          local sub_name
          sub_name=$(basename "$path")
          local sub_hr
          sub_hr=$(kb_to_human "$sz")
          if (( sz >= 1048576 )); then
            status_warn "  └─ ${sub_name}: ${sub_hr}"
          elif (( sz >= 102400 )); then
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
      _storage_report "$label" "$(_dir_size_kb "$xdg_dir")" || true
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
    if (( sz >= 1048576 )); then
      status_warn "  ${app_name}: ${app_hr}"
      STORAGE_FOUND_ANY=true
    elif (( sz >= 524288 )); then
      status_info "  ${app_name}: ${app_hr}"
      STORAGE_FOUND_ANY=true
    fi
  done < <(
    for _app in /Applications/*.app/; do
      [ -e "$_app" ] || continue
      printf '%s\t%s\n' "$(du_size_kb "$_app")" "$_app"
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
    _storage_report "$label" "$(_dir_size_kb "$dev_dir")" || true
  done
}

# _storage_scan_cloud — Category 4: cloud storage (macOS only).
_storage_scan_cloud() {
  is_macos || return 0
  local cloud_dir="${HOME}/Library/CloudStorage"
  [ -d "$cloud_dir" ] || return 0
  # shellcheck disable=SC2088
  _storage_report "~/Library/CloudStorage" "$(_dir_size_kb "$cloud_dir")" || true
}

# _storage_scan_nodedeps SEARCH_DIRS... — Category 5: node_modules sweep.
_storage_scan_nodedeps() {
  status_info "Scanning for node_modules (this may take a moment)..."
  (( $# > 0 )) || return 0

  local nm_result nm_total_kb nm_count
  nm_result=$(_find_and_sum "node_modules" "$@")
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
    _storage_report "${clabel} (${cpath_label})" "$(_dir_size_kb "$cpath")" || true
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
      venv_result=$(_find_and_sum "$venv_name" "$@")
      venv_kb=$(echo "$venv_result" | awk '{print $1}')
      venv_cnt=$(echo "$venv_result" | awk '{print $2}')
      _storage_report "Python ${venv_name}/ (${venv_cnt} found)" "$venv_kb" || true
    done
  fi

  local conda_base
  for conda_base in "${HOME}/miniconda3/envs" "${HOME}/anaconda3/envs"; do
    [ -d "$conda_base" ] || continue
    local conda_label="${conda_base/#$HOME/~}"
    _storage_report "$conda_label" "$(_dir_size_kb "$conda_base")" || true
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
  if [ "$STORAGE_FOUND_ANY" = true ]; then
    local grand_hr
    grand_hr=$(kb_to_human "$STORAGE_TOTAL_KB")
    if (( STORAGE_TOTAL_KB >= 10485760 )); then  # > 10 GB
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
