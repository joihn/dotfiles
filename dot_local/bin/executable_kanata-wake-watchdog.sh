#!/usr/bin/env bash
#
# kanata wake WATCHDOG — closes the gap that the sleepwatcher wake hook can't.
#
# sleepwatcher's `-w` only fires on a *full* user wake. But on macOS the kanata
# keyboard *input* grab can also silently die on **DarkWake / scheduled-alarm**
# wakes (e.g. a calendar/maintenance wake), which `-w` never sees. kanata's
# DriverKit *output*-sink recovery doesn't catch this either (the output side is
# fine; it's the input grab that's gone), so kanata sits there grabbed-but-deaf
# until something kickstarts it. Observed 2026-06-19: grab died on a 10:00:00
# `calaccessd` alarm wake; no hook fired; keyboard unremapped until a manual
# `launchctl kickstart -k`.
#
# Strategy: don't try to *detect* the (silent) grab death, and don't depend on
# the *kind* of wake. Run on a short launchd StartInterval and simply re-grab
# whenever the most-recent wake (full OR DarkWake) is newer than kanata's current
# process start time — i.e. a wake happened since kanata last (re)started, so its
# grab may be stale. This self-dedupes: after a re-grab the process start moves
# past the wake, so it won't fire again until the *next* wake. It also dedupes
# against sleepwatcher (which updates the same process start on full wakes).
#
# launchd defers StartInterval jobs while the machine is asleep and runs them in
# the CPU window of a wake, so this costs ~nothing on battery and never wakes a
# sleeping machine.
set -euo pipefail

DAEMON_LABEL="dev.kanata.kanata"
# kanata-wake-restart.sh lives next to this script; it does the settle + kickstart
# + verify + retry and carries the self-expiring lock that prevents this watchdog
# and sleepwatcher from stomping each other.
RESTART="$(cd "$(dirname "$0")" && pwd)/kanata-wake-restart.sh"

ts() { date '+%Y-%m-%d %H:%M:%S'; }

# Most recent wake transition (full Wake or DarkWake) from the power log.
# Exclude the non-transition "Wake Requests/Reason/Delay/Acks" info rows.
wake_ts="$(pmset -g log 2>/dev/null \
  | grep -E ' [+-][0-9]{4} +(Wake|DarkWake) ' \
  | grep -vE 'Wake (Requests|Reason|Delay|Acks)' \
  | tail -n1 | awk '{print $1" "$2" "$3}')"
[ -n "${wake_ts:-}" ] || exit 0
wake_epoch="$(date -j -f "%Y-%m-%d %H:%M:%S %z" "$wake_ts" +%s 2>/dev/null)" || exit 0

# kanata daemon PID + its start time (proxy for "when it last (re)grabbed").
pid="$(launchctl print "system/${DAEMON_LABEL}" 2>/dev/null \
  | awk -F'= ' '/^[[:space:]]*pid =/{print $2; exit}')"
[ -n "${pid:-}" ] || exit 0
proc_start="$(ps -o lstart= -p "$pid" 2>/dev/null)" || exit 0
proc_start="$(echo "$proc_start" | sed -E 's/[[:space:]]+$//')"
grab_epoch="$(date -j -f "%a %b %e %T %Y" "$proc_start" +%s 2>/dev/null)" || exit 0

# A wake landed after kanata last started -> grab may be stale -> re-grab.
if [ "$wake_epoch" -gt "$grab_epoch" ]; then
  echo "$(ts) watchdog: wake at ${wake_ts} is newer than kanata start ($(date -r "$grab_epoch" '+%F %T')); triggering re-grab"
  exec "$RESTART"
fi
exit 0
