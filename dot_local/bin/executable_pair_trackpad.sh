#!/bin/bash

set -euo pipefail

# This script is intentionally specific to this MacBook. Using the Bluetooth
# address avoids depending on the punctuation in the device's display name.
readonly device_name="Maxime’s Magic Trackpad"
readonly device_address="BC:D0:74:B8:BD:F6"
readonly pairing_timeout=30

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "pair_trackpad.sh: this script only supports macOS." >&2
    exit 1
fi

if ! command -v blueutil >/dev/null 2>&1; then
    echo "pair_trackpad.sh: blueutil is required." >&2
    echo "Install it with: brew install blueutil" >&2
    exit 127
fi

if blueutil --unpair "$device_address"; then
    printf 'Forgot Bluetooth device: %s\n' "$device_name"
else
    printf 'Could not forget Bluetooth device; continuing with pairing: %s (%s)\n' \
        "$device_name" "$device_address" >&2
fi

printf 'Trying to pair Bluetooth device for at least %d seconds: %s\n' \
    "$pairing_timeout" "$device_name"

pairing_started_at=$SECONDS
pairing_attempt=1

while true; do
    printf 'Pairing attempt %d...\n' "$pairing_attempt"

    if blueutil --pair "$device_address"; then
        printf 'Paired Bluetooth device: %s\n' "$device_name"
        exit 0
    fi

    pairing_elapsed=$((SECONDS - pairing_started_at))
    if (( pairing_elapsed >= pairing_timeout )); then
        break
    fi

    printf 'Pairing failed; retrying...\n' >&2
    sleep 0.5
    pairing_attempt=$((pairing_attempt + 1))
done

printf 'pair_trackpad.sh: could not pair Bluetooth device after %d seconds: %s (%s)\n' \
    "$pairing_elapsed" "$device_name" "$device_address" >&2
exit 1
