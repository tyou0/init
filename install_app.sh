#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAYBOOK_FILE="${ROOT_DIR}/apps-playbook.yml"
MISE_BIN="${MISE_BIN:-}"
UNAME_S="$(uname -s)"
ANSIBLE_ARGS=()
ANSIBLE_EXTRA_VARS=()

case "$UNAME_S" in
    Darwin)
        export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:/opt/homebrew/bin:/usr/local/bin:$PATH"
        ;;
    *)
        export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
        ;;
esac

has() {
    command -v "$1" >/dev/null 2>&1
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -y|--yes)
                ANSIBLE_EXTRA_VARS+=(
                    "confirm_install=yes"
                    "install_secondary_apps=yes"
                )
                ;;
            *)
                ANSIBLE_ARGS+=("$1")
                ;;
        esac
        shift
    done
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
    elif [ "$UNAME_S" = "Darwin" ]; then
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

run_uv() {
    if has uv; then
        uv "$@"
    else
        "$MISE_BIN" exec uv@latest -- uv "$@"
    fi
}

ensure_uv() {
    if ! has uv; then
        "$MISE_BIN" use -g --yes uv@latest
        "$MISE_BIN" reshim uv >/dev/null 2>&1 || true
    fi
}

ensure_ansible() {
    if has ansible-playbook; then
        return
    fi

    if ! run_uv tool list | awk '{print $1}' | grep -qx 'ansible-core'; then
        run_uv tool install ansible-core
    fi

    if ! has ansible-playbook; then
        ANSIBLE_PLAYBOOK_BIN="$(run_uv tool dir --bin)/ansible-playbook"
    fi
}

run_ansible_playbook() {
    local ansible_playbook_bin="${ANSIBLE_PLAYBOOK_BIN:-ansible-playbook}"
    local cmd=("$ansible_playbook_bin" -i "${ROOT_DIR}/inventory.ini" "$PLAYBOOK_FILE")
    local extra_var arg

    if [ "${#ANSIBLE_EXTRA_VARS[@]}" -gt 0 ]; then
        for extra_var in "${ANSIBLE_EXTRA_VARS[@]}"; do
            cmd+=(--extra-vars="$extra_var")
        done
    fi

    if [ "${#ANSIBLE_ARGS[@]}" -gt 0 ]; then
        for arg in "${ANSIBLE_ARGS[@]}"; do
            cmd+=("$arg")
        done
    fi

    exec "${cmd[@]}"
}

parse_args "$@"
ensure_fetcher
ensure_mise
ensure_uv
ensure_ansible

run_ansible_playbook
