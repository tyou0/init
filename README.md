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

`init.sh` installs a `mise`-managed Python before `uv`, not the system `python3`. It forces `python.compile=false` and `python.precompiled_flavor=install_only` so `mise` uses a working precompiled CPython artifact instead of the broken freethreaded stripped build or a local source compile that depends on missing system headers. The script defaults to `PYTHON_MISE_VERSION=lts`, then maps that to `PYTHON_LTS_VERSION=3.13` because the `mise` Python backend does not support the literal selector `python@lts`. If you want a different Python track, set `PYTHON_MISE_VERSION` before running the script, for example `PYTHON_MISE_VERSION=3.12 ./init.sh`. `init.sh` resolves the interpreter with `mise which python3` and passes that path to `pipx` so `pipx` does not try to build its shared venv with `/usr/bin/python3`.

`init.sh` can download with either `curl` or `wget`. If neither exists, it exits and asks you to install one first so the bootstrap path stays on `mise`, `uv`, and `pipx` for programming languages and tools.

The playbook asks all install questions first, prints a summary, and only starts after you type `yes`.

## Idempotency

The playbook is written to be rerunnable. File installs use Ansible modules, shell rc edits use managed `blockinfile` markers, Zim installs only when missing, tmux plugins install only when plugin directories are missing, and reload/source tasks do not report changes.

Some parts track a stable line rather than an exact patch release:

- `config/mise/config.toml` uses stable or rolling tracks such as `python = "3.13"`, `node = "lts"`, and `bun`/`deno` on `latest`.
- `init.sh` sets `python.compile=false` and `python.precompiled_flavor=install_only`, bootstraps `python@3.13` and `uv@latest` through `mise use -g`, installs `pipx` with `uv tool install pipx`, and installs `ansible` with `pipx install --python "$(mise which python3)" --include-deps ansible` when missing.
- tpack and Powerlevel10k are git checkouts with `update: true`.

That means repeated runs should converge within a major or chosen release line, but a future run can still move to a newer patch or compatible release in that line. For strict reproducibility, pin exact mise tool versions and pin git checkouts to specific tags or commits.

Symlink mode uses Ansible `force: true` so repo-managed files become the source of truth. This is intentional for a dotfiles repo, but it can replace an existing destination on first run. Use `copy` mode for standalone files, or review existing home files before running in `symlink` mode.

Optional OS packages such as `aria2` are best-effort because package availability differs across distros. A missing optional package should not block the rest of the bootstrap.

`yt-dlp` is installed through mise. `aria2` stays as an optional OS package because `mise registry aria2` does not resolve to a default registry tool. If a reliable mise backend is added later, move it into `config/mise/config.toml`.

## Dotfiles

The default file mode is `symlink`, so repo-managed files stay in this repo and the home directory points back to them. Choose `copy` at the prompt if a machine should get standalone files instead.

Managed files include:

- `~/.tmux.conf`
- `~/.aliases`
- `~/.zshrc`, `~/.bashrc`, `~/.profile`, `~/.zimrc`, and `~/.p10k.zsh`
- `~/.gitconfig`, sanitized to exclude credential helper commands
- `~/.config/mise/config.toml`
- `~/.config/git/ignore`
- helper scripts in `~/.local/bin`
- shell rc blocks for aliases, mise, and direnv

## Secrets

Do not commit secrets. `.envrc` and `.envrc.*` are ignored on purpose; store sensitive `.envrc` contents in Bitwarden and restore them manually where needed. Commit only non-sensitive examples such as `.envrc.example`.
