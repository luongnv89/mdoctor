#!/usr/bin/env bash
#
# lib/platform.sh
# Platform detection — sourced first by every entry-point script.
# Sets globals used by all modules to gate platform-specific logic.
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
unset _mdoctor_lib_dir


if is_truthy "${_MDOCTOR_PLATFORM_LOADED:-}"; then
  return 0 2>/dev/null || true
fi
_MDOCTOR_PLATFORM_LOADED=true

# Detect at source time. Zero-fork (issue #102): the OSTYPE builtin covers
# the two supported families (darwin*, linux*) without execing uname; the
# uname probe remains as the fallback for unrecognized OSTYPE values.
case "${OSTYPE:-}" in
  darwin*)  _MDOCTOR_UNAME="Darwin" ;;
  linux*)   _MDOCTOR_UNAME="Linux" ;;
  *)        _MDOCTOR_UNAME="$(uname -s 2>/dev/null || echo "unknown")" ;;
esac

case "$_MDOCTOR_UNAME" in
  Darwin)
    MDOCTOR_PLATFORM="macos"
    MDOCTOR_DISTRO=""
    MDOCTOR_DISTRO_VER=""
    _product_name="$(sw_vers -productName 2>/dev/null || echo "macOS")"
    _product_ver="$(sw_vers -productVersion 2>/dev/null || echo "")"
    MDOCTOR_OS_NAME="${_product_name}${_product_ver:+ ${_product_ver}}"
    unset _product_name _product_ver
    ;;
  Linux)
    MDOCTOR_PLATFORM="linux"
    if [ -r /etc/os-release ]; then
      # shellcheck source=/dev/null
      . /etc/os-release
      MDOCTOR_DISTRO="${ID:-unknown}"
      MDOCTOR_DISTRO_VER="${VERSION_ID%%.*}"
      MDOCTOR_OS_NAME="${PRETTY_NAME:-Linux}"
    else
      MDOCTOR_DISTRO="unknown"
      MDOCTOR_DISTRO_VER=""
      MDOCTOR_OS_NAME="Linux (unknown distro)"
    fi
    ;;
  *)
    MDOCTOR_PLATFORM="unknown"
    MDOCTOR_DISTRO=""
    MDOCTOR_DISTRO_VER=""
    MDOCTOR_OS_NAME="Unknown OS ($_MDOCTOR_UNAME)"
    ;;
esac
unset _MDOCTOR_UNAME

export MDOCTOR_PLATFORM MDOCTOR_DISTRO MDOCTOR_DISTRO_VER MDOCTOR_OS_NAME

# ---------------------------------------------------------------------------
# Predicates (return 0 = true, 1 = false)
# ---------------------------------------------------------------------------

is_macos() {
  [ "$MDOCTOR_PLATFORM" = "macos" ]
}

is_linux() {
  [ "$MDOCTOR_PLATFORM" = "linux" ]
}

# Returns true for Debian-family: debian, ubuntu, linuxmint, pop, raspbian, etc.
is_debian() {
  is_linux || return 1
  case "$MDOCTOR_DISTRO" in
    debian|ubuntu|linuxmint|pop|raspbian|elementary|zorin|kali) return 0 ;;
    *) return 1 ;;
  esac
}

platform_name() {
  printf '%s\n' "$MDOCTOR_OS_NAME"
}

# Platform-aware log directory
platform_log_dir() {
  if is_macos; then
    echo "${HOME}/Library/Logs"
  else
    echo "${HOME}/.local/share/mdoctor"
  fi
}

# Platform-aware user cache directory
platform_cache_dir() {
  if is_macos; then
    echo "${HOME}/Library/Caches"
  else
    echo "${HOME}/.cache"
  fi
}

# Platform-aware user log directory
platform_user_log_dir() {
  if is_macos; then
    echo "${HOME}/Library/Logs"
  else
    # Scoped to mdoctor's own data dir (Task 0.2): the wider
    # ${HOME}/.local/share tree holds other apps' data (keyrings, pki,
    # editor state) and must never be a deletion root.
    echo "${XDG_DATA_HOME:-$HOME/.local/share}/mdoctor"
  fi
}

# Platform-aware trash directory
platform_trash_dir() {
  if is_macos; then
    echo "${HOME}/.Trash"
  else
    echo "${HOME}/.local/share/Trash/files"
  fi
}

# Platform-aware trash *metadata* directory (issue #109). The
# freedesktop.org Trash spec pairs every files/<name> with
# info/<name>.trashinfo — emptying only files/ leaves phantom entries in
# the desktop trash UI. macOS ~/.Trash has no metadata dir (prints
# nothing).
platform_trash_info_dir() {
  if is_linux; then
    echo "${HOME}/.local/share/Trash/info"
  fi
}

# Platform-aware crash reports directories (prints one per line).
# Linux covers both collectors (issue #109): apport drops *.crash files
# in /var/crash (and the user mirror under ~/.local/share/apport);
# systemd-coredump writes core.* files under /var/lib/systemd/coredump.
platform_crash_dirs() {
  if is_macos; then
    echo "${HOME}/Library/Logs/DiagnosticReports"
    echo "/Library/Logs/DiagnosticReports"
  else
    echo "/var/crash"
    echo "${HOME}/.local/share/apport"
    echo "/var/lib/systemd/coredump"
  fi
}

# platform_crash_name_patterns DIR — the `find -name` patterns (one per
# line) matching crash artifacts in DIR for the running platform
# (issue #109). macOS keeps the historical .crash/.diag/.ips set; on
# Linux the systemd-coredump dir holds core.<exe>.<uid>.… files while
# apport paths hold *.crash.
platform_crash_name_patterns() {
  local dir="${1-}"
  if is_macos; then
    printf '%s\n' "*.crash" "*.diag" "*.ips"
    return 0
  fi
  case "$dir" in
    */systemd/coredump|*/systemd/coredump/)
      printf '%s\n' "core.*"
      ;;
    *)
      printf '%s\n' "*.crash" "core.*" "*.core"
      ;;
  esac
}
