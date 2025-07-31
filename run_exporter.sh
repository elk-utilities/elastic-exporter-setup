#!/bin/bash

# --- Script Configuration ---
# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error when substituting.
set -u
# Pipelines fail if any command fails, not just the last one.
set -o pipefail

# --- Environment Variables ---
# How long to wait after setting up the instance
delay=10
# Timeout for connectivity checks
connect_timeout=5

# --- Function Definitions ---

# NEW: Logging function that adds a timestamp and log level.
# Arguments:
#   $1: Log level (e.g., INFO, WARNING, ERROR)
#   $2: Log message
log() {
    local level=$1
    local message=$2
    # Prints a timestamp in ISO 8601 format, the log level, and the message.
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") [$level] $message"
}

# A function to check connectivity to a given URL.
# It uses curl to send a HEAD request, which is efficient as it doesn't download the page body.
# Arguments:
#   $1: The full URL to check (e.g., "http://my-proxy/api/ping")
#   $2: The human-readable name of the service (e.g., "Proxy Server")
check_connectivity() {
    local url=$1
    local service_name=$2
    log "INFO" "Checking connection to $service_name."
    if ! curl --head --silent --fail --connect-timeout "$connect_timeout" "$url" > /dev/null; then
        log "ERROR" "Could not connect to $service_name."
        log "ERROR" "Please check the URL, network connectivity, and ensure the service is running."
        exit 1
    fi
    log "INFO" "$service_name is reachable."
}


# --- Environment Variable Validation ---
log "INFO" "Validating environment variables..."
if [ -z "${ELASTIC_URL-}" ]; then
    log "ERROR" "ELASTIC_URL environment variable is not set."
    exit 1
fi

if [ -z "${PROXY_IP-}" ]; then
    log "ERROR" "PROXY_IP environment variable is not set."
    exit 1
fi

if [ -z "${EXPORTER_TIMEOUT-}" ]; then
    log "WARNING" "EXPORTER_TIMEOUT environment variable is not set. Making default value to 60s."
    EXPORTER_TIMEOUT="60s"
    export EXPORTER_TIMEOUT
fi

if [ -z "${TOKEN-}" ]; then
    log "ERROR" "TOKEN environment variable is not set."
    exit 1
fi

# If ELASTIC_USER is set, ELASTIC_PASSWORD must also be set.
if [ -n "${ELASTIC_USER-}" ] && [ -z "${ELASTIC_PASSWORD-}" ]; then
    log "ERROR" "ELASTIC_USER is set, but ELASTIC_PASSWORD is not. Please set both or neither."
    exit 1
fi
log "INFO" "Environment variables validated."

# --- Protocol and URL/IP Cleaning ---
log "INFO" "Determining protocols and cleaning URLs..."
if [ -z "${PROTOCOL-}" ]; then
    if [[ "$ELASTIC_URL" == https://* ]]; then
        PROTOCOL="https"
    else
        PROTOCOL="http"
    fi
fi

if [[ "$PROXY_IP" == https://* ]]; then
    PROXY_PROTOCOL="https"
else
    PROXY_PROTOCOL="http"
fi

ELASTIC_URL_CLEAN=$(echo "$ELASTIC_URL" | sed -E 's~^https?://~~')
PROXY_IP_CLEAN=$(echo "$PROXY_IP" | sed -E 's~^https?://~~')

export ELASTIC_URL="$ELASTIC_URL_CLEAN"
export PROTOCOL
export PROXY_IP="$PROXY_IP_CLEAN"
export PROXY_PROTOCOL
log "INFO" "URLs cleaned and variables exported."


# --- Token Validation ---
log "INFO" "Validating authentication token..."
# Create a temporary file to store the body of the HTTP response.
token_response_file=$(mktemp)
token_validation_url="https://elkutils.com/wp-json/wp/v2/verify-token/$TOKEN"

# Use curl to make the request to the token validation endpoint.
token_http_status=$(curl -s -w "%{http_code}" -o "$token_response_file" "$token_validation_url")

if [ "$token_http_status" -eq 200 ]; then
    if jq -e '.success == true' "$token_response_file" > /dev/null; then
        status=$(jq -r '.status' "$token_response_file")
        port=$(jq -r '.host' "$token_response_file")

        if [ "$status" == "Running" ]; then
            log "INFO" "Token is valid and instance is already running at $PROXY_PROTOCOL://$PROXY_IP_CLEAN/instance-$port Skipping setup."
            export ENVIROMENT_ALREADY_SETUP="true"
        elif [ "$status" == "Trial expired" ]; then
            log "ERROR" "Your trial has expired. Please contact support to renew your plan at https://elkutils.com/contact-us."
            rm "$token_response_file"
            exit 1
        else
            log "INFO" "Token is valid. Proceeding with setup..."
        fi
    else
        log "ERROR" "Token validation failed. The server responded with success, but the response indicates failure."
        cat "$token_response_file"
        rm "$token_response_file"
        exit 1
    fi
elif [ "$token_http_status" -eq 404 ]; then
    log "ERROR" "The provided TOKEN is invalid or not associated with any user (HTTP 404)."
    log "ERROR" "Please check your token and try again."
    rm "$token_response_file"
    exit 1
elif [ "$token_http_status" -ge 500 ]; then
    log "ERROR" "The token validation service encountered an internal error (HTTP $token_http_status)."
    log "ERROR" "Please try again in a few moments. If the problem persists, contact support."
    rm "$token_response_file"
    exit 1
else
    log "ERROR" "An unexpected error occurred during token validation. The service responded with HTTP status $token_http_status."
    log "ERROR" "Server response:"
    cat "$token_response_file"
    rm "$token_response_file"
    exit 1
fi
rm "$token_response_file" # Clean up the temp file


# --- Connectivity Checks ---
check_connectivity "$PROXY_PROTOCOL://$PROXY_IP_CLEAN/api/ping" "Proxy Server"
check_connectivity "$PROTOCOL://$ELASTIC_USER:$ELASTIC_PASSWORD@$ELASTIC_URL_CLEAN/" "Elasticsearch"


# --- IP Resolution for Proxy ---
log "INFO" "Resolving Proxy IP address..."
# Check if PROXY_IP_CLEAN is already an IP address.
if [[ $PROXY_IP_CLEAN =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    IP=$PROXY_IP_CLEAN
else
    log "INFO" "Domain name detected. Resolving '$PROXY_IP_CLEAN' with dig..."
    # Priority 1: Try to resolve an IPv4 address (A record).
    IP=$(dig +short "$PROXY_IP_CLEAN" A | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1)

    # Priority 2: If no IPv4 found, try to resolve an IPv6 address (AAAA record).
    if [ -z "$IP" ]; then
        log "INFO" "No IPv4 address found for '$PROXY_IP_CLEAN'. Trying IPv6..."
        IP=$(dig +short "$PROXY_IP_CLEAN" AAAA | head -n 1)
    fi
    
    # Priority 3: If no IP address could be resolved, use the domain name as a last resort.
    if [ -z "$IP" ]; then
        log "WARNING" "Could not resolve an IPv4 or IPv6 address for '$PROXY_IP_CLEAN'."
        log "WARNING" "Using the domain name as a last resort. This may fail if the container's resolver is not configured correctly."
        IP=$PROXY_IP_CLEAN
    fi
fi
export IP
log "INFO" "Proxy IP resolved to '$IP'."


# --- Initialize Monitoring Instance (if not already done) ---
if [ -z "${ENVIROMENT_ALREADY_SETUP-}" ] || [ "$ENVIROMENT_ALREADY_SETUP" != "true" ]; then
    log "INFO" "First-time setup: Initializing monitoring instance..."

    MACHINE_NAME=$(hostname)
    
    response_body_file=$(mktemp)

    http_status=$(curl -s -w "%{http_code}" -o "$response_body_file" \
        -F instance_id="$MACHINE_NAME" \
        -X POST "$PROXY_PROTOCOL://$PROXY_IP_CLEAN/api/monitoring/create_instance/$TOKEN")

    if [ "$http_status" -eq 403 ]; then
        if grep -q "Your trial has already expired!" "$response_body_file"; then
            log "ERROR" "Your trial has expired. Please contact support to renew your plan."
        else
            log "ERROR" "Access Denied (HTTP 403). Please check that your TOKEN is correct and has the necessary permissions."
        fi
        rm "$response_body_file"
        exit 1
    elif [ "$http_status" -ge 500 ]; then
        log "ERROR" "The server encountered an internal error (HTTP $http_status)."
        log "ERROR" "Please try again in a few moments. If the problem persists, contact support."
        rm "$response_body_file"
        exit 1
    elif [ "$http_status" -ne 201 ]; then
        log "ERROR" "An unexpected error occurred. The server responded with HTTP status $http_status."
        log "ERROR" "Server response:"
        cat "$response_body_file"
        rm "$response_body_file"
        exit 1
    fi
    
    response=$(cat "$response_body_file")
    rm "$response_body_file"

    port=$(echo "$response" | jq -e -r '.port')

    # This user-facing message is kept as a simple echo to make it stand out.
    echo
    echo "################################################################"
    echo "#"
    echo "# Your monitoring instance is now up!"
    echo "# You can access it at: $PROXY_PROTOCOL://$PROXY_IP_CLEAN/instance-$port/"
    echo "#"
    echo "################################################################"
    echo
    log "INFO" "The exporter will initialize after $delay seconds."

    sleep "$delay"

    export ENVIROMENT_ALREADY_SETUP="true"
else
    log "INFO" "Environment already set up. Skipping instance initialization."
fi

# --- Start Main Services ---
log "INFO" "Initializing exporter via supervisord..."
/usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
