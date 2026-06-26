#!/bin/bash

URL="https://nest.xmrchat.com/tips/page/dacctal"
POLL_INTERVAL=10
SEEN_IDS_FILE="/tmp/xmrchat_seen_ids"

# Seed seen IDs with all currently existing tips so we don't read them out on startup
echo "Seeding existing tip IDs..."
curl -s "$URL" | jq -r '.[].id' > "$SEEN_IDS_FILE"
echo "Done. Watching for new tips..."

while true; do
    response=$(curl -s "$URL")

    if [ -z "$response" ]; then
        echo "Warning: empty response, skipping..."
        sleep "$POLL_INTERVAL"
        continue
    fi

    # Parse IDs and messages using jq
    echo "$response" | jq -c '.[] | {id: .id, name: .name, message: .message}' | while read -r entry; do
        id=$(echo "$entry" | jq -r '.id')
        name=$(echo "$entry" | jq -r '.name')
        message=$(echo "$entry" | jq -r '.message // ""')

        # Skip if already seen or message is empty
        if grep -qx "$id" "$SEEN_IDS_FILE" || [ -z "$message" ]; then
            echo "$id" >> "$SEEN_IDS_FILE"
            continue
        fi

        echo "New tip from $name (ID $id): $message"
        echo "$name says: $message" | espeak

        echo "$id" >> "$SEEN_IDS_FILE"
    done

    # Deduplicate the seen IDs file occasionally to keep it tidy
    sort -u "$SEEN_IDS_FILE" -o "$SEEN_IDS_FILE"

    sleep "$POLL_INTERVAL"
done
