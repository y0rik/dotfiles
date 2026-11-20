# dotfiles

Bootstraps my workstation: a fresh **Fedora KDE Plasma** or **Kubuntu** install becomes a fully configured machine from one command. Safe to re-run: a second run changes nothing, and new tools added to the repo get installed.

> 🚧 Under construction. Sections marked _(planned)_ aren't built yet.

## Quick start

One command (the gist link is published once the repo is ready; until then use the repo's raw `install.sh`):

```bash
bash -c "$(curl -fsSL <gist-url>/raw/install.sh)"                      # bootstrap, then ask about post-bootstrap
bash -c "$(curl -fsSL <gist-url>/raw/install.sh)" -- --bootstrap --yes  # any dotfiles flags go after --
```

The launcher:
1. stops with exit 2 on anything but Fedora or Ubuntu/Kubuntu;
2. installs `git` and `curl` if missing (asks for sudo);
3. installs [mise](https://mise.jdx.dev/) with its official installer if missing, and stops with exit 2 if it is older than 2026.10.10;
4. clones this repo to `~/.dotfiles`, or fast-forwards an existing clone. It refuses (exit 2) if the clone has local changes;
5. links `~/.local/bin/dotfiles` and runs it with your flags.

Running it again is safe: it pulls the latest repo and re-applies. After the first run, use `dotfiles` directly (open a new terminal first: the `bash` module puts `~/.local/bin` on PATH; without it, on Kubuntu, log out and back in).

Launcher settings (environment variables): `DOTFILES_BRANCH` (default `main`), `DOTFILES_DIR` (default `~/.dotfiles`), `DOTFILES_REPO`.

> While the repo is under construction, the work lives on `develop`; `main` gets it at the first release. To try it now:
> ```bash
> DOTFILES_BRANCH=develop bash -c "$(curl -fsSL https://raw.githubusercontent.com/y0rik/dotfiles/develop/install.sh)" -- --bootstrap
> ```

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

| Module | Phase | Installs | Needs |
|---|---|---|---|
| `base` | bootstrap | git, curl, wget, gnupg, ca-certificates, tar, unzip, tree, rsync, nano | — |
| `mise` | bootstrap | usage (for mise's bash completion); mise itself comes from `install.sh` | base |
| `bash` | bootstrap | `~/.bash_bootstrap` (PATH, mise activation and completion, oh-my-posh prompt), one line in `~/.bashrc` that sources it; oh-my-posh | base, mise |
| `network` | bootstrap | openssl, dig, tcpdump, traceroute, iperf3, nmap, whois (distro packages) | base |
| `cli` | bootstrap | jq, yq, fzf, bat, btop, xh, lnav, hunk (mise, same names on both distros) | base |
| `neovim` | bootstrap | Neovim, ripgrep, fd; `~/.config/nvim/init.lua` (starter options, no plugins) | base |
| `kitty` | bootstrap | kitty (distro package); `~/.config/kitty/kitty.conf` (starter) | base |
| `yazi` | bootstrap | yazi, file; `~/.config/yazi/yazi.toml` (empty: defaults) | base |
| `lazygit` | bootstrap | lazygit; `~/.config/lazygit/config.yml` (empty: defaults) | base |

_(More modules are being added.)_

## Config files

Config files are links into the repo (`~/.config/kitty/kitty.conf -> ~/.dotfiles/…/modules/kitty/files/kitty.conf`): edit the repo copy, and commit it to keep the change.

If a real file is already where a link goes, the module fails with `files: refusing to overwrite existing files` and the file is left alone; the log names it. Move it away (or merge it into the repo copy) and re-run.

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
