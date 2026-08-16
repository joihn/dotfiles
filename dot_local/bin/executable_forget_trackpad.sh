#!/bin/bash

set -euo pipefail

# This script is intentionally specific to this MacBook. Using the Bluetooth
# address avoids depending on the punctuation in the device's display name.
readonly device_name="Maxime’s Magic Trackpad"
readonly device_address="BC:D0:74:B8:BD:F6"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "forget_trackpad.sh: this script only supports macOS." >&2
    exit 1
fi

if ! command -v blueutil >/dev/null 2>&1; then
    echo "forget_trackpad.sh: blueutil is required." >&2
    echo "Install it with: brew install blueutil" >&2
    exit 127
fi

if blueutil --unpair "$device_address"; then
    printf 'Forgot Bluetooth device: %s\n' "$device_name"
else
    printf 'forget_trackpad.sh: could not forget Bluetooth device: %s (%s)\n' \
        "$device_name" "$device_address" >&2
    exit 1
fi
