#!/usr/bin/env bash
pkill -f '/opt/homebrew/bin/kanata'      2>/dev/null || true   # stop any running kanata
screen -S kanata_main -X quit   2>/dev/null || true   # close old screen session
screen -dmS kanata_main sudo /opt/homebrew/bin/kanata \
      -c /Users/maximegardoni/code/kanata/cfg_samples/my_config.kbd \
      -p 5829



pkill -f kanata-vk-agent      2>/dev/null || true   # stop any running kanata
screen -S kanata_vk_agent -X quit   2>/dev/null || true   # close old screen session
sleep 1s
screen -dmS kanata_vk_agent kanata-vk-agent -p 5829 -b net.kovidgoyal.kitty 
