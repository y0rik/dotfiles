# shellcheck shell=bash
# lib/os.sh: detect the operating system the bootstrap runs on.
#
# Supported: Fedora and Ubuntu (Kubuntu reports ID=ubuntu). Anything else
# is rejected with exit status 2 before the runner changes anything.
#
# The os-release path can be overridden with DOTFILES_OS_RELEASE (tests).

# _os_field <file> <KEY>: print one value from an os-release file.
# Parsed, not sourced, so a malformed file cannot run code.
_os_field() {
  local file="$1" key="$2" line value
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == "$key="* ]] || continue
    value="${line#*=}"
    value="${value#\"}"; value="${value%\"}"
    value="${value#\'}"; value="${value%\'}"
    printf '%s\n' "$value"
    return 0
  done <"$file"
  return 1
}

_os_release_file() {
  printf '%s\n' "${DOTFILES_OS_RELEASE:-/etc/os-release}"
}

# os_detect: print "fedora" or "ubuntu"; exit status 2 for anything else.
os_detect() {
  local file id
  file="$(_os_release_file)"
  if [[ ! -r "$file" ]]; then
    printf 'dotfiles: cannot read %s; unsupported system\n' "$file" >&2
    return 2
  fi
  id="$(_os_field "$file" ID || true)"
  case "$id" in
    fedora) printf 'fedora\n' ;;
    ubuntu) printf 'ubuntu\n' ;;
    *)
      printf 'dotfiles: unsupported OS "%s" (supported: Fedora, Ubuntu/Kubuntu)\n' "${id:-unknown}" >&2
      return 2
      ;;
  esac
}

# os_version: print VERSION_ID (e.g. "45", "26.10"), empty if absent.
os_version() {
  _os_field "$(_os_release_file)" VERSION_ID || true
}

# os_codename: print VERSION_CODENAME (Ubuntu apt suites), empty if absent.
os_codename() {
  _os_field "$(_os_release_file)" VERSION_CODENAME || true
}
