#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config"
AUTO_YES=false
STOP_AFTER_MINUTES=0

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Error: Config file not found. Copy config.example to config and fill in your keys."
    exit 1
fi

# az container commands use an outdated API version — use az rest with a pinned version instead
ACI_API="2023-05-01"

_aci_url() {
    local subid
    subid=$(az account show --query id -o tsv 2>/dev/null)
    echo "https://management.azure.com/subscriptions/${subid}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ContainerInstance/containerGroups/${CONTAINER_NAME}"
}

aci_exists() {
    az rest --method get --url "$(_aci_url)?api-version=${ACI_API}" &>/dev/null 2>&1
}

aci_get() {
    az rest --method get --url "$(_aci_url)?api-version=${ACI_API}" "$@" 2>/dev/null
}

aci_delete() {
    az rest --method delete --url "$(_aci_url)?api-version=${ACI_API}" --output none 2>&1
}

aci_logs() {
    az rest --method get \
        --url "$(_aci_url)/containers/${CONTAINER_NAME}/logs?api-version=${ACI_API}" \
        --query "content" -o tsv 2>/dev/null
}

usage() {
    cat << EOF
Usage: $0 [-y] [-t <minutes>] <command>

Options:
    -y           - Skip confirmation prompt
    -t <minutes> - Auto-stop after specified minutes (0 = disabled)

Commands:
    start      - Launch ACI container and wait for stream
    stop       - Delete ACI container (stops billing)
    status     - Show container state and RTMP URL
    checklist  - Show pre-broadcast checklist
    logs       - Show container logs (polls every 5s)

Configuration: $CONFIG_FILE
EOF
    exit 1
}

get_fqdn() {
    aci_get --query "properties.ipAddress.fqdn" -o tsv 2>/dev/null
}

notify_discord() {
    [ -z "${NOTIFY_DISCORD_URL:-}" ] && return 0
    local message="$1"
    curl -s -X POST "${NOTIFY_DISCORD_URL}" \
        -H "Content-Type: application/json" \
        -d "{\"content\": \"${message}\"}" &>/dev/null || true
}

confirm_start() {
    echo "=== Launch Configuration ==="
    echo ""
    local account sub
    account=$(az account show --query "user.name" -o tsv 2>/dev/null || echo "(not logged in)")
    sub=$(az account show --query "name" -o tsv 2>/dev/null || echo "(none)")
    echo "Azure account      : $account"
    echo "Subscription       : $sub"
    echo ""
    echo "Resource group     : $RESOURCE_GROUP ($LOCATION)"
    echo "Container          : $CONTAINER_NAME ($CPU vCPU / ${MEMORY}GB RAM)"
    echo "Image              : $IMAGE"
    echo ""
    echo "Destinations:"
    [ -n "${YOUTUBE_RTMP:-}"  ] && echo "  [enabled] YouTube Live"
    [ -n "${FACEBOOK_RTMP:-}" ] && echo "  [enabled] Facebook Live"
    [ -n "${X_RTMP:-}"        ] && echo "  [enabled] X (Twitter)"
    [ -n "${LINKEDIN_RTMP:-}" ] && echo "  [enabled] LinkedIn Live"
    echo ""

    if $AUTO_YES; then
        echo "Auto-confirmed (-y flag)"
        return 0
    fi

    read -p "Start with this configuration? [y/N]: " answer
    case "$answer" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) exit 0 ;;
    esac
}

cmd_start() {
    confirm_start
    echo ""

    if ! az group show --name "$RESOURCE_GROUP" &>/dev/null; then
        echo "Creating resource group: $RESOURCE_GROUP"
        az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none
    fi

    echo "Starting ACI container..."
    DNS_LABEL="${CONTAINER_NAME}-$(openssl rand -hex 4)"

    # Stream keys are passed as secure environment variables (hidden in Azure Portal)
    az container create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CONTAINER_NAME" \
        --image "$IMAGE" \
        --os-type Linux \
        --cpu "$CPU" \
        --memory "$MEMORY" \
        --ip-address Public \
        --ports 1935 \
        --dns-name-label "$DNS_LABEL" \
        --environment-variables \
            STREAM_NAME="${STREAM_NAME:-stream}" \
        --secure-environment-variables \
            YOUTUBE_RTMP="${YOUTUBE_RTMP:-}" \
            FACEBOOK_RTMP="${FACEBOOK_RTMP:-}" \
            X_RTMP="${X_RTMP:-}" \
            X_KEY="${X_KEY:-}" \
            LINKEDIN_RTMP="${LINKEDIN_RTMP:-}" \
            LINKEDIN_KEY="${LINKEDIN_KEY:-}" \
        --output none

    echo ""
    cmd_checklist

    if [ "$STOP_AFTER_MINUTES" -gt 0 ]; then
        local stop_time
        stop_time=$(date -d "+${STOP_AFTER_MINUTES} minutes" "+%H:%M" 2>/dev/null || \
                    date -v "+${STOP_AFTER_MINUTES}M" "+%H:%M")
        nohup bash -c "sleep $((STOP_AFTER_MINUTES * 60)) && cd '$SCRIPT_DIR' && ./multistream.sh -y stop" \
            &>/dev/null &
        echo ""
        echo "Auto-stop timer set: ${STOP_AFTER_MINUTES} min (around ${stop_time})"
    fi

    local fqdn
    fqdn=$(get_fqdn)
    local timer_msg
    if [ "$STOP_AFTER_MINUTES" -gt 0 ]; then
        timer_msg="Auto-stop in ${STOP_AFTER_MINUTES} min"
    else
        timer_msg="⚠️ No auto-stop. Remember to run: ./multistream.sh stop"
    fi
    notify_discord "🔴 **multistream started (billing active)**\n\`rtmp://${fqdn}:1935/live/${STREAM_NAME:-stream}\`\n${timer_msg}\n\nTo stop: \`cd ~/ffmpeg-multistream-azure && ./multistream.sh stop\`"
}

cmd_stop() {
    if ! aci_exists; then
        echo "Container not found."
        return 0
    fi
    echo "Deleting ACI container..."
    aci_delete
    echo "Deleted. Billing stopped."
}

cmd_status() {
    if ! aci_exists; then
        echo "Container not found (stopped)"
        exit 1
    fi
    local fqdn state
    fqdn=$(get_fqdn)
    state=$(aci_get --query "properties.instanceView.state" -o tsv)
    echo "State : $state"
    echo "RTMP  : rtmp://${fqdn}:1935/live/${STREAM_NAME:-stream}"
}

cmd_checklist() {
    local fqdn=""
    if aci_exists; then
        fqdn=$(get_fqdn)
    fi

    echo "=================================================="
    echo "  Pre-Broadcast Checklist"
    echo "=================================================="
    echo ""

    if [ -n "$fqdn" ]; then
        echo "[Streaming app settings]"
        echo "  Server     : rtmp://${fqdn}:1935/live/"
        echo "  Stream key : ${STREAM_NAME:-stream}"
    else
        echo "[Streaming app settings]  (* FQDN will be set after start)"
        echo "  Stream key : ${STREAM_NAME:-stream}  (fixed)"
    fi

    echo ""
    echo "[Destination check]  Verify stream keys are active on each platform"
    [ -n "${YOUTUBE_RTMP:-}"  ] && echo "  [ ] YouTube Live"
    [ -n "${FACEBOOK_RTMP:-}" ] && echo "  [ ] Facebook Live"
    [ -n "${X_RTMP:-}"        ] && echo "  [ ] X (Twitter)  * Requires a new key for each session"
    [ -n "${LINKEDIN_RTMP:-}" ] && echo "  [ ] LinkedIn Live  * Server URL changes each session"

    echo ""
    echo "[How to start]"
    echo "  1. Enter the server and stream key in your streaming app"
    echo "  2. Start broadcasting → MediaMTX receives and ffmpeg fans out to each platform"
    echo "  3. Verify video and audio on each platform"
    echo "  4. When done: ./multistream.sh stop"
}

cmd_logs() {
    if ! aci_exists; then
        echo "Container not found."
        exit 1
    fi
    echo "Streaming logs... (Ctrl+C to stop, updates every 5s)"
    echo "---"
    local prev_lines=0
    while true; do
        local all_logs
        all_logs=$(aci_logs)
        local total_lines
        total_lines=$(echo "$all_logs" | wc -l)
        if [ "$total_lines" -gt "$prev_lines" ]; then
            echo "$all_logs" | tail -n "$((total_lines - prev_lines))"
            prev_lines=$total_lines
        fi
        sleep 5
    done
}

# Main
while getopts "yt:" opt; do
    case "$opt" in
        y) AUTO_YES=true ;;
        t) STOP_AFTER_MINUTES="$OPTARG" ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

case "${1:-}" in
    start)     cmd_start ;;
    stop)      cmd_stop ;;
    status)    cmd_status ;;
    checklist) cmd_checklist ;;
    logs)      cmd_logs ;;
    *)         usage ;;
esac
