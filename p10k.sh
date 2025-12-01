#!/usr/bin/env bash
set -e

ZDOT="${ZDOTDIR:-$HOME}"
ZIM_HOME="$ZDOT/.zim"
ZSHRC="$ZDOT/.zshrc"
ZIMRC="$ZDOT/.zimrc"

### ------------------------------------------------------------
### Cross‑platform safe "delete matching lines" function
### ------------------------------------------------------------
delete_lines() {
    local pattern="$1"
    local file="$2"
    [ ! -f "$file" ] && touch "$file"
    grep -vF "$pattern" "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
}

echo "=== Installing dependencies ==="
if ! command -v zsh >/dev/null 2>&1; then
    if command -v apt >/dev/null 2>&1; then
        sudo apt update && sudo apt install -y zsh curl git fonts-powerline
    else
        echo "Install zsh, curl, git manually and re-run."
        exit 1
    fi
fi

echo "=== Installing Zim if missing ==="
if [ ! -d "$ZIM_HOME" ]; then
    curl -fsSL https://raw.githubusercontent.com/zimfw/install/master/install.zsh | zsh
fi

echo "=== Fixing .zimrc ==="
touch "$ZIMRC"
delete_lines "modules/powerlevel10k" "$ZIMRC"
delete_lines "zmodule powerlevel10k" "$ZIMRC"
echo "zmodule powerlevel10k" >> "$ZIMRC"

echo "=== Removing old Powerlevel10k module ==="
rm -rf "$ZIM_HOME/modules/powerlevel10k"

echo "=== Installing fresh Powerlevel10k ==="
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
    "$ZIM_HOME/modules/powerlevel10k"

echo "=== Fixing .zshrc ==="
touch "$ZSHRC"
delete_lines "oh-my-zsh" "$ZSHRC"
delete_lines "ZSH_THEME" "$ZSHRC"
delete_lines "plugins=" "$ZSHRC"

# Ensure Zim init block exists
if ! grep -q "zimfw.zsh" "$ZSHRC"; then
cat >> "$ZSHRC" <<EOF

# >>> Zim Initialization >>>
export ZIM_HOME="\${ZDOTDIR:-\$HOME}/.zim"
source "\$ZIM_HOME/zimfw.zsh" init -q
# <<< Zim Initialization <<<
EOF
fi

echo "=== Rebuilding Zim ==="
zsh -c "export ZIM_HOME='$ZIM_HOME'; source '$ZIM_HOME/zimfw.zsh' init -q; zimfw install"
zsh -c "export ZIM_HOME='$ZIM_HOME'; source '$ZIM_HOME/zimfw.zsh' init -q; zimfw update"

echo "=== Adding Powerlevel10k auto-config ==="
if ! grep -q "p10k configure" "$ZSHRC"; then
cat >> "$ZSHRC" <<'EOF'

# Auto-run Powerlevel10k configuration if missing
if [ ! -f ~/.p10k.zsh ]; then
  (sleep 1; p10k configure) &
fi
EOF
fi

echo
echo "==========================================="
echo " INSTALL COMPLETE"
echo " Open a NEW terminal and P10K WILL START."
echo " If not, run: zsh"
echo "==========================================="
