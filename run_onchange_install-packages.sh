#!/bin/sh

# Check if running inside Docker container
if [ ! -f "/.dockerenv" ]; then
    # Execute only if not in Docker
    sudo apt update && sudo apt install git vim-gtk3 xclip sshfs wget zsh 
fi

# Check if GNOME is installed
if dpkg -l | grep -q gnome-shell; then
    # Check if the system architecture is x86-64
    if [ "$(uname -m)" = "x86_64" ]; then
        # Install mpv if both conditions are met
        sudo apt install -y mpv
    fi
fi
