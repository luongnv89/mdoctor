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

  du -sk "$dir"/*/ 2>/dev/null | sort -rn | head -n "$limit"
}

# _dir_size_kb dir
# Returns size in KB for a single directory (with timeout).
_dir_size_kb() {
  local dir="$1"
  [ -d "$dir" ] || { echo 0; return; }

  local size
  size=$(timeout 30 du -sk "$dir" 2>/dev/null | awk '{print $1}')
  echo "${size:-0}"
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
      sz=$(timeout 30 du -sk "$match" 2>/dev/null | awk '{print $1}')
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

check_storage() {
  step "Storage Hogs Analysis"

  local grand_total_kb=0
  local found_any=false

  # ── Category 1: Application Data ──
  status_info "Scanning application data..."

  local categories=("Application Support" "Caches" "Containers" "Group Containers")
  for cat in "${categories[@]}"; do
    local cat_dir="${HOME}/Library/${cat}"
    [ -d "$cat_dir" ] || continue

    local cat_size_kb
    cat_size_kb=$(_dir_size_kb "$cat_dir")

    if (( cat_size_kb > 102400 )); then  # > 100 MB
      local cat_hr
      cat_hr=$(kb_to_human "$cat_size_kb")
      grand_total_kb=$((grand_total_kb + cat_size_kb))
      found_any=true

      if (( cat_size_kb >= 1048576 )); then  # > 1 GB
        # shellcheck disable=SC2088
        status_warn "~/Library/${cat}: ${cat_hr}"
      else
        # shellcheck disable=SC2088
        status_info "~/Library/${cat}: ${cat_hr}"
      fi

      # Show top 3 subdirs
      while IFS=$'\t' read -r sz path; do
        [ -z "$sz" ] && continue
        local sub_hr
        sub_hr=$(kb_to_human "$sz")
        local sub_name
        sub_name=$(basename "$path")
        if (( sz >= 1048576 )); then
          status_warn "  └─ ${sub_name}: ${sub_hr}"
        elif (( sz >= 102400 )); then
          status_info "  └─ ${sub_name}: ${sub_hr}"
        fi
      done < <(_scan_dir_for_hogs "$cat_dir" 3)
    fi
  done

  # ── Category 2: Applications ──
  if [ -d "/Applications" ]; then
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
        found_any=true
      elif (( sz >= 524288 )); then  # > 512 MB
        status_info "  ${app_name}: ${app_hr}"
        found_any=true
      fi
    done < <(du -sk /Applications/*.app 2>/dev/null | sort -rn | head -n 5)
    grand_total_kb=$((grand_total_kb + app_total))
  fi

  # ── Category 3: Dev Tools ──
  status_info "Scanning developer tools..."

  local dev_dirs=("${HOME}/Library/Developer" "${HOME}/.docker")
  for dev_dir in "${dev_dirs[@]}"; do
    if [ -d "$dev_dir" ]; then
      local dev_sz
      dev_sz=$(_dir_size_kb "$dev_dir")
      if (( dev_sz > 102400 )); then
        local dev_hr
        dev_hr=$(kb_to_human "$dev_sz")
        grand_total_kb=$((grand_total_kb + dev_sz))
        found_any=true
        local dev_label
        dev_label="${dev_dir/#$HOME/~}"
        if (( dev_sz >= 1048576 )); then
          status_warn "${dev_label}: ${dev_hr}"
        else
          status_info "${dev_label}: ${dev_hr}"
        fi
      fi
    fi
  done

  # ── Category 4: Cloud Storage ──
  local cloud_dir="${HOME}/Library/CloudStorage"
  if [ -d "$cloud_dir" ]; then
    local cloud_sz
    cloud_sz=$(_dir_size_kb "$cloud_dir")
    if (( cloud_sz > 102400 )); then
      local cloud_hr
      cloud_hr=$(kb_to_human "$cloud_sz")
      grand_total_kb=$((grand_total_kb + cloud_sz))
      found_any=true
      # shellcheck disable=SC2088
      status_info "~/Library/CloudStorage: ${cloud_hr}"
    fi
  fi

  # ── Category 5: Dev Dependencies (node_modules) ──
  status_info "Scanning for node_modules (this may take a moment)..."

  local search_dirs=()
  for d in "${HOME}/Projects" "${HOME}/projects" "${HOME}/code" "${HOME}/workspace" "${HOME}/dev" "${HOME}/src"; do
    [ -d "$d" ] && search_dirs+=("$d")
  done

  if (( ${#search_dirs[@]} > 0 )); then
    local nm_result
    nm_result=$(_find_and_sum "node_modules" "${search_dirs[@]}")
    local nm_total_kb nm_count
    nm_total_kb=$(echo "$nm_result" | awk '{print $1}')
    nm_count=$(echo "$nm_result" | awk '{print $2}')

    if (( nm_total_kb > 0 )); then
      local nm_hr
      nm_hr=$(kb_to_human "$nm_total_kb")
      grand_total_kb=$((grand_total_kb + nm_total_kb))
      found_any=true
      if (( nm_total_kb >= 1048576 )); then
        status_warn "node_modules (${nm_count} found): ${nm_hr}"
      else
        status_info "node_modules (${nm_count} found): ${nm_hr}"
      fi
    fi
  fi

  # ── Category 6: Other Dev Caches ──
  status_info "Scanning development caches..."

  local -a cache_labels cache_paths
  cache_labels=("Python venvs" "Conda envs (miniconda3)" "Conda envs (anaconda3)" "Cargo registry" "Go packages" "Maven repository" "Gradle caches")
  cache_paths=("" "" "" "${HOME}/.cargo/registry" "${HOME}/go/pkg" "${HOME}/.m2/repository" "${HOME}/.gradle/caches")

  # Python venvs — search in project dirs
  if (( ${#search_dirs[@]} > 0 )); then
    for venv_name in "venv" ".venv"; do
      local venv_result
      venv_result=$(_find_and_sum "$venv_name" "${search_dirs[@]}")
      local venv_kb venv_cnt
      venv_kb=$(echo "$venv_result" | awk '{print $1}')
      venv_cnt=$(echo "$venv_result" | awk '{print $2}')
      if (( venv_kb > 102400 )); then
        local venv_hr
        venv_hr=$(kb_to_human "$venv_kb")
        grand_total_kb=$((grand_total_kb + venv_kb))
        found_any=true
        if (( venv_kb >= 1048576 )); then
          status_warn "Python ${venv_name}/ (${venv_cnt} found): ${venv_hr}"
        else
          status_info "Python ${venv_name}/ (${venv_cnt} found): ${venv_hr}"
        fi
      fi
    done
  fi

  # Conda envs
  for conda_base in "${HOME}/miniconda3/envs" "${HOME}/anaconda3/envs"; do
    if [ -d "$conda_base" ]; then
      local conda_sz
      conda_sz=$(_dir_size_kb "$conda_base")
      if (( conda_sz > 102400 )); then
        local conda_hr
        conda_hr=$(kb_to_human "$conda_sz")
        local conda_label="${conda_base/#$HOME/~}"
        grand_total_kb=$((grand_total_kb + conda_sz))
        found_any=true
        if (( conda_sz >= 1048576 )); then
          status_warn "${conda_label}: ${conda_hr}"
        else
          status_info "${conda_label}: ${conda_hr}"
        fi
      fi
    fi
  done

  # Static dev caches (Cargo, Go, Maven, Gradle)
  local i=3  # start at index 3 in cache_paths (skipping venv/conda handled above)
  while (( i < ${#cache_labels[@]} )); do
    local cpath="${cache_paths[$i]}"
    local clabel="${cache_labels[$i]}"
    if [ -d "$cpath" ]; then
      local csz
      csz=$(_dir_size_kb "$cpath")
      if (( csz > 102400 )); then
        local chr
        chr=$(kb_to_human "$csz")
        local cpath_label="${cpath/#$HOME/~}"
        grand_total_kb=$((grand_total_kb + csz))
        found_any=true
        if (( csz >= 1048576 )); then
          status_warn "${clabel} (${cpath_label}): ${chr}"
        else
          status_info "${clabel} (${cpath_label}): ${chr}"
        fi
      fi
    fi
    i=$((i + 1))
  done

  # ── Summary ──
  echo
  if [ "$found_any" = true ]; then
    local grand_hr
    grand_hr=$(kb_to_human "$grand_total_kb")
    if (( grand_total_kb >= 10485760 )); then  # > 10 GB
      status_warn "Total scanned storage: ${grand_hr}"
      add_action "Large storage usage detected (${grand_hr}). Run 'mdoctor clean -m dev_caches' to clean developer caches, or 'mdoctor clean' for full cleanup."
    elif (( grand_total_kb >= 5242880 )); then  # > 5 GB
      status_info "Total scanned storage: ${grand_hr}"
      add_action "Consider running 'mdoctor clean -m dev_caches' to reclaim space from developer caches."
    else
      status_ok "Total scanned storage: ${grand_hr} (manageable)"
    fi
  else
    status_ok "No major storage hogs found."
  fi
}
