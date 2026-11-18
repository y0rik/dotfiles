#!/usr/bin/env bash
# install.sh: launcher for a fresh machine (also published as a gist).
#
#   bash -c "$(curl -fsSL <gist-url>/raw/install.sh)" -- [dotfiles flags]
#
# 1. checks the OS (Fedora or Ubuntu/Kubuntu)
# 2. installs git and curl with dnf/apt if missing
# 3. installs mise with its official installer if missing; needs >= MISE_MIN_VERSION
# 4. clones the repo to ~/.dotfiles, or fast-forwards an existing clone
# 5. links ~/.local/bin/dotfiles and runs it with the flags given here
#
# Exit codes are the runner's; 2 means the launcher stopped before running it.
#
# Overrides: DOTFILES_DIR (clone path), DOTFILES_REPO (clone URL),
# DOTFILES_BRANCH (branch), DOTFILES_OS_RELEASE (tests).

# Everything runs from main, called on the last line, so a partly downloaded
# script runs nothing.

set -euo pipefail

readonly MISE_MIN_VERSION="2026.10.10"

say() { printf '==> %s\n' "$*"; }
fail() { # fail <message>: stop before the runner, exit 2
  printf 'install.sh: error: %s\n' "$*" >&2
  exit 2
}

# os_id: ID from os-release, parsed (not sourced).
os_id() {
  local file="${DOTFILES_OS_RELEASE:-/etc/os-release}" line value
  [[ -r "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == ID=* ]] || continue
    value="${line#ID=}"
    value="${value#\"}"; value="${value%\"}"
    printf '%s\n' "$value"
    return 0
  done <"$file"
}

as_root() { # run a command as root: directly if we are root, else through sudo
  if ((EUID == 0)); then "$@"; else sudo "$@"; fi
}

install_prerequisites() {
  local os="$1" missing=() tool
  for tool in git curl; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
  done
  ((${#missing[@]})) || return 0
  say "installing ${missing[*]}"
  case "$os" in
    fedora) as_root dnf install -y "${missing[@]}" ;;
    ubuntu)
      as_root apt-get update
      as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}" ca-certificates
      ;;
  esac
}

mise_version() { mise --version 2>/dev/null | awk 'NR == 1 {print $1}'; }

version_ok() { # version_ok <version>: >= MISE_MIN_VERSION
  [[ -n "$1" && "$(printf '%s\n%s\n' "$MISE_MIN_VERSION" "$1" | sort -V | head -n1)" == "$MISE_MIN_VERSION" ]]
}

install_mise() {
  local version
  if ! command -v mise >/dev/null 2>&1; then
    say "installing mise (https://mise.run)"
    curl -fsSL https://mise.run | sh
    hash -r
    command -v mise >/dev/null 2>&1 || fail "mise was installed but is not on PATH"
  fi
  version="$(mise_version)"
  version_ok "$version" ||
    fail "mise ${version:-(unknown version)} at $(command -v mise) is too old; need $MISE_MIN_VERSION or newer (run: mise self-update)"
  say "mise $version"
}

sync_repo() {
  local dir="$1" repo="$2" branch="$3"
  if [[ ! -e "$dir" ]]; then
    say "cloning $repo ($branch) to $dir"
    git clone --branch "$branch" "$repo" "$dir"
    return 0
  fi
  git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
    fail "$dir exists and is not a git clone; move it away and re-run"
  if [[ -n "$(git -C "$dir" status --porcelain)" ]]; then
    fail "$dir has local changes; commit or stash them, then re-run"
  fi
  say "updating $dir"
  git -C "$dir" pull --ff-only ||
    fail "$dir can't be fast-forwarded; sort out the clone, then re-run"
}

link_runner() {
  local dir="$1" bin="$HOME/.local/bin"
  mkdir -p "$bin"
  if [[ -e "$bin/dotfiles" && ! -L "$bin/dotfiles" ]]; then
    fail "$bin/dotfiles exists and is not a link; move it away and re-run"
  fi
  ln -sfn "$dir/bin/dotfiles" "$bin/dotfiles"
}

main() {
  local os dir="${DOTFILES_DIR:-$HOME/.dotfiles}"
  local repo="${DOTFILES_REPO:-https://github.com/y0rik/dotfiles.git}"
  local branch="${DOTFILES_BRANCH:-main}"

  os="$(os_id)"
  case "$os" in
    fedora | ubuntu) ;;
    *) fail "unsupported OS \"${os:-unknown}\" (supported: Fedora, Ubuntu/Kubuntu)" ;;
  esac

  # mise's installer puts it here; make sure this run (and the runner) find it.
  local path_hint=0
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH"; path_hint=1 ;;
  esac

  install_prerequisites "$os"
  install_mise
  sync_repo "$dir" "$repo" "$branch"
  link_runner "$dir"

  if ((path_hint)); then
    say "$HOME/.local/bin is not on your PATH yet: open a new terminal (on Kubuntu, log out and back in) to use \`dotfiles\` directly"
  fi
  say "running: dotfiles $*"
  exec "$HOME/.local/bin/dotfiles" "$@"
}

main "$@"
