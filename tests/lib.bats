#!/usr/bin/env bats
# Unit tests for lib/os.sh, lib/log.sh and lib/ui.sh.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
  # shellcheck source=../lib/os.sh
  source "$REPO/lib/os.sh"
  # shellcheck source=../lib/log.sh
  source "$REPO/lib/log.sh"
  # shellcheck source=../lib/ui.sh
  source "$REPO/lib/ui.sh"
  export DOTFILES_LOG_DIR="$BATS_TEST_TMPDIR/logs"
  unset NO_COLOR DOTFILES_COLOR DOTFILES_LOG_FILE
}

# --- os.sh -------------------------------------------------------------------

@test "os: Fedora is detected as fedora" {
  DOTFILES_OS_RELEASE="$FIXTURES/os-release/fedora" run os_detect
  [ "$status" -eq 0 ]
  [ "$output" = "fedora" ]
}

@test "os: Kubuntu (ID=ubuntu) is detected as ubuntu" {
  DOTFILES_OS_RELEASE="$FIXTURES/os-release/kubuntu" run os_detect
  [ "$status" -eq 0 ]
  [ "$output" = "ubuntu" ]
}

@test "os: Arch is rejected with exit 2" {
  DOTFILES_OS_RELEASE="$FIXTURES/os-release/arch" run os_detect
  [ "$status" -eq 2 ]
  [[ "$output" == *'unsupported OS "arch"'* ]]
}

@test "os: Debian (ubuntu's parent, not ubuntu) is rejected with exit 2" {
  DOTFILES_OS_RELEASE="$FIXTURES/os-release/debian" run os_detect
  [ "$status" -eq 2 ]
}

@test "os: missing os-release is rejected with exit 2" {
  DOTFILES_OS_RELEASE="$BATS_TEST_TMPDIR/nope" run os_detect
  [ "$status" -eq 2 ]
  [[ "$output" == *"cannot read"* ]]
}

@test "os: os-release is parsed, never executed" {
  rm -f /tmp/dotfiles-pwned
  DOTFILES_OS_RELEASE="$FIXTURES/os-release/malicious" run os_detect
  [ "$status" -eq 2 ]
  [ ! -e /tmp/dotfiles-pwned ]
}

@test "os: version and codename are read (quoted and unquoted)" {
  export DOTFILES_OS_RELEASE="$FIXTURES/os-release/kubuntu"
  [ "$(os_version)" = "26.10" ]
  [ "$(os_codename)" = "stonking" ]
  export DOTFILES_OS_RELEASE="$FIXTURES/os-release/fedora"
  [ "$(os_version)" = "45" ]
  [ "$(os_codename)" = "" ]
}

# --- log.sh ------------------------------------------------------------------

@test "log: init creates the directory and <ISO-timestamp>-<phase>.log" {
  [ ! -d "$DOTFILES_LOG_DIR" ]
  log_init bootstrap >/dev/null
  [ -d "$DOTFILES_LOG_DIR" ]
  [ -f "$DOTFILES_LOG_FILE" ]
  [[ "$(basename "$DOTFILES_LOG_FILE")" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}-[0-9]{2}-[0-9]{2}-bootstrap\.log$ ]]
}

@test "log: default directory is ~/.dotfiles_log" {
  unset DOTFILES_LOG_DIR
  HOME="$BATS_TEST_TMPDIR/home" log_init post-bootstrap >/dev/null
  [[ "$DOTFILES_LOG_FILE" == "$BATS_TEST_TMPDIR/home/.dotfiles_log/"*-post-bootstrap.log ]]
}

@test "log: two runs in the same second get different files" {
  log_init bootstrap >/dev/null; first="$DOTFILES_LOG_FILE"
  log_init bootstrap >/dev/null; second="$DOTFILES_LOG_FILE"
  [ "$first" != "$second" ]
}

@test "log: module output is framed by START and END lines" {
  log_init bootstrap >/dev/null
  log_module_start docker
  printf 'dnf output\n' | log_capture
  log_module_end docker fail
  run cat "$DOTFILES_LOG_FILE"
  [[ "${lines[0]}" =~ ^===\ docker\ START\ .*\ ===$ ]]
  [ "${lines[1]}" = "dnf output" ]
  [ "${lines[2]}" = "=== docker END fail ===" ]
}

@test "log: writing before init fails loudly" {
  run log_line hello
  [ "$status" -eq 1 ]
  [[ "$output" == *"log_init was not called"* ]]
}

# --- ui.sh -------------------------------------------------------------------

@test "ui: plain output when stdout is not a terminal" {
  run ui_status ok base 12
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\033'* ]]
  [[ "$output" == "  ✓ base"*"12s" ]]
}

@test "ui: colour when forced, none when NO_COLOR is set" {
  DOTFILES_COLOR=always run ui_status ok base 1
  [[ "$output" == *$'\033['* ]]
  NO_COLOR=1 DOTFILES_COLOR=always run ui_status ok base 1
  [[ "$output" != *$'\033'* ]]
}

@test "ui: every status renders its mark and detail" {
  run ui_status fail docker 9 "dnf: no match"
  [[ "$output" == "  ✗ docker"*"9s   dnf: no match" ]]
  run ui_status skipped nvidia 0 "no NVIDIA GPU"
  [[ "$output" == "  - nvidia"*"skipped: no NVIDIA GPU" ]]
  run ui_status blocked lazydocker 0 docker
  [[ "$output" == "  ✗ lazydocker"*"blocked by docker" ]]
}

@test "ui: unknown status is an error" {
  run ui_status weird base 1
  [ "$status" -eq 1 ]
}
