# shellcheck shell=bash
# lib/log.sh: one log file per run, with each module's output framed.
#
# Logs live in ~/.dotfiles_log/, next to the repo clone (~/.dotfiles) and
# outside it, so deleting and re-cloning the repo keeps old logs.
# Override the directory with DOTFILES_LOG_DIR (tests).

DOTFILES_LOG_FILE="${DOTFILES_LOG_FILE:-}"

# log_init <phase>: create the log directory and this run's log file.
# Sets DOTFILES_LOG_FILE and prints its path.
log_init() {
  local phase="${1:?log_init: phase required}" dir stamp file n=1
  dir="${DOTFILES_LOG_DIR:-$HOME/.dotfiles_log}"
  mkdir -p "$dir" || {
    printf 'dotfiles: cannot create log directory %s\n' "$dir" >&2
    return 1
  }
  stamp="$(date +%Y-%m-%dT%H-%M-%S)"
  file="$dir/$stamp-$phase.log"
  # Two runs in the same second must not share a file.
  while [[ -e "$file" ]]; do
    file="$dir/$stamp-$phase.$n.log"
    n=$((n + 1))
  done
  : >"$file" || return 1
  DOTFILES_LOG_FILE="$file"
  printf '%s\n' "$file"
}

_log_require() {
  if [[ -z "$DOTFILES_LOG_FILE" ]]; then
    printf 'dotfiles: log_init was not called\n' >&2
    return 1
  fi
}

# log_line <text...>: append one timestamped line.
log_line() {
  _log_require || return 1
  printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >>"$DOTFILES_LOG_FILE"
}

# log_module_start <id>
log_module_start() {
  _log_require || return 1
  printf '=== %s START %s ===\n' "${1:?module id required}" "$(date +%Y-%m-%dT%H:%M:%S)" >>"$DOTFILES_LOG_FILE"
}

# log_module_end <id> <status>  (status: ok | fail | skipped | blocked)
log_module_end() {
  _log_require || return 1
  printf '=== %s END %s ===\n' "${1:?module id required}" "${2:?status required}" >>"$DOTFILES_LOG_FILE"
}

# log_capture: append stdin to the log unchanged (command output).
log_capture() {
  _log_require || return 1
  cat >>"$DOTFILES_LOG_FILE"
}
