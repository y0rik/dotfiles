#!/usr/bin/env bats
# Unit tests for lib/config.sh (dotfiles.toml) and lib/toml.sh.

setup() {
  load helpers
  load_libs toml config
  CFG="$BATS_TEST_TMPDIR/dotfiles.toml"
}

@test "config: the shipped dotfiles.toml loads and selects everything" {
  config_load "$REPO/dotfiles.toml"
  [ "${#CONFIG_INCLUDE[@]}" -eq 0 ]
  [ "${#CONFIG_EXCLUDE[@]}" -eq 0 ]
}

@test "config: include is read" {
  write_config "$CFG" 'include = ["kubernetes", "docker"]'
  config_load "$CFG"
  [ "${CONFIG_INCLUDE[*]}" = "kubernetes docker" ]
  [ "${#CONFIG_EXCLUDE[@]}" -eq 0 ]
}

@test "config: exclude is read" {
  write_config "$CFG" 'exclude = ["nvidia"]'
  config_load "$CFG"
  [ "${CONFIG_EXCLUDE[*]}" = "nvidia" ]
  [ "${#CONFIG_INCLUDE[@]}" -eq 0 ]
}

@test "config: an empty or comment-only file selects everything" {
  write_config "$CFG" '# nothing here'
  config_load "$CFG"
  [ "${#CONFIG_INCLUDE[@]}" -eq 0 ]
  [ "${#CONFIG_EXCLUDE[@]}" -eq 0 ]
}

@test "config: include and exclude both set is an error (2)" {
  write_config "$CFG" $'include = ["a"]\nexclude = ["b"]'
  run config_load "$CFG"
  [ "$status" -eq 2 ]
  [[ "$output" == *"include OR exclude, not both"* ]]
}

@test "config: an unknown key (typo) is an error (2)" {
  write_config "$CFG" 'includes = ["a"]'
  run config_load "$CFG"
  [ "$status" -eq 2 ]
  [[ "$output" == *'unknown setting "includes"'* ]]
}

@test "config: a string instead of a list is an error (2)" {
  write_config "$CFG" 'include = "docker"'
  run config_load "$CFG"
  [ "$status" -eq 2 ]
  [[ "$output" == *"must be a list of strings"* ]]
}

@test "config: a non-string element is an error (2)" {
  write_config "$CFG" 'exclude = ["a", 1]'
  run config_load "$CFG"
  [ "$status" -eq 2 ]
  [[ "$output" == *"only strings"* ]]
}

@test "config: malformed TOML is an error (2), reported once" {
  write_config "$CFG" 'include = ["a"'
  run config_load "$CFG"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not valid TOML"* ]]
  [ "$(grep -c 'not valid TOML' <<<"$output")" -eq 1 ]
}

@test "config: a missing file is an error (2)" {
  run config_load "$BATS_TEST_TMPDIR/absent.toml"
  [ "$status" -eq 2 ]
  [[ "$output" == *"cannot read"* ]]
}
