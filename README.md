# init

Personal workstation bootstrap repo for macOS and Linux.

This repo installs a local Ansible runner, applies shell and tool configuration,
and optionally installs desktop apps and helper scripts. It is designed to be
rerunnable on an existing machine.

## Quick Start

Run the main workstation bootstrap:

```sh
./init.sh
```

Accept the default answers and run non-interactively:

```sh
./init.sh -y
```

Install secondary desktop apps separately:

```sh
./install_app.sh
```

Run that secondary app install non-interactively:

```sh
./install_app.sh -y
```

Both scripts forward any other arguments to `ansible-playbook`, so you can pass
extra vars or Ansible flags when needed:

```sh
./init.sh -e install_tmux=no
./install_app.sh --check
```

## Entry Points

`init.sh` is the main bootstrap path. It ensures `curl` or `wget` exists,
installs `mise` if needed, installs a `mise`-managed Python and `uv`, installs
`pipx`, installs Ansible through `pipx`, then runs:

```sh
ansible-playbook -i inventory.ini playbook.yml
```

With `-y`, it passes defaults for copy-mode dotfiles, base packages, optional
CLI packages, workspace directories, mise/direnv setup, profiles, tmux, Zim,
Powerlevel10k, aliases, and the `fetchall` helper.

`install_app.sh` handles secondary apps. It bootstraps enough tooling to run
Ansible, then runs:

```sh
ansible-playbook -i inventory.ini apps-playbook.yml
```

If `ansible-playbook` is missing, it installs `ansible-core` with
`uv tool install`. With `-y`, it passes `confirm_install=yes` and
`install_secondary_apps=yes`.

You can also call the playbooks directly once Ansible is available:

```sh
ansible-playbook playbook.yml
ansible-playbook apps-playbook.yml
```

`ansible.cfg` already points at `inventory.ini`, where `localhost` is configured
with `ansible_connection=local`.

The playbooks ask install questions first, print a summary, and only start after
confirmation. The `-y` flag supplies that confirmation and the default answers
used by the wrapper scripts.

## What Gets Installed

The main playbook can install:

- Base CLI packages such as `bash`, `curl`, `wget`, `git`, `jq`, `ripgrep`,
  `tmux`, `zsh`, and language build dependencies.
- Optional CLI packages such as `aria2`, `htop`, `btop`, `ctop`, `watch`, and
  `fd` or `fd-find`.
- `~/src`.
- `mise` and `direnv`.
- Global mise tools from `config/mise/config.toml`: `bat`, `bun`, `deno`,
  `dart`, `direnv`, `ffmpeg`, `go`, `lazydocker`, `lazygit`, `neovim`, Node
  LTS, `pnpm`, Python 3.13, Rust, `uv`, `yt-dlp`, Ruby, and Temurin Java 25.
- Tmux config, tpack, and tmux plugins.
- Zim and Powerlevel10k.
- Shell aliases and profile files.
- Helper scripts in `~/.local/bin`.

The secondary app playbook can install:

- macOS Homebrew taps: `v2rayA/v2raya` and `asmvik/formulae`.
- macOS formulae: `v2raya`, `asmvik/formulae/yabai`, and `tailscale`.
- macOS casks: Vivaldi, Bitwarden, Signal, Zed, VS Code, Antigravity, Codex,
  Docker Desktop, DisplayLink, IINA, DBeaver, iTerm2, cmux, Alfred, Stats,
  Thaw, Dropbox, Tailscale, and JetBrains Mono.
- Linux packages where available: `v2raya`, `vivaldi-stable`, `bitwarden`, and
  `signal-desktop`.
- Linux Flatpaks when Flatpak is available: Vivaldi, Bitwarden, Signal, and
  DBeaver Community.
- The `bitwarden-proxy` helper in `~/.local/bin`.

## Dotfiles

The default mode is `copy`, which is the safer path for an existing machine.
Choose `symlink` at the prompt only when this repo should be the source of
truth for the installed files.

Managed files include:

- `~/.tmux.conf`
- `~/.aliases`
- `~/.zshrc`, `~/.bashrc`, `~/.profile`, `~/.zimrc`, and `~/.p10k.zsh`
- `~/.gitconfig`, sanitized to exclude credential helper commands
- `~/.config/mise/config.toml`
- `~/.config/git/ignore`
- Shell rc blocks for aliases, mise, direnv, Zim, and Powerlevel10k when the
  profile files are not installed by symlink.

## Helper Scripts

Helper installs are explicit and platform-aware:

- `wifi` is macOS-only.
- `updateProxmoxGuestIp` is opt-in for Proxmox hosts.
- `newt_service` is only for Linux systemd hosts after the upstream Newt or
  Pangolin install has already run.
- `fetchall` runs `git fetch --all --prune` for repositories under the current
  directory.
- `bitwarden-proxy` starts Bitwarden through `http://localhost:8889` by default.
  Override it with:

```sh
BITWARDEN_PROXY_URL=http://host:port bitwarden-proxy
```

## Bootstrap Notes

`init.sh` installs a `mise`-managed Python before installing `uv`; it does not
depend on the system `python3`. The default `MISE_INSTALL_VERSION` is
`v2026.4.14`.

The Python bootstrap defaults to `PYTHON_MISE_VERSION=lts`, which maps to
`PYTHON_LTS_VERSION=3.13` because the mise Python backend does not support the
literal selector `python@lts`. To use another Python track:

```sh
PYTHON_MISE_VERSION=3.12 ./init.sh
```

The bootstrap sets:

```sh
mise settings set python.compile=false
mise settings set python.precompiled_flavor=install_only
```

That keeps mise on precompiled CPython artifacts instead of local source builds
that can fail when system headers are missing. `init.sh` resolves the Python
path with `mise which python3` and passes it to `pipx` for the Ansible install.

On macOS, Homebrew is required for package installs. On Linux, `init.sh` can
install `curl` with common package managers if neither `curl` nor `wget` exists.

`init.sh` downloads the mise installer to a temporary file and runs that file.
The app installer uses the shorter mise bootstrap path because it only needs
enough tooling to launch the secondary app playbook.

## Idempotency

The playbooks are intended to converge cleanly across repeated runs:

- File installs use Ansible modules.
- Shell rc edits use managed `blockinfile` markers.
- Zim installs only when missing.
- Tpack and Powerlevel10k checkouts avoid automatic git updates.
- Tmux plugin installation runs only when plugin directories are missing.
- Reload and source tasks avoid reporting changes.

Some tools intentionally track a stable or rolling line rather than an exact
patch release. For example, `config/mise/config.toml` uses tracks such as
`node = "lts"` and several `latest` tools. For strict reproducibility, pin exact
mise tool versions and git checkouts.

Optional packages are best-effort because package availability differs across
distros. A missing optional package should not block the rest of the bootstrap.

## Secrets

Do not commit secrets. `.envrc` and `.envrc.*` are ignored on purpose; store
sensitive `.envrc` contents in Bitwarden and restore them manually where needed.
Commit only non-sensitive examples such as `.envrc.example`.
