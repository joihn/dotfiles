#!/bin/sh

# Check if running inside Docker container
if [ ! -f "/.dockerenv" ]; then
    # Execute only if not in Docker
    sudo apt update && sudo apt install git vim xclip sshfs wget zsh
fi
