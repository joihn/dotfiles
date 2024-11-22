#!/bin/sh

# Ask user for confirmation
printf "Do you want to install basic tools? (y/n): "
# Read a single character without waiting for Enter
if [ -t 0 ]; then
    # Save the current terminal settings
    old_stty_cfg=$(stty -g)
    # Set terminal to raw mode to read one character at a time
    stty raw -echo
    answer=$(dd bs=1 count=1 2>/dev/null)
    # Restore the terminal settings
    stty "$old_stty_cfg"
else
    # Non-interactive shell; read normally
    read answer
fi
echo

case "$answer" in
    [Yy])
        # Check if running inside Docker container
        if [ ! -f "/.dockerenv" ]; then
            # Execute only if not in Docker
            sudo apt update && sudo apt install git vim-gtk3 xclip sshfs wget zsh git-delta screen htop
        fi

        # Check if GNOME is installed
        if dpkg -l | grep -q gnome-shell; then
            # Check if the system architecture is x86-64
            if [ "$(uname -m)" = "x86_64" ]; then
                # Install mpv if both conditions are met
                sudo apt install -y mpv
            fi
        fi
        ;;
    [Nn])
        echo "Installation cancelled."
        exit 0
        ;;
    *)
        echo "Invalid input. Please enter 'y' or 'n'."
        exit 1
        ;;
esac

