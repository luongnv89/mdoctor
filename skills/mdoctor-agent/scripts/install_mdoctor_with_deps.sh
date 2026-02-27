#!/usr/bin/env bash
set -euo pipefail

# Installs mdoctor + required dependencies for macOS / Debian-based Linux.
# Safe preview mode:
#   ./install_mdoctor_with_deps.sh --dry-run
#
# Default behavior:
# - checks platform support
# - installs missing deps where possible (Linux apt)
# - runs mdoctor install.sh from local repo if available
# - verifies installation with basic smoke commands

DRY_RUN=false
INSTALL_DEPS=true
METHOD="auto"   # auto|local|remote
USE_USER_BIN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --no-install-deps) INSTALL_DEPS=false; shift ;;
    --method) METHOD="${2:-auto}"; shift 2 ;;
    --user-bin) USE_USER_BIN=true; shift ;;
    -h|--help)
      cat <<'EOF'
Usage: install_mdoctor_with_deps.sh [options]

Options:
  --dry-run           Print commands without executing
  --no-install-deps   Do not auto-install missing dependencies
  --method <m>        auto|local|remote (default: auto)
  --user-bin          Install symlink into ~/.local/bin (no sudo preferred)
  -h, --help          Show help
EOF
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

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

missing=()
for c in git; do
  need_cmd "$c" || missing+=("$c")
done

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

if [ "$USE_USER_BIN" = true ]; then
  run "mkdir -p \"$HOME/.local/bin\""
  export MDOCTOR_BIN_DIR="$HOME/.local/bin"
  export PATH="$HOME/.local/bin:$PATH"
fi

if [[ "$METHOD" == "auto" ]]; then
  if [ -f "$REPO_ROOT/install.sh" ]; then
    METHOD="local"
  else
    METHOD="remote"
  fi
fi

if [[ "$METHOD" == "local" ]]; then
  if [ ! -f "$REPO_ROOT/install.sh" ]; then
    echo "Local install.sh not found at: $REPO_ROOT/install.sh" >&2
    exit 1
  fi
  run "bash \"$REPO_ROOT/install.sh\""
else
  run "curl -fsSL https://raw.githubusercontent.com/luongnv89/mdoctor/main/install.sh | bash"
fi

# Verification
run "mdoctor version"
run "mdoctor help >/dev/null"
run "mdoctor info >/dev/null"
run "mdoctor check -m system >/dev/null"

echo "mdoctor install + verification completed."
