#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MISE_BIN="${MISE_BIN:-}"
MISE_INSTALL_VERSION="${MISE_INSTALL_VERSION:-v2026.4.14}"
PYTHON_MISE_VERSION="${PYTHON_MISE_VERSION:-lts}"
PYTHON_PRECOMPILED_FLAVOR="${PYTHON_PRECOMPILED_FLAVOR:-install_only}"
PYTHON_LTS_VERSION="${PYTHON_LTS_VERSION:-3.13}"
AUTO_YES=0
declare -a ANSIBLE_ARGS=()

has() {
    command -v "$1" >/dev/null 2>&1
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -y|--yes)
                AUTO_YES=1
                ;;
            *)
                ANSIBLE_ARGS+=("$1")
                ;;
        esac
        shift
    done
}

ensure_fetcher() {
    if has curl || has wget; then
        return
    fi

    printf 'Neither curl nor wget is available. Install one and rerun this script.\n' >&2
    exit 1
}

fetch_url() {
    local url="$1"

    if has curl; then
        curl -fsSL "$url"
    elif has wget; then
        wget -qO- "$url"
    else
        printf 'Neither curl nor wget is available.\n' >&2
        return 1
    fi
}

download_url() {
    local url="$1"
    local destination="$2"

    if has curl; then
        curl -fsSL "$url" -o "$destination"
    elif has wget; then
        wget -qO "$destination" "$url"
    else
        printf 'Neither curl nor wget is available.\n' >&2
        return 1
    fi
}

ensure_mise() {
    local installer_path

    if [ -n "$MISE_BIN" ] && [ -x "$MISE_BIN" ]; then
        return
    fi

    if has mise; then
        MISE_BIN="$(command -v mise)"
        return
    fi

    mkdir -p "$HOME/.local/bin"
    installer_path="$(mktemp)"
    trap 'rm -f "$installer_path"' RETURN
    download_url "https://mise.jdx.dev/install.sh" "$installer_path"
    chmod +x "$installer_path"
    MISE_VERSION="$MISE_INSTALL_VERSION" MISE_INSTALL_PATH="$HOME/.local/bin/mise" sh "$installer_path"
    MISE_BIN="$HOME/.local/bin/mise"
}

activate_mise() {
    eval "$("$MISE_BIN" activate bash)"
    hash -r
}

trust_global_mise_config() {
    local config_file="${XDG_CONFIG_HOME:-$HOME/.config}/mise/config.toml"

    if [ -f "$config_file" ]; then
        "$MISE_BIN" trust -y "$config_file" >/dev/null 2>&1 || true
    fi
}

ensure_mise_python_settings() {
    local compile_value
    local flavor_value

    compile_value="$("$MISE_BIN" settings get python.compile 2>/dev/null || true)"
    if [ "$compile_value" != "false" ]; then
        "$MISE_BIN" settings set python.compile false
    fi

    flavor_value="$("$MISE_BIN" settings get python.precompiled_flavor 2>/dev/null || true)"
    if [ "$flavor_value" != "$PYTHON_PRECOMPILED_FLAVOR" ]; then
        "$MISE_BIN" settings set python.precompiled_flavor "$PYTHON_PRECOMPILED_FLAVOR"
    fi
}

resolve_python_mise_version() {
    if [ "$PYTHON_MISE_VERSION" = "lts" ]; then
        printf '%s\n' "$PYTHON_LTS_VERSION"
    else
        printf '%s\n' "$PYTHON_MISE_VERSION"
    fi
}

ensure_python() {
    local resolved_python_version

    ensure_mise_python_settings
    resolved_python_version="$(resolve_python_mise_version)"

    if ! "$MISE_BIN" which python3 >/dev/null 2>&1; then
        "$MISE_BIN" use -g --yes "python@${resolved_python_version}"
    fi

    activate_mise

    if ! has uv; then
        "$MISE_BIN" use -g --yes uv@latest
        activate_mise
    fi
}

ensure_pipx() {
    if ! uv tool list | awk '{print $1}' | grep -qx 'pipx'; then
        uv tool install pipx
    fi
}

ensure_ansible() {
    if has ansible-playbook; then
        return
    fi

    export PATH="$HOME/.local/bin:$PATH"
    export PIPX_DEFAULT_PYTHON="$("$MISE_BIN" which python3)"
    pipx install --python "$PIPX_DEFAULT_PYTHON" --include-deps ansible

    if ! has ansible-playbook; then
        printf 'Failed to install ansible-playbook with pipx.\n' >&2
        exit 1
    fi
}

parse_args "$@"

ensure_fetcher
ensure_mise
trust_global_mise_config
activate_mise
ensure_python
ensure_pipx
ensure_ansible "${ANSIBLE_ARGS[@]}"

if [ "$AUTO_YES" -eq 1 ]; then
    ANSIBLE_ARGS+=(
        -e config_mode=copy
        -e install_packages=yes
        -e install_optional_packages=yes
        -e install_mise_direnv=yes
        -e trust_mise_config=yes
        -e install_wifi_helper=no
        -e install_proxmox_helper=no
        -e install_newt_service_helper=no
        -e install_aliases=yes
        -e install_profiles=yes
        -e install_tmux=yes
        -e install_zsh_theme=yes
        -e confirm_install=yes
    )
fi

exec ansible-playbook -i "${ROOT_DIR}/inventory.ini" "${ROOT_DIR}/playbook.yml" "${ANSIBLE_ARGS[@]}"
