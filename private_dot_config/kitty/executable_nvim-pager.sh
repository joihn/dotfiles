#!/bin/sh
# This script will receive the line number as its first argument ($1)

# The '-' at the end tells nvim to read from standard input,
# which is how Kitty sends the scrollback buffer content.
/opt/homebrew/bin/nvim -u NONE -R -M -c "lua require('kitty+page')($1)" -
