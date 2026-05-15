#!/usr/bin/env bash
set -euo pipefail

# Installs mdoctor + required dependencies for macOS / Debian-based Linux.
# Supports a dev-mode install that links the current repository checkout,
# useful for testing branch changes on the same machine.

DRY_RUN=false
INSTALL_DEPS=true
METHOD="auto"   # auto|dev|local|remote
USE_USER_BIN=false
REPO_ROOT_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --no-install-deps) INSTALL_DEPS=false; shift ;;
    --method) METHOD="${2:-auto}"; shift 2 ;;
    --user-bin) USE_USER_BIN=true; shift ;;
    --repo-root) REPO_ROOT_OVERRIDE="${2:-}"; shift 2 ;;
    -h|--help)
      cat <<'EOF'
Usage: install_mdoctor_with_deps.sh [options]

Options:
  --dry-run           Print commands without executing
  --no-install-deps   Do not auto-install missing dependencies
  --method <m>        auto|dev|local|remote (default: auto)
  --user-bin          Install symlink into ~/.local/bin (no sudo preferred)
  --repo-root <path>  Override repository root (for --method dev/local)
  -h, --help          Show help

Method details:
  auto   Prefer dev (if current repo is available), then local install.sh, then remote
  dev    Symlink current repo's ./mdoctor directly (best for branch testing)
  local  Run local install.sh (installs under ~/.mdoctor)
  remote Use GitHub one-line installer
EOF
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

case "$METHOD" in
  auto|dev|local|remote) ;;
  *)
    echo "Invalid --method: $METHOD (expected auto|dev|local|remote)" >&2
    exit 2
    ;;
esac

run() {
  if [ "$DRY_RUN" = true ]; then
    echo "[dry-run] $*"
  else
    eval "$@"
  fi
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

OS="$(uname -s)"
if [[ "$OS" != "Darwin" && "$OS" != "Linux" ]]; then
  echo "Unsupported OS: $OS (mdoctor supports macOS + Debian-family Linux)" >&2
  exit 1
fi

if [[ "$OS" == "Linux" ]]; then
  if [ ! -r /etc/os-release ]; then
    echo "Cannot determine Linux distro (missing /etc/os-release)" >&2
    exit 1
  fi
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}" in
    debian|ubuntu|linuxmint|pop|raspbian|elementary|zorin|kali) ;;
    *)
      echo "Unsupported Linux distro for mdoctor installer: ${ID:-unknown}" >&2
      exit 1
      ;;
  esac
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT_DEFAULT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
REPO_ROOT="${REPO_ROOT_OVERRIDE:-$REPO_ROOT_DEFAULT}"

if [[ "$METHOD" == "auto" ]]; then
  if [ -f "$REPO_ROOT/mdoctor" ] && [ -d "$REPO_ROOT/.git" ]; then
    METHOD="dev"
  elif [ -f "$REPO_ROOT/install.sh" ]; then
    METHOD="local"
  else
    METHOD="remote"
  fi
fi

echo "Install method: $METHOD"

missing=()
# git is required for local/remote install paths
if [[ "$METHOD" != "dev" ]]; then
  need_cmd git || missing+=("git")
fi
# curl is required for remote installer path
if [[ "$METHOD" == "remote" ]]; then
  need_cmd curl || missing+=("curl")
fi

if (( ${#missing[@]} > 0 )); then
  echo "Missing dependencies: ${missing[*]}"
  if [ "$INSTALL_DEPS" = false ]; then
    echo "Install them first, then re-run." >&2
    exit 1
  fi

  if [[ "$OS" == "Linux" ]]; then
    run "sudo apt update"
    run "sudo apt install -y ${missing[*]} ca-certificates"
  else
    echo "On macOS, install missing tools via Xcode Command Line Tools or Homebrew:" >&2
    echo "  xcode-select --install" >&2
    echo "  brew install ${missing[*]}" >&2
    exit 1
  fi
fi

if [ "$USE_USER_BIN" = true ]; then
  run "mkdir -p \"$HOME/.local/bin\""
  export MDOCTOR_BIN_DIR="$HOME/.local/bin"
  export PATH="$HOME/.local/bin:$PATH"
fi

install_dev() {
  if [ ! -f "$REPO_ROOT/mdoctor" ]; then
    echo "Dev install failed: mdoctor binary not found at $REPO_ROOT/mdoctor" >&2
    exit 1
  fi

  local bin_dir
  bin_dir="${MDOCTOR_BIN_DIR:-/usr/local/bin}"
  local target
  target="$REPO_ROOT/mdoctor"

  run "chmod +x \"$target\""

  if [ -w "$bin_dir" ]; then
    run "ln -sf \"$target\" \"$bin_dir/mdoctor\""
  else
    run "sudo ln -sf \"$target\" \"$bin_dir/mdoctor\""
  fi
}

case "$METHOD" in
  dev)
    install_dev
    ;;
  local)
    if [ ! -f "$REPO_ROOT/install.sh" ]; then
      echo "Local install.sh not found at: $REPO_ROOT/install.sh" >&2
      exit 1
    fi
    run "bash \"$REPO_ROOT/install.sh\""
    ;;
  remote)
    run "curl -fsSL https://raw.githubusercontent.com/luongnv89/mdoctor/main/install.sh | bash"
    ;;
esac

# Verification
MDOCTOR_CMD="mdoctor"
if ! need_cmd mdoctor; then
  candidate="${MDOCTOR_BIN_DIR:-/usr/local/bin}/mdoctor"
  if [ -x "$candidate" ]; then
    MDOCTOR_CMD="$candidate"
  fi
fi

TERM_FOR_CHECKS="${TERM:-xterm}"
run "TERM=\"$TERM_FOR_CHECKS\" $MDOCTOR_CMD version"
run "TERM=\"$TERM_FOR_CHECKS\" $MDOCTOR_CMD help >/dev/null"
run "TERM=\"$TERM_FOR_CHECKS\" $MDOCTOR_CMD info >/dev/null"
run "TERM=\"$TERM_FOR_CHECKS\" $MDOCTOR_CMD check -m system >/dev/null"

echo "mdoctor install + verification completed."
