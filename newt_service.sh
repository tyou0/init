#!/usr/bin/env bash
set -euo pipefail

# Manual post-install helper for Newt.
# Run this only after the upstream Newt/Pangolin install has already completed
# and created /root/.config/newt-client/config.json.

has() {
    command -v "$1" >/dev/null 2>&1
}

run_as_root() {
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        "$@"
    else
        if ! has sudo; then
            printf 'sudo is required when not running as root.\n' >&2
            exit 1
        fi
        sudo "$@"
    fi
}

if [ "$(uname -s)" != "Linux" ]; then
    printf 'newt_service.sh only supports Linux hosts.\n' >&2
    exit 1
fi

if ! has systemctl; then
    printf 'systemctl is required to install the Newt service helper.\n' >&2
    exit 1
fi

if ! has newt; then
    printf 'newt must already be installed before running this helper.\n' >&2
    exit 1
fi

# 1. Setup Service User and Directories
run_as_root useradd -r -s /bin/false newt 2>/dev/null || true
run_as_root mkdir -p /etc/newt
run_as_root mkdir -p /var/lib/newt

# 2. Securely Move Existing Root Config
# This assumes you ran the official Pangolin script previously
ROOT_CONFIG="/root/.config/newt-client/config.json"

if [ -f "$ROOT_CONFIG" ]; then
    echo "Found existing config. Moving to secure location..."
    run_as_root cp "$ROOT_CONFIG" /etc/newt/config.json
    # Set permissions: root owns it, newt user can only read it
    run_as_root chown root:newt /etc/newt/config.json
    run_as_root chmod 640 /etc/newt/config.json
else
    echo "Error: Could not find config at $ROOT_CONFIG"
    echo "Please ensure you have run the upstream Pangolin/Newt install script first."
    exit 1
fi

# 3. Ensure Binary is in Path
if [ ! -f "/usr/local/bin/newt" ]; then
    run_as_root cp "$(command -v newt)" /usr/local/bin/newt
fi

# 4. Create the Systemd Unit File
# Uses the --config flag to hide credentials from 'ps' commands
cat <<EOF | run_as_root tee /etc/systemd/system/newt.service >/dev/null
[Unit]
Description=Newt Reverse Proxy Daemon
After=network.target

[Service]
Type=simple
User=newt
Group=newt
WorkingDirectory=/var/lib/newt
ExecStart=/usr/local/bin/newt --config /etc/newt/config.json
Restart=always
RestartSec=5

# Security Hardening
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
NoNewPrivileges=true
ReadOnlyPaths=/etc/newt/config.json

[Install]
WantedBy=multi-user.target
EOF

# 5. Launch the Daemon
run_as_root systemctl daemon-reload
run_as_root systemctl enable newt
run_as_root systemctl restart newt

echo "-----------------------------------------------"
echo "Newt is now running as a secure background service."
echo "Check status: sudo systemctl status newt"
echo "View logs:   sudo journalctl -u newt -f"
echo "-----------------------------------------------"
