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

The bootstrap path is:

```sh
mise -> uv -> uv tool install pipx -> mise use -g ansible
```

`init.sh` can download with either `curl` or `wget`. If neither exists on Linux, it tries to install `curl` with the native package manager before bootstrapping mise.

The playbook asks all install questions first, prints a summary, and only starts after you type `yes`.

## Idempotency

The playbook is written to be rerunnable. File installs use Ansible modules, shell rc edits use managed `blockinfile` markers, Zim installs only when missing, tmux plugins install only when plugin directories are missing, and reload/source tasks do not report changes.

Some parts are intentionally current rather than strictly pinned:

- `config/mise/config.toml` uses `latest` for several tools.
- `init.sh` bootstraps `uv@latest` and `ansible@latest` when missing.
- tpack and Powerlevel10k are git checkouts with `update: true`.

That means repeated runs should converge, but a future run can still change state if upstream versions move. For strict reproducibility, pin mise tool versions and pin git checkouts to specific tags or commits.

Symlink mode uses Ansible `force: true` so repo-managed files become the source of truth. This is intentional for a dotfiles repo, but it can replace an existing destination on first run. Use `copy` mode for standalone files, or review existing home files before running in `symlink` mode.

Optional OS packages such as `aria2` are best-effort because package availability differs across distros. A missing optional package should not block the rest of the bootstrap.

`yt-dlp` is installed through mise. `aria2` stays as an optional OS package because `mise registry aria2` does not resolve to a default registry tool. If a reliable mise backend is added later, move it into `config/mise/config.toml`.

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
