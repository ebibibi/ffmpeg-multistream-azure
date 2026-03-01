#!/bin/sh
# fanout.sh — called by MediaMTX via runOnReady when a publisher connects
#
# MediaMTX-provided environment variables:
#   MTX_PATH       - stream path (e.g. live/stream)
#
# ACI secure environment variables (stream keys):
#   YOUTUBE_RTMP   - YouTube Live RTMP URL (e.g. rtmp://a.rtmp.youtube.com/live2/KEY)
#   FACEBOOK_RTMP  - Facebook Live RTMP URL (rtmps:// required by Facebook)
#   X_RTMP         - X (Twitter) RTMP server URL
#   X_KEY          - X stream key (must create a new Live Event for each session)
#   LINKEDIN_RTMP  - LinkedIn Live RTMP server URL (changes each session)
#   LINKEDIN_KEY   - LinkedIn stream key

INPUT="rtmp://127.0.0.1:1935/${MTX_PATH}"

echo "[fanout $(date)] Stream started: path=${MTX_PATH}"
echo "[fanout] Input : $INPUT"
[ -n "$YOUTUBE_RTMP"  ] && echo "[fanout] Output: YouTube Live"
[ -n "$FACEBOOK_RTMP" ] && echo "[fanout] Output: Facebook Live"
[ -n "$X_RTMP"        ] && echo "[fanout] Output: X (Twitter)"
[ -n "$LINKEDIN_RTMP" ] && echo "[fanout] Output: LinkedIn Live"

# Build the ffmpeg command safely using POSIX sh set -- pattern (preserves quoting)
# Output options must come BEFORE each output URL in ffmpeg
set -- ffmpeg -loglevel warning -i "$INPUT"

[ -n "$YOUTUBE_RTMP"  ] && set -- "$@" -c copy -f flv "$YOUTUBE_RTMP"
[ -n "$FACEBOOK_RTMP" ] && set -- "$@" -c copy -f flv "$FACEBOOK_RTMP"

# X and LinkedIn use a separate playpath from the server URL
if [ -n "$X_RTMP" ] && [ -n "$X_KEY" ]; then
    set -- "$@" -rtmp_playpath "$X_KEY" -rtmp_flashver FMLE/3.0 -c copy -f flv "$X_RTMP"
fi

if [ -n "$LINKEDIN_RTMP" ] && [ -n "$LINKEDIN_KEY" ]; then
    set -- "$@" -rtmp_playpath "$LINKEDIN_KEY" -rtmp_flashver FMLE/3.0 -c copy -f flv "$LINKEDIN_RTMP"
fi

exec "$@"
