FROM alpine:3.20

RUN apk add --no-cache ffmpeg

COPY container-start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 1935

ENTRYPOINT ["/bin/sh", "/start.sh"]
