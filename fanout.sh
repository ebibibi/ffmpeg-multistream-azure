#!/bin/sh
# MediaMTX の runOnPublish フックから呼ばれるファンアウトスクリプト
#
# MediaMTX が設定する環境変数:
#   MNTX_PATH      - 配信パス (例: live/stream)
#
# ACI 起動時に渡されるストリームキー（secure-environment-variables）:
#   YOUTUBE_RTMP   - YouTube Live RTMP URL（例: rtmp://a.rtmp.youtube.com/live2/XXXX）
#   FACEBOOK_RTMP  - Facebook Live RTMP URL
#   X_RTMP         - X (Twitter) RTMP サーバー URL
#   X_KEY          - X stream key
#   LINKEDIN_RTMP  - LinkedIn Live RTMP サーバー URL
#   LINKEDIN_KEY   - LinkedIn stream key

INPUT="rtmp://127.0.0.1:1935/${MTX_PATH}"

echo "[fanout $(date)] 配信開始: path=${MTX_PATH}"
echo "[fanout] 入力: $INPUT"
[ -n "$YOUTUBE_RTMP"  ] && echo "[fanout] 出力: YouTube Live"
[ -n "$FACEBOOK_RTMP" ] && echo "[fanout] 出力: Facebook Live"
[ -n "$X_RTMP"        ] && echo "[fanout] 出力: X (Twitter)"
[ -n "$LINKEDIN_RTMP" ] && echo "[fanout] 出力: LinkedIn Live"

# POSIX sh で ffmpeg コマンドを安全に組み立てる（クォート保持のため set -- パターンを使用）
# ffmpeg では出力オプションは出力 URL の前に置く必要がある
set -- ffmpeg -loglevel warning -i "$INPUT"

[ -n "$YOUTUBE_RTMP"  ] && set -- "$@" -c copy -f flv "$YOUTUBE_RTMP"
[ -n "$FACEBOOK_RTMP" ] && set -- "$@" -c copy -f flv "$FACEBOOK_RTMP"

# X と LinkedIn は playpath が URL と別になっているため個別指定
if [ -n "$X_RTMP" ] && [ -n "$X_KEY" ]; then
    set -- "$@" -rtmp_playpath "$X_KEY" -rtmp_flashver FMLE/3.0 -c copy -f flv "$X_RTMP"
fi

if [ -n "$LINKEDIN_RTMP" ] && [ -n "$LINKEDIN_KEY" ]; then
    set -- "$@" -rtmp_playpath "$LINKEDIN_KEY" -rtmp_flashver FMLE/3.0 -c copy -f flv "$LINKEDIN_RTMP"
fi

exec "$@"
