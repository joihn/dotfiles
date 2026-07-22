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
# Because kanata runs from a root LaunchDaemon, launchd starts it as root for you --
# there is no sudo password to type and no screen session to attach.
#
# This script just wraps launchctl for convenient manual control.
set -euo pipefail

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
    sudo launchctl bootstrap system "$DAEMON_PLIST" 2>/dev/null || \
      sudo launchctl kickstart -k "system/${DAEMON_LABEL}"
    launchctl bootstrap "$GUI" "$AGENT_PLIST" 2>/dev/null || \
      launchctl kickstart -k "${GUI}/${AGENT_LABEL}"
    echo "started."
    ;;
  stop)
    launchctl bootout "${GUI}/${AGENT_LABEL}" 2>/dev/null || true
    sudo launchctl bootout "system/${DAEMON_LABEL}" 2>/dev/null || true
    echo "stopped."
    ;;
  restart)
    sudo launchctl kickstart -k "system/${DAEMON_LABEL}"
    launchctl kickstart -k "${GUI}/${AGENT_LABEL}"
    echo "restarted."
    ;;
  status)
    echo "== daemon (kanata, root) =="
    sudo launchctl print "system/${DAEMON_LABEL}" 2>/dev/null | grep -E 'state|pid|program' | head || echo "not loaded"
    echo "== agent (kanata-vk-agent, user) =="
    launchctl print "${GUI}/${AGENT_LABEL}" 2>/dev/null | grep -E 'state|pid|program' | head || echo "not loaded"
    echo "== processes =="
    pgrep -fl 'kanata' || echo "(no kanata processes)"
    ;;
  logs)
    tail -n 40 -f /var/log/kanata.log "${HOME}/.local/log/kanata-vk-agent.log"
    ;;
  *)
    usage; exit 1 ;;
esac
