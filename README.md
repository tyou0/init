# init

Personal workstation bootstrap repo.

Run it locally:

```sh
./init.sh
```

`init.sh` bootstraps Ansible if it is missing, then runs:

```sh
ansible-playbook -i inventory.ini playbook.yml
```

Install secondary desktop apps separately:

```sh
./install_app.sh
```

`install_app.sh` uses the same local bootstrap path, then runs:

```sh
ansible-playbook -i inventory.ini apps-playbook.yml
```

The bootstrap path is:

```sh
mise -> uv -> uv tool install pipx -> uv tool install ansible-core
```

`init.sh` can download with either `curl` or `wget`. If neither exists on Linux, it tries to install `curl` with the native package manager before bootstrapping mise.
On macOS, `init.sh` adds the standard Homebrew paths for Apple Silicon and Intel Macs before checking tools. The playbook installs OS packages with Homebrew when available and stops with a clear message if package installation is requested without Homebrew installed.
On Linux, the playbook installs `zsh` with the base packages and sets it as the default shell for the user running the playbook. The initial bootstrap also offers to create `~/src`, because that is where most local repos on this machine live.
Secondary apps are installed by `install_app.sh`, not by `init.sh`. On macOS this uses Homebrew, including the `v2rayA/v2raya` tap for `v2raya`, the `asmvik/formulae` tap for `asmvik/formulae/yabai`, runs `brew services start v2raya`, installs formulae for Tailscale, and installs casks for Vivaldi, Bitwarden, Signal, Zed, VS Code, Antigravity, Codex, Docker Desktop, DisplayLink, IINA, DBeaver, iTerm2, cmux, Alfred, Stats, Thaw, Dropbox, Tailscale, and JetBrains Mono. On Linux, secondary desktop packages are best-effort because distro repositories vary; if Flatpak is available, the app playbook also installs Vivaldi, Bitwarden, Signal, and DBeaver from Flathub. The secondary app playbook installs `bitwarden-proxy` into `~/.local/bin`; it starts Bitwarden through `http://localhost:8889` on macOS and Linux. Override the proxy with `BITWARDEN_PROXY_URL=http://host:port bitwarden-proxy`.

The playbook asks all install questions first, prints a summary, and only starts after you type `yes`.

## Idempotency

The playbook is written to be rerunnable. File installs use Ansible modules, shell rc edits use managed `blockinfile` markers, Zim installs only when missing, tmux plugins install only when plugin directories are missing, and reload/source tasks do not report changes.

Some parts are intentionally current rather than strictly pinned:

- `config/mise/config.toml` uses `latest` for several tools.
- `init.sh` bootstraps `uv@latest` and the latest `ansible-core` Python tool when missing.
- tpack and Powerlevel10k are git checkouts with `update: true`.

That means repeated runs should converge, but a future run can still change state if upstream versions move. For strict reproducibility, pin mise tool versions and pin git checkouts to specific tags or commits.

Symlink mode uses Ansible `force: true` so repo-managed files become the source of truth. This is intentional for a dotfiles repo, but it can replace an existing destination on first run. Use `copy` mode for standalone files, or review existing home files before running in `symlink` mode.

Optional OS packages such as `aria2`, `htop`, `btop`, `ctop`, `watch`, and `fd`/`fd-find` are best-effort because package availability differs across distros. A missing optional package should not block the rest of the bootstrap.

`yt-dlp` and `ffmpeg` are installed through mise. `aria2` stays as an optional OS package because `mise registry aria2` does not resolve to a default registry tool. If a reliable mise backend is added later, move it into `config/mise/config.toml`.
`htop`, `btop`, `ctop`, `watch`, and `fd` also stay as optional OS packages because they are tightly tied to the host shell environment and are simpler to source from the platform package manager.

## Dotfiles

The default file mode is `symlink`, so repo-managed files stay in this repo and the home directory points back to them. Choose `copy` at the prompt if a machine should get standalone files instead.

Managed files include:

- `~/.tmux.conf`
- `~/.aliases`
- `~/.zshrc`, `~/.bashrc`, `~/.profile`, and `~/.p10k.zsh`
- `~/.gitconfig`, sanitized to exclude credential helper commands
- `~/.config/mise/config.toml`
- `~/.config/git/ignore`
- helper scripts in `~/.local/bin`
- shell rc blocks for aliases, mise, and direnv

## Secrets

Do not commit secrets. `.envrc` and `.envrc.*` are ignored on purpose; store sensitive `.envrc` contents in Bitwarden and restore them manually where needed. Commit only non-sensitive examples such as `.envrc.example`.
