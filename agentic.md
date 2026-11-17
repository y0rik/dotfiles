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
- **`bin/dotfiles` orchestrates** _(planned)_: OS check, module selection, one `mise -E <id> bootstrap --yes` per module, a ✓ / ✗ / skipped / blocked line per module, a log, a summary, and the exit code.
- **One module = one folder**, a mise config fragment named `mise.<id>.toml`, loaded only when mise environment `<id>` is active. `~/.config/mise/conf.d/` holds one link per selected module.
- **A failed module is a failure, never a warning.** The run continues with independent modules and exits 1 at the end.

Modelled on [TechDufus/dotfiles](https://github.com/TechDufus/dotfiles) (`main`), but with Fedora/Kubuntu, strict failures, and continue-and-summarise.

## Repository layout

```
install.sh            → gist launcher (planned)
bin/dotfiles          → runner (planned)
dotfiles.toml         → which modules run: include / exclude (planned)
lib/os.sh             → os_detect (fedora|ubuntu, else exit 2), os_version, os_codename
lib/log.sh            → log_init <phase>, log_module_start/end, log_capture, log_line
lib/ui.sh             → ui_status <ok|fail|skipped|blocked> <module> <seconds> [detail], ui_header, ui_error
modules/<id>/         → bootstrap-phase modules
post-bootstrap/<id>/  → post-bootstrap-phase modules
tests/                → bats unit tests + fixtures
.github/workflows/    → CI
README.md             → user documentation
agentic.md            → this file
```

Run logs go to `~/.dotfiles_log/<ISO-timestamp>-<phase>.log`, outside the repo.

## How a run works

_(planned, Task 4)_

## Adding or changing a module

_(planned, Tasks 4–6: module template, `module.toml` fields, naming)_

Rules already fixed:
- The config file is `modules/<id>/mise.<id>.toml`; the folder name is the module id.
- Versions sit in that file, `"latest"` by default; pin by editing the line.
- Use **real** package names. Virtual names (Fedora's `wget` → `wget2-wget`) break safe re-runs.
- Fedora vendor repos: add them in a `[bootstrap.hooks] pre-packages` hook with a file-exists guard (`[bootstrap.dnf.repos]` is COPR only).
- Ubuntu vendor repos: `[bootstrap.apt.sources]` needs `key` **and** `fingerprint`, otherwise mise skips the source with only a warning.
- Anything imperative goes in `[tasks.bootstrap]` (run last), with `skip_if` where an "already done" check is cheap. Exit 3 means "does not apply here" (`skipped`).

## Conventions

- Bash, `set -euo pipefail` in executables; libraries in `lib/` are sourced and only define functions.
- Functions `snake_case`; private helpers start with `_`.
- Never hide a failure: no `|| true` / `exit 0` around steps that can fail.
- Parse files, don't source them, when their content isn't ours (see `_os_field`).
- Colour only on a terminal; `NO_COLOR` disables it, `DOTFILES_COLOR=always|never` overrides.

## Testing

```bash
bats tests/                        # unit tests
shellcheck -x lib/*.sh             # lint
# Without local installs:
docker run --rm -v "$PWD:/code:ro" -w /code bats/bats:1.11.0 tests/
docker run --rm -v "$PWD:/mnt:ro" -w /mnt koalaman/shellcheck:v0.10.0 -x lib/*.sh
```

CI (`.github/workflows/ci.yml`) runs shellcheck and bats on every push to `develop`/`main` and on PRs. Container integration runs on Fedora and Ubuntu, plus a re-run check, are _(planned, Task 6)_.

Test hooks: `DOTFILES_OS_RELEASE` (os-release path), `DOTFILES_LOG_DIR` (log directory), `DOTFILES_COLOR`.

## Boundaries

- **Always:** keep steps safe to re-run; let failures surface; update `README.md` and this file with the change; run shellcheck + bats before committing; test on both distros.
- **Ask first:** new install paths outside mise; changing `dotfiles.toml` semantics; raising the mise minimum version; sudo beyond package installs and group membership.
- **Never:** commit secrets, private keys, hostnames or `~/.ssh/config` contents; run full system upgrades implicitly; perform CLI sign-ins.

## Planning docs

`docs/.agentic/` (intent, requirements, spec, spike findings, plan, tasks) is **local only and git-ignored**. When it's present, it holds the full rationale; this file must stand on its own without it.
