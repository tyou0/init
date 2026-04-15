#!/bin/bash

# 1. Setup Service User and Directories
sudo useradd -r -s /bin/false newt 2>/dev/null
sudo mkdir -p /etc/newt
sudo mkdir -p /var/lib/newt

# 2. Securely Move Existing Root Config
# This assumes you ran the official Pangolin script previously
ROOT_CONFIG="/root/.config/newt-client/config.json"

if [ -f "$ROOT_CONFIG" ]; then
    echo "Found existing config. Moving to secure location..."
    sudo cp "$ROOT_CONFIG" /etc/newt/config.json
    # Set permissions: root owns it, newt user can only read it
    sudo chown root:newt /etc/newt/config.json
    sudo chmod 640 /etc/newt/config.json
else
    echo "Error: Could not find config at $ROOT_CONFIG"
    echo "Please ensure you have run the Pangolin install script first."
    exit 1
fi

# 3. Ensure Binary is in Path
if [ ! -f "/usr/local/bin/newt" ]; then
    sudo cp $(which newt) /usr/local/bin/newt 2>/dev/null
fi

# 4. Create the Systemd Unit File
# Uses the --config flag to hide credentials from 'ps' commands
cat <<EOF | sudo tee /etc/systemd/system/newt.service
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
sudo systemctl daemon-reload
sudo systemctl enable newt
sudo systemctl restart newt

echo "-----------------------------------------------"
echo "Newt is now running as a secure background service."
echo "Check status: sudo systemctl status newt"
echo "View logs:   sudo journalctl -u newt -f"
echo "-----------------------------------------------"
