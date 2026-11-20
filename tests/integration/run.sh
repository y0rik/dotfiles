#!/usr/bin/env bash
# Integration check, run inside a fresh fedora:latest / ubuntu:rolling container
# with the repo mounted read-only at /src and the commit under test on branch
# ci-under-test (see .github/workflows/ci.yml):
#   1. install.sh from scratch: git/curl, mise, clone, runner → exit 0
#   2. every applied module has nothing left to change: `bootstrap plan` shows
#      no package changes and `bootstrap status --missing` passes (tools, dotfiles)
#   3. second and third runs exit 0
#   4. module "bash": ~/.bashrc has the include line once; a new interactive
#      shell has ~/.local/bin on PATH, mise activated and the oh-my-posh prompt
set -euo pipefail

export DOTFILES_REPO=/src DOTFILES_BRANCH=ci-under-test
# /src belongs to another uid; let git clone from it.
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0='*'
config=/src/tests/integration/dotfiles.ci.toml

show_logs() {
  local f
  for f in "$HOME"/.dotfiles_log/*.log; do
    [[ -f "$f" ]] || continue
    printf '\n----- %s -----\n' "$f"
    cat "$f"
  done
}
on_exit() {
  local rc=$?
  ((rc == 0)) || show_logs
  return "$rc"
}
trap on_exit EXIT

echo "## run 1: fresh install"
bash /src/install.sh --bootstrap --yes --config "$config"

export PATH="$HOME/.local/bin:$PATH"
miserc="$HOME/.config/mise/miserc.local.toml"
mapfile -t ids < <(sed -n 's/^env = \[\(.*\)\]$/\1/p' "$miserc" | tr -d '" ' | tr ',' '\n' | sed '/^$/d')
((${#ids[@]})) || { echo "no modules were applied"; exit 1; }

echo "## nothing left to change after run 1"
changed=0
for id in "${ids[@]}"; do
  plan="$(cd "$HOME" && mise -E "$id" bootstrap plan 2>&1)"
  summary="$(printf '%s\n' "$plan" | sed -n 's/^Plan: //p')"
  # plan covers system packages only; a module without any says so.
  if [[ -z "$summary" && "$plan" == *"nothing configured for bootstrap planning"* ]]; then
    summary="no packages"
  elif [[ ! "$summary" =~ ^0\ create,\ 0\ update,\ [0-9]+\ unchanged,\ 0\ remove ]]; then
    printf '%s\n' "$plan"
    changed=1
  fi
  if ! status="$(cd "$HOME" && NO_COLOR=1 mise -E "$id" bootstrap status --missing 2>&1)"; then
    printf '%s\n' "$status"
    summary+=" · status: something missing"
    changed=1
  fi
  printf '  %-16s %s\n' "$id" "$summary"
done
((changed == 0)) || { echo "FAILED: modules still have changes after a run (virtual package name?)"; exit 1; }

echo "## runs 2 and 3: re-run"
dotfiles --bootstrap --yes --config "$config"
dotfiles --bootstrap --yes --config "$config"

if [[ " ${ids[*]} " == *" bash "* ]]; then
  echo "## module bash: ~/.bashrc and a new shell"
  count="$(grep -c '\.bash_bootstrap' "$HOME/.bashrc")"
  ((count == 1)) || { echo "FAILED: ~/.bashrc has the .bash_bootstrap line $count times"; exit 1; }
  # A clean environment, as in a new terminal: only ~/.bashrc sets things up.
  # shellcheck disable=SC2016 # expands in the new shell
  env -i HOME="$HOME" PATH=/usr/bin:/bin TERM=dumb bash -ic '
    fail() { echo "FAILED: new shell: $*"; exit 1; }
    case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) fail "~/.local/bin not on PATH" ;; esac
    command -v dotfiles >/dev/null || fail "dotfiles not found"
    declare -F _mise_hook >/dev/null || fail "mise not activated"
    command -v oh-my-posh >/dev/null || fail "oh-my-posh not on PATH"
    [[ "${POSH_SHELL:-}" == bash ]] || fail "oh-my-posh prompt not set up"
    complete -p mise >/dev/null 2>&1 || fail "no mise completion"
    echo "  new shell: PATH, mise, completion, oh-my-posh ok"
  ' 2>&1 | grep -v -e 'cannot set terminal process group' -e 'no job control'
fi
