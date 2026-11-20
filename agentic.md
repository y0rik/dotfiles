# agentic.md: how this repo works

Read this before changing anything. It is the working guide for agent sessions on this repo. Keep it current: **any change to structure, conventions, flags or modules updates this file in the same commit.**

> Status: under construction. Sections marked _(planned)_ describe the agreed design but are not built yet.

## Purpose

Bootstraps the owner's workstation: a fresh **Fedora KDE Plasma (latest)** or **Kubuntu (latest)** install becomes a fully configured machine from one command launched from a GitHub gist. The repo keeps growing; re-running applies whatever was added. Every step must be **safe to run again**: a second run changes nothing.

Out of scope: CLI sign-ins (gh, az, aws, gcloud, …), Ansible, keeping machines in sync without a re-run.

## Design in one minute

Two phases:

| Phase | Needs secrets | Does |
|---|---|---|
| **bootstrap** | no | system packages, CLI tools, runtimes, desktop apps, bash + KDE config |
| **post-bootstrap** | yes (1Password) | SSH public keys, `~/.ssh/config`, 1Password SSH agent, git commit signing |

- **mise does the installing** (≥ 2026.10.10): `[tools]`, `[bootstrap.packages]`, `[dotfiles]`, `[bootstrap.hooks]`, `[tasks.bootstrap]`.
- **`bin/dotfiles` orchestrates**: OS check, module selection, one `mise -E <id> bootstrap --yes` per module, a ✓ / ✗ / skipped / blocked line per module, a log, a summary, and the exit code.
- **One module = one folder**, a mise config fragment named `mise.<id>.toml`, loaded only when mise environment `<id>` is active. `~/.config/mise/conf.d/` holds one link per selected module.
- **A failed module is a failure, never a warning.** The run continues with independent modules and exits 1 at the end.

Modelled on [TechDufus/dotfiles](https://github.com/TechDufus/dotfiles) (`main`), but with Fedora/Kubuntu, strict failures, and continue-and-summarise.

## Repository layout

```
install.sh            → gist launcher: OS check, git/curl, mise (>= min), clone/pull ~/.dotfiles, link ~/.local/bin/dotfiles, exec runner
bin/dotfiles          → runner: flags, preconditions, phases, prompt, exit code
dotfiles.toml         → which modules run: include / exclude
lib/os.sh             → os_detect (fedora|ubuntu, else exit 2), os_version, os_codename
lib/log.sh            → log_init <phase>, log_module_start/end, log_capture, log_line
lib/ui.sh             → ui_status <ok|fail|skipped|blocked> <module> <seconds> [detail], ui_header, ui_error
lib/toml.sh           → toml_query, toml_check_keys, toml_string_list (mikefarah yq v4; falls back to `mise exec yq@4`)
lib/config.sh         → config_load <file> → CONFIG_INCLUDE / CONFIG_EXCLUDE
lib/modules.sh        → modules_discover <root>, modules_select <phase> [only-csv] → ordered ids
lib/apply.sh          → conf.d links, apply_module <id> (mise call + status), apply_save_env, apply_summary
modules/<id>/         → bootstrap-phase modules (module.toml, mise.<id>.toml, optional files/ for dotfiles)
post-bootstrap/<id>/  → post-bootstrap-phase modules
tests/                → bats tests, helpers.bash (mkmod fixture builder), fixtures, stubs/ (fake mise, sudo), Dockerfile (bats, yq, git, curl)
.github/workflows/    → CI
README.md             → user documentation
agentic.md            → this file
```

Run logs go to `~/.dotfiles_log/<ISO-timestamp>-<phase>.log`, outside the repo.

## The launcher (`install.sh`)

Published as a gist; the repo copy is the source of truth. It can't source `lib/` (the repo isn't cloned yet), so it parses os-release itself. All code is inside `main`, called on the last line, so a partly downloaded script runs nothing. Exit 2 = stopped before the runner (unsupported OS, mise too old, `~/.dotfiles` not a clone or has local changes, can't fast-forward, a real file at `~/.local/bin/dotfiles`); otherwise it `exec`s the runner, so the exit code is the runner's. `MISE_MIN_VERSION` is duplicated in `install.sh` and `bin/dotfiles`: change both. Overrides: `DOTFILES_BRANCH` (default `main`), `DOTFILES_DIR`, `DOTFILES_REPO`, `DOTFILES_OS_RELEASE`.

## How a run works

`bin/dotfiles` (`lib/apply.sh` does the per-module work):

1. **Preconditions, nothing changed yet** (any failure → exit 2): parse flags; supported OS; `mise` ≥ 2026.10.10; load `dotfiles.toml` (skipped with `--only`); discover modules; select both phases; check nothing foreign sits where a `conf.d` link goes; `sudo -v` once if bootstrap runs as non-root (kept fresh in the background until exit).
2. **Links:** `~/.config/mise/conf.d/` (or `$MISE_CONFIG_DIR/conf.d`) gets one link per module, `conf.d/<id> -> <repo>/modules/<id>`. The set is the config's selection for **both** phases; with `--only`, existing links are kept and the `--only` modules added, so a one-off run doesn't drop other tools. Links into this repo that aren't in the set are removed; anything else in `conf.d` is left alone. An old single `conf.d -> modules` link is replaced by a folder.
3. **Per module, in dependency order:**
   - a dependency that failed or was blocked → `blocked by <dep>`, not attempted; a skipped dependency → `skipped: needs <dep>`.
   - `mise -E <id> bootstrap --yes` from `$HOME`, `NO_COLOR=1`, output into the log.
   - exit 0 → `mise -E <id> bootstrap status --missing` must also pass, else ✗ "still missing after apply".
   - exit 3 → `skipped`; the reason shown is the text after the module's last `SKIP:` line.
   - any other exit → ✗ with the last error-looking output line.
   - a mise `WARN … unknown field` / `… is required` line → ✗ even on exit 0 (mise ignores that part of the module).
4. **Phases:** bootstrap, then the prompt `Continue to post-bootstrap …? [y/N]` (only if post-bootstrap modules are selected; EOF = no). `--yes` alone = bootstrap only. `--bootstrap` / `--post-bootstrap` pick phases explicitly; both = both, no prompt. Statuses carry across phases, so a failed `base` blocks `ssh`.
5. **After:** each phase prints `OK: N modules (k skipped)` or `FAILED: k of N modules (…); blocked: …. See log.` The linked set is saved as `env = [...]` in `miserc.local.toml` (only that line is owned; other lines kept), even when modules failed. Exit 1 if anything in any phase was ✗ or blocked.

`--dry-run`: no sudo, links built in a temporary `MISE_CONFIG_DIR` (deleted at exit), `mise … bootstrap --yes --dry-run` per module, no `status` check, no env save. Only the log is written.

One log per phase: `~/.dotfiles_log/<timestamp>-<phase>.log`, with the header, the command line, every mise call and its output framed `=== <id> START … ===` / `=== <id> END <status> ===`, and the summary.

## Selecting modules

`dotfiles.toml` has exactly two allowed keys, `include` and `exclude` (lists of module ids); any other key is an error, so typos can't silently install everything. Setting both is an error. `--only a,b` replaces both for one run.

`modules_select` (lib/modules.sh):
- **include / --only:** the listed modules plus everything they depend on, transitively.
- **exclude:** every module except those listed. Excluding something a selected module depends on is an error.
- **Order:** dependencies first; ties alphabetical, so the order is always the same.
- **Phases:** a post-bootstrap module may depend on a bootstrap module (it's assumed to be applied already when post-bootstrap runs alone). The reverse is an error.
- Every config problem (unknown id, cycle, bad TOML, wrong types) returns **2 before anything changes**, and unknown-id messages list the valid ids.

## Adding or changing a module

A module is a folder `modules/<id>/` (bootstrap) or `post-bootstrap/<id>/` with two files. `modules/base/` is the reference example.

```toml
# module.toml (required; only these two keys are allowed)
description = "Docker Engine, lazydocker, dive"
depends = ["base"]          # every module except base depends on base
```

```toml
# mise.<id>.toml: what mise applies under `mise -E <id> bootstrap`
[bootstrap.packages]
git = "latest"                                           # same name on both distros
wget = { names = { apt = "wget", dnf = "wget2-wget" } }  # names differ per distro

[tools]
jq = "latest"               # pin by replacing "latest" with a version

[dotfiles]                  # paths in $HOME; sources relative to the module folder
"~/.config/jq/x" = "files/x"                                   # symlink into the repo
"~/.bashrc/my-line" = { line = 'source ~/.something' }          # one line, added once

[tasks.bootstrap]           # optional, runs last, every run: keep it safe to repeat
run = "command -v realpath"
```

Steps:
1. Create the folder and both files; add the module to the README module table.
2. Check it: `docker run --rm -v "$PWD:/src:ro" fedora:latest bash /src/tests/integration/run.sh` needs the commit on a `ci-under-test` branch, so the simplest path is to push and let CI run it on both distros. For a quick look in a container: install mise, link the folder into `~/.config/mise/conf.d/<id>`, run `mise -E <id> bootstrap plan`, then `mise -E <id> bootstrap --yes`.
3. GUI or hardware module (no systemd/GUI/GPU in containers)? Add it to `exclude` in `tests/integration/dotfiles.ci.toml`.

Rules:
- The folder name is the module id: lowercase letters, digits, dashes. An id can exist in only one phase, and every folder there must have a `module.toml`.
- The mise config file is `<folder>/mise.<id>.toml`.
- Versions sit in that file, `"latest"` by default; pin by editing the line.
- Use **real** package names. Virtual names (Fedora's `wget` → `wget2-wget`) are never reported installed, so they reinstall every run; CI's "nothing left to change" check fails on them.
- `"latest"` for a package means "installed, any version": re-runs don't upgrade system packages (no implicit full upgrades).
- Fedora vendor repos: add them in a `[bootstrap.hooks] pre-packages` hook with a file-exists guard (`[bootstrap.dnf.repos]` is COPR only).
- Ubuntu vendor repos: `[bootstrap.apt.sources]` needs `key` **and** `fingerprint`, otherwise mise skips the source with only a warning.
- Dotfiles are **symlinks into the repo** (`~/.x -> ~/.config/mise/conf.d/<id>/files/x`), so editing the repo copy takes effect at once. Link **files, not folders**: tools write state into their config folders (lazygit's `state.yml`, Neovim's `lazy-lock.json`), and an untracked file in the clone makes `install.sh` refuse to pull. A real file already at the target makes mise refuse (module ✗, file untouched); the runner never passes `--force-dotfiles`. To add a line to a file you don't own (`~/.bashrc`), use a `{ line = … }` entry with a unique name after the file path; mise adds it once.
- Shell setup goes in `modules/bash/files/bash_bootstrap` (sourced from `~/.bashrc`): it puts `~/.local/bin` on PATH, then, in interactive shells only, activates mise (plus `mise hook-env`, so tools are on PATH right away), mise completion and the oh-my-posh prompt. Guard each tool with `command -v`, so a missing tool never breaks a new shell.
- Prefer `[tools]` (mise registry) for CLI tools: same name and version on both distros. Use `[bootstrap.packages]` for what the registry lacks or what belongs to the system (network tools, libraries).
- Config files go in `files/` with a header saying where the link lives. Where the tool can check its own config cheaply, the bootstrap task does it (`nvim --headless -c qa` must print nothing).
- End a module with a `[tasks.bootstrap]` that checks each tool by the name you type (`command -v dig`, `bat --version`): it catches a package that installs a different binary name (Ubuntu's `batcat`).
- Anything imperative goes in `[tasks.bootstrap]` (run last), with `skip_if` where an "already done" check is cheap.
- "Does not apply on this machine" (no NVIDIA GPU, …): print `SKIP: <reason>` and `exit 3`. The runner shows `skipped: <reason>`; it is not a failure.

## Conventions

- Bash, `set -euo pipefail` in executables; libraries in `lib/` are sourced and only define functions.
- Functions `snake_case`; private helpers start with `_`.
- Never hide a failure: no `|| true` / `exit 0` around steps that can fail.
- `bin/dotfiles` runs under `set -e`, and so do the library functions it calls: use `sed -n …p`, not `grep`, to look for text that may be absent.
- Parse files, don't source them, when their content isn't ours (see `_os_field`).
- Colour only on a terminal; `NO_COLOR` disables it, `DOTFILES_COLOR=always|never` overrides.

## Testing

```bash
bats tests/                        # unit tests (needs mikefarah yq v4 on PATH)
shellcheck -x install.sh lib/*.sh bin/dotfiles tests/stubs/* tests/integration/*.sh modules/bash/files/bash_bootstrap   # lint (CI pins v0.11.0)
# Without local installs:
docker build -q -t dotfiles-test tests/
docker run --rm -v "$PWD:/code:ro" -w /code dotfiles-test tests/
docker run --rm --user 1000:1000 -v "$PWD:/code:ro" -w /code dotfiles-test tests/   # also runs the sudo tests
docker run --rm -v "$PWD:/mnt:ro" -w /mnt koalaman/shellcheck:v0.11.0 -x install.sh lib/*.sh bin/dotfiles tests/stubs/* tests/integration/*.sh modules/bash/files/bash_bootstrap
```

Fixture modules are built per test with `mkmod <root> <bootstrap|post-bootstrap> <id> [dep...]` from `tests/helpers.bash`.

`tests/install.bats` runs `install.sh` offline: `DOTFILES_REPO` is a local fixture repo whose `bin/dotfiles` only records its arguments, and the stub `mise` stands in for the real one (one test fakes `curl` to check the mise install path). Installing git/curl with dnf/apt is checked by hand in `fedora:latest` / `ubuntu:rolling` containers.

`tests/runner.bats` runs the real `bin/dotfiles` against a fixture tree (`DOTFILES_ROOT`) and a temporary `HOME`, with `tests/stubs/` first on `PATH`. The stub `mise` only answers for modules reachable as `$MISE_CONFIG_DIR/conf.d/<id>/mise.<id>.toml`, logs every call to `STUB_MISE_LOG`, and misbehaves per module id via `STUB_FAIL` (dnf-style error plus mise's footer), `STUB_TASKFAIL`, `STUB_SKIP`, `STUB_WARN`, `STUB_MISSING` (space-separated ids) and `STUB_MISE_VERSION`. The stub `sudo` logs to `STUB_SUDO_LOG` and exits `STUB_SUDO_EXIT`. Sudo tests skip when run as root.

CI (`.github/workflows/ci.yml`) on every push to `develop`/`main` and on PRs:
- `shellcheck` (pinned image) and `bats`;
- `integration (fedora:latest | ubuntu:rolling)`, after both pass: the commit is put on branch `ci-under-test`, mounted read-only at `/src` in a fresh container, and `tests/integration/run.sh` runs the real launcher (`DOTFILES_REPO=/src`) with `tests/integration/dotfiles.ci.toml`, then for every applied module checks `mise -E <id> bootstrap plan` shows `0 create, 0 update, … 0 remove` (plan covers system packages only; "nothing configured" is fine) and `mise -E <id> bootstrap status --missing` passes (tools and dotfiles too), then runs `dotfiles` twice more. If `bash` was applied it also checks `~/.bashrc` has the include line once and that a clean `env -i … bash -ic` shell has `~/.local/bin` on PATH, `dotfiles`, mise activated, mise completion and the oh-my-posh prompt. On failure it prints the run logs.

Test hooks: `DOTFILES_ROOT` (repo/module tree), `DOTFILES_OS_RELEASE` (os-release path), `DOTFILES_LOG_DIR` (log directory), `DOTFILES_COLOR`, `DOTFILES_YQ` (yq command), `MISE_CONFIG_DIR` (mise's config dir, as mise itself reads it).

Libraries are sourced from inside functions in tests, so their global variables are declared with `declare -g`.

## Boundaries

- **Always:** keep steps safe to re-run; let failures surface; update `README.md` and this file with the change; run shellcheck + bats before committing; test on both distros.
- **Ask first:** new install paths outside mise; changing `dotfiles.toml` semantics; raising the mise minimum version; sudo beyond package installs and group membership.
- **Never:** commit secrets, private keys, hostnames or `~/.ssh/config` contents; run full system upgrades implicitly; perform CLI sign-ins.

## Planning docs

`docs/.agentic/` (intent, requirements, spec, spike findings, plan, tasks) is **local only and git-ignored**. When it's present, it holds the full rationale; this file must stand on its own without it.
