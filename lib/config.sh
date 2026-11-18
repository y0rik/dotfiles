# shellcheck shell=bash
# lib/config.sh: read dotfiles.toml, the central selection config.
#
# dotfiles.toml holds only selection, at most one of:
#   include = [...]   install ONLY these modules (and their dependencies)
#   exclude = [...]   install everything EXCEPT these modules
# Both empty means install everything. Any other key is an error, so a
# typo can't silently install everything.
#
# Requires lib/toml.sh.

declare -ga CONFIG_INCLUDE=()
declare -ga CONFIG_EXCLUDE=()

# config_load <file>: fill CONFIG_INCLUDE / CONFIG_EXCLUDE. Exit status 2 on any error.
config_load() {
  local file="$1" list
  CONFIG_INCLUDE=()
  CONFIG_EXCLUDE=()
  toml_check_keys "$file" include exclude || return 2

  list="$(toml_string_list "$file" include)" || return 2
  [[ -n "$list" ]] && mapfile -t CONFIG_INCLUDE <<<"$list"
  list="$(toml_string_list "$file" exclude)" || return 2
  [[ -n "$list" ]] && mapfile -t CONFIG_EXCLUDE <<<"$list"

  if ((${#CONFIG_INCLUDE[@]} && ${#CONFIG_EXCLUDE[@]})); then
    printf 'dotfiles: %s: set include OR exclude, not both\n' "$file" >&2
    return 2
  fi
  return 0
}
