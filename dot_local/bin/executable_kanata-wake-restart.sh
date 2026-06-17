#!/usr/bin/env bash
#
# Wake hook for kanata.
#
# macOS tears down kanata's IOHIDManager keyboard grab when the machine sleeps,
# but kanata's connection to the Karabiner virtual HID device survives. On wake
# kanata can get stuck looping on `virtual_hid_keyboard_ready true` and never
# re-grab the real keyboard, so remaps silently stop working.
#
# Run by sleepwatcher (as root, via /Library/LaunchDaemons/dev.kanata.wake.plist)
# on every wake. A hard `kickstart -k` forces kanata to tear down and re-grab the
# keyboard. Hazards this script guards against:
#
#   1. Driver-not-ready race: if we kickstart too soon after wake, kanata reaches
#      "Starting kanata proper" before the Karabiner virtual HID driver has fully
#      re-initialized, the grab silently fails (no crash, so launchd KeepAlive
#      does NOT catch it), and the keyboard is dead. -> generous settle delay.
#   2. Wake bursts (e.g. a sleep/wake test loop) firing this script several times
#      concurrently and stomping each other's restart. -> single-run lock.
#   3. A restart that still didn't take. -> verify kanata actually reached its
#      grab-init milestone, and retry a couple of times if not.
set -euo pipefail

DAEMON_LABEL="dev.kanata.kanata"
LOG="/var/log/kanata.log"
LOCK="/tmp/kanata-wake.lock"
SETTLE=7        # seconds to let the HID stack + virtual device come back first
MAX_TRIES=3

ts() { date '+%Y-%m-%d %H:%M:%S'; }

# (2) Single-run lock: mkdir is atomic. If a run is already in flight (wake
# burst), bail out rather than stack concurrent kickstarts. The lock is
# self-expiring: if a previous run was killed mid-flight (e.g. the machine slept
# again before its trap fired) a stale lock dir would otherwise block every
# future wake, so reclaim any lock older than STALE_SECS.
STALE_SECS=45
if ! mkdir "$LOCK" 2>/dev/null; then
  lock_age=$(( $(date +%s) - $(stat -f %m "$LOCK" 2>/dev/null || date +%s) ))
  if [ "$lock_age" -ge "$STALE_SECS" ]; then
    echo "$(ts) wake: reclaiming stale lock (age ${lock_age}s)"
    rmdir "$LOCK" 2>/dev/null || true
    mkdir "$LOCK" 2>/dev/null || { echo "$(ts) wake: lock contended, skipping"; exit 0; }
  else
    echo "$(ts) wake: another run in progress (lock age ${lock_age}s), skipping"
    exit 0
  fi
fi
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT

# "Starting kanata proper" is logged once per (re)start, right as kanata begins
# grabbing. Counting it tells us whether a kickstart actually produced a fresh
# start. (-a: the log carries ANSI colour bytes, treat as text.)
milestone_count() { grep -ac 'Starting kanata proper' "$LOG" 2>/dev/null || echo 0; }

# (1) Let the driver settle before the first attempt.
sleep "$SETTLE"

for try in $(seq 1 "$MAX_TRIES"); do
  before=$(milestone_count)
  /bin/launchctl kickstart -k "system/${DAEMON_LABEL}"
  echo "$(ts) wake: kickstarted ${DAEMON_LABEL} (try ${try}/${MAX_TRIES}, settle ${SETTLE}s)"

  # kanata's startup: 2s key-release wait + ~2s driver reconnect + grab. Give it
  # room, then confirm it advanced past the grab-init milestone.
  sleep 8
  if [ "$(milestone_count)" -gt "$before" ]; then
    echo "$(ts) wake: kanata reached grab init, done"
    exit 0
  fi
  echo "$(ts) wake: kanata did not reach grab init, retrying"
  SETTLE=4   # already waited once; shorter settle on retries
done

echo "$(ts) wake: gave up after ${MAX_TRIES} tries"
exit 1
