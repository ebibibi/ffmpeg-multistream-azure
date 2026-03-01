#!/bin/sh
# コンテナ内で実行されるスタートアップスクリプト
# 環境変数から配信先を読み取り、ffmpeg でファンアウトする

STREAM_NAME="${STREAM_NAME:-stream}"
INPUT="rtmp://0.0.0.0:1935/live/$STREAM_NAME"

echo "=== ffmpeg multistream ==="
echo "Input : $INPUT"
[ -n "$YOUTUBE_RTMP"  ] && echo "Output: YouTube"
[ -n "$FACEBOOK_RTMP" ] && echo "Output: Facebook Live"
[ -n "$X_RTMP"        ] && echo "Output: X (Twitter)"
[ -n "$LINKEDIN_RTMP" ] && echo "Output: LinkedIn Live"
echo "=========================="

while true; do
    echo "[$(date)] Waiting for stream..."

    # 引数を POSIX sh で安全に組み立てる（クォート保持のため set -- パターンを使用）
    # グローバルオプション（-loglevel）は最初に、入力オプションは -i の直前に置く
    # -timeout -1 = RTMP 接続待機を無制限に（RTMP専用オプション、単位:秒、-1=無制限）
    set -- ffmpeg -loglevel warning -timeout -1 -listen 1 -i "$INPUT"

    [ -n "$YOUTUBE_RTMP"  ] && set -- "$@" -c copy -f flv "$YOUTUBE_RTMP"
    [ -n "$FACEBOOK_RTMP" ] && set -- "$@" -c copy -f flv "$FACEBOOK_RTMP"

    # X: playpath が URL と別になっているため個別指定
    # ffmpeg では出力オプションは URL より前に置く必要がある
    if [ -n "$X_RTMP" ] && [ -n "$X_KEY" ]; then
        set -- "$@" -rtmp_playpath "$X_KEY" -rtmp_flashver FMLE/3.0 -c copy -f flv "$X_RTMP"
    fi

    # LinkedIn: playpath が URL と別になっているため個別指定
    if [ -n "$LINKEDIN_RTMP" ] && [ -n "$LINKEDIN_KEY" ]; then
        set -- "$@" -rtmp_playpath "$LINKEDIN_KEY" -rtmp_flashver FMLE/3.0 -c copy -f flv "$LINKEDIN_RTMP"
    fi

    "$@" || true

    echo "[$(date)] Stream ended. Restarting in 1s..."
    sleep 1
done
