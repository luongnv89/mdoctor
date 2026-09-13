#!/usr/bin/env bash
#
# lib/clean_common.sh
# Single-module + interactive cleanup helpers hoisted out of cmd_clean
# (Task 8.5). Every helper takes the cleanup module list as an explicit first
# parameter (space-separated, registry-derived) so each one is directly
# unit-testable; cmd_clean is argument parsing plus three dispatch branches.
#
# Sourcing contract (provided by the entry point, stubbed in unit tests):
#   lib/platform.sh, lib/metadata.sh, lib/registry.sh, lib/common.sh,
#   lib/logging.sh, lib/disk.sh, lib/safety.sh, lib/cleanup_scope.sh,
#   plus globals MDOCTOR_DIR and an error() function.
#


# TRUTHY_BOOTSTRAP (Task 9.5): is_truthy lives in constants.sh, the
# zero-dependency base lib. Source it before the guard so standalone
# sourcing of this file still sees the predicate.
# Zero-fork (issue #102): the lib dir is the literal directory part of
# ${BASH_SOURCE[0]} — parameter expansion replaces the old
# $(cd "$(dirname …)" && pwd) probe, and the declare -f guard skips the
# source entirely once the base lib is loaded.
_mdoctor_lib_dir="${BASH_SOURCE[0]%/*}"
if [ "$_mdoctor_lib_dir" = "${BASH_SOURCE[0]}" ]; then
  _mdoctor_lib_dir="."
fi
if ! declare -f is_truthy >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "${_mdoctor_lib_dir}/constants.sh"
fi
# cleanup_mode_name (issue #106) lives in lib/common.sh next to
# is_dry_run. select_interactive_modules runs BEFORE the entry point's
# later source of common.sh (the menu renders ahead of
# run_single_cleanup_module), so the menu path needs common.sh loaded
# here — same declare -f bootstrap safety.sh/logging.sh use.
if ! declare -f cleanup_mode_name >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "${_mdoctor_lib_dir}/common.sh"
fi
unset _mdoctor_lib_dir

# Guard against double-sourcing.
if is_truthy "${_MDOCTOR_CLEAN_COMMON_LOADED:-}"; then
  return 0 2>/dev/null || true
fi
_MDOCTOR_CLEAN_COMMON_LOADED=true

# module_documented_days MODULE — the module's own ${DAYS_OLD:-N} fallback as
# declared in cleanups/<MODULE>.sh. The module file is the single source of
# truth for its threshold; this keeps the force-mode preflight size summary
# at the same effective age the module will apply (issue #94).
module_documented_days() {
  local file="${MDOCTOR_DIR}/cleanups/${1}.sh"
  [ -f "$file" ] || { echo 7; return 0; }
  local d
  d="$(sed -n 's/.*DAYS_OLD:-\([0-9][0-9]*\).*/\1/p' "$file" | head -1)"
  echo "${d:-7}"
}

# is_valid_cleanup_module MODULE_LIST NEEDLE — membership in the passed list.
# Rejects paths, traversal and option-lookalikes before any comparison.
is_valid_cleanup_module() {
  local module_list="$1"
  local needle="${2-}"
  case "$needle" in
    ""|*/*|*..*|-*) return 1 ;;
  esac
  case "$needle" in
    *[!a-z0-9_]* ) return 1 ;;
  esac
  local item
  for item in $module_list; do
    [ "$item" = "$needle" ] && return 0
  done
  return 1
}

# cleanup_module_description MODULE_LIST NAME — registry description for a
# listed module, empty string otherwise.
cleanup_module_description() {
  local module_list="$1"
  local name="${2-}"
  if ! is_valid_cleanup_module "$module_list" "$name"; then
    echo ""
    return 0
  fi
  get_module_desc "$name" cleanup 2>/dev/null || true
}

# run_single_cleanup_module MODULE_LIST MODULE FORCE — run one cleanup
# module by registry dispatch (unknown names rejected before sourcing).
run_single_cleanup_module() {
  local module_list="$1"
  local selected_module="$2"
  local selected_force="$3"

  if ! is_valid_cleanup_module "$module_list" "$selected_module"; then
    error "Unknown cleanup module: ${selected_module}"
    registry_available_text cleanup "Available modules"
    return 1
  fi

  local clean_file="${MDOCTOR_DIR}/cleanups/${selected_module}.sh"
  if [ ! -f "$clean_file" ]; then
    error "Unknown cleanup module: ${selected_module}"
    registry_available_text cleanup "Available modules"
    return 1
  fi

  # Source libraries (platform.sh already loaded at top level)
  source "${MDOCTOR_DIR}/lib/common.sh"
  source "${MDOCTOR_DIR}/lib/logging.sh"
  source "${MDOCTOR_DIR}/lib/disk.sh"
  source "${MDOCTOR_DIR}/lib/safety.sh"
  source "${MDOCTOR_DIR}/lib/cleanup_scope.sh"

  # Initialize progress globals for spinner
  export STEP_CURRENT=0
  export STEP_TOTAL=1
  init_colors
  debug_log "cmd_clean module=${selected_module} force=${selected_force} debug=${MDOCTOR_DEBUG}"

  # Mode banner (issue #106): every cleanup run opens by naming the mode,
  # so `clean -m x` and `clean -m x --force` can never read identically.
  local _run_mode
  _run_mode="$(cleanup_mode_name "$selected_force")"
  echo
  if is_truthy "$selected_force"; then
    echo "${BOLD}== Cleanup module: ${selected_module} — force mode ==${RESET}"
    echo "This run will DELETE files."
  else
    echo "${BOLD}== Cleanup module: ${selected_module} — dry-run mode ==${RESET}"
    echo "Preview only: nothing will be deleted (re-run with --force to apply)."
  fi

  # Set globals (used by sourced cleanup modules via run_cmd_args)
  export DRY_RUN=true
  LOGFILE="$(platform_log_dir)/mdoctor_cleanup.log"
  # Issue #94: export DAYS_OLD only when an override is present — otherwise
  # a force-exported 7 shadows the per-module defaults the cleanups/* files
  # document (30/90). Without an override the module's own fallback applies.
  local summary_days=7
  if [ -n "${DAYS_OLD_OVERRIDE:-}" ]; then
    export DAYS_OLD="${DAYS_OLD_OVERRIDE}"
    summary_days="$DAYS_OLD"
  else
    summary_days="$(module_documented_days "$selected_module")"
  fi

  if is_truthy "$selected_force"; then
    export DRY_RUN=false
    cmd_clean_preflight_summary_module "$selected_module" "$summary_days"
    # Confirmation gate (Task 0.5): y/N prompt, or refusal on a
    # non-tty unless MDOCTOR_ASSUME_YES=true.
    confirm_destructive_execution "cleanup module ${selected_module}" || return 1
  fi

  mkdir -p "$(dirname "$LOGFILE")"
  if declare -f ensure_cleanup_whitelist_file >/dev/null 2>&1; then
    ensure_cleanup_whitelist_file
  fi
  if declare -f ensure_cleanup_scope_file >/dev/null 2>&1; then
    ensure_cleanup_scope_file
  fi

  # Disk-delta baseline for the force-mode closing summary (issue #106):
  # measured only when the run can actually free space — the same
  # used-before/used-after approach as cleanup.sh main().
  local _used_before_kb=0
  if is_truthy "$selected_force"; then
    _used_before_kb="$(disk_used_kb 2>/dev/null)" || _used_before_kb=0
    case "$_used_before_kb" in ''|*[!0-9]*) _used_before_kb=0 ;; esac
  fi

  # shellcheck source=/dev/null
  source "$clean_file"

  op_session_start "clean:module:${selected_module}"

  # Start spinner for single cleanup module
  export STEP_CURRENT=1
  progress_start "Cleaning ${selected_module}..."

  local module_rc=0

  # Registry-driven dispatch (Task 8.1): the function name comes from the
  # single registry declaration, so adding a module to the registry is
  # enough to make it runnable here.
  local _dispatch_func
  _dispatch_func="$(get_module_func "$selected_module" cleanup 2>/dev/null || true)"
  if [ -n "$_dispatch_func" ] && declare -f "$_dispatch_func" >/dev/null 2>&1; then
    "$_dispatch_func" || module_rc=$?
  else
    error "Unknown cleanup module: ${selected_module}"
    return 1
  fi

  progress_stop

  # Closing summary (issue #106): every cleanup run terminates with a
  # deleted/would-free line naming the mode — the same guarantee the
  # full engine's "Cleanup finished"/"Estimated space" footer gives.
  echo
  if [ "$module_rc" -eq 0 ]; then
    echo "${BOLD}Cleanup finished: ${selected_module} (${_run_mode} mode)${RESET}"
    if is_truthy "$selected_force"; then
      local _used_after_kb=0 _freed_kb=0
      _used_after_kb="$(disk_used_kb 2>/dev/null)" || _used_after_kb=0
      case "$_used_after_kb" in ''|*[!0-9]*) _used_after_kb="$_used_before_kb" ;; esac
      _freed_kb=$(( _used_before_kb - _used_after_kb ))
      if [ "$_freed_kb" -lt 0 ]; then _freed_kb=0; fi
      echo "Estimated space freed: ~$(human_readable_kb "$_freed_kb")."
    elif [ "${OP_ACTION_COUNT:-0}" -gt 0 ]; then
      echo "Nothing was deleted — ${OP_ACTION_COUNT} change(s) would be applied. Re-run with --force."
    else
      echo "Nothing was deleted. Re-run with --force to apply."
    fi
  else
    echo "${BOLD}Cleanup finished with errors: ${selected_module} (${_run_mode} mode, exit ${module_rc})${RESET}"
  fi

  if [ "$module_rc" -eq 0 ]; then
    op_session_end "ok"
  else
    op_session_end "error:${module_rc}"
  fi
  return "$module_rc"
}

# select_interactive_modules MODULE_LIST [FORCE] — numbered picker over the
# passed list; prints the chosen space-separated names on stdout. The menu
# heading names the run mode (issue #106): `clean -i` and `clean -i --force`
# must not render identically, so the picker states up front whether
# selecting a module previews or deletes.
select_interactive_modules() {
  local module_list="$1"
  local menu_mode
  menu_mode="$(cleanup_mode_name "${2:-false}")"
  local -a _mods=()
  local _m
  for _m in $module_list; do
    _mods+=("$_m")
  done

  local i=1
  local selected=""
  local input token idx selected_module
  local -a picks=()

  echo >&2
  if [ "$menu_mode" = "force" ]; then
    echo "${BOLD}Interactive cleanup — force mode (selected modules will DELETE files)${RESET}" >&2
  else
    echo "${BOLD}Interactive cleanup — dry-run mode (preview only, nothing will be deleted)${RESET}" >&2
  fi
  echo "Select modules to run:" >&2

  for selected_module in "${_mods[@]}"; do
    printf "  [%d] %-14s %s\n" "$i" "$selected_module" "$(cleanup_module_description "$module_list" "$selected_module")" >&2
    i=$((i + 1))
  done

  echo >&2
  echo "Enter numbers (comma-separated), 'all', or press Enter to cancel:" >&2
  printf "> " >&2
  IFS= read -r input || true

  input="${input//[[:space:]]/}"

  if [ -z "$input" ]; then
    return 1
  fi

  if [ "$input" = "all" ] || [ "$input" = "ALL" ]; then
    printf '%s\n' "${_mods[*]}"
    return 0
  fi

  IFS=',' read -r -a picks <<< "$input"

  # Bash 3.2 floor: empty picks (e.g. input ",") would be unbound under
  # `set -u` — the ${arr[@]+"${arr[@]}"} idiom expands to nothing instead.
  for token in "${picks[@]+"${picks[@]}"}"; do
    [ -z "$token" ] && continue
    case "$token" in
      *[!0-9]*)
        error "Invalid selection token: ${token}"
        return 2
        ;;
    esac

    idx=$((token))
    if [ "$idx" -lt 1 ] || [ "$idx" -gt "${#_mods[@]}" ]; then
      error "Selection out of range: ${token}"
      return 2
    fi

    selected_module="${_mods[$((idx - 1))]}"
    case " ${selected} " in
      *" ${selected_module} "*) ;;
      *) selected="${selected}${selected:+ }${selected_module}" ;;
    esac
  done

  if [ -z "$selected" ]; then
    error "No valid modules selected."
    return 2
  fi

  printf '%s\n' "$selected"
}

# run_interactive_cleanup MODULE_LIST FORCE — picker plus per-module runs.
run_interactive_cleanup() {
  local module_list="$1"
  local force="$2"
  local selected_line selection_rc=0 all_rc=0 selected_module
  local _run_mode
  _run_mode="$(cleanup_mode_name "$force")"
  selected_line="$(select_interactive_modules "$module_list" "$force")" || selection_rc=$?

  if [ "$selection_rc" -eq 1 ]; then
    echo "No modules selected. Cancelled."
    return 0
  fi
  if [ "$selection_rc" -ne 0 ]; then
    return "$selection_rc"
  fi

  # Restate the resolved selection with the mode before the first module
  # runs (issue #106): what was picked and what will happen to it.
  echo
  if is_truthy "$force"; then
    echo "${BOLD}Selected: ${selected_line} — force mode (files will be deleted)${RESET}"
  else
    echo "${BOLD}Selected: ${selected_line} — dry-run mode (nothing will be deleted)${RESET}"
  fi

  for selected_module in $selected_line; do
    echo
    echo "${BOLD}== Running cleanup module: ${selected_module} ==${RESET}"
    run_single_cleanup_module "$module_list" "$selected_module" "$force" || all_rc=$?
  done

  # Terminator (issue #106): the interactive run ends with a clear
  # completion line, never silence after the last module.
  echo
  if [ "$all_rc" -eq 0 ]; then
    echo "Interactive cleanup finished (${_run_mode} mode)."
  else
    echo "Interactive cleanup finished with errors (${_run_mode} mode, exit ${all_rc})."
  fi

  return "$all_rc"
}
