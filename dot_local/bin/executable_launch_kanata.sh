#!/usr/bin/env bash
#
# kanata control helper.
#
# Autostart is handled by launchd (two jobs — no watchdogs anymore):
#   - kanata          -> /Library/LaunchDaemons/dev.kanata.kanata.plist    (root, at boot)
#   - kanata-vk-agent -> ~/Library/LaunchAgents/dev.kanata.vk-agent.plist  (your user, at login)
#
# The daemon runs the Homebrew binary /opt/homebrew/bin/kanata with -p 5829 so the
# vk-agent can drive app-aware layer switching over TCP. Post-wake recovery is
# handled by kanata itself (1.12.0+) plus launchd KeepAlive on hard crashes; the
# old sleepwatcher / wake-watchdog / vkagent-trigger recovery layers were removed
# on 2026-07-22.
#
# Because kanata runs from a root LaunchDaemon, launchd starts it as root at boot
# and there is no screen session to attach. Driving the daemon by hand still needs
# root, so the four privileged launchctl calls below are granted passwordless via
# /etc/sudoers.d/kanata -- each pinned to its exact argv against this one label.
#
# That pinning is why launchctl is called through $LAUNCHCTL as an absolute path:
# sudoers matches the resolved binary, so a PATH-resolved bare `launchctl` may not
# match the rule (and would silently prompt for a password). It also keeps the
# script working under the minimal environment Shortcuts.app runs scripts in --
# the "Restart kanata" shortcut (hotkey) invokes `launch_kanata.sh restart`.
#
# This script just wraps launchctl for convenient manual control.
set -euo pipefail

LAUNCHCTL="/bin/launchctl"
DAEMON_LABEL="dev.kanata.kanata"
AGENT_LABEL="dev.kanata.vk-agent"
DAEMON_PLIST="/Library/LaunchDaemons/${DAEMON_LABEL}.plist"
AGENT_PLIST="${HOME}/Library/LaunchAgents/${AGENT_LABEL}.plist"
GUI="gui/$(id -u)"

usage() {
  cat <<EOF
Usage: $(basename "$0") {start|stop|restart|status|logs}

  start     bootstrap + start both launchd jobs
  stop      stop both jobs (kanata daemon needs sudo)
  restart   kickstart -k both jobs (fast reload, e.g. after editing the .kbd)
  status    show launchd state + running processes
  logs      tail both log files
EOF
}

cmd="${1:-status}"
case "$cmd" in
  start)
    sudo "$LAUNCHCTL" bootstrap system "$DAEMON_PLIST" 2>/dev/null || \
      sudo "$LAUNCHCTL" kickstart -k "system/${DAEMON_LABEL}"
    "$LAUNCHCTL" bootstrap "$GUI" "$AGENT_PLIST" 2>/dev/null || \
      "$LAUNCHCTL" kickstart -k "${GUI}/${AGENT_LABEL}"
    echo "started."
    ;;
  stop)
    "$LAUNCHCTL" bootout "${GUI}/${AGENT_LABEL}" 2>/dev/null || true
    sudo "$LAUNCHCTL" bootout "system/${DAEMON_LABEL}" 2>/dev/null || true
    echo "stopped."
    ;;
  restart)
    sudo "$LAUNCHCTL" kickstart -k "system/${DAEMON_LABEL}"
    "$LAUNCHCTL" kickstart -k "${GUI}/${AGENT_LABEL}"
    echo "restarted."
    ;;
  status)
    echo "== daemon (kanata, root) =="
    sudo "$LAUNCHCTL" print "system/${DAEMON_LABEL}" 2>/dev/null | grep -E 'state|pid|program' | head || echo "not loaded"
    echo "== agent (kanata-vk-agent, user) =="
    "$LAUNCHCTL" print "${GUI}/${AGENT_LABEL}" 2>/dev/null | grep -E 'state|pid|program' | head || echo "not loaded"
    echo "== processes =="
    pgrep -fl 'kanata' || echo "(no kanata processes)"
    ;;
  logs)
    tail -n 40 -f /var/log/kanata.log "${HOME}/.local/log/kanata-vk-agent.log"
    ;;
  *)
    usage; exit 1 ;;
esac
