#!/usr/bin/env bats
# Tests for bin/dotfiles with a stub mise (tests/stubs/mise).

setup() {
  load helpers
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  ROOT="$BATS_TEST_TMPDIR/repo"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$ROOT" "$HOME"
  unset MISE_CONFIG_DIR XDG_CONFIG_HOME NO_COLOR
  export DOTFILES_ROOT="$ROOT"
  export DOTFILES_LOG_DIR="$HOME/.dotfiles_log"
  export DOTFILES_OS_RELEASE="$REPO/tests/fixtures/os-release/fedora"
  export DOTFILES_COLOR=never
  export STUB_MISE_LOG="$BATS_TEST_TMPDIR/mise.calls"
  export STUB_SUDO_LOG="$BATS_TEST_TMPDIR/sudo.calls"
  export PATH="$REPO/tests/stubs:$PATH"
  : >"$STUB_MISE_LOG"
  MISE_DIR="$HOME/.config/mise"

  # base, cli -> base, docker -> base, kubernetes -> docker,
  # ssh (post) -> base, git-signing (post) -> ssh
  mkmod "$ROOT" bootstrap base
  mkmod "$ROOT" bootstrap cli base
  mkmod "$ROOT" bootstrap docker base
  mkmod "$ROOT" bootstrap kubernetes docker
  mkmod "$ROOT" post-bootstrap ssh base
  mkmod "$ROOT" post-bootstrap git-signing ssh
  write_config "$ROOT/dotfiles.toml" 'include = []'
}

dotfiles() { "$REPO/bin/dotfiles" "$@"; }

# applied: the module ids mise was asked to bootstrap, in order, space-joined.
applied() {
  sed -n -E 's/.* -E ([a-z0-9-]+) bootstrap --yes.*/\1/p' "$STUB_MISE_LOG" | tr '\n' ' ' | sed 's/ $//'
}

links() { (cd "$MISE_DIR/conf.d" && ls) | tr '\n' ' ' | sed 's/ $//'; }

# --- statuses, summary, exit code -------------------------------------------------

@test "all modules succeed: ✓ per module, OK summary, exit 0" {
  run dotfiles --bootstrap
  [ "$status" -eq 0 ]
  [[ "$output" == *"bootstrap · fedora 45 · 4 modules · log ~/.dotfiles_log/"* ]]
  [[ "$output" == *"✓ base"* && "$output" == *"✓ kubernetes"* ]]
  [[ "$output" == *"OK: 4 modules"* ]]
  [ "$(applied)" = "base cli docker kubernetes" ]
  grep -q -- '-E base bootstrap status --missing' "$STUB_MISE_LOG"
}

@test "a failing module is ✗, its dependents are blocked, the rest run, exit 1" {
  STUB_FAIL=docker run dotfiles --bootstrap
  [ "$status" -eq 1 ]
  [[ "$output" == *"✗ docker"*"Error: No match for argument: docker-ce"* ]]
  [[ "$output" == *"✗ kubernetes"*"blocked by docker"* ]]
  [[ "$output" == *"✓ cli"* ]]
  [[ "$output" == *"FAILED: 1 of 4 modules (docker); blocked: kubernetes. See log."* ]]
  [ "$(applied)" = "base cli docker" ]
}

@test "the log frames every module with START/END and holds mise output" {
  STUB_FAIL=docker run dotfiles --bootstrap
  log="$(ls "$DOTFILES_LOG_DIR"/*-bootstrap.log)"
  grep -q '^=== base START ' "$log"
  grep -q '^=== base END ok ===$' "$log"
  grep -q '^=== docker END fail ===$' "$log"
  grep -q '^=== kubernetes END blocked ===$' "$log"
  grep -q 'Error: No match for argument: docker-ce' "$log"
  grep -q 'FAILED: 1 of 4 modules' "$log"
}

@test "a config WARN from mise marks the module ✗ even though mise exits 0" {
  STUB_WARN=cli run dotfiles --bootstrap
  [ "$status" -eq 1 ]
  [[ "$output" == *"✗ cli"*"config warning: unknown field"* ]]
}

@test "something still missing after apply marks the module ✗" {
  STUB_MISSING=base run dotfiles --bootstrap
  [ "$status" -eq 1 ]
  [[ "$output" == *"✗ base"*"still missing after apply"* ]]
}

@test "exit 3 means skipped, with the module's reason; dependents are skipped too; exit 0" {
  STUB_SKIP=docker run dotfiles --bootstrap
  [ "$status" -eq 0 ]
  [[ "$output" == *"- docker"*"skipped: no NVIDIA GPU"* ]]
  [[ "$output" == *"- kubernetes"*"skipped: needs docker, which was skipped"* ]]
  [[ "$output" == *"OK: 4 modules (2 skipped)"* ]]
}

# --- phases and the post-bootstrap prompt ------------------------------------------

@test "default run asks before post-bootstrap; 'n' skips it" {
  run dotfiles <<<"n"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Continue to post-bootstrap"* ]]
  [[ "$output" == *'Run "dotfiles --post-bootstrap" later'* ]]
  [ "$(applied)" = "base cli docker kubernetes" ]
}

@test "default run with 'y' continues into post-bootstrap, with its own log" {
  run dotfiles <<<"y"
  [ "$status" -eq 0 ]
  [ "$(applied)" = "base cli docker kubernetes ssh git-signing" ]
  [[ "$output" == *"post-bootstrap · fedora 45 · 2 modules"* ]]
  ls "$DOTFILES_LOG_DIR"/*-post-bootstrap.log
}

@test "no answer (stdin closed) counts as no" {
  run dotfiles </dev/null
  [ "$status" -eq 0 ]
  [ "$(applied)" = "base cli docker kubernetes" ]
}

@test "--yes alone runs bootstrap only, without asking" {
  run dotfiles --yes
  [ "$status" -eq 0 ]
  [[ "$output" != *"Continue to post-bootstrap"* ]]
  [ "$(applied)" = "base cli docker kubernetes" ]
}

@test "--post-bootstrap runs only post-bootstrap" {
  run dotfiles --post-bootstrap
  [ "$status" -eq 0 ]
  [ "$(applied)" = "ssh git-signing" ]
  [ -z "$(ls "$DOTFILES_LOG_DIR" | grep -v post-bootstrap)" ]
}

@test "--bootstrap --post-bootstrap runs both without asking" {
  run dotfiles --bootstrap --post-bootstrap
  [ "$status" -eq 0 ]
  [[ "$output" != *"Continue to post-bootstrap"* ]]
  [ "$(applied)" = "base cli docker kubernetes ssh git-signing" ]
}

@test "a bootstrap failure blocks dependent post-bootstrap modules in the same run" {
  STUB_FAIL=base run dotfiles --bootstrap --post-bootstrap
  [ "$status" -eq 1 ]
  [[ "$output" == *"✗ ssh"*"blocked by base"* ]]
  [[ "$output" == *"✗ git-signing"*"blocked by ssh"* ]]
  [ "$(applied)" = "base" ]
}

# --- selection --------------------------------------------------------------------

@test "--only runs just the listed modules and their dependencies" {
  run dotfiles --bootstrap --only cli
  [ "$status" -eq 0 ]
  [ "$(applied)" = "base cli" ]
}

@test "--config uses the given file" {
  write_config "$BATS_TEST_TMPDIR/mine.toml" 'include = ["docker"]'
  run dotfiles --bootstrap --config "$BATS_TEST_TMPDIR/mine.toml"
  [ "$status" -eq 0 ]
  [ "$(applied)" = "base docker" ]
}

# --- mise config: conf.d links and saved envs -------------------------------------

@test "conf.d gets one link per selected module (both phases) and envs are saved" {
  run dotfiles --bootstrap
  [ "$status" -eq 0 ]
  [ "$(links)" = "base cli docker git-signing kubernetes ssh" ]
  [ "$(readlink "$MISE_DIR/conf.d/docker")" = "$ROOT/modules/docker" ]
  [ "$(readlink "$MISE_DIR/conf.d/ssh")" = "$ROOT/post-bootstrap/ssh" ]
  grep -qx 'env = \["base", "cli", "docker", "git-signing", "kubernetes", "ssh"\]' "$MISE_DIR/miserc.local.toml"
}

@test "envs are saved even when a module fails" {
  STUB_FAIL=docker run dotfiles --bootstrap
  grep -q '^env = \[.*"docker"' "$MISE_DIR/miserc.local.toml"
}

@test "rebuild: excluded and removed modules lose their link; other files stay" {
  run dotfiles --bootstrap
  printf 'mine\n' >"$MISE_DIR/conf.d/my-own.toml"
  rm -rf "$ROOT/modules/cli"
  write_config "$ROOT/dotfiles.toml" 'exclude = ["kubernetes"]'
  run dotfiles --bootstrap
  [ "$status" -eq 0 ]
  [ "$(links)" = "base docker git-signing my-own.toml ssh" ]
}

@test "--only keeps the links of modules from earlier runs" {
  run dotfiles --bootstrap
  run dotfiles --bootstrap --only cli
  [ "$status" -eq 0 ]
  [ "$(links)" = "base cli docker git-signing kubernetes ssh" ]
}

@test "other settings in miserc.local.toml are kept; only the env line is replaced" {
  mkdir -p "$MISE_DIR"
  printf 'env = ["old"]\nexperimental = true\n' >"$MISE_DIR/miserc.local.toml"
  run dotfiles --bootstrap
  [ "$(grep -c '^env' "$MISE_DIR/miserc.local.toml")" -eq 1 ]
  grep -qx 'experimental = true' "$MISE_DIR/miserc.local.toml"
  ! grep -q '"old"' "$MISE_DIR/miserc.local.toml"
}

@test "an older single conf.d link is replaced by a folder" {
  mkdir -p "$MISE_DIR"
  ln -s "$ROOT/modules" "$MISE_DIR/conf.d"
  run dotfiles --bootstrap
  [ "$status" -eq 0 ]
  [ -d "$MISE_DIR/conf.d" ] && [ ! -L "$MISE_DIR/conf.d" ]
  [ -d "$ROOT/modules/base" ]
}

@test "a foreign file where a module link goes: exit 2, nothing changed" {
  mkdir -p "$MISE_DIR/conf.d"
  printf 'x\n' >"$MISE_DIR/conf.d/docker"
  run dotfiles --bootstrap
  [ "$status" -eq 2 ]
  [[ "$output" == *"conf.d/docker exists and is not a dotfiles module link"* ]]
  [ "$(links)" = "docker" ]
  [ "$(applied)" = "" ]
}

# --- dry run ----------------------------------------------------------------------

@test "--dry-run passes --dry-run to mise and changes nothing but the log" {
  run dotfiles --bootstrap --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry run"* ]]
  grep -q -- '-E base bootstrap --yes --dry-run' "$STUB_MISE_LOG"
  ! grep -q 'status --missing' "$STUB_MISE_LOG"
  [ "$(ls -A "$HOME")" = ".dotfiles_log" ]
  # mise read the modules from a temporary config dir, removed afterwards.
  tmpdir="$(sed -n -E 's/^MISE_CONFIG_DIR=([^ ]+) -E base.*/\1/p' "$STUB_MISE_LOG" | head -n1)"
  [ -n "$tmpdir" ] && [ ! -e "$tmpdir" ]
  [ ! -s "$STUB_SUDO_LOG" ]
}

# --- preconditions: exit 2 before any change --------------------------------------

assert_untouched() {
  [ "$(applied)" = "" ]
  [ ! -e "$MISE_DIR" ]
}

@test "unsupported OS: exit 2, nothing changed" {
  DOTFILES_OS_RELEASE="$REPO/tests/fixtures/os-release/arch" run dotfiles --bootstrap
  [ "$status" -eq 2 ]
  assert_untouched
}

@test "mise older than the minimum: exit 2, nothing changed" {
  STUB_MISE_VERSION=2026.9.1 run dotfiles --bootstrap
  [ "$status" -eq 2 ]
  [[ "$output" == *"too old; need 2026.10.10"* ]]
  assert_untouched
}

@test "unknown option: exit 2 with a usage hint" {
  run dotfiles --bootsrap
  [ "$status" -eq 2 ]
  [[ "$output" == *'unknown option "--bootsrap"'* ]]
  [[ "$output" == *"dotfiles --help"* ]]
}

@test "--only without a value: exit 2" {
  run dotfiles --only
  [ "$status" -eq 2 ]
}

@test "unknown module in --only: exit 2, nothing changed" {
  run dotfiles --bootstrap --only kubernets
  [ "$status" -eq 2 ]
  [[ "$output" == *'unknown module "kubernets"'* ]]
  assert_untouched
}

@test "bad config: exit 2, nothing changed" {
  write_config "$ROOT/dotfiles.toml" 'includes = ["cli"]'
  run dotfiles --bootstrap
  [ "$status" -eq 2 ]
  assert_untouched
}

@test "--help prints usage and exits 0" {
  run dotfiles --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: dotfiles"* ]]
}

# --- sudo -------------------------------------------------------------------------

@test "sudo is asked once, up front, when not root" {
  [ "$EUID" -ne 0 ] || skip "running as root: sudo is not needed"
  run dotfiles --bootstrap
  [ "$status" -eq 0 ]
  [ "$(head -n1 "$STUB_SUDO_LOG")" = "sudo -v" ]
}

@test "sudo failing: exit 2, nothing changed" {
  [ "$EUID" -ne 0 ] || skip "running as root: sudo is not needed"
  STUB_SUDO_EXIT=1 run dotfiles --bootstrap
  [ "$status" -eq 2 ]
  [ "$(applied)" = "" ]
}
