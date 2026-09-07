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

REPO_URL="${MDOCTOR_REPO_URL:-https://github.com/luongnv89/mdoctor.git}"
INSTALL_DIR="${MDOCTOR_INSTALL_DIR:-${HOME}/.mdoctor}"
BIN_DIR="${MDOCTOR_BIN_DIR:-/usr/local/bin}"
BINARY_NAME="${MDOCTOR_BINARY_NAME:-mdoctor}"

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

# --- Install-dir validation (Task 1.1) --------------------------------------
# INSTALL_DIR is environment-controlled and this script documents curl|bash
# invocation, so never rm -rf it without proving it is an mdoctor checkout.
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd 2>/dev/null || pwd)"
if [ -f "$_SCRIPT_DIR/lib/safety.sh" ]; then
  # shellcheck source=/dev/null
  source "$_SCRIPT_DIR/lib/safety.sh"
fi

assert_mdoctor_install_dir() {
  local dir="$1"
  local norm_dir norm_home
  if declare -f _normalize_path >/dev/null 2>&1; then
    norm_dir="$(_normalize_path "$dir")"
    norm_home="$(_normalize_path "${HOME:-}")"
  else
    norm_dir="$dir"
    norm_home="${HOME:-}"
  fi
  if [ -z "$norm_dir" ] || [ "$norm_dir" = "/" ] || { [ -n "$norm_home" ] && [ "$norm_dir" = "$norm_home" ]; }; then
    fail "Refusing to touch '${dir}': not a valid install location."
  fi
  if [ ! -f "${dir}/mdoctor" ] || [ ! -d "${dir}/.git" ]; then
    fail "Refusing to remove '${dir}': no mdoctor checkout found (missing mdoctor entry point or .git)."
  fi
  # NOTE: validate_deletion_path is intentionally not used here — install
  # dirs are not cache/temp roots (e.g. ~/.mdoctor), so the 0.4 allowlist
  # would reject legitimate checkouts. The markers above are the proof of
  # identity for this path.
}

########################################
# Pre-flight checks
########################################

# Must be macOS or Linux (Debian-family) unless explicitly bypassed for CI
if [[ "${MDOCTOR_SKIP_PLATFORM_CHECK:-false}" != "true" ]]; then
  case "$(uname -s)" in
    Darwin) ;;
    Linux)
      if [ -r /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        case "${ID:-}" in
          debian|ubuntu|linuxmint|pop|raspbian|elementary|zorin|kali) ;;
          *) fail "mdoctor supports Debian-family Linux only. Detected distro: ${ID:-unknown}" ;;
        esac
      else
        fail "Cannot determine Linux distribution (missing /etc/os-release)."
      fi
      ;;
    *) fail "mdoctor supports macOS and Debian/Ubuntu Linux. Detected: $(uname -s)" ;;
  esac
fi

# Need git
if ! command -v git >/dev/null 2>&1; then
  if [[ "$(uname -s)" == "Darwin" ]]; then
    fail "git is required but not found. Install Xcode CLT: xcode-select --install"
  else
    fail "git is required but not found. Install with: sudo apt install git"
  fi
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
echo "${DIM}  Keep your system healthy${RESET}"
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
    assert_mdoctor_install_dir "$INSTALL_DIR"
    rm -rf -- "$INSTALL_DIR"
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

# Make fix modules executable
if [ -d "${INSTALL_DIR}/fixes" ]; then
  chmod +x "${INSTALL_DIR}"/fixes/*.sh 2>/dev/null || true
fi

# Create symlink (Task 4.2: validated overrides, confirmed, no clobber)
validate_bin_override() {
  # Binary name: strict charset, never a path.
  case "$BINARY_NAME" in
    ""|*/*)
      fail "Invalid binary name '${BINARY_NAME}': must be a plain filename (no /)."
      ;;
  esac
  case "$BINARY_NAME" in
    *[!A-Za-z0-9_.-]*)
      fail "Invalid binary name '${BINARY_NAME}': allowed characters are A-Z a-z 0-9 _ . -."
      ;;
  esac
  # Bin dir: allowlisted, or an existing directory ending in /bin.
  case "$BIN_DIR" in
    /usr/local/bin|"${HOME}/.local/bin"|"${HOME}/bin") ;;
    *)
      case "$BIN_DIR" in
        */bin) ;;
        *)
          fail "Invalid bin directory '${BIN_DIR}': must be an existing directory ending in /bin."
          ;;
      esac
      [ -d "$BIN_DIR" ] || fail "Invalid bin directory '${BIN_DIR}': directory does not exist."
      ;;
  esac
}

info "Creating symlink: ${BIN_DIR}/${BINARY_NAME} -> ${INSTALL_DIR}/mdoctor"
validate_bin_override

BIN_LINK="${BIN_DIR}/${BINARY_NAME}"
if [ -n "${MDOCTOR_BIN_DIR:-}" ] || [ -n "${MDOCTOR_BINARY_NAME:-}" ]; then
  # Overrides are in play: print the exact command and confirm (Task 4.2).
  echo "  ln -s \"${INSTALL_DIR}/mdoctor\" \"${BIN_LINK}\""
  # Confirmation mirrors the cleanup gate (Task 0.5 semantics): an
  # explicit y proceeds (tty or pipe); anything else aborts, and a
  # non-tty without an answer names the skip flag.
  if [ "${MDOCTOR_ASSUME_YES:-false}" != true ]; then
    if [ -t 0 ]; then
      printf 'Create this symlink? [y/N] ' >&2
    fi
    answer=""
    IFS= read -r answer || answer=""
    case "$answer" in
      [yY]|[yY][eE][sS]) ;;
      *)
        if [ -t 0 ]; then
          fail "Aborted: symlink not created."
        else
          fail "Refusing to create symlink on a non-tty without MDOCTOR_ASSUME_YES=true."
        fi
        ;;
    esac
  fi
fi

# Refuse to clobber anything that is not mdoctor's own symlink (Task 4.2):
# a previous mdoctor link is replaced, anything else aborts the install.
if [ ! -d "$BIN_DIR" ]; then
  fail "Bin directory '${BIN_DIR}' does not exist."
fi
if [ -L "$BIN_LINK" ]; then
  if [ "$(readlink "$BIN_LINK" 2>/dev/null || true)" != "${INSTALL_DIR}/mdoctor" ]; then
    fail "Refusing to overwrite '${BIN_LINK}': not mdoctor's symlink (points elsewhere)."
  fi
  info "Replacing existing mdoctor symlink ${BIN_LINK}"
  if [ -w "$(dirname "$BIN_LINK")" ]; then
    rm -f "$BIN_LINK"
  else
    info "Need sudo to write to ${BIN_DIR}"
    sudo rm -f "$BIN_LINK"
  fi
elif [ -e "$BIN_LINK" ]; then
  fail "Refusing to overwrite '${BIN_LINK}': not a symlink."
fi

if [ -w "$BIN_DIR" ]; then
  ln -s "${INSTALL_DIR}/mdoctor" "${BIN_LINK}"
else
  info "Need sudo to write to ${BIN_DIR}"
  sudo ln -s "${INSTALL_DIR}/mdoctor" "${BIN_LINK}"
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
