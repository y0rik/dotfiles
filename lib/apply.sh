# shellcheck shell=bash
# lib/apply.sh: apply selected modules with mise, one module per call.
#
# How a module is applied (see agentic.md, "How a run works"):
#   1. ~/.config/mise/conf.d/ holds one link per module (conf.d/<id> -> module folder).
#   2. Each module's mise file is mise.<id>.toml, loaded only under env <id>.
#   3. `mise -E <id> bootstrap --yes` applies just that module.
#   4. `mise -E <id> bootstrap status --missing` confirms nothing is left.
#
# Requires lib/modules.sh, lib/log.sh and lib/ui.sh, and DOTFILES_ROOT.

declare -gA APPLY_STATUS=() # id -> ok | fail | skipped | blocked (whole run, both phases)
declare -ga APPLY_FAILED=() APPLY_BLOCKED=() APPLY_SKIPPED=() APPLY_OK=()
declare -g APPLY_DRY_RUN=0
declare -g APPLY_MISE_DIR="" # config dir mise reads during this run (temporary in a dry run)

# Exit code a module uses for "does not apply on this machine".
readonly APPLY_EXIT_SKIP=3

# mise's own config directory (where conf.d/ and miserc.local.toml live).
apply_mise_config_dir() {
  printf '%s\n' "${MISE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/mise}"
}

_apply_module_dir() {
  local sub=modules
  [[ "${MOD_PHASE[$1]}" == post-bootstrap ]] && sub=post-bootstrap
  printf '%s/%s/%s\n' "$DOTFILES_ROOT" "$sub" "$1"
}

# _apply_is_ours <link>: the link points into this repo's module folders.
_apply_is_ours() {
  local target
  target="$(readlink "$1")" || return 1
  [[ "$target" == "$DOTFILES_ROOT/modules/"* || "$target" == "$DOTFILES_ROOT/post-bootstrap/"* ]]
}

# apply_managed_ids: ids that currently have a link from this repo in conf.d.
apply_managed_ids() {
  local confd link
  confd="$(apply_mise_config_dir)/conf.d"
  [[ -d "$confd" && ! -L "$confd" ]] || return 0
  for link in "$confd"/*; do
    [[ -L "$link" ]] || continue
    _apply_is_ours "$link" || continue
    # Only modules that still exist; links to removed modules are dropped.
    [[ -n "${MOD_PHASE[$(basename "$link")]:-}" ]] && basename "$link"
  done
  return 0
}

# apply_check_links <id>...: fail (2) before changing anything if a link
# can't be created because something else is in the way.
apply_check_links() {
  local confd id
  confd="$(apply_mise_config_dir)/conf.d"
  # An older layout linked the whole conf.d folder; apply_links replaces it.
  [[ -L "$confd" ]] && return 0
  if [[ -e "$confd" && ! -d "$confd" ]]; then
    ui_error "$confd exists and is not a folder; move it away and re-run"
    return 2
  fi
  for id in "$@"; do
    if [[ -e "$confd/$id" || -L "$confd/$id" ]] && ! { [[ -L "$confd/$id" ]] && _apply_is_ours "$confd/$id"; }; then
      ui_error "$confd/$id exists and is not a dotfiles module link; move it away and re-run"
      return 2
    fi
  done
}

# apply_links <confd> <id>...: make <confd> hold exactly one link per given
# module (plus any files that aren't ours, which are left alone).
apply_links() {
  local confd="$1" link id
  shift
  # An older layout linked the whole conf.d folder; replace that link with a folder.
  if [[ -L "$confd" ]]; then rm -f "$confd" || return 1; fi
  mkdir -p "$confd" || return 1
  for link in "$confd"/*; do
    [[ -L "$link" ]] || continue
    _apply_is_ours "$link" || continue
    rm -f "$link" || return 1
  done
  for id in "$@"; do
    ln -sfn "$(_apply_module_dir "$id")" "$confd/$id" || return 1
  done
}

# apply_save_env <id>...: save the module list as mise's active envs, so their
# tools are on PATH in every shell. Owns only the `env = [...]` line of
# miserc.local.toml; other lines are kept.
apply_save_env() {
  local file line list="" id tmp
  file="$(apply_mise_config_dir)/miserc.local.toml"
  for id in "$@"; do list+="\"$id\", "; done
  tmp="$(mktemp "$file.XXXXXX")" || return 1
  {
    printf 'env = [%s]\n' "${list%, }"
    if [[ -f "$file" ]]; then
      while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*env[[:space:]]*= ]] && continue
        printf '%s\n' "$line"
      done <"$file"
    fi
  } >"$tmp" && mv -f "$tmp" "$file"
}

# _apply_detail <output-file> <kind>: one short reason for the status line.
#   skip: text after the last "SKIP:" line (modules print it before exit 3)
#   fail: the first [tools] entry mise marked ✗ ("node@26: <its stderr>"); else the
#         last error-looking line from the tool mise ran (dnf, apt, a task),
#         skipping mise's progress bars; else mise's own last ERROR line, minus
#         its generic footer ("Version: …", "Run with --verbose …"); else the
#         last line.
_apply_detail() {
  local file="$1" kind="$2" line="" tool msg
  # sed, not grep: "no match" must not count as an error under set -e.
  if [[ "$kind" == skip ]]; then
    line="$(sed -n -E 's/.*SKIP:[[:space:]]*//p' "$file" | tail -n1)"
  else
    # The first ✗ is the cause; later ones are often "Skipped due to failed dependency".
    line="$(sed -n -E '/failed: Skipped due to failed dependency/d; s/^mise ✗ ([^ ]+) .*failed: /\1 /p' "$file" | head -n1)"
    if [[ -n "$line" ]]; then
      tool="${line%% *}" msg="${line#* }"
      [[ "$msg" == *"last stderr: "* ]] && msg="${msg##*last stderr: }"
      [[ "$msg" =~ ^/[^\ ]*:\ (.*)$ ]] && msg="${BASH_REMATCH[1]}" # drop "/path/to/bin: "
      line="$tool: $msg"
    fi
    [[ -n "$line" ]] || line="$(sed -n -E '/^mise ERROR/d; /█|░/d; /^E: |[Ee][Rr][Rr][Oo][Rr]|[Ff]ailed|[Nn]o match|[Nn]ot found|[Uu]nable|[Cc]annot/p' "$file" | tail -n1)"
    [[ -n "$line" ]] || line="$(sed -n -E '/^mise ERROR (Version:|Run with)/d; /^mise ERROR/p' "$file" | tail -n1)"
    [[ -n "$line" ]] || line="$(sed -n '/[^[:space:]]/p' "$file" | tail -n1)"
  fi
  line="${line#"${line%%[![:space:]]*}"}"
  ((${#line} > 100)) && line="${line:0:97}..."
  printf '%s' "$line"
}

# _apply_mise <output-file> <args...>: run mise from $HOME (so no project
# config is picked up), output appended to <output-file> without colour.
_apply_mise() {
  local out="$1"
  shift
  (cd "$HOME" && NO_COLOR=1 MISE_CONFIG_DIR="$APPLY_MISE_DIR" mise "$@") >>"$out" 2>&1
}

# _apply_dep_problem <id>: print "<status> <dep>" for the first dependency
# that failed, was blocked or was skipped in this run.
_apply_dep_problem() {
  local dep st
  for dep in ${MOD_DEPS[$1]}; do
    st="${APPLY_STATUS[$dep]:-}"
    case "$st" in
      fail | blocked | skipped) printf '%s %s\n' "$st" "$dep"; return 0 ;;
    esac
  done
  return 1
}

_apply_record() { # _apply_record <id> <status> <seconds> [detail]
  APPLY_STATUS[$1]="$2"
  case "$2" in
    ok) APPLY_OK+=("$1") ;;
    fail) APPLY_FAILED+=("$1") ;;
    blocked) APPLY_BLOCKED+=("$1") ;;
    skipped) APPLY_SKIPPED+=("$1") ;;
  esac
  log_module_end "$1" "$2"
  [[ -n "${4:-}" ]] && log_line "$1: $2: $4"
  _apply_live_clear
  ui_status "$2" "$1" "$3" "${4:-}"
}

_apply_live() { [[ -t 1 ]] && printf '  … %s' "$1"; return 0; }
_apply_live_clear() { [[ -t 1 ]] && printf '\r\033[K'; return 0; }

# apply_module <id>: apply one module and record its status.
apply_module() {
  local id="$1" out rc=0 missing=0 start problem warn detail
  log_module_start "$id"

  if problem="$(_apply_dep_problem "$id")"; then
    case "${problem%% *}" in
      skipped) _apply_record "$id" skipped 0 "needs ${problem#* }, which was skipped" ;;
      *) _apply_record "$id" blocked 0 "${problem#* }" ;;
    esac
    return 0
  fi

  _apply_live "$id"
  start=$SECONDS
  out="$(mktemp)" || return 1
  local -a args=(-E "$id" bootstrap --yes)
  ((APPLY_DRY_RUN)) && args+=(--dry-run)
  printf '$ mise %s\n' "${args[*]}" >>"$out"
  _apply_mise "$out" "${args[@]}" || rc=$?

  # mise only warns about some config mistakes and then carries on without
  # that part of the module. Treat them as failures.
  warn="$(sed -n -E '/WARN.*(unknown field|is required)/p' "$out" | tail -n1)"

  if ((rc == 0 && APPLY_DRY_RUN == 0)) && [[ -z "$warn" ]]; then
    printf '$ mise -E %s bootstrap status --missing\n' "$id" >>"$out"
    _apply_mise "$out" -E "$id" bootstrap status --missing || missing=1
  fi
  log_capture <"$out"

  if [[ -n "$warn" ]]; then
    detail="${warn#*WARN}"
    detail="config warning: ${detail#"${detail%%[![:space:]]*}"}"
    _apply_record "$id" fail $((SECONDS - start)) "$detail"
  elif ((rc == 0 && missing)); then
    _apply_record "$id" fail $((SECONDS - start)) "still missing after apply (see log)"
  elif ((rc == 0)); then
    _apply_record "$id" ok $((SECONDS - start))
  elif ((rc == APPLY_EXIT_SKIP)); then
    _apply_record "$id" skipped $((SECONDS - start)) "$(_apply_detail "$out" skip)"
  else
    _apply_record "$id" fail $((SECONDS - start)) "$(_apply_detail "$out" fail)"
  fi
  rm -f "$out"
}

_apply_noun() { if (($1 == 1)); then printf 'module'; else printf 'modules'; fi; }

# apply_reset_phase: start counting a new phase (statuses of earlier phases
# are kept, so a post-bootstrap module sees a failed bootstrap dependency).
apply_reset_phase() {
  APPLY_OK=() APPLY_FAILED=() APPLY_BLOCKED=() APPLY_SKIPPED=()
}

# apply_summary <total>: the run's last line. Returns 1 if anything failed.
apply_summary() {
  local total="$1" failed blocked msg noun
  noun="$(_apply_noun "$total")"
  if ((${#APPLY_FAILED[@]} + ${#APPLY_BLOCKED[@]})); then
    failed="$(printf '%s, ' "${APPLY_FAILED[@]}")"
    msg="FAILED: ${#APPLY_FAILED[@]} of $total $noun (${failed%, })"
    if ((${#APPLY_BLOCKED[@]})); then
      blocked="$(printf '%s, ' "${APPLY_BLOCKED[@]}")"
      msg+="; blocked: ${blocked%, }"
    fi
    printf '%s. See log.\n' "$(_ui_paint 31 "$msg")"
    log_line "$msg"
    return 1
  fi
  msg="OK: $total $noun"
  ((${#APPLY_SKIPPED[@]})) && msg+=" (${#APPLY_SKIPPED[@]} skipped)"
  printf '%s\n' "$(_ui_paint 32 "$msg")"
  log_line "$msg"
}
