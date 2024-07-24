#!/bin/bash

delay=10

# Check if ELASTIC_URL environment variable is set
if [ -z "$ELASTIC_URL" ]; then
    echo "ELASTIC_URL environment variable is not set."
    exit 1
fi

if [ -z "$PROXY_IP" ]; then
    echo "PROXY_IP environment variable is not set."
    exit 1
fi

if [ -z "$PROTOCOL" ]; then
    # Store protocol in PROTOCOL variable
    if [[ "$ELASTIC_URL" == https://* ]]; then
        PROTOCOL="https"
    elif [[ "$ELASTIC_URL" == http://* ]]; then
        PROTOCOL="http"
    else
        echo "Protocol not found in ELASTIC_URL. Using unsafe protocol (http)."
        PROTOCOL="http"
    fi
fi

if [[ "$PROXY_IP" == https://* ]]; then
    PROXY_PROTOCOL="https"
else
    PROXY_PROTOCOL="http"
fi

# Remove http:// or https:// from ELASTIC_URL if present
ELASTIC_URL_CLEAN=$(echo "$ELASTIC_URL" | sed -e 's/^http[s]*:\/\///')

# Remove http:// or https:// from PROXY_IP if present
PROXY_IP_CLEAN=$(echo "$PROXY_IP" | sed -e 's/^http[s]*:\/\///')

# Set ELASTIC_URL to cleaned value
export ELASTIC_URL="$ELASTIC_URL_CLEAN"
export PROTOCOL

export PROXY_IP="$PROXY_IP_CLEAN"
export PROXY_PROTOCOL

if [ -z "$ENVIROMENT_ALREADY_SETUP" ] || [ "$ENVIROMENT_ALREADY_SETUP" != "true" ]; then
    echo "Initializing monitoring instance..."

    MACHINE_NAME=$(hostname)

    response=$(curl -F instance_id=$MACHINE_NAME -X POST $PROXY_PROTOCOL://$PROXY_IP/api/monitoring/create_instance/$TOKEN)

    port=$(echo "$response" | jq -r '.port')

    if [ "$port" == "null" ]; then
        echo "Error while retrieving port from the proxy. (Are the enviroment variables correct?)"
        exit 1
    fi

    echo "#"
    echo "#"
    echo "#"
    echo "#"
    echo "#"
    echo "# Your Grafana instance is now up!"
    echo "# You can access it from your browser at $PROXY_PROTOCOL://$PROXY_IP/instance-$port/"
    echo "#"
    echo "#"
    echo "#"
    echo "#"
    echo "#"
    echo "The exporter will initialize after $delay seconds."

    sleep $delay

    ENVIROMENT_ALREADY_SETUP=true
    export ENVIROMENT_ALREADY_SETUP
fi

echo "Initializing exporter..."

/usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf