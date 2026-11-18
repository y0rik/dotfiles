# dotfiles

Bootstraps my workstation: a fresh **Fedora KDE Plasma** or **Kubuntu** install becomes a fully configured machine from one command. Safe to re-run: a second run changes nothing, and new tools added to the repo get installed.

> 🚧 Under construction. Sections marked _(planned)_ aren't built yet.

## Quick start

_(planned)_ One command from a gist:

```bash
bash -c "$(curl -fsSL <gist-url>/raw/install.sh)"
```

It installs git, curl and [mise](https://mise.jdx.dev/), clones this repo to `~/.dotfiles`, runs **bootstrap**, then asks whether to continue with **post-bootstrap**.

## What it does

| Phase | Needs secrets | Does |
|---|---|---|
| **bootstrap** | no | system packages, CLI tools, runtimes, desktop apps, bash and KDE settings |
| **post-bootstrap** | yes, 1Password signed in | SSH public keys, `~/.ssh/config`, 1Password SSH agent, git commit signing |

## Usage

```bash
dotfiles                                    # bootstrap, then ask about post-bootstrap
dotfiles --bootstrap                        # bootstrap only
dotfiles --post-bootstrap                   # post-bootstrap only
dotfiles --bootstrap --post-bootstrap       # both, without asking
dotfiles --config <file>                    # use your own copy of dotfiles.toml
dotfiles --only <a,b>                       # run only these modules (and what they need) this time
dotfiles --dry-run                          # show what would change, change nothing
dotfiles --yes                              # no prompts; skips post-bootstrap unless --post-bootstrap is given
```

Bootstrap asks for your sudo password once at the start, so the run never stops halfway to ask again.

## Choosing what gets installed

`dotfiles.toml` sets **at most one** of two lists. Both empty means install everything.

```toml
include = ["kubernetes"]   # install ONLY these modules, plus what they depend on
exclude = ["nvidia"]       # install everything EXCEPT these modules
```

- Values are module ids: the folder names under `modules/` and `post-bootstrap/`.
- `dotfiles --only a,b` works like `include` for one run and ignores the file.
- Mistakes stop the run **before anything is installed**: setting both lists, an unknown module id (the error lists the valid ones), a misspelled key such as `includes`, or excluding a module that another selected module needs.
- To customise: download `dotfiles.toml`, edit it, and run with `--config <your-file>`.

## Modules

_(planned)_ Module table.

## Pinning a version

_(planned)_ Each tool's version is a line in its module's `mise.<id>.toml`, `"latest"` by default. Change it to a version and re-run.

## Logs and results

Every module gets one line:

```
bootstrap · fedora 45 · 4 modules · log ~/.dotfiles_log/2026-11-18T09-40-00-bootstrap.log
  ✓ base                 3s
  ✓ cli                  8s
  ✗ docker               2s   Error: No match for argument: docker-ce
  ✗ kubernetes           0s   blocked by docker
FAILED: 1 of 4 modules (docker); blocked: kubernetes. See log.
```

- ✓ installed and verified; ✗ failed; `blocked by X`: not attempted because X failed; `skipped: reason`: doesn't apply on this machine (e.g. no NVIDIA GPU), not a failure.
- If any module fails, the run still finishes the others, prints the summary and exits with **1**. Exit **2** means it stopped before changing anything (unsupported OS, old mise, bad config or flag).

Full output of every run: `~/.dotfiles_log/<timestamp>-<phase>.log`. It lives next to `~/.dotfiles`, not inside it, so re-cloning the repo keeps old logs.

## Supported systems

The latest Fedora KDE Plasma and the latest Kubuntu. Anything else is refused before any change is made.

## Troubleshooting

_(planned)_

## Development

See [agentic.md](agentic.md) for structure, conventions and tests.
