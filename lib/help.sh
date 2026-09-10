#!/usr/bin/env bash
#
# lib/help.sh
# Help rendering + shared common-flag parser (Task 8.4, god-module part 2).
# Per-command usage lives in usage_* functions OUTSIDE the option-parse loops;
# every user-facing count is computed from the platform-filtered registry at
# render time, per type. parse_common_args handles --debug/--help once for all
# five command parsers.
#
# Sourcing contract: lib/platform.sh, lib/metadata.sh and lib/registry.sh must
# be sourced first. Color variables (BOLD/GREEN/...) are optional.
#

# Guard against double-sourcing.
if [ "${_MDOCTOR_HELP_LOADED:-false}" = true ]; then
  return 0 2>/dev/null || true
fi
_MDOCTOR_HELP_LOADED=true

# _COMMON_REST — remaining args after parse_common_args strips common flags.
_COMMON_REST=()

# parse_common_args USAGE_FN [ARGS...]
# Single shared common-flag parser for all command option loops: consumes
# --debug (enables MDOCTOR_DEBUG globally) and --help|-h (prints the given
# usage function), collecting everything else into _COMMON_REST. Callers run
# `set --` over _COMMON_REST and parse only command-specific options.
# Returns 0 normally; returns 0 via the caller's `|| return 0` after printing
# help (help has always exited 0).
parse_common_args() {
  local usage_fn="$1"
  shift
  _COMMON_REST=()
  local _a
  for _a in "$@"; do
    case "$_a" in
      --debug)
        MDOCTOR_DEBUG=true
        export MDOCTOR_DEBUG
        ;;
      --help|-h)
        "$usage_fn"
        return 2
        ;;
      *)
        _COMMON_REST+=("$_a")
        ;;
    esac
  done
  return 0
}

# usage_check — check command help (counts from the registry).
usage_check() {
  register_all_modules
  echo "Usage: mdoctor check [options]"
  echo
  echo "Run system health audit (read-only, changes nothing)."
  echo
  echo "Options:"
  echo "  -m, --module <name>   Run only a specific check module"
  echo "  --json                Output results as JSON"
  echo "  --debug               Enable structured debug diagnostics"
  echo "  -h, --help            Show this help"
  echo
  echo "Check modules ($(registry_count check), all [SAFE] read-only):"
  registry_check_names_plain check
}

# usage_clean — clean command help (counts from the registry).
usage_clean() {
  register_all_modules
  echo "Usage: mdoctor clean [options]"
  echo
  echo "Run system cleanup. Default is dry-run mode (shows what would"
  echo "be deleted without actually removing anything)."
  echo
  echo "Options:"
  echo "  -f, --force           Actually delete files (no dry-run)"
  echo "  -m, --module <name>   Run only a specific cleanup module"
  echo "  -i, --interactive     Interactively choose cleanup modules"
  echo "  --debug               Enable structured debug diagnostics"
  echo "  -h, --help            Show this help"
  echo
  echo "Cleanup modules ($(registry_count cleanup), risk-rated by blast radius):"
  registry_help_group cleanup
  echo
  echo "Whitelist file: ~/.config/mdoctor/cleanup_whitelist"
  echo "Scope file: ~/.config/mdoctor/cleanup_scope.conf (dev_caches node_modules scan)"
}

# usage_fix — fix command help (targets from the registry).
usage_fix() {
  register_all_modules
  echo "Usage: mdoctor fix [--debug] <target>"
  echo
  echo "Apply common fixes for system issues."
  echo
  echo "Targets ($(registry_count fix)):"
  registry_target_lines fix
  echo "  all             Run all applicable fixes"
  echo
  echo "Options:"
  echo "  --debug       Enable structured debug diagnostics"
  echo "  -h, --help    Show this help"
}

# usage_diagnose — diagnose command help (static copy).
usage_diagnose() {
  echo "Usage: mdoctor diagnose [options]"
  echo
  echo "Run active performance diagnosis with bottleneck detection."
  echo "Checks CPU, memory, disk I/O, swap, and system configuration."
  echo
  echo "Output includes a prioritized list of actionable recommendations."
  echo
  echo "Options:"
  echo "  --debug       Enable structured debug diagnostics"
  echo "  -h, --help    Show this help"
  echo
  echo "Checks performed:"
  echo "  CPU           Load average, top consumers, user/sys ratio (Linux)"
  echo "  Memory        Usage %, pressure level, OOM risk, swap usage"
  echo "  Disk I/O      I/O wait percentage, disk usage hotspots"
  echo "  Swap          Swap usage %, swap thrashing detection"
  echo "  Zombie        Zombie process count and parent identification"
  echo "  System Config FD limits, open connections"
  echo "  Correlation   Swap+I/O thrashing, CPU+I/O contention"
}

# usage_update — update command help (static copy).
usage_update() {
  echo "Usage: mdoctor update [options]"
  echo
  echo "Update mdoctor to the latest stable release tag."
  echo
  echo "Options:"
  echo "  --check              Check for updates without applying"
  echo "  --channel <name>     Update channel: stable (latest vX.Y.Z tag,"
  echo "                       default) or main (branch head — opt in to"
  echo "                       track main)"
  echo "  --debug              Enable structured debug diagnostics"
  echo "  -h, --help           Show this help"
  echo
  echo "Environment Variables:"
  echo "  MDOCTOR_UPDATE_REMOTE   Override git remote name (default: origin;"
  echo "                          must be a configured remote, never a URL)"
  echo "  MDOCTOR_UPDATE_BRANCH   Branch for --channel main (default: main)"
  echo "  MDOCTOR_CHANNEL         Same as --channel (default: stable)"
  echo "  MDOCTOR_REQUIRE_TAG_SIGNATURE"
  echo "                          Refuse unsigned release tags (default: false)"
}
