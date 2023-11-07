send_telegram_message() {
    local message=$1
    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" -d chat_id="$TELEGRAM_CHAT_ID" -d text="$message" -d parse_mode=Markdown
    
}


send_slack_message() {
    local message="$1"
    curl -s -X POST -H "Content-type: application/json" --data "{\"text\":\"$message\"}" "$SLACK_WEBHOOK_URL"
}

run_lavad_command() {
  local retries=$MAX_RETRIES
  local success=false

  while [ $retries -gt 0 ]; do
    output=$(lavad test events $PAST_BLOCKS --event $event_name --node $NODE --timeout $TIMEOUT 2>&1)
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

skip_to_jailed_events() {
    while read -r line; do
        if [[ "$line" == *"lava_provider_jailed"* ]]; then
            # Found the first jailed event line, break the loop to continue processing.
            break
        fi
    done < <(run_lavad_command)
}

parse_and_display_jailed_events() {
    local event_name=$1
    local output
    local event_found=false

    # Run the lavad command and capture its output.
    if ! output=$(run_lavad_command); then
        echo "Failed to get output from lavad command."
        return 1
    fi

    # Check if the event name is correct.
    if [ "$event_name" != "lava_provider_jailed" ]; then
        echo "Event '$event_name' is not 'lava_provider_jailed'. Skipping..."
        return 0
    fi

    # Read through each line of the output.
    echo "$output" | while IFS= read -r line; do
        # If we find a line with "Current Block", we skip it.
        if echo "$line" | grep -q "Current Block:"; then
            continue
        fi

        # Check for the "lava_provider_jailed" event.
        if echo "$line" | grep -q "lava_provider_jailed"; then
            event_found=true

            local date_time=$(echo "$line" | awk '{print $1, $2, $3}')
            local provider=$(echo "$line" | awk -F'provider_address =' '{print $2}' | awk '{print $1}' | tr -d ',')
            local chain_id=$(echo "$line" | awk -F'chain_id = ' '{print $2}' | awk '{print $1}')
            local complaint_cu=$(echo "$line" | awk -F'complaint_cu = ' '{print $2}' | awk '{print $1}')
            local height=$(echo "$line" | awk -F'height=' '{print $2}' | awk '{print $1}')
            
            # ... (rest of your existing logic to handle the event)
        fi
    done

    # If no events were found, we output a message.
    if ! $event_found; then
        echo "No 'lava_provider_jailed' events found."
    fi
}


parse_and_display_freeze_events() {
    local event_name=$1
    local output
    if ! output=$(run_lavad_command); then
      return 1
    fi

    if [ "$event_name" != "lava_freeze_provider" ]; then
        echo "Event '$event_name' is not 'lava_freeze_provider'. Skipping..."
        return 0
    fi

    echo "$output" | grep "lava_freeze_provider" | while read -r line; do
        local date_time=$(echo "$line" | awk '{print $1, $2, $3}')
        local provider_address=$(echo "$line" | awk -F'providerAddress = ' '{print $2}' | awk '{print $1}' | tr -d ',')
        local freeze_reason=$(echo "$line" | awk -F'freezeReason = ' '{print $2}' | awk '{print $1}' | tr -d ',')
        local chain_ids=$(echo "$line" | awk -F'chainIDs = ' '{print $2}' | awk -F', ' '{print $1}')
        local height=$(echo "$line" | awk -F'height=' '{print $2}' | awk '{print $1}' | tr -d ',')
        event_time=$(echo "$line" | grep -oP 'Event Time: \K.*?(?=Provider:)' | sed 's/Current Block: //')

        local event_key="${provider_address}_${chain_ids}_${height}"

        if [[ -z ${processed_events[$event_key]} ]]; then
            processed_events[$event_key]=1
            
            if is_provider_monitored "$provider"; then
       
            if [ "$USE_TELEGRAM" = true ]; then
            local provider_link="[$provider](https://info.lavanet.xyz/provider/$provider)"
            local provider_name=$(jq -r --arg provider "$provider_address" '.[] | select(.wallet == $provider) | .name' monitored2.json)
            local telegram_message="----------------------------------------%0A"
            telegram_message+="Provider freeze event detected for $provider_name%0A"
            telegram_message+="Event Time: $event_time %0A"
            telegram_message+="Provider Address: $provider_link%0A"
            telegram_message+="Freeze Reason: $freeze_reason%0A"
            telegram_message+="Chain IDs: $chain_ids%0A"
            telegram_message+="Height: $height%0A"
            telegram_message+="----------------------------------------"

            send_telegram_message "$telegram_message"

            elif [ "$USE_SLACK" = true ]; then
                local provider_name=$(jq -r --arg provider "$provider_address" '.[] | select(.wallet == $provider) | .name' monitored2.json)
                local slack_message="{
                    \"text\": \"Provider freeze event detected for $provider_name\",
                    \"attachments\": [
                        {
                            \"fields\": [
                                { \"title\": \"Event Time\", \"value\": \"$date_time\", \"short\": true },
                                { \"title\": \"Provider Address\", \"value\": \"$provider_address\", \"short\": true },
                                { \"title\": \"Freeze Reason\", \"value\": \"$freeze_reason\", \"short\": true },
                                { \"title\": \"Chain IDs\", \"value\": \"$chain_ids\", \"short\": true },
                                { \"title\": \"Height\", \"value\": \"$height\", \"short\": true }
                            ],
                            \"color\": \"#FF5733\"
                        }
                    ]
                }"

                send_slack_message "$slack_message"

            else
                echo "----------------------------------------"
                echo "Date Time: $date_time"
                echo "Provider Address: $provider_address"
                echo "Freeze Reason: $freeze_reason"
                echo "Chain IDs: $chain_ids"
                echo "Height: $height"
                echo "----------------------------------------"
            fi

            else
                echo "Provider $provider is not on the monitored list."
            fi

        else
            echo "Event for provider $provider_address with chain IDs $chain_ids at height $height has already been processed."
        fi
    done
}

parse_and_display_unfreeze_events() {
local event_name=$1
local output
if ! output=$(run_lavad_command); then
    return 1
fi

if [ "$event_name" != "lava_unfreeze_provider" ]; then
    echo "Event '$event_name' is not 'lava_unfreeze_provider'. Skipping..."
    return 0
fi

echo "$output" | grep "lava_unfreeze_provider" | while read -r line; do
    local date_time=$(echo "$line" | awk '{print $1, $2, $3}')
    local provider_address=$(echo "$line" | awk -F'providerAddress = ' '{print $2}' | awk '{print $1}' | tr -d ',')
    local chain_ids=$(echo "$line" | awk -F'chainIDs = ' '{print $2}' | awk -F', ' '{print $1}')
    local height=$(echo "$line" | awk -F'height=' '{print $2}' | awk '{print $1}' | tr -d ',')
    event_time=$(echo "$line" | grep -oP 'Event Time: \K.*?(?=Provider:)' | sed 's/Current Block: //')

    local event_key="${provider_address}_${chain_ids}_${height}"

    if [[ -z ${processed_events[$event_key]} ]]; then
        processed_events[$event_key]=1

        if is_provider_monitored "$provider"; then

        if [ "$USE_TELEGRAM" = true ]; then
        local provider_link="[$provider](https://info.lavanet.xyz/provider/$provider)"
        local provider_name=$(jq -r --arg provider "$provider_address" '.[] | select(.wallet == $provider) | .name' monitored2.json)
        local telegram_message="----------------------------------------%0A"
        telegram_message+="Provider unfreeze event detected for $provider_name%0A"
        telegram_message+="Event Time: $event_time %0A"
        telegram_message+="Provider Address: $provider_link%0A"
        telegram_message+="Chain IDs: $chain_ids%0A"
        telegram_message+="Height: $height%0A"
        telegram_message+="----------------------------------------"

        send_telegram_message "$telegram_message"

        elif [ "$USE_SLACK" = true ]; then
            local provider_name=$(jq -r --arg provider "$provider_address" '.[] | select(.wallet == $provider) | .name' monitored2.json)
            local slack_message="{
                \"text\": \"Provider unfreeze event detected for $provider_name\",
                \"attachments\": [
                    {
                        \"fields\": [
                            { \"title\": \"Event Time\", \"value\": \"$date_time\", \"short\": true },
                            { \"title\": \"Provider Address\", \"value\": \"$provider_address\", \"short\": true },
                            { \"title\": \"Chain IDs\", \"value\": \"$chain_ids\", \"short\": true },
                            { \"title\": \"Height\", \"value\": \"$height\", \"short\": true }
                        ],
                        \"color\": \"#FF5733\"
                    }
                ]
            }"

            send_slack_message "$slack_message"

        else
            echo "----------------------------------------"
            echo "Date Time: $date_time"
            echo "Provider Address: $provider_address"
            echo "unfreeze Reason: $unfreeze_reason"
            echo "Chain IDs: $chain_ids"
            echo "Height: $height"
            echo "----------------------------------------"
        fi

        else
                echo "Provider $provider is not on the monitored list."
        fi

    else
        echo "Event for provider $provider_address with chain IDs $chain_ids at height $height has already been processed."
    fi
done
}
parse_and_display_new_stake_events() {
    local event_name=$1
    local output
    if ! output=$(run_lavad_command); then
      return 1
    fi

    if [ "$event_name" != "lava_stake_new_provider" ]; then
        echo "Event '$event_name' is not 'lava_stake_new_provider'. Skipping..."
        return 0
    fi

    echo "$output" | grep "lava_stake_new_provider" | while read -r line; do
        local date_time=$(echo "$line" | awk '{print $1, $2, $3}')
        local provider=$(echo "$line" | awk -F'provider = ' '{print $2}' | awk '{print $1}' | tr -d ',')
        local stake=$(echo "$line" | awk -F'stake = ' '{print $2}' | awk '{print $1}')
        local geolocation=$(echo "$line" | awk -F'geolocation = ' '{print $2}' | awk '{print $1}')
        local moniker=$(echo "$line" | awk -F'moniker = ' '{print $2}' | awk '{print $1}')
        local spec=$(echo "$line" | awk -F'spec = ' '{print $2}' | awk '{print $1}' | tr -d ',')
        local stake_applied_block=$(echo "$line" | awk -F'stakeAppliedBlock = ' '{print $2}' | awk '{print $1}')
        event_time=$(echo "$line" | grep -oP 'Event Time: \K.*?(?=Provider:)' | sed 's/Current Block: //')

        local event_key="${provider}_${stake_applied_block}"

        if [[ -z ${processed_events[$event_key]} ]]; then
            processed_events[$event_key]=1
            
            if is_provider_monitored "$provider"; then

            if [ "$USE_TELEGRAM" = true ]; then
                local provider_link="[$provider](https://info.lavanet.xyz/provider/$provider)"
                local provider_name=$(jq -r --arg provider "$provider" '.[] | select(.wallet == $provider) | .name' monitored2.json)
                local telegram_message="----------------------------------------%0A"
                telegram_message+="New provider stake event detected%0A"
                telegram_message+="Event Time: $event_time%0A"
                telegram_message+="Provider: $provider_link%0A"
                telegram_message+="Moniker: $moniker%0A"
                telegram_message+="Geolocation: $geolocation%0A"
                telegram_message+="Spec: $spec%0A"
                telegram_message+="Stake: $stake%0A"
                telegram_message+="Stake Applied Block: $stake_applied_block%0A"
                telegram_message+="----------------------------------------"

                send_telegram_message "$telegram_message"

            elif [ "$USE_SLACK" = true ]; then
                local provider_link="<https://info.lavanet.xyz/provider/$provider|$provider>"
                local slack_message="{
                    \"text\": \"New provider stake event detected\",
                    \"attachments\": [
                        {
                            \"fields\": [
                                { \"title\": \"Event Time\", \"value\": \"$date_time\", \"short\": true },
                                { \"title\": \"Provider\", \"value\": \"$provider_link\", \"short\": true },
                                { \"title\": \"Moniker\", \"value\": \"$moniker\", \"short\": true },
                                { \"title\": \"Geolocation\", \"value\": \"$geolocation\", \"short\": true },
                                { \"title\": \"Spec\", \"value\": \"$spec\", \"short\": true },
                                { \"title\": \"Stake\", \"value\": \"$stake\", \"short\": true },
                                { \"title\": \"Stake Applied Block\", \"value\": \"$stake_applied_block\", \"short\": true }
                            ]
                        }
                    ]
                }"
                send_slack_message "$slack_message"
            else
                echo "----------------------------------------"
                echo "Date Time: $date_time"
                echo "Provider: $provider"
                echo "Moniker: $moniker"
                echo "Geolocation: $geolocation"
                echo "Spec: $spec"
                echo "Stake: $stake"
                echo "Stake Applied Block: $stake_applied_block"
                echo "----------------------------------------"
            fi

            else
                echo "Provider $provider is not on the monitored list."
            fi
        else
            echo "Event for provider $provider at stake applied block $stake_applied_block has already been processed."
        fi
    done
}