#!/usr/bin/env bash
#
# kanata vk-agent log TRIGGER — symptom-based recovery layer.
#
# The sleepwatcher hook (dev.kanata.wake) and the pmset watchdog
# (dev.kanata.wake-watchdog) both key off *system* sleep/wake events. But the
# kanata grab/sink can also break on things that are NOT a system wake at all —
# e.g. a display-wake, a power-adapter attach, or virtual-HID churn
# (IOHIDLibUserClient open/close on the Karabiner keyboard). Observed
# 2026-06-22 ~10:23: no system sleep occurred, yet the daemon socket died and
# the keyboard went unremapped until a manual restart.
#
# The one distinctive signal in those cases is in the vk-agent log: when the
# daemon's TCP socket dies under the agent, the agent logs
#   [ERROR] failed to write message to kanata: Broken pipe (os error 32)
# This watcher tails that log and, on that line, calls kanata-wake-restart.sh
# (settle + kickstart + verify, with the shared self-expiring lock that dedupes
# against sleepwatcher and the watchdog).
#
# IMPORTANT — we match ONLY the broken-pipe / failed-write line, never the
# "failed to connect to kanata within 2 seconds" panic: that panic is emitted
# routinely right after every kickstart (the agent races the restarting daemon),
# so triggering on it would loop forever.
#
# Feedback-loop guard: our own kickstart kills the daemon socket, which can make
# the agent log ANOTHER broken pipe. So we ignore any match while the kanata
# daemon process is younger than COOLDOWN seconds — i.e. it just (re)started.
# This is stateless (no cooldown file): a genuine break long after the last
# restart has a large daemon age and fires; kickstart-induced echoes have a tiny
# daemon age and are skipped.
#
# Must run as root (kickstarting a system LaunchDaemon needs root). Installed as
# /Library/LaunchDaemons/dev.kanata.vkagent-trigger.plist with KeepAlive, so the
# tail is resurrected if it ever exits (e.g. the log file is rotated away).
set -u

DAEMON_LABEL="dev.kanata.kanata"
VKLOG="/Users/maximegardoni/.local/log/kanata-vk-agent.log"
RESTART="$(cd "$(dirname "$0")" && pwd)/kanata-wake-restart.sh"
COOLDOWN=45                       # ignore matches while kanata is younger than this
MATCH='Broken pipe|failed to write message to kanata'

ts() { date '+%Y-%m-%d %H:%M:%S'; }

# Seconds since the kanata daemon last (re)started. 999999 if it can't be found
# (treat "unknown" as old, so a genuine problem still triggers a restart).
daemon_age() {
  local pid start epoch
  pid="$(launchctl print "system/${DAEMON_LABEL}" 2>/dev/null \
    | awk -F'= ' '/^[[:space:]]*pid =/{print $2; exit}')"
  [ -n "${pid:-}" ] || { echo 999999; return; }
  start="$(ps -o lstart= -p "$pid" 2>/dev/null | sed -E 's/[[:space:]]+$//')"
  [ -n "${start:-}" ] || { echo 999999; return; }
  epoch="$(date -j -f "%a %b %e %T %Y" "$start" +%s 2>/dev/null)" || { echo 999999; return; }
  echo $(( $(date +%s) - epoch ))
}

echo "$(ts) vkagent-trigger: watching ${VKLOG} (cooldown ${COOLDOWN}s)"

# -n0: only react to NEW lines, never historical ones (no spurious restart on
# load). -F: follow by name and retry, so log rotation/recreation is handled.
# --line-buffered: forward matches immediately.
tail -n0 -F "$VKLOG" 2>/dev/null | grep --line-buffered -E "$MATCH" | while read -r _line; do
  age="$(daemon_age)"
  if [ "$age" -lt "$COOLDOWN" ]; then
    echo "$(ts) vkagent-trigger: agent write-failure, but kanata age ${age}s < ${COOLDOWN}s cooldown -> skipping"
    continue
  fi
  echo "$(ts) vkagent-trigger: agent write-failure (kanata age ${age}s) -> triggering re-grab"
  "$RESTART" || echo "$(ts) vkagent-trigger: restart helper returned non-zero"
done
