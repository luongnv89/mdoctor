#!/usr/bin/env bash
#
# uninstall.sh - Remove mdoctor from your system
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/luongnv89/mdoctor/main/uninstall.sh | bash
#   # Or locally: ./uninstall.sh
#
# Environment:
#   MDOCTOR_INSTALL_DIR  install location (default: ~/.mdoctor)
#   MDOCTOR_BIN_LINK     symlink to remove (default: /usr/local/bin/mdoctor)
#   MDOCTOR_ASSUME_YES   when "true", skip the confirmation prompt
#                        (same flag as the cleanup confirmation gate)
#

# Errexit posture (issue #113): `set -e` is deliberate — a half-completed
# uninstall is worse than none, so any failure aborts immediately.
# See CONTRIBUTING.md "Errexit posture".
set -euo pipefail

INSTALL_DIR="${MDOCTOR_INSTALL_DIR:-${HOME}/.mdoctor}"
BIN_LINK="${MDOCTOR_BIN_LINK:-/usr/local/bin/mdoctor}"
CONFIG_DIR="${HOME}/.config/mdoctor"

# --- Safety primitives (Task 1.1) -------------------------------------------
# Prefer the repo's validators when running from a checkout; fall back to a
# minimal inline guard for curl|bash invocation (no lib/ on disk there).
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd 2>/dev/null || pwd)"
if [ -f "$_SCRIPT_DIR/lib/safety.sh" ]; then
  # shellcheck source=/dev/null
  source "$_SCRIPT_DIR/lib/safety.sh"
else
  _normalize_path() {
    local p="${1-}"
    [ "$p" != "/" ] && p="${p%/}"
    printf '%s' "$p"
  }
  validate_deletion_path() {
    local p
    p="$(_normalize_path "${1-}")"
    case "$p" in
      ""|/|"${HOME}") return 22 ;;
    esac
    case "$p" in
      /*) return 0 ;;
      *) return 21 ;;
    esac
  }
fi

# Same color contract as init_colors (issue #108): tty only, and never
# when NO_COLOR / MDOCTOR_NO_COLOR carries a non-empty value.
if command -v tput >/dev/null 2>&1 && [ -t 1 ] \
  && [ -z "${NO_COLOR:-}" ] && [ -z "${MDOCTOR_NO_COLOR:-}" ]; then
  GREEN="$(tput setaf 2)"
  CYAN="$(tput setaf 6)"
  RESET="$(tput sgr0)"
else
  GREEN="" CYAN="" RESET=""
fi

info()    { echo "${CYAN}[info]${RESET} $*"; }
success() { echo "${GREEN}[ok]${RESET} $*"; }
die()     { echo "${CYAN}[error]${RESET} $*" >&2; exit 1; }

echo
info "Uninstalling mdoctor..."

# Validate the install directory before any rm (Task 1.1): never empty,
# $HOME or /. INSTALL_DIR is environment-controlled and this script
# documents curl|bash invocation, so every check matters. NOTE: the
# cache/temp allowlist in validate_deletion_path does NOT apply here —
# install dirs are not cache roots (e.g. ~/.mdoctor); only _normalize_path
# is reused from lib/safety.sh.
norm_home="$(_normalize_path "${HOME:-}")"
norm_dir="$(_normalize_path "$INSTALL_DIR")"
if [ -z "$norm_dir" ] || [ "$norm_dir" = "/" ] || { [ -n "$norm_home" ] && [ "$norm_dir" = "$norm_home" ]; }; then
  die "Refusing to uninstall from '${INSTALL_DIR}': not a valid install location."
fi

# True when every entry in DIR is mdoctor-owned: the history/ state dir, a
# .git remnant, or the mdoctor entry point (same predicate as install.sh —
# ~/.mdoctor doubles as mdoctor's state dir, so a dir without a working
# checkout is a normal state, not an error). An empty dir is trivially
# ours; anything else makes the dir foreign — never ours to delete.
_dir_is_mdoctor_owned() {
  local entry
  for entry in "$1"/* "$1"/.[!.]* "$1"/..?*; do
    [ -e "$entry" ] || continue
    case "${entry##*/}" in
      history|.git|mdoctor) ;;
      *) return 1 ;;
    esac
  done
  return 0
}

# Classify INSTALL_DIR: a proven checkout (mdoctor entry point + .git) or
# a dir holding only mdoctor-owned entries is removable after confirmation;
# foreign content refuses; an absent dir just skips removal (the symlink
# cleanup below still runs — a dangling link is a normal leftover).
remove_install_dir=false
if [ -d "$INSTALL_DIR" ]; then
  if [ -f "${INSTALL_DIR}/mdoctor" ] && [ -d "${INSTALL_DIR}/.git" ]; then
    remove_install_dir=true
  elif _dir_is_mdoctor_owned "$INSTALL_DIR"; then
    remove_install_dir=true
  else
    die "Refusing to remove '${INSTALL_DIR}': no mdoctor checkout found and it contains files mdoctor does not own. Move it aside or remove it manually (e.g. mv \"${INSTALL_DIR}\" \"${INSTALL_DIR}.bak\") and re-run."
  fi
elif [ -e "$INSTALL_DIR" ]; then
  die "Refusing to remove '${INSTALL_DIR}': exists and is not a directory."
fi

# Confirmation gate (Task 1.1): prompt on a tty, skippable with the
# documented MDOCTOR_ASSUME_YES=true flag.
if [ "${MDOCTOR_ASSUME_YES:-false}" != true ]; then
  if [ -t 0 ]; then
    if [ "$remove_install_dir" = true ]; then
      printf 'Remove %s and %s? [y/N] ' "$INSTALL_DIR" "$BIN_LINK" >&2
    else
      printf 'Remove %s? [y/N] ' "$BIN_LINK" >&2
    fi
    answer=""
    IFS= read -r answer || answer=""
    case "$answer" in
      [yY]|[yY][eE][sS]) ;;
      *) echo "Aborted: nothing was removed." >&2; exit 1 ;;
    esac
  else
    die "Refusing to uninstall on a non-tty without MDOCTOR_ASSUME_YES=true."
  fi
fi

# Remove symlink (refuse to clobber a non-symlink: Task 4.2 owns the
# installer side; uninstall only ever removes a symlink — Task 1.1).
if [ -L "$BIN_LINK" ]; then
  info "Removing symlink ${BIN_LINK}"
  if [ -w "$(dirname "$BIN_LINK")" ]; then
    rm -f "$BIN_LINK"
  else
    sudo rm -f "$BIN_LINK"
  fi
elif [ -e "$BIN_LINK" ]; then
  die "Refusing to remove '${BIN_LINK}': not a symlink."
fi

# Remove install directory (validated above: checkout or mdoctor state only)
if [ "$remove_install_dir" = true ]; then
  info "Removing ${INSTALL_DIR}"
  rm -rf -- "$INSTALL_DIR"
fi

echo
success "mdoctor has been uninstalled."
info "Retained user config: ${CONFIG_DIR} (whitelist, scope, operations log)."
info "To remove it as well: rm -rf \"${CONFIG_DIR}\""
echo
