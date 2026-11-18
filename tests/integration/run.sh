#!/usr/bin/env bash
# Integration check, run inside a fresh fedora:latest / ubuntu:rolling container
# with the repo mounted read-only at /src and the commit under test on branch
# ci-under-test (see .github/workflows/ci.yml):
#   1. install.sh from scratch: git/curl, mise, clone, runner → exit 0
#   2. every applied module has nothing left to change (mise bootstrap plan)
#   3. a second run exits 0
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
  printf '  %-16s %s\n' "$id" "$summary"
  if [[ ! "$summary" =~ ^0\ create,\ 0\ update,\ [0-9]+\ unchanged,\ 0\ remove ]]; then
    printf '%s\n' "$plan"
    changed=1
  fi
done
((changed == 0)) || { echo "FAILED: modules still have changes after a run (virtual package name?)"; exit 1; }

echo "## run 2: re-run"
dotfiles --bootstrap --yes --config "$config"
