#!/bin/bash
set -ex
cd ~

# Tier-0 bootstrap (pre-chezmoi). Ensures git + a package manager exist before
# `chezmoi init` clones the repo and runs the in-repo bootstrap scripts
# (.chezmoiscripts/run_once_before_*). Those scripts then install Homebrew and
# the rest of the toolchain; this file only needs to get us far enough to clone.

# On Linux, seed git/curl so the clone works even on a bare machine.
if [ "$(uname)" = "Linux" ] && command -v sudo >/dev/null 2>&1 && [ ! -f /.dockerenv ]; then
    sudo apt-get update && sudo apt-get install -y git curl
fi

# A login shell to land in. zsh is installed properly via brew by the chezmoi
# bootstrap scripts; this static build just gives us a usable zsh immediately.
sh -c "$(curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/romkatv/zsh-bin/master/install)" -- -d ~/.local/ -e no -q
export PATH="$HOME/.local/bin:$PATH"

mkdir -p ~/.config/chezmoi
printf "data:\n    DISPLAY_VAR: :1\n" >> ~/.config/chezmoi/chezmoi.yaml
sh -c "$(curl --proto '=https' --tlsv1.2 -fsLS https://chezmoi.io/get)" -- init --apply joihn

curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh

export TERM=xterm-256color

zsh -l
