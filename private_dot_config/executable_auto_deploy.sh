#!/bin/bash
cd ~
# static zsh
sh -c "$(curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/romkatv/zsh-bin/master/install)" -- -d ~/.local/ -e no -q

export PATH="$HOME/.local/bin:$PATH"
# ho my zsh
ZSH="$HOME/.oh-my-zsh" SHELL="$HOME/.local/bin/zsh" sh -c "$(curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

mkdir -p ~/.config/chezmoi
printf "data:\n    DISPLAY_VAR: :1\n" >> ~/.config/chezmoi/chezmoi.yaml
sh -c "$(curl --proto '=https' --tlsv1.2 -fsLS https://chezmoi.io/get)" -- init --apply joihn

curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh

export TERM=xterm-256color

source ~/.zshrc && omz reload
