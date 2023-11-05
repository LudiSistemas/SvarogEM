#!/bin/bash

if [ -f .env ]; then
    source .env
else
    echo ".env file not found. Please create one with the necessary variables."
    exit 1
fi
 source functions.sh

declare -A processed_events


IFS=',' read -r -a event_names <<< "$event_name"
for en in "${event_names[@]}"; do
    if [ "$en" == "lava_provider_jailed" ]; then
        parse_and_display_jailed_events "$en"
    elif [ "$en" == "lava_freeze_provider" ]; then
        parse_and_display_freeze_events "$en"
    else
        echo "Unsupported event name: $en"
    fi
done
