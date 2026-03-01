FROM bluenviron/mediamtx:latest-ffmpeg

# MediaMTX 設定ファイルを上書き
COPY mediamtx.yml /mediamtx.yml

# Teams 接続時に起動するファンアウトスクリプト
COPY fanout.sh /fanout.sh
RUN chmod +x /fanout.sh

EXPOSE 1935
