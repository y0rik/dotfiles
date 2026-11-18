# shellcheck shell=bash
# lib/toml.sh: read TOML files with mikefarah's yq (v4).
#
# yq must be mikefarah's Go yq. Ubuntu's apt package "yq" is a different,
# incompatible tool, so a yq on PATH is used only if it identifies itself
# as mikefarah's; otherwise mise (always installed by the launcher) runs it.
# Override with DOTFILES_YQ="<command>" (tests).

_TOML_YQ=()

_toml_resolve_yq() {
  ((${#_TOML_YQ[@]})) && return 0
  if [[ -n "${DOTFILES_YQ:-}" ]]; then
    read -r -a _TOML_YQ <<<"$DOTFILES_YQ"
  elif command -v yq >/dev/null 2>&1 && yq --version 2>/dev/null | grep -q mikefarah; then
    _TOML_YQ=(yq)
  elif command -v mise >/dev/null 2>&1; then
    _TOML_YQ=(mise exec yq@4 -- yq)
  else
    printf 'dotfiles: need mikefarah/yq v4 or mise to read TOML\n' >&2
    return 2
  fi
}

# toml_query <file> <yq-expression>: print the result (YAML scalars, one per line).
# Exit status 2 on a missing or malformed file.
toml_query() {
  local file="$1" expr="$2" out
  _toml_resolve_yq || return 2
  if [[ ! -r "$file" ]]; then
    printf 'dotfiles: cannot read %s\n' "$file" >&2
    return 2
  fi
  if ! out="$("${_TOML_YQ[@]}" -p toml -o yaml "$expr" "$file" 2>&1)"; then
    printf 'dotfiles: %s is not valid TOML: %s\n' "$file" "$out" >&2
    return 2
  fi
  printf '%s\n' "$out"
}

# toml_check_keys <file> <allowed-key>...: fail (2) on any top-level key not allowed.
# Catches typos such as "includes = [...]", which would otherwise be ignored.
toml_check_keys() {
  local file="$1" key allowed found
  shift
  toml_query "$file" '.' >/dev/null || return 2
  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    found=0
    for allowed in "$@"; do [[ "$key" == "$allowed" ]] && found=1; done
    if ((!found)); then
      printf 'dotfiles: %s: unknown setting "%s" (allowed: %s)\n' "$file" "$key" "$*" >&2
      return 2
    fi
  done < <(toml_query "$file" '(. // {}) | keys | .[]')
}

# toml_string_list <file> <key>: print a list of strings, one per line.
# Missing key → nothing. Not a list, or a non-string element → exit 2.
toml_string_list() {
  local file="$1" key="$2" type bad
  type="$(toml_query "$file" ".\"$key\" | type")" || return 2
  case "$type" in
    '!!null') return 0 ;;
    '!!seq') ;;
    *)
      printf 'dotfiles: %s: "%s" must be a list of strings, e.g. %s = ["a", "b"]\n' "$file" "$key" "$key" >&2
      return 2
      ;;
  esac
  bad="$(toml_query "$file" "[.\"$key\"[] | select(type != \"!!str\")] | length")" || return 2
  if [[ "$bad" != 0 ]]; then
    printf 'dotfiles: %s: "%s" must contain only strings\n' "$file" "$key" >&2
    return 2
  fi
  toml_query "$file" ".\"$key\"[]" | sed '/^\[\]$/d'
}
