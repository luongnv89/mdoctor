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

# Errexit posture (issue #113): `set -e` is deliberate — a half-completed
# install is worse than no install, so any failure aborts immediately.
# See CONTRIBUTING.md "Errexit posture".
set -euo pipefail

########################################
# Configuration
########################################

REPO_URL="${MDOCTOR_REPO_URL:-https://github.com/luongnv89/mdoctor.git}"
INSTALL_DIR="${MDOCTOR_INSTALL_DIR:-${HOME}/.mdoctor}"
BIN_DIR="${MDOCTOR_BIN_DIR:-/usr/local/bin}"
BINARY_NAME="${MDOCTOR_BINARY_NAME:-mdoctor}"
CHANNEL="${MDOCTOR_CHANNEL:-stable}"

usage() {
  echo "Usage: ./install.sh [--channel <name>] [--help]"
  echo
  echo "Install mdoctor from a signed release tag (default channel: stable)."
  echo
  echo "Options:"
  echo "  --channel <name>  Update channel: stable (latest vX.Y.Z tag, default)"
  echo "                    or main (branch head — opt in to track main)"
  echo "  -h, --help        Show this help"
  echo
  echo "Environment Variables:"
  echo "  MDOCTOR_CHANNEL               Same as --channel (default: stable)"
  echo "  MDOCTOR_REPO_URL              Git remote to install from"
  echo "  MDOCTOR_INSTALL_DIR           Install location (default: ~/.mdoctor)"
  echo "  MDOCTOR_BIN_DIR               Directory for the symlink (default: /usr/local/bin)"
  echo "  MDOCTOR_BINARY_NAME           Symlink name (default: mdoctor)"
  echo "  MDOCTOR_REQUIRE_TAG_SIGNATURE Set to true to refuse unsigned tags"
}

########################################
# Colors
########################################

# Colors only on a tty and only when the caller has not opted out —
# NO_COLOR / MDOCTOR_NO_COLOR set to a non-empty value disables them
# (issue #108, same convention as init_colors in lib/common.sh).
if command -v tput >/dev/null 2>&1 && [ -t 1 ] \
  && [ -z "${NO_COLOR:-}" ] && [ -z "${MDOCTOR_NO_COLOR:-}" ]; then
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

while [ $# -gt 0 ]; do
  case "$1" in
    --channel)
      [ -n "${2:-}" ] || fail "Missing value for --channel (stable|main)"
      CHANNEL="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown option: $1 (see --help)"
      ;;
  esac
done

case "$CHANNEL" in
  stable|main) ;;
  *) fail "Unknown channel '${CHANNEL}' (supported: stable, main)" ;;
esac

# --- Signed release tags (Task 4.1) -----------------------------------------
# latest_release_tag URL — newest vX.Y.Z tag at the remote (numeric sort,
# portable: no sort -V, no ls-remote --sort). Pre-releases and peeled
# ^{} lines are excluded by the awk pattern.
latest_release_tag() {
  git ls-remote --tags "$1" 2>/dev/null \
    | awk '$2 ~ /^refs\/tags\/v[0-9]+\.[0-9]+\.[0-9]+$/ {t=$2; sub(/^refs\/tags\/v/, "", t); print t}' \
    | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1 | awk '{if ($0 != "") print "v" $0}'
}

# verify_release_tag REPO_DIR TAG — require an annotated tag; verify a
# gpg signature when present and fail closed on a bad one. Unsigned
# legacy tags warn (releases are signed going forward); set
# MDOCTOR_REQUIRE_TAG_SIGNATURE=true to refuse them.
# Prints the reason to stderr and returns non-zero on refusal (callers
# decide cleanup — a fresh clone removes its own directory).
verify_release_tag() {
  local repo_dir="$1" tag="$2"
  local objtype
  objtype="$(git -C "$repo_dir" cat-file -t "$tag" 2>/dev/null || true)"
  if [ "$objtype" != "tag" ]; then
    echo "[error] Refusing to use '${tag}': not an annotated release tag." >&2
    return 1
  fi
  local verify_out verify_rc
  # Posture-agnostic capture (issue #113): the `if` keeps a failing
  # substitution from aborting under `set -e` without toggling flags.
  if verify_out="$(git -C "$repo_dir" verify-tag "$tag" 2>&1)"; then
    verify_rc=0
  else
    verify_rc=$?
  fi
  if [ "$verify_rc" -eq 0 ]; then
    info "Verified release tag signature: ${tag}"
    return 0
  fi
  case "$verify_out" in
    *"BAD signature"*)
      echo "[error] BAD signature on release tag '${tag}' — refusing to install." >&2
      return 1
      ;;
  esac
  if [ "${MDOCTOR_REQUIRE_TAG_SIGNATURE:-false}" = true ]; then
    echo "[error] Release tag '${tag}' has no verifiable signature and MDOCTOR_REQUIRE_TAG_SIGNATURE=true." >&2
    return 1
  fi
  warn "Release tag '${tag}' is not cryptographically verified; installing anyway. Releases are signed going forward."
  return 0
}

# --- Install-dir handling (Task 1.1) ----------------------------------------
# INSTALL_DIR is environment-controlled and this script documents curl|bash
# invocation, so it is never rm -rf'd: existing dirs are repaired in place
# (git refuses to clobber untracked files) or moved aside — not deleted.
# ~/.mdoctor doubles as mdoctor's state dir (lib/history.sh writes
# ~/.mdoctor/history on every check run, installed or not), so a dir that
# is not a checkout is a normal state, not an error.

# True when every entry in DIR is mdoctor-owned: the history/ state dir, a
# .git remnant, or the mdoctor entry point. An empty dir is trivially ours;
# anything else makes the dir foreign — never merge a checkout into it.
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

########################################
# Pre-flight checks
########################################

# Must be macOS or Linux (Debian- or Arch-family) unless explicitly bypassed for CI
if [[ "${MDOCTOR_SKIP_PLATFORM_CHECK:-false}" != "true" ]]; then
  case "$(uname -s)" in
    Darwin) ;;
    Linux)
      if [ -r /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        case "${ID:-}" in
          debian|ubuntu|linuxmint|pop|raspbian|elementary|zorin|kali) ;;
          arch|omarchy|endeavouros|manjaro|cachyos|garuda|artix|arcolinux) ;;
          *)
            case " ${ID_LIKE:-} " in
              *" debian "*|*" arch "*) ;;
              *) fail "mdoctor supports Debian- and Arch-family Linux only. Detected distro: ${ID:-unknown}" ;;
            esac
            ;;
        esac
      else
        fail "Cannot determine Linux distribution (missing /etc/os-release)."
      fi
      ;;
    *) fail "mdoctor supports macOS and Debian/Ubuntu/Arch Linux. Detected: $(uname -s)" ;;
  esac
fi

# Need git
if ! command -v git >/dev/null 2>&1; then
  if [[ "$(uname -s)" == "Darwin" ]]; then
    fail "git is required but not found. Install Xcode CLT: xcode-select --install"
  elif [ -r /etc/os-release ]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    case "${ID:-} ${ID_LIKE:-}" in
      # *arch* also matches ID=omarchy ("omarchy" contains "arch").
      *arch*)
        fail "git is required but not found. Install with: sudo pacman -S git"
        ;;
      *)
        fail "git is required but not found. Install with: sudo apt install git"
        ;;
    esac
  else
    fail "git is required but not found. Install with: sudo apt install git"
  fi
fi

# Validate install overrides BEFORE any clone/update (Task 4.2): invalid
# input fails fast with no side effects (no rm -rf, no re-clone) and the
# policy error is deterministic regardless of install-dir git state.
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
validate_bin_override

# Location guard (Task 1.1): /, $HOME and the empty string are never valid
# install dirs — the dispatch below may mv INSTALL_DIR aside, so this must
# be settled before any of it runs.
_install_dir_norm="${INSTALL_DIR%/}"
[ -z "$_install_dir_norm" ] && _install_dir_norm="/"
_install_home_norm="${HOME%/}"
if [ "$_install_dir_norm" = "/" ] \
  || { [ -n "$_install_home_norm" ] && [ "$_install_dir_norm" = "$_install_home_norm" ]; }; then
  fail "Refusing to use '${INSTALL_DIR}': not a valid install location."
fi
unset _install_dir_norm _install_home_norm

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
install_fresh_clone() {
  if [ "$CHANNEL" = "main" ]; then
    info "Channel main: cloning branch head from ${REPO_URL}..."
    git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
  else
    local tag
    tag="$(latest_release_tag "$REPO_URL")"
    [ -n "$tag" ] || fail "No release tags (vX.Y.Z) found at ${REPO_URL}."
    info "Channel stable: cloning release ${tag} from ${REPO_URL}..."
    git clone --depth 1 --branch "$tag" "$REPO_URL" "$INSTALL_DIR"
    verify_release_tag "$INSTALL_DIR" "$tag" || {
      rm -rf -- "$INSTALL_DIR"
      fail "Release tag '${tag}' failed verification — removed '${INSTALL_DIR}'."
    }
  fi
}

# (Re)create the checkout inside INSTALL_DIR without deleting anything:
# `git init` is a no-op on an existing repo and `checkout -f` touches
# tracked files only, so untracked state (history/) survives. Git aborts
# the checkout when a tracked path would clobber an untracked file —
# exactly the safe outcome for unexpected content.
reseed_checkout_in_place() {
  git -C "$INSTALL_DIR" init -q || return 1
  if git -C "$INSTALL_DIR" remote get-url origin >/dev/null 2>&1; then
    git -C "$INSTALL_DIR" remote set-url origin "$REPO_URL" || return 1
  else
    git -C "$INSTALL_DIR" remote add origin "$REPO_URL" || return 1
  fi
  if [ "$CHANNEL" = "main" ]; then
    git -C "$INSTALL_DIR" fetch --depth 1 origin \
      "+refs/heads/main:refs/remotes/origin/main" || return 1
    git -C "$INSTALL_DIR" checkout -q -f -B main origin/main || return 1
    git -C "$INSTALL_DIR" branch --set-upstream-to=origin/main main >/dev/null 2>&1 || true
  else
    local tag
    tag="$(latest_release_tag "$REPO_URL")"
    [ -n "$tag" ] || return 1
    info "Channel stable: fetching release ${tag}..."
    git -C "$INSTALL_DIR" fetch --depth 1 origin \
      "+refs/tags/${tag}:refs/tags/${tag}" || return 1
    git -C "$INSTALL_DIR" checkout -q -f "$tag" || return 1
    verify_release_tag "$INSTALL_DIR" "$tag" || return 1
  fi
}

# Fallback when in-place repair cannot work: rename the directory (a plain
# mv — nothing is deleted), clone fresh, then carry history/ forward from
# the moved-aside copy. If the clone fails the original directory is put
# back so no state is stranded.
move_aside_and_clone() {
  local backup backup_base n
  backup="${INSTALL_DIR}.moved-$(date +%Y%m%d%H%M%S)"
  backup_base="$backup"
  n=1
  while [ -e "$backup" ]; do
    backup="${backup_base}.${n}"
    n=$((n + 1))
  done
  mv "$INSTALL_DIR" "$backup" \
    || fail "Could not move '${INSTALL_DIR}' aside to '${backup}'."
  # Subshell so a fail() inside install_fresh_clone does not abort the
  # restore path below.
  if ( install_fresh_clone ); then
    info "Previous directory moved aside to ${backup}"
    if [ -d "${backup}/history" ] && [ ! -e "${INSTALL_DIR}/history" ]; then
      mv "${backup}/history" "${INSTALL_DIR}/history" \
        && info "Carried mdoctor history forward into ${INSTALL_DIR}/history"
    fi
  else
    # A leftover at INSTALL_DIR can only be output of the failed clone —
    # the original directory is safely at $backup.
    if [ -e "$INSTALL_DIR" ]; then rm -rf -- "$INSTALL_DIR"; fi
    mv "$backup" "$INSTALL_DIR"
    fail "Clone failed; restored '${INSTALL_DIR}' unchanged."
  fi
}

if [ -d "$INSTALL_DIR" ] \
  && git -C "$INSTALL_DIR" rev-parse --git-dir >/dev/null 2>&1 \
  && { [ -f "${INSTALL_DIR}/mdoctor" ] \
    || [ "$(git -C "$INSTALL_DIR" remote get-url origin 2>/dev/null)" = "$REPO_URL" ]; }; then
  info "Existing installation found at ${INSTALL_DIR}"
  if git -C "$INSTALL_DIR" describe --tags --exact-match >/dev/null 2>&1; then
    # Tag-pinned install (Task 4.1): move to the newest verified tag.
    info "Tag-pinned install detected — checking for newer release tags..."
    git -C "$INSTALL_DIR" fetch --tags --quiet origin 2>/dev/null || warn "Could not fetch tags."
    LATEST_TAG="$(latest_release_tag "$REPO_URL")"
    if [ -n "$LATEST_TAG" ]; then
      verify_release_tag "$INSTALL_DIR" "$LATEST_TAG" \
        || fail "Release tag '${LATEST_TAG}' failed verification."
      git -C "$INSTALL_DIR" checkout --quiet "$LATEST_TAG" 2>/dev/null || warn "Could not check out ${LATEST_TAG}."
    fi
  else
    info "Updating..."
    git -C "$INSTALL_DIR" pull --ff-only origin main 2>/dev/null || {
      warn "Could not fast-forward. Re-cloning..."
      reseed_checkout_in_place || move_aside_and_clone
    }
  fi
elif [ -d "$INSTALL_DIR" ]; then
  # Dir that is not an mdoctor checkout: adoptable only when every entry
  # is mdoctor-owned (empty dirs and e.g. history/ written by check runs);
  # foreign content is never merged into or deleted.
  if _dir_is_mdoctor_owned "$INSTALL_DIR"; then
    info "No checkout at ${INSTALL_DIR} — installing in place (existing mdoctor state is preserved)..."
    reseed_checkout_in_place || move_aside_and_clone
  else
    fail "Refusing to install over '${INSTALL_DIR}': not an mdoctor checkout and contains files mdoctor does not own. Move it aside (e.g. mv \"${INSTALL_DIR}\" \"${INSTALL_DIR}.bak\") and re-run."
  fi
elif [ -e "$INSTALL_DIR" ]; then
  fail "Refusing to install over '${INSTALL_DIR}': exists and is not a directory."
else
  install_fresh_clone
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
# (Override values were validated up front in pre-flight; see above.)
info "Creating symlink: ${BIN_DIR}/${BINARY_NAME} -> ${INSTALL_DIR}/mdoctor"

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
  echo "  mdoctor help       # Show all commands (read-only)"
  echo "  mdoctor check      # Run health audit (read-only)"
  echo "  mdoctor info       # Quick system overview (read-only)"
  echo "  mdoctor clean      # Preview cleanup (dry-run)"
  echo "  mdoctor fix all    # Preview common fixes [MED] (dry-run only)"
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
