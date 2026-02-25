#!/usr/bin/env bash
#
# lib/platform.sh
# Platform detection — sourced first by every entry-point script.
# Sets globals used by all modules to gate platform-specific logic.
#

# Guard against double-sourcing
if [ "${_MDOCTOR_PLATFORM_LOADED:-false}" = true ]; then
  return 0 2>/dev/null || true
fi
_MDOCTOR_PLATFORM_LOADED=true

# Detect at source time
_MDOCTOR_UNAME="$(uname -s 2>/dev/null || echo "unknown")"

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

is_supported_platform() {
  is_macos || is_debian
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
    # Linux user logs are scattered; use /var/log for system, ~/.local/share for user
    echo "${HOME}/.local/share"
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

# Platform-aware crash reports directories (prints one per line)
platform_crash_dirs() {
  if is_macos; then
    echo "${HOME}/Library/Logs/DiagnosticReports"
    echo "/Library/Logs/DiagnosticReports"
  else
    echo "/var/crash"
    echo "${HOME}/.local/share/apport"
  fi
}
