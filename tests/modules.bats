#!/usr/bin/env bats
# Unit tests for lib/modules.sh: discovery, selection and ordering.

setup() {
  load helpers
  load_libs toml config modules
  ROOT="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$ROOT"
}

# A small realistic tree:
#   base
#   cli          -> base
#   docker       -> base
#   lazydocker   -> docker
#   kubernetes   -> base, docker
#   ssh          (post-bootstrap) -> base
#   git-signing  (post-bootstrap) -> ssh
standard_tree() {
  mkmod "$ROOT" bootstrap base
  mkmod "$ROOT" bootstrap cli base
  mkmod "$ROOT" bootstrap docker base
  mkmod "$ROOT" bootstrap lazydocker docker
  mkmod "$ROOT" bootstrap kubernetes base docker
  mkmod "$ROOT" post-bootstrap ssh base
  mkmod "$ROOT" post-bootstrap git-signing ssh
  modules_discover "$ROOT"
}

select_lines() { # select_lines <phase> [only]: run modules_select, join output with spaces
  run modules_select "$@"
  output="$(tr '\n' ' ' <<<"$output" | sed 's/ $//')"
}

# --- discovery ---------------------------------------------------------------

@test "discover: finds modules in both phases, sorted" {
  standard_tree
  [ "${MOD_IDS[*]}" = "base cli docker git-signing kubernetes lazydocker ssh" ]
  [ "${MOD_PHASE[ssh]}" = "post-bootstrap" ]
  [ "${MOD_PHASE[docker]}" = "bootstrap" ]
  [ "${MOD_DEPS[kubernetes]}" = "base docker" ]
}

@test "discover: a folder without module.toml is an error (2)" {
  mkdir -p "$ROOT/modules/stray"
  run modules_discover "$ROOT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"modules/stray: missing module.toml"* ]]
}

@test "discover: an invalid id is an error (2)" {
  mkmod "$ROOT" bootstrap Bad_Name
  run modules_discover "$ROOT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"lowercase letters, digits and dashes"* ]]
}

@test "discover: the same id in both phases is an error (2)" {
  mkmod "$ROOT" bootstrap ssh
  mkmod "$ROOT" post-bootstrap ssh
  run modules_discover "$ROOT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"both modules/ and post-bootstrap/"* ]]
}

@test "discover: an unknown key in module.toml is an error (2)" {
  mkmod "$ROOT" bootstrap base
  printf 'depend = ["x"]\n' >"$ROOT/modules/base/module.toml"
  run modules_discover "$ROOT"
  [ "$status" -eq 2 ]
  [[ "$output" == *'unknown setting "depend"'* ]]
}

@test "discover: depending on an unknown module is an error (2)" {
  mkmod "$ROOT" bootstrap cli nope
  run modules_discover "$ROOT"
  [ "$status" -eq 2 ]
  [[ "$output" == *'unknown module "nope" (in depends of cli)'* ]]
}

@test "discover: a bootstrap module can't depend on a post-bootstrap one (2)" {
  mkmod "$ROOT" post-bootstrap ssh
  mkmod "$ROOT" bootstrap cli ssh
  run modules_discover "$ROOT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"can't depend on post-bootstrap"* ]]
}

@test "discover: no modules at all is fine" {
  modules_discover "$ROOT"
  [ "${#MOD_IDS[@]}" -eq 0 ]
  select_lines bootstrap
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

# --- selection ---------------------------------------------------------------

@test "select: both lists empty → every bootstrap module, dependencies first" {
  standard_tree
  select_lines bootstrap
  [ "$status" -eq 0 ]
  [ "$output" = "base cli docker kubernetes lazydocker" ]
}

@test "select: post-bootstrap phase lists only its own modules, in order" {
  standard_tree
  select_lines post-bootstrap
  [ "$status" -eq 0 ]
  [ "$output" = "ssh git-signing" ]
}

@test "select: include pulls in dependencies" {
  standard_tree
  CONFIG_INCLUDE=(kubernetes)
  select_lines bootstrap
  [ "$output" = "base docker kubernetes" ]
}

@test "select: include of a post-bootstrap module selects its bootstrap deps too" {
  standard_tree
  CONFIG_INCLUDE=(git-signing)
  select_lines bootstrap
  [ "$output" = "base" ]
  select_lines post-bootstrap
  [ "$output" = "ssh git-signing" ]
}

@test "select: --only overrides include" {
  standard_tree
  CONFIG_INCLUDE=(kubernetes)
  select_lines bootstrap cli
  [ "$output" = "base cli" ]
}

@test "select: --only overrides exclude" {
  standard_tree
  CONFIG_EXCLUDE=(docker lazydocker kubernetes)
  select_lines bootstrap lazydocker
  [ "$output" = "base docker lazydocker" ]
}

@test "select: --only takes a comma-separated list" {
  standard_tree
  select_lines bootstrap cli,lazydocker
  [ "$output" = "base cli docker lazydocker" ]
}

@test "select: exclude removes modules" {
  standard_tree
  CONFIG_EXCLUDE=(lazydocker cli)
  select_lines bootstrap
  [ "$output" = "base docker kubernetes" ]
}

@test "select: excluding a dependency of a selected module is an error (2)" {
  standard_tree
  CONFIG_EXCLUDE=(docker)
  run modules_select bootstrap
  [ "$status" -eq 2 ]
  [[ "$output" == *'"kubernetes" depends on excluded module "docker"'* || "$output" == *'"lazydocker" depends on excluded module "docker"'* ]]
}

@test "select: excluding a dependency counts transitively" {
  mkmod "$ROOT" bootstrap base
  mkmod "$ROOT" bootstrap mid base
  mkmod "$ROOT" bootstrap top mid
  modules_discover "$ROOT"
  CONFIG_EXCLUDE=(base mid)
  run modules_select bootstrap
  [ "$status" -eq 2 ]
  [[ "$output" == *'"top" depends on excluded module'* ]]
}

@test "select: an unknown id in include is an error (2) listing valid ids" {
  standard_tree
  CONFIG_INCLUDE=(kubernets)
  run modules_select bootstrap
  [ "$status" -eq 2 ]
  [[ "$output" == *'unknown module "kubernets"'* ]]
  [[ "$output" == *"Valid modules: base, cli, docker, git-signing, kubernetes, lazydocker, ssh"* ]]
}

@test "select: an unknown id in exclude or --only is an error (2)" {
  standard_tree
  CONFIG_EXCLUDE=(nope)
  run modules_select bootstrap
  [ "$status" -eq 2 ]
  CONFIG_EXCLUDE=()
  run modules_select bootstrap nope
  [ "$status" -eq 2 ]
}

@test "select: an unknown phase is an error (2)" {
  standard_tree
  run modules_select install
  [ "$status" -eq 2 ]
}

# --- ordering ----------------------------------------------------------------

@test "order: ties are broken alphabetically, deterministically" {
  mkmod "$ROOT" bootstrap zeta
  mkmod "$ROOT" bootstrap alpha
  mkmod "$ROOT" bootstrap mid zeta
  modules_discover "$ROOT"
  select_lines bootstrap
  [ "$output" = "alpha zeta mid" ]
  first="$output"
  select_lines bootstrap
  [ "$output" = "$first" ]
}

@test "order: a dependency cycle is an error (2), reported once" {
  mkmod "$ROOT" bootstrap base
  mkmod "$ROOT" bootstrap a b
  mkmod "$ROOT" bootstrap b c
  mkmod "$ROOT" bootstrap c a
  modules_discover "$ROOT"
  run modules_select bootstrap
  [ "$status" -eq 2 ]
  [[ "$output" == *"dependency cycle between: a b c"* ]]
  [ "$(grep -c 'dependency cycle' <<<"$output")" -eq 1 ]
}

@test "order: a module depending on itself is an error (2)" {
  mkmod "$ROOT" bootstrap loop loop
  run modules_discover "$ROOT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"depends on itself"* ]]
}
