#!/bin/bash

URL="https://nest.xmrchat.com/tips/page/dacctal"
COINGECKO_XMR="https://api.coingecko.com/api/v3/simple/price?ids=monero&vs_currencies=usd"
POLL_INTERVAL=10 # loop delay seconds
PRICECALL_SKIPS=6 # once every minute
SEEN_IDS_FILE="/tmp/xmrchat_seen_ids"
MIN_DONATION_DOLLARCENTS=490

# Seed seen IDs with all currently existing tips so we don't read them out on startup
echo "Seeding existing tip IDs..."
curl -s "$URL" | jq -r '.[].id' > "$SEEN_IDS_FILE"
echo "Done. Watching for new tips..."

PRICECALL_COUNTER=$PRICECALL_SKIPS
while true; do
    if [ $PRICECALL_COUNTER -eq $PRICECALL_SKIPS ]; then
        xmr_price=$(curl -s $COINGECKO_XMR | jq -c '.monero.usd')
        if [ $xmr_price == null ]; then
            echo "Warning: couldn't fetch price, retrying..."
            sleep "$POLL_INTERVAL"
            continue
        fi
        IFS='.' read -ra xmr_price <<< "$xmr_price"
        len=${#xmr_price[1]}
        if [ $len -lt 2 ]; then
            needed=$((2-len))
            zeros=$(for ((i=1;i<=$needed;++i)); do echo -n '0'; done)
            xmr_price[1]="${xmr_price[1]}${zeros}"
        fi
        xmr_price=("${xmr_price[0]}""${xmr_price[1]}")
        PRICECALL_COUNTER=0
    fi
    response=$(curl -s "$URL")

    if [ -z "$response" ]; then
        echo "Warning: empty response, skipping..."
        sleep "$POLL_INTERVAL"
        continue
    fi

    # Parse IDs and messages using jq
    echo "$response" | jq -c '.[] | {id: .id, name: .name, message: .message, amount: .payment.paidAmount}' | while read -r entry; do
        id=$(echo "$entry" | jq -r '.id')
        name=$(echo "$entry" | jq -r '.name')
        amount=$(echo "$entry" | jq -r '.amount') # actual amount * 1000000000000
        dollar_cents=$((amount * xmr_price / 1000000000000))
        message=$(echo "$entry" | jq -r '.message // ""')

        # # Skip if already seen or message is empty
        if grep -qx "$id" "$SEEN_IDS_FILE" || [ -z "$message" ]; then
            echo "$id" >> "$SEEN_IDS_FILE"
            continue
        fi

        echo "New tip from $name (ID $id): $message"
        if [[ $dollar_cents -ge $MIN_DONATION_DOLLARCENTS ]]; then
            echo "$name says: $message" | espeak 2>&1
        fi

        echo "$id" >> "$SEEN_IDS_FILE"
    done

    # Deduplicate the seen IDs file occasionally to keep it tidy
    sort -u "$SEEN_IDS_FILE" -o "$SEEN_IDS_FILE"

    PRICECALL_COUNTER=$((PRICECALL_COUNTER + 1))
    sleep "$POLL_INTERVAL"
done
