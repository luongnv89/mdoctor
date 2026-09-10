#!/usr/bin/env bash
#
# lib/registry.sh
# Single source of truth for the check/cleanup/fix/diagnose module registry
# (Task 8.1 — closes M3's module-list duplication clause: 1 declaration, not 13).
#
# Sourcing contract: lib/platform.sh and lib/metadata.sh must be sourced first.
# This file defines register_all_modules() plus derivation helpers so help text,
# error messages, validation and dispatch are all read from the registry instead
# of hand-maintained copies.
#

# Guard against double-sourcing (re-sourcing would double-register).
if [ "${_MDOCTOR_REGISTRY_LOADED:-false}" = true ]; then
  return 0 2>/dev/null || true
fi
_MDOCTOR_REGISTRY_LOADED=true

# register_all_modules — declare every module once, platform-filtered.
# Idempotent: several commands may run per process.
register_all_modules() {
  if [ "${_MDOCTOR_MODULES_REGISTERED:-false}" = true ]; then
    return 0
  fi
  # Check modules — Hardware
  if is_macos; then
    register_module check battery    Hardware SAFE check_battery     "Battery health, cycle count, capacity"
  fi
  register_module check hardware   Hardware SAFE check_hardware    "CPU, RAM, model, thermals"
  if is_macos; then
    register_module check bluetooth  Hardware SAFE check_bluetooth   "Bluetooth power state & devices"
    register_module check usb        Hardware SAFE check_usb         "Connected USB devices"
  fi
  # Check modules — System
  register_module check system      System SAFE check_system        "OS version, memory, load average"
  register_module check disk        System SAFE check_disk          "Disk usage & health"
  register_module check updates     System SAFE check_updates_basic "System updates"
  register_module check security    System SAFE check_security      "Firewall, encryption, security settings"
  register_module check startup     System SAFE check_startup       "Startup services & agents"
  register_module check network     System SAFE check_network       "Connectivity, DNS, Wi-Fi signal"
  register_module check performance System SAFE check_performance   "Memory pressure, CPU, processes"
  register_module check storage     System SAFE check_storage       "Large files & app storage analysis"
  # Diagnose modules
  register_module diagnose diagnose System HIGH check_diagnose_performance "Active performance diagnosis with bottleneck detection"
  # Check modules — Software
  if is_macos; then
    register_module check homebrew   Software SAFE check_homebrew    "Homebrew installation & packages"
  fi
  register_module check node       Software SAFE check_node_npm    "Node.js & npm"
  register_module check python     Software SAFE check_python      "Python & pip"
  register_module check devtools   Software SAFE check_dev_tools   "Developer tools, Git, Docker"
  register_module check shell      Software SAFE check_shell_configs "Shell config syntax"
  register_module check apps       Software SAFE check_apps        "Crash reports, application health"
  register_module check git_config Software SAFE check_git_config  "Git & SSH configuration"
  register_module check containers Software SAFE check_containers  "Docker & container health"
  if is_linux; then
    register_module check apt      Software SAFE check_apt         "APT package manager health"
  fi

  # Cleanup modules
  register_module cleanup trash         System   MED clean_trash               "Empty Trash"
  register_module cleanup caches        System   LOW clean_user_caches         "User cache directories"
  register_module cleanup logs          System   MED clean_logs                "Old log files"
  register_module cleanup downloads     System   LOW clean_downloads_large_files "Large files in Downloads"
  register_module cleanup crash_reports System   MED clean_crash_reports       "Old crash/diagnostic reports"
  if is_macos; then
    register_module cleanup ios_backups   System   HIGH clean_ios_backups         "Old iOS device backups"
  fi
  register_module cleanup browser       Software LOW clean_browser_caches      "Browser cache cleanup"
  register_module cleanup dev           Software MED clean_dev_stuff           "Developer tool caches"
  if is_macos; then
    register_module cleanup xcode         Software MED clean_xcode              "Xcode DerivedData, archives, simulators"
  fi
  register_module cleanup dev_caches    Software MED clean_dev_caches         "Developer dependency & package caches"
  if is_linux; then
    register_module cleanup apt          System   MED clean_apt_cache          "APT package cache cleanup"
  fi

  # Fix modules
  register_module fix dns         System   LOW  fix_dns         "Flush DNS cache"
  if is_macos; then
    register_module fix disk        System   LOW  fix_disk        "Free disk space"
    register_module fix homebrew    Software LOW  fix_homebrew    "Update, upgrade, cleanup Homebrew"
    register_module fix permissions System   MED  fix_permissions "Reset file permissions"
    register_module fix spotlight   System   MED  fix_spotlight   "Rebuild Spotlight index"
    register_module fix bluetooth   Hardware LOW  fix_bluetooth   "Reset Bluetooth module"
    register_module fix audio       System   LOW  fix_audio       "Restart Core Audio daemon"
    register_module fix wifi        System   LOW  fix_wifi        "Renew DHCP, flush DNS, cycle Wi-Fi"
    register_module fix timemachine System   MED  fix_timemachine "Verify Time Machine backups"
  fi
  if is_linux; then
    register_module fix apt        System   LOW  fix_apt         "Fix APT packages (update, upgrade, autoremove)"
  fi
  _MDOCTOR_MODULES_REGISTERED=true
}

# registry_names TYPE — space-separated module names of one type, in order.
registry_names() {
  local type="$1"
  local i=0
  local out=""
  while (( i < _MOD_COUNT )); do
    if [ "${_MOD_TYPES[$i]}" = "$type" ]; then
      out="${out}${out:+ }${_MOD_NAMES[$i]}"
    fi
    i=$((i + 1))
  done
  printf '%s\n' "$out"
}

# registry_available_text TYPE — "Available modules: a, b, c" derived line.
registry_available_text() {
  local type="$1"
  local label="${2:-Available modules}"
  local names
  names="$(registry_names "$type")"
  # shellcheck disable=SC2086
  local IFS=" "
  local joined=""
  local n
  # Bash 3.2 compatible join with ", ".
  for n in $names; do
    if [ -z "$joined" ]; then
      joined="$n"
    else
      joined="$joined, $n"
    fi
  done
  printf '%s: %s\n' "$label" "$joined"
}

# registry_help_group TYPE — "  Category:  name [RISK], ..." lines grouped
# Hardware / System / Software, derived from the registry.
registry_help_group() {
  local type="$1"
  local cat
  local i
  for cat in Hardware System Software; do
    local line=""
    i=0
    while (( i < _MOD_COUNT )); do
      if [ "${_MOD_TYPES[$i]}" = "$type" ] && [ "${_MOD_CATS[$i]}" = "$cat" ]; then
        if [ -z "$line" ]; then
          line="${_MOD_NAMES[$i]} [${_MOD_RISKS[$i]}]"
        else
          line="$line, ${_MOD_NAMES[$i]} [${_MOD_RISKS[$i]}]"
        fi
      fi
      i=$((i + 1))
    done
    if [ -n "$line" ]; then
      printf '  %-9s %s\n' "$cat:" "$line"
    fi
  done
}

# registry_check_names_plain TYPE — comma-separated names without risk badges,
# for the Check Modules help block (matches historic format).
registry_check_names_plain() {
  local type="$1"
  local cat
  local i
  for cat in Hardware System Software; do
    local line=""
    i=0
    while (( i < _MOD_COUNT )); do
      if [ "${_MOD_TYPES[$i]}" = "$type" ] && [ "${_MOD_CATS[$i]}" = "$cat" ]; then
        if [ -z "$line" ]; then
          line="${_MOD_NAMES[$i]}"
        else
          line="$line, ${_MOD_NAMES[$i]}"
        fi
      fi
      i=$((i + 1))
    done
    if [ -n "$line" ]; then
      printf '  %-9s %s\n' "$cat:" "$line"
    fi
  done
}

# registry_count TYPE — number of registered modules of one type on the
# running platform. Every user-facing count derives from this (Task 8.4).
registry_count() {
  local type="$1"
  local i=0
  local n=0
  while (( i < _MOD_COUNT )); do
    if [ "${_MOD_TYPES[$i]}" = "$type" ]; then
      n=$((n + 1))
    fi
    i=$((i + 1))
  done
  echo "$n"
}

# registry_target_lines TYPE — "  name [RISK]  description" per module.
registry_target_lines() {
  local type="$1"
  local i=0
  while (( i < _MOD_COUNT )); do
    if [ "${_MOD_TYPES[$i]}" = "$type" ]; then
      printf '  %-14s [%s]  %s\n' \
        "${_MOD_NAMES[$i]}" "${_MOD_RISKS[$i]}" "${_MOD_DESCS[$i]}"
    fi
    i=$((i + 1))
  done
}
