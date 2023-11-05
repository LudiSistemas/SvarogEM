#!/bin/bash

if [ -f .env ]; then
    source .env
else
    echo ".env file not found. Please create one with the necessary variables."
    exit 1
fi
 source functions.sh

declare -A processed_events


parse_and_display_jailed_events
