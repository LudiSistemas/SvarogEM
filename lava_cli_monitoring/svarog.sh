#!/bin/bash

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Check if the .env file exists in the script's directory
if [ -f "$script_dir/.env" ]; then
    source "$script_dir/.env"
else
    echo ".env file not found in the script's directory. Please create one with the necessary variables."
    exit 1
fi

source functions.sh
declare -A processed_events


IFS=',' read -r -a event_names <<< "$event_name"
for en in "${event_names[@]}"; do
    if [ "$en" == "lava_provider_jailed" ]; then
        echo "starting with $en"
        parse_and_display_jailed_events "$en" 

    elif [ "$en" == "lava_freeze_provider" ]; then
        echo "starting with $en"
        parse_and_display_freeze_events "$en"

    elif [ "$en" == "lava_unfreeze_provider" ]; then
        echo "starting with $en"
        parse_and_display_unfreeze_events "$en"

    elif [ "$en" == "lava_stake_new_provider" ]; then
        echo "starting with $en"
        parse_and_display_new_stake_events "$en"
        
    else
        echo "Unsupported event name: $en"
    fi
done
