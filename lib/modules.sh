# shellcheck shell=bash
# lib/modules.sh: find modules, check their dependencies, and decide what
# runs and in which order.
#
# A module is a folder modules/<id>/ (bootstrap phase) or
# post-bootstrap/<id>/ (post-bootstrap phase) that contains module.toml:
#   description = "..."          optional
#   depends     = ["base", ...]  optional; module ids
# Every folder there must be a module; the id is the folder name.
#
# Requires lib/toml.sh. Errors print to stderr and return 2.

# -g: these files are sourced from inside functions (tests), and must stay global.
declare -ga MOD_IDS=()   # all module ids, sorted
declare -gA MOD_PHASE=() # id -> bootstrap | post-bootstrap
declare -gA MOD_DEPS=()  # id -> space-separated direct dependencies

_mod_err() {
  printf 'dotfiles: %s\n' "$*" >&2
  return 2
}

_mod_valid_ids() {
  local joined
  joined="$(printf '%s, ' "${MOD_IDS[@]}")"
  printf '%s' "${joined%, }"
}

_mod_unknown() {
  _mod_err "unknown module \"$1\"${2:+ ($2)}. Valid modules: $(_mod_valid_ids)"
}

# modules_discover <repo-root>: load every module's metadata.
modules_discover() {
  local root="$1" dir phase path id deps ids=()
  MOD_IDS=()
  MOD_PHASE=()
  MOD_DEPS=()
  for dir in modules post-bootstrap; do
    phase="bootstrap"
    [[ "$dir" == post-bootstrap ]] && phase="post-bootstrap"
    [[ -d "$root/$dir" ]] || continue
    for path in "$root/$dir"/*/; do
      [[ -d "$path" ]] || continue
      id="$(basename "$path")"
      [[ "$id" =~ ^[a-z0-9][a-z0-9-]*$ ]] ||
        { _mod_err "$dir/$id: module ids use lowercase letters, digits and dashes"; return 2; }
      [[ -f "$path/module.toml" ]] ||
        { _mod_err "$dir/$id: missing module.toml"; return 2; }
      [[ -z "${MOD_PHASE[$id]:-}" ]] ||
        { _mod_err "module \"$id\" exists in both modules/ and post-bootstrap/"; return 2; }
      toml_check_keys "$path/module.toml" description depends || return 2
      deps="$(toml_string_list "$path/module.toml" depends)" || return 2
      MOD_PHASE[$id]="$phase"
      MOD_DEPS[$id]="$(printf '%s' "$deps" | tr '\n' ' ')"
      ids+=("$id")
    done
  done
  ((${#ids[@]})) && mapfile -t MOD_IDS < <(printf '%s\n' "${ids[@]}" | sort)
  _modules_check_deps
}

# Every dependency must exist, and a bootstrap module can't depend on a
# post-bootstrap one (post-bootstrap runs later and needs secrets).
_modules_check_deps() {
  local id dep
  for id in "${MOD_IDS[@]}"; do
    for dep in ${MOD_DEPS[$id]}; do
      [[ -n "${MOD_PHASE[$dep]:-}" ]] || { _mod_unknown "$dep" "in depends of $id"; return 2; }
      [[ "$dep" != "$id" ]] || { _mod_err "module \"$id\" depends on itself"; return 2; }
      if [[ "${MOD_PHASE[$id]}" == bootstrap && "${MOD_PHASE[$dep]}" == post-bootstrap ]]; then
        _mod_err "bootstrap module \"$id\" can't depend on post-bootstrap module \"$dep\""
        return 2
      fi
    done
  done
}

# _modules_closure <id>...: print the ids plus all their dependencies.
_modules_closure() {
  local -A seen=()
  local -a stack=("$@")
  local id dep
  while ((${#stack[@]})); do
    id="${stack[-1]}"
    unset 'stack[-1]'
    [[ -n "${seen[$id]:-}" ]] && continue
    seen[$id]=1
    for dep in ${MOD_DEPS[$id]}; do stack+=("$dep"); done
  done
  ((${#seen[@]})) && printf '%s\n' "${!seen[@]}" | sort
}

# _modules_order <id>...: dependency-first order, ties alphabetical.
# Fails (2) on a dependency cycle.
_modules_order() {
  local -A selected=() pending=()
  local id dep ready next out=() n
  for id in "$@"; do selected[$id]=1; done
  for id in "$@"; do
    n=0
    for dep in ${MOD_DEPS[$id]}; do [[ -n "${selected[$dep]:-}" ]] && n=$((n + 1)); done
    pending[$id]=$n
  done
  while ((${#pending[@]})); do
    ready=""
    for id in "${!pending[@]}"; do
      ((pending[$id] == 0)) && ready+="$id"$'\n'
    done
    if [[ -z "$ready" ]]; then
      _mod_err "dependency cycle between: $(printf '%s\n' "${!pending[@]}" | sort | tr '\n' ' ')"
      return 2
    fi
    next="$(printf '%s' "$ready" | sort | head -n1)"
    out+=("$next")
    unset 'pending[$next]'
    for id in "${!pending[@]}"; do
      for dep in ${MOD_DEPS[$id]}; do
        [[ "$dep" == "$next" ]] && pending[$id]=$((pending[$id] - 1))
      done
    done
  done
  printf '%s\n' "${out[@]}"
}

# modules_select <phase> [only-csv]
#   Uses CONFIG_INCLUDE / CONFIG_EXCLUDE (lib/config.sh); a non-empty
#   only-csv (the --only flag) replaces both for this run.
#   Prints the modules of <phase> to apply, in order, one per line.
#   Dependencies in an earlier phase are assumed applied and not printed.
modules_select() {
  local phase="$1" only="${2:-}" id dep mode="all"
  local -a requested=() excluded=() chosen=() ordered=()
  case "$phase" in
    bootstrap | post-bootstrap) ;;
    *) _mod_err "unknown phase \"$phase\""; return 2 ;;
  esac

  if [[ -n "$only" ]]; then
    IFS=',' read -r -a requested <<<"$only"
    mode="include"
  elif ((${#CONFIG_INCLUDE[@]})); then
    requested=("${CONFIG_INCLUDE[@]}")
    mode="include"
  elif ((${#CONFIG_EXCLUDE[@]})); then
    excluded=("${CONFIG_EXCLUDE[@]}")
    mode="exclude"
  fi

  for id in "${requested[@]}" "${excluded[@]}"; do
    [[ -n "${MOD_PHASE[$id]:-}" ]] || { _mod_unknown "$id"; return 2; }
  done

  case "$mode" in
    all) chosen=("${MOD_IDS[@]}") ;;
    include) mapfile -t chosen < <(_modules_closure "${requested[@]}") ;;
    exclude)
      local -A is_excluded=()
      for id in "${excluded[@]}"; do is_excluded[$id]=1; done
      for id in "${MOD_IDS[@]}"; do
        [[ -n "${is_excluded[$id]:-}" ]] && continue
        while IFS= read -r dep; do
          if [[ -n "${is_excluded[$dep]:-}" ]]; then
            _mod_err "\"$id\" depends on excluded module \"$dep\"; exclude \"$id\" too or keep \"$dep\""
            return 2
          fi
        done < <(_modules_closure "$id")
        chosen+=("$id")
      done
      ;;
  esac

  ((${#chosen[@]})) || return 0
  local order
  order="$(_modules_order "${chosen[@]}")" || return 2
  mapfile -t ordered <<<"$order"
  for id in "${ordered[@]}"; do
    [[ "${MOD_PHASE[$id]}" == "$phase" ]] && printf '%s\n' "$id"
  done
  return 0
}
