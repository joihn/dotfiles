#!/usr/bin/env bash

# When called from LaunchAgent at login, give macOS time to load input monitoring
# and virtual HID drivers before kanata tries to grab the keyboard.
if [ "$LAUNCH_FROM_AGENT" = "1" ]; then
  sleep 5
fi

pkill -f '/opt/homebrew/bin/kanata'      2>/dev/null || true
screen -S kanata_main -X quit            2>/dev/null || true
screen -dmS kanata_main bash -c 'sudo /opt/homebrew/bin/kanata \
      -c /Users/maximegardoni/code/kanata/cfg_samples/my_config.kbd \
      -p 5829 2>&1 | tee -a /Users/maximegardoni/.local/log/kanata.log'

pkill -f kanata-vk-agent                 2>/dev/null || true
screen -S kanata_vk_agent -X quit        2>/dev/null || true
sleep 3s

if [ "$LAUNCH_FROM_AGENT" = "1" ]; then
  # Run directly — screen isolates from WindowServer, which kanata-vk-agent needs for app detection
  exec /opt/homebrew/bin/kanata-vk-agent -p 5829 -b net.kovidgoyal.kitty \
    >> /Users/maximegardoni/.local/log/kanata-vk-agent.log 2>&1
else
  screen -dmS kanata_vk_agent bash -c 'while true; do /opt/homebrew/bin/kanata-vk-agent -p 5829 -b net.kovidgoyal.kitty \
        2>&1 | tee -a /Users/maximegardoni/.local/log/kanata-vk-agent.log; sleep 3; done'
fi
