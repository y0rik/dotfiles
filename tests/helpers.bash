# Shared helpers for bats tests.

load_libs() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  local lib
  for lib in "$@"; do
    # shellcheck disable=SC1090
    source "$REPO/lib/$lib.sh"
  done
}

# mkmod <root> <bootstrap|post-bootstrap> <id> [dep...]: create a fixture module.
mkmod() {
  local root="$1" phase="$2" id="$3" dir deps="" d
  shift 3
  dir="$root/modules/$id"
  [[ "$phase" == post-bootstrap ]] && dir="$root/post-bootstrap/$id"
  mkdir -p "$dir"
  for d in "$@"; do deps+="\"$d\", "; done
  printf 'description = "fixture %s"\ndepends = [%s]\n' "$id" "${deps%, }" >"$dir/module.toml"
  : >"$dir/mise.$id.toml"
}

# write_config <file> <toml text>
write_config() {
  printf '%s\n' "$2" >"$1"
}
