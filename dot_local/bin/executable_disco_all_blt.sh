#!/bin/bash

devices=$(bluetoothctl devices | cut -f2 -d' ')

for device in $devices
do
    echo "disco_all_blt: Disconnecting $device"
    bluetoothctl disconnect $device
done
