#!/bin/sh
set -eu

proxy_url="${BITWARDEN_PROXY_URL:-http://localhost:8889}"

case "$(uname -s)" in
  Darwin)
    if [ ! -d "/Applications/Bitwarden.app" ]; then
      printf '%s\n' "Bitwarden.app was not found in /Applications." >&2
      exit 1
    fi

    exec open -na "/Applications/Bitwarden.app" --args --proxy-server="$proxy_url" "$@"
    ;;
  Linux)
    if command -v bitwarden >/dev/null 2>&1; then
      exec env \
        HTTP_PROXY="$proxy_url" \
        HTTPS_PROXY="$proxy_url" \
        http_proxy="$proxy_url" \
        https_proxy="$proxy_url" \
        bitwarden --proxy-server="$proxy_url" "$@"
    fi

    if command -v flatpak >/dev/null 2>&1 && flatpak info com.bitwarden.desktop >/dev/null 2>&1; then
      exec flatpak run \
        --env=HTTP_PROXY="$proxy_url" \
        --env=HTTPS_PROXY="$proxy_url" \
        --env=http_proxy="$proxy_url" \
        --env=https_proxy="$proxy_url" \
        com.bitwarden.desktop \
        --proxy-server="$proxy_url" \
        "$@"
    fi

    printf '%s\n' "Bitwarden was not found. Install the native bitwarden command or the com.bitwarden.desktop Flatpak." >&2
    exit 1
    ;;
  *)
    printf '%s\n' "Unsupported OS: $(uname -s)" >&2
    exit 1
    ;;
esac
