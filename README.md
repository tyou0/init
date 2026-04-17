# init

Personal workstation bootstrap repo.

Run it locally:

```sh
./init.sh
```

To accept the default answers and run non-interactively:

```sh
./init.sh -y
```

`init.sh` bootstraps Ansible if it is missing, then runs:

```sh
ansible-playbook -i inventory.ini playbook.yml
```

The bootstrap path is:

```sh
mise settings set python.compile=false -> mise settings set python.precompiled_flavor=install_only -> mise use -g python@lts -> mise use -g uv@latest -> uv tool install pipx -> pipx install ansible
```

`init.sh` installs a `mise`-managed Python before `uv`, not the system `python3`. It downloads the official `mise` installer to a local temporary file and runs it with `MISE_INSTALL_VERSION=v2026.4.14` by default instead of piping a remote script directly into a shell. The script then forces `python.compile=false` and `python.precompiled_flavor=install_only` so `mise` uses a working precompiled CPython artifact instead of the broken freethreaded stripped build or a local source compile that depends on missing system headers. The script defaults to `PYTHON_MISE_VERSION=lts`, then maps that to `PYTHON_LTS_VERSION=3.13` because the `mise` Python backend does not support the literal selector `python@lts`. If you want a different Python track, set `PYTHON_MISE_VERSION` before running the script, for example `PYTHON_MISE_VERSION=3.12 ./init.sh`. `init.sh` resolves the interpreter with `mise which python3` and passes that path to `pipx` so `pipx` does not try to build its shared venv with `/usr/bin/python3`.

`init.sh` can download with either `curl` or `wget`. If neither exists, it exits and asks you to install one first so the bootstrap path stays on `mise`, `uv`, and `pipx` for programming languages and tools.

The playbook asks all install questions first, prints a summary, and only starts after you type `yes`.

## Idempotency

The playbook is written to be rerunnable. File installs use Ansible modules, shell rc edits use managed `blockinfile` markers, Zim installs only when missing, tmux plugins install only when plugin directories are missing, and reload/source tasks do not report changes.

Some parts track a stable line rather than an exact patch release:

- `config/mise/config.toml` uses stable or rolling tracks such as `python = "3.13"`, `node = "lts"`, and `bun`/`deno` on `latest`.
- `init.sh` sets `python.compile=false` and `python.precompiled_flavor=install_only`, bootstraps `python@3.13` and `uv@latest` through `mise use -g`, installs `pipx` with `uv tool install pipx`, and installs `ansible` with `pipx install --python "$(mise which python3)" --include-deps ansible` when missing.
- `playbook.yml` downloads a pinned Zim release asset (`v1.20.0`) and avoids auto-updating existing tpack and Powerlevel10k checkouts.

That means repeated runs should converge within a major or chosen release line, but a future run can still move to a newer patch or compatible release in that line. For strict reproducibility, pin exact mise tool versions and pin git checkouts to specific tags or commits.

Copy mode is the default because it is the safer bootstrap path for an existing machine. Symlink mode still uses Ansible `force: true` so repo-managed files become the source of truth; use it only when you explicitly want this repo to own those files.

Optional OS packages such as `aria2` are best-effort because package availability differs across distros. A missing optional package should not block the rest of the bootstrap, and the `yt` helper falls back to plain `yt-dlp` when `aria2c` is unavailable.

`yt-dlp` is installed through mise. `aria2` stays as an optional OS package because `mise registry aria2` does not resolve to a default registry tool. If a reliable mise backend is added later, move it into `config/mise/config.toml`.

## Dotfiles

The default file mode is `copy`, so a bootstrap run on an existing machine starts from the less destructive path. Choose `symlink` at the prompt only when repo-managed files should stay in this repo and the home directory should point back to them.

Managed files include:

- `~/.tmux.conf`
- `~/.aliases`
- `~/.zshrc`, `~/.bashrc`, `~/.profile`, `~/.zimrc`, and `~/.p10k.zsh`
- `~/.gitconfig`, sanitized to exclude credential helper commands
- `~/.config/mise/config.toml`
- `~/.config/git/ignore`
- optional helper scripts in `~/.local/bin`
- shell rc blocks for aliases, mise, and direnv

Helper installs are explicit and platform-aware:

- `wifi` is macOS-only.
- `updateProxmoxGuestIp` is opt-in for Proxmox hosts.
- `newt_service.sh` is a manual post-install helper for Linux systemd hosts after the upstream Newt/Pangolin install has already run.

## Secrets

Do not commit secrets. `.envrc` and `.envrc.*` are ignored on purpose; store sensitive `.envrc` contents in Bitwarden and restore them manually where needed. Commit only non-sensitive examples such as `.envrc.example`.
