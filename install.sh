#!/usr/bin/env bash
#
# install.sh - One-line installer for mdoctor
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/luongnv89/mdoctor/main/install.sh | bash
#
# Or clone and run locally:
#   git clone https://github.com/luongnv89/mdoctor.git && cd mdoctor && ./install.sh
#

set -euo pipefail

########################################
# Configuration
########################################

REPO_URL="https://github.com/luongnv89/mdoctor.git"
INSTALL_DIR="${HOME}/.mdoctor"
BIN_DIR="/usr/local/bin"
BINARY_NAME="mdoctor"

########################################
# Colors
########################################

if command -v tput >/dev/null 2>&1 && [ -t 1 ]; then
  RED="$(tput setaf 1)"
  GREEN="$(tput setaf 2)"
  YELLOW="$(tput setaf 3)"
  CYAN="$(tput setaf 6)"
  BOLD="$(tput bold)"
  DIM="$(tput dim)"
  RESET="$(tput sgr0)"
else
  RED="" GREEN="" YELLOW="" CYAN="" BOLD="" DIM="" RESET=""
fi

########################################
# Helpers
########################################

info()    { echo "${CYAN}[info]${RESET} $*"; }
success() { echo "${GREEN}[ok]${RESET} $*"; }
warn()    { echo "${YELLOW}[warn]${RESET} $*"; }
fail()    { echo "${RED}[error]${RESET} $*" >&2; exit 1; }

########################################
# Pre-flight checks
########################################

# Must be macOS
if [[ "$(uname -s)" != "Darwin" ]]; then
  fail "mdoctor is designed for macOS only. Detected: $(uname -s)"
fi

# Need git
if ! command -v git >/dev/null 2>&1; then
  fail "git is required but not found. Install Xcode CLT: xcode-select --install"
fi

########################################
# Banner
########################################

echo
echo "${BOLD}${CYAN}"
echo '  __  __ ____             _             '
echo ' |  \/  |  _ \  ___   ___| |_ ___  _ __ '
echo ' | |\/| | | | |/ _ \ / __| __/ _ \| '\''__|'
echo ' | |  | | |_| | (_) | (__| || (_) | |   '
echo ' |_|  |_|____/ \___/ \___|\__\___/|_|   '
echo "${RESET}"
echo "${DIM}  Keep your Mac healthy${RESET}"
echo

########################################
# Install
########################################

# Clone or update
if [ -d "$INSTALL_DIR" ]; then
  info "Existing installation found at ${INSTALL_DIR}"
  info "Updating..."
  cd "$INSTALL_DIR"
  git pull --ff-only origin main 2>/dev/null || {
    warn "Could not fast-forward. Re-cloning..."
    cd ..
    rm -rf "$INSTALL_DIR"
    git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
  }
else
  info "Cloning mac-doctor to ${INSTALL_DIR}..."
  git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
fi

# Make scripts executable
chmod +x "${INSTALL_DIR}/mdoctor"
chmod +x "${INSTALL_DIR}/doctor.sh"
chmod +x "${INSTALL_DIR}/cleanup.sh"

# Create symlink
info "Creating symlink: ${BIN_DIR}/${BINARY_NAME} -> ${INSTALL_DIR}/mdoctor"

if [ -w "$BIN_DIR" ]; then
  ln -sf "${INSTALL_DIR}/mdoctor" "${BIN_DIR}/${BINARY_NAME}"
else
  info "Need sudo to write to ${BIN_DIR}"
  sudo ln -sf "${INSTALL_DIR}/mdoctor" "${BIN_DIR}/${BINARY_NAME}"
fi

# Verify
if command -v mdoctor >/dev/null 2>&1; then
  echo
  success "mdoctor installed successfully!"
  echo
  echo "  Version:  $(mdoctor version)"
  echo "  Location: ${INSTALL_DIR}"
  echo "  Binary:   ${BIN_DIR}/${BINARY_NAME}"
  echo
  echo "${BOLD}Get started:${RESET}"
  echo "  mdoctor help       # Show all commands"
  echo "  mdoctor check      # Run health audit"
  echo "  mdoctor info       # Quick system overview"
  echo "  mdoctor clean      # Cleanup (dry-run)"
  echo "  mdoctor fix all    # Apply common fixes"
  echo
else
  warn "mdoctor was installed but '${BIN_DIR}' may not be in your PATH."
  echo
  echo "Add this to your shell profile (~/.zshrc or ~/.bashrc):"
  echo "  export PATH=\"${BIN_DIR}:\$PATH\""
  echo
  echo "Then restart your terminal or run:"
  echo "  source ~/.zshrc"
  echo
fi
