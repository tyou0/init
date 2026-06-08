#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MISE_BIN="${MISE_BIN:-}"
SUDO_TARGET_USER=""
SUDO_TARGET_HOME=""
BOOTSTRAP_MISE_CONFIG=""
MISE_INSTALL_VERSION="${MISE_INSTALL_VERSION:-latest}"
PYTHON_MISE_VERSION="${PYTHON_MISE_VERSION:-lts}"
PYTHON_PRECOMPILED_FLAVOR="${PYTHON_PRECOMPILED_FLAVOR:-install_only}"
PYTHON_LTS_VERSION="${PYTHON_LTS_VERSION:-3.13}"
AUTO_YES=0
UNAME_S="$(uname -s)"
declare -a ANSIBLE_ARGS=()
declare -a AUTO_ANSIBLE_ARGS=()
declare -a TARGET_ANSIBLE_ARGS=()
declare -a SUDO_ANSIBLE_ARGS=()
BOOTSTRAP_PATH=""

add_path_entry() {
    local entry="$1"

    if [ -z "$entry" ]; then
        return
    fi

    case ":$BOOTSTRAP_PATH:" in
        *":$entry:"*) return ;;
    esac

    BOOTSTRAP_PATH="${BOOTSTRAP_PATH:+$BOOTSTRAP_PATH:}$entry"
}

set_bootstrap_path() {
    local entry
    local old_ifs="$IFS"

    BOOTSTRAP_PATH=""
    add_path_entry "$HOME/.local/bin"
    add_path_entry "$HOME/.local/share/mise/shims"

    if [ "$UNAME_S" = "Darwin" ]; then
        add_path_entry /opt/homebrew/bin
        add_path_entry /usr/local/bin
    fi

    IFS=:
    for entry in $PATH; do
        if [ -d "$entry" ] && [ -x "$entry" ]; then
            add_path_entry "$entry"
        fi
    done
    IFS="$old_ifs"

    export PATH="$BOOTSTRAP_PATH"
}

set_bootstrap_path

has() {
    command -v "$1" >/dev/null 2>&1
}

ensure_locale() {
    local current
    local candidate
    local available=""
    local choice=""

    if has locale; then
        available="$(locale -a 2>/dev/null || true)"
    fi

    # If the inherited locale already works, keep it.
    if [ -n "${LC_ALL:-}" ]; then
        current="$LC_ALL"
    elif [ -n "${LANG:-}" ]; then
        current="$LANG"
    else
        current=""
    fi

    if [ -n "$current" ] && [ -n "$available" ]; then
        case "$current" in
            *.[Uu][Tt][Ff]-8 | *.[Uu][Tt][Ff]8)
                if printf '%s\n' "$available" | grep -qiE "^${current%.*}\.(utf-?8)$"; then
                    return
                fi
                ;;
        esac
    fi

    # Pick the first supported UTF-8 locale we know how to use.
    for candidate in C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8; do
        if [ -z "$available" ] || printf '%s\n' "$available" | grep -qiFx "$candidate"; then
            choice="$candidate"
            break
        fi
    done

    if [ -z "$choice" ]; then
        choice="C.UTF-8"
    fi

    unset LC_ALL LANGUAGE
    export LANG="$choice"
    export LC_ALL="$choice"
}

ensure_locale

configure_bootstrap_mise() {
    BOOTSTRAP_MISE_CONFIG="$(mktemp "${TMPDIR:-/tmp}/init-mise-bootstrap.XXXXXX.toml")"
    chmod 600 "$BOOTSTRAP_MISE_CONFIG"
    {
        printf '[tools]\n'
        printf 'python = "%s"\n' "$(resolve_python_mise_version)"
        printf 'uv = "latest"\n'
        printf '\n[settings.python]\n'
        printf 'compile = false\n'
        printf 'precompiled_flavor = "%s"\n' "$PYTHON_PRECOMPILED_FLAVOR"
        printf '\n[settings.ruby]\n'
        printf 'compile = false\n'
    } >"$BOOTSTRAP_MISE_CONFIG"

    export MISE_GLOBAL_CONFIG_FILE="$BOOTSTRAP_MISE_CONFIG"
}

cleanup_bootstrap_mise() {
    if [ -n "$BOOTSTRAP_MISE_CONFIG" ]; then
        rm -f "$BOOTSTRAP_MISE_CONFIG"
    fi
}

detect_sudo_target_user() {
    local sudo_user="${SUDO_USER:-}"
    local passwd_entry
    local _name _passwd _uid _gid _gecos home _shell

    if [ "$(id -u)" -ne 0 ] || [ -z "$sudo_user" ] || [ "$sudo_user" = "root" ]; then
        return
    fi

    if ! id "$sudo_user" >/dev/null 2>&1; then
        printf 'sudo invoked init for unknown user %s.\n' "$sudo_user" >&2
        exit 1
    fi

    if has getent; then
        passwd_entry="$(getent passwd "$sudo_user" || true)"
        if [ -n "$passwd_entry" ]; then
            IFS=: read -r _name _passwd _uid _gid _gecos home _shell <<EOF
$passwd_entry
EOF
            SUDO_TARGET_HOME="$home"
        fi
    fi

    if [ -z "$SUDO_TARGET_HOME" ]; then
        SUDO_TARGET_HOME="$(sudo -H -u "$sudo_user" sh -c 'printf %s "$HOME"')"
    fi

    if [ -z "$SUDO_TARGET_HOME" ]; then
        printf 'Failed to resolve home directory for sudo user %s.\n' "$sudo_user" >&2
        exit 1
    fi

    SUDO_TARGET_USER="$sudo_user"
    TARGET_ANSIBLE_ARGS+=(
        -e "init_target_user=$SUDO_TARGET_USER"
        -e "init_target_home=$SUDO_TARGET_HOME"
    )
    printf 'sudo detected; package tasks run as root and user tasks target %s (%s).\n' "$SUDO_TARGET_USER" "$SUDO_TARGET_HOME" >&2
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

    mkdir -p "$HOME/.local/bin"

    # Prefer a mise already installed in ~/.local/bin so we don't re-download
    # on every run. Otherwise install mise (latest by default) and prefer it,
    # even when an older system mise exists on PATH.
    if [ -x "$HOME/.local/bin/mise" ]; then
        MISE_BIN="$HOME/.local/bin/mise"
        return
    fi

    installer_path="$(mktemp)"
    trap 'rm -f "$installer_path"' RETURN
    download_url "https://mise.jdx.dev/install.sh" "$installer_path"
    chmod +x "$installer_path"
    if [ -n "$MISE_INSTALL_VERSION" ] && [ "$MISE_INSTALL_VERSION" != "latest" ]; then
        MISE_VERSION="$MISE_INSTALL_VERSION" MISE_INSTALL_PATH="$HOME/.local/bin/mise" sh "$installer_path"
    else
        MISE_INSTALL_PATH="$HOME/.local/bin/mise" sh "$installer_path"
    fi
    MISE_BIN="$HOME/.local/bin/mise"
}

activate_mise() {
    set +u
    eval "$("$MISE_BIN" activate bash)"
    set -u
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
        "$MISE_BIN" reshim uv >/dev/null 2>&1 || true
    fi
}

run_uv() {
    if has uv; then
        uv "$@"
    else
        "$MISE_BIN" exec uv@latest -- uv "$@"
    fi
}

ensure_pipx() {
    if ! run_uv tool list | awk '{print $1}' | grep -qx 'pipx'; then
        run_uv tool install pipx
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

resolve_ansible_python_interpreter() {
    local python_bin

    if [ -n "$SUDO_TARGET_USER" ]; then
        if [ -x /usr/bin/python3 ]; then
            printf '%s\n' /usr/bin/python3
            return
        fi

        if has python3; then
            command -v python3
            return
        fi
    fi

    python_bin="$("$MISE_BIN" which python3 2>/dev/null || true)"
    if [ -n "$python_bin" ] && [ -x "$python_bin" ]; then
        printf '%s\n' "$python_bin"
        return
    fi

    if has python3; then
        command -v python3
        return
    fi

    printf 'Failed to resolve a Python interpreter for Ansible.\n' >&2
    exit 1
}

resolve_install_packages_choice() {
    local choice="unknown"
    local i=0
    local arg
    local value

    if [ "$AUTO_YES" -eq 1 ]; then
        choice="yes"
    fi

    while [ "$i" -lt "${#ANSIBLE_ARGS[@]}" ]; do
        arg="${ANSIBLE_ARGS[$i]}"
        value=""

        case "$arg" in
            -e|--extra-vars)
                i=$((i + 1))
                if [ "$i" -lt "${#ANSIBLE_ARGS[@]}" ]; then
                    value="${ANSIBLE_ARGS[$i]}"
                fi
                ;;
            -e*)
                value="${arg#-e}"
                ;;
            --extra-vars=*)
                value="${arg#--extra-vars=}"
                ;;
        esac

        case "$value" in
            *install_packages=no*|*install_packages=false*|*install_packages=0*|*"install_packages":"no"*|*"install_packages":\ "no"*|*"install_packages":false*|*"install_packages":\ false*)
                choice="no"
                ;;
            *install_packages=yes*|*install_packages=true*|*install_packages=1*|*"install_packages":"yes"*|*"install_packages":\ "yes"*|*"install_packages":true*|*"install_packages":\ true*)
                choice="yes"
                ;;
        esac

        i=$((i + 1))
    done

    printf '%s\n' "$choice"
}

extra_vars_have_become_password() {
    case "$1" in
        *ansible_become_password*|*ansible_become_pass*) return 0 ;;
    esac

    return 1
}

has_ansible_become_auth() {
    local i=0
    local arg
    local value

    if [ -n "${ANSIBLE_BECOME_PASSWORD:-}" ] || [ -n "${ANSIBLE_BECOME_PASS:-}" ]; then
        return 0
    fi

    while [ "$i" -lt "${#ANSIBLE_ARGS[@]}" ]; do
        arg="${ANSIBLE_ARGS[$i]}"
        value=""

        case "$arg" in
            -K|--ask-become-pass|--ask-become-password|--become-password-file|--become-password-file=*)
                return 0
                ;;
            -e|--extra-vars)
                i=$((i + 1))
                if [ "$i" -lt "${#ANSIBLE_ARGS[@]}" ]; then
                    value="${ANSIBLE_ARGS[$i]}"
                fi
                ;;
            -e*)
                value="${arg#-e}"
                ;;
            --extra-vars=*)
                value="${arg#--extra-vars=}"
                ;;
        esac

        if [ -n "$value" ] && extra_vars_have_become_password "$value"; then
            return 0
        fi

        i=$((i + 1))
    done

    return 1
}

ensure_sudo_for_linux_packages() {
    local install_packages_choice

    if [ "$UNAME_S" != "Linux" ] || [ "$(id -u)" -eq 0 ]; then
        return
    fi

    install_packages_choice="$(resolve_install_packages_choice)"
    if [ "$install_packages_choice" = "no" ]; then
        return
    fi

    if [ "$install_packages_choice" = "unknown" ]; then
        return
    fi

    if ! has sudo; then
        printf 'Linux package installation requires sudo, but sudo is not installed. Rerun as root or pass -e install_packages=no.\n' >&2
        exit 1
    fi

    if sudo -n true 2>/dev/null; then
        return
    fi

    if has_ansible_become_auth; then
        return
    fi

    # sudo needs a password and none was supplied. If we have an interactive
    # terminal, ask ansible to prompt for it so the (only) become tasks, the
    # Linux package installs, can authenticate. Otherwise we cannot continue.
    if [ -t 0 ]; then
        SUDO_ANSIBLE_ARGS+=(--ask-become-pass)
        printf 'Linux package installation needs sudo; you will be prompted for your sudo password.\n' >&2
        return
    fi

    printf 'Linux package installation requires sudo credentials. Run sudo -v first, rerun as root, pass --ask-become-pass from an interactive terminal, or pass -e install_packages=no.\n' >&2
    exit 1
}

trap cleanup_bootstrap_mise EXIT

parse_args "$@"
detect_sudo_target_user
configure_bootstrap_mise

ensure_fetcher
ensure_mise
trust_global_mise_config
activate_mise
ensure_python
ensure_pipx
ensure_ansible

if [ "$AUTO_YES" -eq 1 ]; then
    AUTO_ANSIBLE_ARGS+=(
        -e config_mode=copy
        -e install_packages=yes
        -e install_optional_packages=yes
        -e install_workspace_dirs=yes
        -e install_mise_direnv=yes
        -e trust_mise_config=yes
        -e install_wifi_helper=no
        -e install_proxmox_helper=no
        -e install_newt_service_helper=no
        -e install_fetchall_helper=yes
        -e install_aliases=yes
        -e install_profiles=yes
        -e install_tmux=yes
        -e install_zsh_theme=yes
        -e confirm_install=yes
    )
fi

ensure_sudo_for_linux_packages

exec ansible-playbook \
    -i "${ROOT_DIR}/inventory.ini" \
    -e "ansible_python_interpreter=$(resolve_ansible_python_interpreter)" \
    "${SUDO_ANSIBLE_ARGS[@]}" \
    "${TARGET_ANSIBLE_ARGS[@]}" \
    "${AUTO_ANSIBLE_ARGS[@]}" \
    "${ANSIBLE_ARGS[@]}" \
    "${ROOT_DIR}/playbook.yml"
