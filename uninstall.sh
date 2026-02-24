#!/usr/bin/env bash
#
# uninstall.sh - Remove mdoctor from your system
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/luongnv89/mdoctor/main/uninstall.sh | bash
#   # Or locally: ./uninstall.sh
#

set -euo pipefail

INSTALL_DIR="${MDOCTOR_INSTALL_DIR:-${HOME}/.mdoctor}"
BIN_LINK="${MDOCTOR_BIN_LINK:-/usr/local/bin/mdoctor}"

if command -v tput >/dev/null 2>&1 && [ -t 1 ]; then
  GREEN="$(tput setaf 2)"
  CYAN="$(tput setaf 6)"
  RESET="$(tput sgr0)"
else
  GREEN="" CYAN="" RESET=""
fi

info()    { echo "${CYAN}[info]${RESET} $*"; }
success() { echo "${GREEN}[ok]${RESET} $*"; }

echo
info "Uninstalling mdoctor..."

# Remove symlink
if [ -L "$BIN_LINK" ]; then
  info "Removing symlink ${BIN_LINK}"
  if [ -w "$(dirname "$BIN_LINK")" ]; then
    rm -f "$BIN_LINK"
  else
    sudo rm -f "$BIN_LINK"
  fi
fi

# Remove install directory
if [ -d "$INSTALL_DIR" ]; then
  info "Removing ${INSTALL_DIR}"
  rm -rf "$INSTALL_DIR"
fi

echo
success "mdoctor has been uninstalled."
echo
