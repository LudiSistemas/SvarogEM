#!/bin/bash

if [ -f .env ]; then
    source .env
else
    echo ".env file not found. Please create one with the necessary variables."
    exit 1
fi

send_telegram_message() {
    local message=$1
    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" -d chat_id="$TELEGRAM_CHAT_ID" -d text="$message" -d parse_mode=Markdown
}


MAX_RETRIES=3

RETRY_INTERVAL=10

run_lavad_command() {
  local retries=$MAX_RETRIES
  local success=false

  while [ $retries -gt 0 ]; do
    output=$(lavad test events 1000 --event lava_provider_jailed --node https://testnet2-rpc-lb.lavanet.xyz:443 --timeout 1m 2>&1)
    exit_status=$?

    if [ $exit_status -eq 0 ]; then
      success=true
      break
    else
      echo "Attempt $(($MAX_RETRIES - $retries + 1)) of $MAX_RETRIES failed. Retrying in $RETRY_INTERVAL seconds..."
      sleep $RETRY_INTERVAL
    fi

    ((retries--))
  done

  if ! $success; then
    echo "Failed to run lavad command after $MAX_RETRIES attempts."
    return 1
  else
    echo "$output"
    return 0
  fi
}

is_provider_monitored() {
    local provider=$1
    jq -e --arg provider "$provider" '.[] | select(.wallet == $provider)' monitored2.json >/dev/null
}


declare -A processed_events

parse_and_display_events() {
    local output
    if ! output=$(run_lavad_command); then
      return 1
    fi

    local count=$(echo "$output" | grep -c "lava_provider_jailed")

    if [ $count -eq 0 ]; then
        echo "No 'lava_provider_jailed' events found in the last output."
        return 0
    fi

    echo "$output" | grep "lava_provider_jailed" | while read -r line; do

    local date_time=$(echo "$line" | awk '{print $1, $2, $3}')
    local provider=$(echo "$line" | awk -F'provider_address =' '{print $2}' | awk '{print $1}' | tr -d ',')
    local chain_id=$(echo "$line" | awk -F'chain_id = ' '{print $2}' | awk '{print $1}')
    local complaint_cu=$(echo "$line" | awk -F'complaint_cu = ' '{print $2}' | awk '{print $1}')
    local height=$(echo "$line" | awk -F'height=' '{print $2}' | awk '{print $1}')


        local event_key="${provider}_${chain_id}"
        

        if [[ -z ${processed_events[$event_key]} ]]; then
            processed_events[$event_key]=1

            if is_provider_monitored "$provider"; then
        local provider_link="[$provider](https://info.lavanet.xyz/provider/$provider)"
        local provider_name=$(jq -r --arg provider "$provider" '.[] | select(.wallet == $provider) | .name' monitored2.json)
        local telegram_message="----------------------------------------%0A"
        telegram_message+="Provider jailed event detected for $provider_name%0A"
        telegram_message+="Event Time: $date_time%0A"
        telegram_message+="Provider: $provider_link%0A"
        telegram_message+="Chain ID: $chain_id%0A"
        telegram_message+="Complaint CU: $complaint_cu%0A"
        telegram_message+="Height: $height%0A"
        telegram_message+="----------------------------------------"

        send_telegram_message "$telegram_message"
            else
                echo "Provider $provider is not on the monitored list."
            fi
        else
            echo "Event for provider $provider on chain ID $chain_id has already been processed."
        fi
    done
}

parse_and_display_events
