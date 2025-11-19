#!/usr/bin/env bash

set -e

# Install Zsh
if ! command -v zsh >/dev/null 2>&1; then
    echo "Installing zsh..."
    if command -v apt >/dev/null 2>&1; then
        sudo apt update && sudo apt install -y zsh
    elif command -v brew >/dev/null 2>&1; then
        brew install zsh
    else
        echo "No supported package manager found. Install zsh manually."
        exit 1
    fi
fi

# Make zsh default shell
if [ "$SHELL" != "$(command -v zsh)" ]; then
    echo "Changing default shell to zsh..."
    chsh -s "$(command -v zsh)"
fi

# Install Zim
if [ ! -d "${ZDOTDIR:-$HOME}/.zim" ]; then
    echo "Installing Zim..."
    curl -fsSL https://raw.githubusercontent.com/zimfw/install/master/install.zsh | zsh
fi

# Install Powerlevel10k
if [ ! -d "${ZDOTDIR:-$HOME}/.zim/modules/powerlevel10k" ]; then
    echo "Adding Powerlevel10k module..."
    mkdir -p "${ZDOTDIR:-$HOME}/.zim/modules/powerlevel10k"
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
        "${ZDOTDIR:-$HOME}/.zim/modules/powerlevel10k"
fi

# Enable p10k in .zimrc
if ! grep -q "zmodule powerlevel10k" "${ZDOTDIR:-$HOME}/.zimrc"; then
    echo "zmodule powerlevel10k" >> "${ZDOTDIR:-$HOME}/.zimrc"
fi

# Rebuild Zim
echo "Rebuilding Zim..."
zsh -c 'zimfw install'
zsh -c 'zimfw update'

echo "Done! Restart your terminal to load Powerlevel10k config."
