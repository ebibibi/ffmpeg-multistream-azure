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

usage() {
    cat << EOF
Usage: $0 [-y] [-t <minutes>] <command>

Options:
    -y           - 確認プロンプトをスキップ
    -t <minutes> - 指定分後に自動停止 (0 = 無効)

Commands:
    start      - ACI を起動して配信待機
    stop       - ACI を削除（課金停止）
    status     - 状態と接続先URLを表示
    checklist  - 配信前チェックリストを表示
    logs       - コンテナログを表示

Configuration: $CONFIG_FILE
EOF
    exit 1
}

get_fqdn() {
    az container show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CONTAINER_NAME" \
        --query "ipAddress.fqdn" \
        --output tsv 2>/dev/null
}

notify_discord() {
    [ -z "${NOTIFY_DISCORD_URL:-}" ] && return 0
    local message="$1"
    curl -s -X POST "${NOTIFY_DISCORD_URL}" \
        -H "Content-Type: application/json" \
        -d "{\"content\": \"${message}\"}" &>/dev/null || true
}

confirm_start() {
    echo "=== 起動設定の確認 ==="
    echo ""
    local account sub
    account=$(az account show --query "user.name" -o tsv 2>/dev/null || echo "(未ログイン)")
    sub=$(az account show --query "name" -o tsv 2>/dev/null || echo "(未選択)")
    echo "Azureアカウント : $account"
    echo "サブスクリプション: $sub"
    echo ""
    echo "リソースグループ: $RESOURCE_GROUP ($LOCATION)"
    echo "コンテナ        : $CONTAINER_NAME ($CPU vCPU / ${MEMORY}GB)"
    echo "イメージ        : $IMAGE"
    echo ""
    echo "配信先:"
    [ -n "${YOUTUBE_RTMP:-}"  ] && echo "  [有効] YouTube Live"
    [ -n "${FACEBOOK_RTMP:-}" ] && echo "  [有効] Facebook Live"
    [ -n "${X_RTMP:-}"        ] && echo "  [有効] X (Twitter)"
    [ -n "${LINKEDIN_RTMP:-}" ] && echo "  [有効] LinkedIn Live"
    echo ""

    if $AUTO_YES; then
        echo "自動確認（-y オプション）"
        return 0
    fi

    read -p "この設定で起動しますか? [y/N]: " answer
    case "$answer" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) exit 0 ;;
    esac
}

cmd_start() {
    confirm_start
    echo ""

    if ! az group show --name "$RESOURCE_GROUP" &>/dev/null; then
        echo "リソースグループを作成: $RESOURCE_GROUP"
        az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none
    fi

    echo "ACI を起動中..."
    DNS_LABEL="${CONTAINER_NAME}-$(openssl rand -hex 4)"

    # ストリームキーは secure-environment-variables で渡す（Portal に平文表示しない）
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
        echo "⏱ 自動停止タイマー: ${STOP_AFTER_MINUTES}分後（約 ${stop_time}）"
    fi

    local fqdn
    fqdn=$(get_fqdn)
    local timer_msg
    if [ "$STOP_AFTER_MINUTES" -gt 0 ]; then
        timer_msg="⏱ ${STOP_AFTER_MINUTES}分後に自動停止"
    else
        timer_msg="⚠️ 自動停止なし。終わったら忘れずに停止してね"
    fi
    notify_discord "🔴 **multistream 起動中（課金中）**\n\`rtmp://${fqdn}:1935/live/${STREAM_NAME:-stream}\`\n${timer_msg}\n\n停止: \`cd ~/ffmpeg-multistream-azure && ./multistream.sh stop\`"
}

cmd_stop() {
    if ! az container show --resource-group "$RESOURCE_GROUP" --name "$CONTAINER_NAME" &>/dev/null; then
        echo "コンテナが見つかりません。"
        return 0
    fi
    echo "ACI を削除中..."
    az container delete \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CONTAINER_NAME" \
        --yes --output none
    echo "削除完了。課金停止。"
}

cmd_status() {
    if ! az container show --resource-group "$RESOURCE_GROUP" --name "$CONTAINER_NAME" &>/dev/null; then
        echo "コンテナが見つかりません（停止中）"
        exit 1
    fi
    local fqdn state
    fqdn=$(get_fqdn)
    state=$(az container show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CONTAINER_NAME" \
        --query "instanceView.state" -o tsv)
    echo "状態: $state"
    echo "RTMP: rtmp://${fqdn}:1935/live/${STREAM_NAME:-stream}"
}

cmd_checklist() {
    local fqdn=""
    if az container show --resource-group "$RESOURCE_GROUP" --name "$CONTAINER_NAME" &>/dev/null 2>&1; then
        fqdn=$(get_fqdn)
    fi

    echo "=================================================="
    echo "  配信前チェックリスト"
    echo "=================================================="
    echo ""

    if [ -n "$fqdn" ]; then
        echo "[配信元アプリの設定]"
        echo "  サーバー      : rtmp://${fqdn}:1935/live/"
        echo "  ストリームキー: ${STREAM_NAME:-stream}"
    else
        echo "[配信元アプリの設定]  ※ start 後に FQDN が確定します"
        echo "  ストリームキー: ${STREAM_NAME:-stream}  (固定値)"
    fi

    echo ""
    echo "[配信先チェック]  各プラットフォームのストリームキー有効期限を確認"
    [ -n "${YOUTUBE_RTMP:-}"  ] && echo "  [ ] YouTube Live"
    [ -n "${FACEBOOK_RTMP:-}" ] && echo "  [ ] Facebook Live"
    [ -n "${X_RTMP:-}"        ] && echo "  [ ] X (Twitter)"
    [ -n "${LINKEDIN_RTMP:-}" ] && echo "  [ ] LinkedIn Live"

    echo ""
    echo "[配信開始手順]"
    echo "  1. 上記のサーバーとキーを配信元アプリに入力"
    echo "  2. 配信開始 → ffmpeg が自動的に各プラットフォームへ転送"
    echo "  3. 各プラットフォームで映像・音声を確認"
    echo "  4. 終了後: ./multistream.sh stop"
}

cmd_logs() {
    az container logs \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CONTAINER_NAME" \
        --follow
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
