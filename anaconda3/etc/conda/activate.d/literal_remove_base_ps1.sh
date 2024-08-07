#!/bin/bash

# Check if the hostname is not 'maximeComputer'
if [[ "$(hostname)" != "maximeComputer" ]]; then
  # Execute the desired command
  PROMPT=$(echo "$PROMPT" | sed 's/(base) //')
fi
