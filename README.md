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

_(planned)_

```bash
dotfiles                    # bootstrap, then ask about post-bootstrap
dotfiles --bootstrap        # bootstrap only
dotfiles --post-bootstrap   # post-bootstrap only
dotfiles --config <file>    # use your own copy of dotfiles.toml
dotfiles --only <a,b>       # run only these modules this time
dotfiles --dry-run          # show what would change
dotfiles --yes              # no prompts (skips post-bootstrap unless asked for)
```

## Choosing what gets installed

`dotfiles.toml` sets **at most one** of two lists. Both empty means install everything.

```toml
include = ["kubernetes"]   # install ONLY these modules, plus what they depend on
exclude = ["nvidia"]       # install everything EXCEPT these modules
```

- Values are module ids: the folder names under `modules/` and `post-bootstrap/`.
- `dotfiles --only a,b` works like `include` for one run and ignores the file.
- Mistakes stop the run **before anything is installed**: setting both lists, an unknown module id (the error lists the valid ones), a misspelled key such as `includes`, or excluding a module that another selected module needs.
- To customise: download `dotfiles.toml`, edit it, and run with `--config <your-file>` _(flag planned)_.

## Modules

_(planned)_ Module table.

## Pinning a version

_(planned)_ Each tool's version is a line in its module's `mise.<id>.toml`, `"latest"` by default. Change it to a version and re-run.

## Logs and results

Every module prints ✓, ✗, `skipped` or `blocked`. If any module fails, the run still finishes the others, prints a summary and exits with 1.

Full output of every run: `~/.dotfiles_log/<timestamp>-<phase>.log`. It lives next to `~/.dotfiles`, not inside it, so re-cloning the repo keeps old logs.

## Supported systems

The latest Fedora KDE Plasma and the latest Kubuntu. Anything else is refused before any change is made.

## Troubleshooting

_(planned)_

## Development

See [agentic.md](agentic.md) for structure, conventions and tests.
