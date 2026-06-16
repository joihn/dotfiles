#!/bin/sh

# Install cross-platform CLI tools via Homebrew (macOS Homebrew + Linux linuxbrew).
# This is a run_onchange script: it re-runs only when the package list below
# changes. `brew bundle` is idempotent, so already-installed tools are skipped.

# Locate brew (chezmoi may run this with a minimal PATH).
if command -v brew >/dev/null 2>&1; then
    BREW=brew
elif [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
    BREW=/home/linuxbrew/.linuxbrew/bin/brew
elif [ -x /opt/homebrew/bin/brew ]; then
    BREW=/opt/homebrew/bin/brew
elif [ -x /usr/local/bin/brew ]; then
    BREW=/usr/local/bin/brew
else
    echo "brew not found; skipping brew package install." >&2
    exit 0
fi

# kitty is a macOS cask only (no linuxbrew formula). On Linux the `kitten`
# binary is installed via a chezmoi external in .chezmoiexternal.toml instead.
cask_line=""
[ "$(uname)" = "Darwin" ] && cask_line='cask "kitty"'

"$BREW" bundle --file=/dev/stdin <<BREWFILE
brew "broot"
brew "lazygit"
brew "lazydocker"
brew "uv"
$cask_line
BREWFILE
