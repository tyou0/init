#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MISE_BIN="${MISE_BIN:-}"

has() {
    command -v "$1" >/dev/null 2>&1
}

sudo_if_needed() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

ensure_fetcher() {
    if has curl || has wget; then
        return
    fi

    if has apt-get; then
        sudo_if_needed apt-get update
        sudo_if_needed apt-get install -y curl
    elif has dnf; then
        sudo_if_needed dnf install -y curl
    elif has yum; then
        sudo_if_needed yum install -y curl
    elif has pacman; then
        sudo_if_needed pacman -Sy --needed --noconfirm curl
    elif has zypper; then
        sudo_if_needed zypper --non-interactive install curl
    elif has apk; then
        sudo_if_needed apk add --no-cache curl
    elif [ "$(uname -s)" = "Darwin" ]; then
        printf 'Neither curl nor wget is available. Install one and rerun this script.\n' >&2
        exit 1
    else
        printf 'Neither curl nor wget is available, and this package manager is unsupported.\n' >&2
        exit 1
    fi
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

ensure_mise() {
    if [ -n "$MISE_BIN" ] && [ -x "$MISE_BIN" ]; then
        return
    fi

    if has mise; then
        MISE_BIN="$(command -v mise)"
        return
    fi

    mkdir -p "$HOME/.local/bin"
    fetch_url https://mise.run | MISE_INSTALL_PATH="$HOME/.local/bin/mise" sh
    MISE_BIN="$HOME/.local/bin/mise"
}

activate_mise() {
    eval "$("$MISE_BIN" activate bash)"
}

trust_global_mise_config() {
    local config_file="${XDG_CONFIG_HOME:-$HOME/.config}/mise/config.toml"

    if [ -f "$config_file" ]; then
        "$MISE_BIN" trust -y "$config_file" >/dev/null 2>&1 || true
    fi
}

ensure_uv() {
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

    "$MISE_BIN" use -g --yes ansible@latest
    activate_mise

    if ! has ansible-playbook; then
        exec "$MISE_BIN" exec ansible@latest -- ansible-playbook -i "${ROOT_DIR}/inventory.ini" "${ROOT_DIR}/playbook.yml" "$@"
    fi
}

ensure_fetcher
ensure_mise
trust_global_mise_config
activate_mise
ensure_uv
ensure_pipx
ensure_ansible "$@"

exec ansible-playbook -i "${ROOT_DIR}/inventory.ini" "${ROOT_DIR}/playbook.yml" "$@"
