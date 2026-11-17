# shellcheck shell=bash
# lib/ui.sh: what the user sees on screen, one line per module.
#
# Colour is used only when stdout is a terminal and NO_COLOR is unset.
# DOTFILES_COLOR=always|never overrides the terminal check (tests, CI);
# NO_COLOR (https://no-color.org) always wins.

_ui_color_enabled() {
  [[ -n "${NO_COLOR:-}" ]] && return 1
  case "${DOTFILES_COLOR:-auto}" in
    always) return 0 ;;
    never) return 1 ;;
    *) [[ -t 1 ]] ;;
  esac
}

_ui_paint() { # _ui_paint <ansi-code> <text>
  if _ui_color_enabled; then
    printf '\033[%sm%s\033[0m' "$1" "$2"
  else
    printf '%s' "$2"
  fi
}

# ui_status <status> <module> <seconds> [detail]
#   status: ok | fail | skipped | blocked
ui_status() {
  local status="$1" module="$2" seconds="$3" detail="${4:-}" mark
  case "$status" in
    ok) mark="$(_ui_paint 32 '✓')" ;;
    fail) mark="$(_ui_paint 31 '✗')" ;;
    blocked) mark="$(_ui_paint 31 '✗')"; detail="blocked by ${detail}" ;;
    skipped) mark="$(_ui_paint 33 '-')"; detail="skipped${detail:+: $detail}" ;;
    *)
      printf 'ui_status: unknown status "%s"\n' "$status" >&2
      return 1
      ;;
  esac
  printf '  %s %-16s %5ss%s\n' "$mark" "$module" "$seconds" "${detail:+   $detail}"
}

# ui_header <text...>: the run's first line.
ui_header() {
  printf '%s\n' "$(_ui_paint 1 "$*")"
}

# ui_error <text...>: message to stderr.
ui_error() {
  printf '%s %s\n' "$(_ui_paint 31 'error:')" "$*" >&2
}
