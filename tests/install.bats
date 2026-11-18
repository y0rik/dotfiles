#!/usr/bin/env bats
# Tests for install.sh (the gist launcher), offline: the "upstream" repo is a
# local fixture whose bin/dotfiles only records how it was called.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export DOTFILES_OS_RELEASE="$REPO/tests/fixtures/os-release/fedora"
  export STUB_MISE_LOG="$BATS_TEST_TMPDIR/mise.calls"
  export RUNNER_LOG="$BATS_TEST_TMPDIR/runner.calls"
  SYSTEM_PATH="$PATH"
  export PATH="$REPO/tests/stubs:$PATH"
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
  export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
  unset DOTFILES_DIR DOTFILES_BRANCH

  UPSTREAM="$BATS_TEST_TMPDIR/upstream"
  mkdir -p "$UPSTREAM/bin"
  cat >"$UPSTREAM/bin/dotfiles" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$RUNNER_LOG"
exit "${FIXTURE_EXIT:-0}"
SH
  chmod +x "$UPSTREAM/bin/dotfiles"
  git -C "$UPSTREAM" -c init.defaultBranch=main init -q
  git -C "$UPSTREAM" add -A
  git -C "$UPSTREAM" commit -q -m initial
  export DOTFILES_REPO="$UPSTREAM"
}

launcher() { bash "$REPO/install.sh" "$@"; }

@test "fresh machine: clones, links dotfiles into ~/.local/bin, runs it with the flags" {
  run launcher --bootstrap --yes --only base
  [ "$status" -eq 0 ]
  [ -d "$HOME/.dotfiles/.git" ]
  [ "$(readlink "$HOME/.local/bin/dotfiles")" = "$HOME/.dotfiles/bin/dotfiles" ]
  [ "$(cat "$RUNNER_LOG")" = "--bootstrap --yes --only base" ]
}

@test "the runner's exit code is the launcher's exit code" {
  FIXTURE_EXIT=1 run launcher --bootstrap
  [ "$status" -eq 1 ]
}

@test "DOTFILES_BRANCH picks the branch to clone" {
  git -C "$UPSTREAM" checkout -q -b develop
  printf 'dev\n' >"$UPSTREAM/DEV"
  git -C "$UPSTREAM" add -A && git -C "$UPSTREAM" commit -q -m dev
  git -C "$UPSTREAM" checkout -q main
  DOTFILES_BRANCH=develop run launcher
  [ "$status" -eq 0 ]
  [ -f "$HOME/.dotfiles/DEV" ]
}

@test "re-run: pulls new commits instead of re-cloning" {
  run launcher
  printf 'new\n' >"$UPSTREAM/NEW"
  git -C "$UPSTREAM" add -A && git -C "$UPSTREAM" commit -q -m new
  run launcher
  [ "$status" -eq 0 ]
  [ -f "$HOME/.dotfiles/NEW" ]
  [[ "$output" == *"updating $HOME/.dotfiles"* ]]
  [ "$(wc -l <"$RUNNER_LOG")" -eq 2 ]
}

@test "re-run with local changes in the clone: exit 2, runner not started" {
  run launcher
  printf 'edit\n' >>"$HOME/.dotfiles/bin/dotfiles"
  run launcher
  [ "$status" -eq 2 ]
  [[ "$output" == *"has local changes"* ]]
  [ "$(wc -l <"$RUNNER_LOG")" -eq 1 ]
}

@test "~/.dotfiles that isn't a git clone: exit 2" {
  mkdir -p "$HOME/.dotfiles"
  run launcher
  [ "$status" -eq 2 ]
  [[ "$output" == *"is not a git clone"* ]]
}

@test "a real file at ~/.local/bin/dotfiles: exit 2, left alone" {
  mkdir -p "$HOME/.local/bin"
  printf 'mine\n' >"$HOME/.local/bin/dotfiles"
  run launcher
  [ "$status" -eq 2 ]
  [ "$(cat "$HOME/.local/bin/dotfiles")" = "mine" ]
  [ ! -e "$RUNNER_LOG" ]
}

@test "unsupported OS: exit 2 before installing or cloning anything" {
  DOTFILES_OS_RELEASE="$REPO/tests/fixtures/os-release/arch" run launcher
  [ "$status" -eq 2 ]
  [[ "$output" == *'unsupported OS "arch"'* ]]
  [ ! -e "$HOME/.dotfiles" ]
  [ ! -s "$STUB_MISE_LOG" ]
}

@test "mise older than the minimum: exit 2 before cloning" {
  STUB_MISE_VERSION=2026.9.1 run launcher
  [ "$status" -eq 2 ]
  [[ "$output" == *"too old; need 2026.10.10"* ]]
  [ ! -e "$HOME/.dotfiles" ]
}

@test "no mise: installs it with the official installer and finds it in ~/.local/bin" {
  PATH="$SYSTEM_PATH" command -v mise >/dev/null && skip "a real mise is on PATH"
  fake="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$fake"
  # Stub curl: "downloads" an installer that drops the stub mise into ~/.local/bin.
  cat >"$fake/curl" <<SH
#!/usr/bin/env bash
printf 'curl %s\n' "\$*" >>"$BATS_TEST_TMPDIR/curl.calls"
printf 'mkdir -p "\$HOME/.local/bin" && cp "%s" "\$HOME/.local/bin/mise"\n' "$REPO/tests/stubs/mise"
SH
  chmod +x "$fake/curl"
  PATH="$fake:$SYSTEM_PATH" run launcher --yes
  [ "$status" -eq 0 ]
  grep -q 'curl -fsSL https://mise.run' "$BATS_TEST_TMPDIR/curl.calls"
  [ -x "$HOME/.local/bin/mise" ]
  [ "$(cat "$RUNNER_LOG")" = "--yes" ]
}
