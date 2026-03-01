# ffmpeg-multistream-azure

Multistream to YouTube, Facebook, X (Twitter), and LinkedIn simultaneously using [MediaMTX](https://github.com/bluenviron/mediamtx) + ffmpeg on Azure Container Instances (ACI).

No transcoding. No audio quality loss. Pay only while streaming.

## Architecture

```
Your streaming app (Teams, OBS, etc.)
        │  RTMP
        ▼
┌─────────────────────────────────────────┐
│  Azure Container Instance               │
│                                         │
│  MediaMTX  ←── always listening :1935  │
│      │                                  │
│      │ runOnReady (publisher connected) │
│      ▼                                  │
│  fanout.sh → ffmpeg (-c copy)           │
│      ├──────────────► YouTube Live      │
│      ├──────────────► Facebook Live     │
│      ├──────────────► X (Twitter)       │
│      └──────────────► LinkedIn Live     │
└─────────────────────────────────────────┘
```

**Why MediaMTX instead of raw `ffmpeg -listen 1`?**

`ffmpeg -listen 1` exits on the very first TCP connection that fails the RTMP handshake (port scanners, Azure probes, etc.), causing an unstable reconnect loop. MediaMTX is a proper RTMP server — it handles bad connections gracefully and stays online until Teams connects.

**Why no audio noise?**

ffmpeg uses `-c copy` (stream copy) throughout — no decode/encode cycle. This avoids the HLS segmentation issues that caused audio crackling in solutions like Restreamer.

## Prerequisites

- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) logged in
- An Azure subscription
- Docker (for building the image)
- Stream keys from each platform you want to target

## Quick Start

```bash
# 1. Clone and configure
git clone https://github.com/ebibibi/ffmpeg-multistream-azure.git
cd ffmpeg-multistream-azure
cp config.example config
$EDITOR config   # fill in your stream keys

# 2. Start
./multistream.sh start

# 3. Point your streaming app at the displayed RTMP URL and start broadcasting

# 4. Stop when done (this stops billing)
./multistream.sh stop
```

## Configuration

Copy `config.example` to `config` and set your values:

```bash
# Azure
RESOURCE_GROUP=multistream-rg
CONTAINER_NAME=multistream
LOCATION=japaneast
CPU=1
MEMORY=2

# Your broadcasting app connects here with stream key = STREAM_NAME
STREAM_NAME=stream

# Destinations (leave blank to skip a platform)
YOUTUBE_RTMP=rtmp://a.rtmp.youtube.com/live2/YOUR_KEY
FACEBOOK_RTMP=rtmps://live-api-s.facebook.com:443/rtmp/YOUR_KEY
X_RTMP=rtmp://jp.pscp.tv:80/x
X_KEY=YOUR_X_KEY
```

Stream keys are passed as **secure environment variables** and are not visible in the Azure Portal.

## Commands

```
./multistream.sh [-y] [-t <minutes>] <command>

  start      Launch ACI and wait for stream
  stop       Delete ACI container (stops billing)
  status     Show state and RTMP ingest URL
  checklist  Show pre-broadcast checklist
  logs       Tail container logs (polls every 5s)

Options:
  -y           Skip confirmation prompt
  -t <minutes> Auto-stop after N minutes
```

## Platform Notes

### YouTube Live
Combine the server URL and stream key into `YOUTUBE_RTMP`:
```
YOUTUBE_RTMP=rtmp://a.rtmp.youtube.com/live2/<YOUR_KEY>
```
Where to find: **YouTube Studio → Go Live → Stream tab**

---

### Facebook Live
Facebook **requires** `rtmps://` (TLS). Combine server + key:
```
FACEBOOK_RTMP=rtmps://live-api-s.facebook.com:443/rtmp/<YOUR_KEY>
```
Where to find: **Facebook → Live Video → Use Stream Key**

---

### X (Twitter)
> ⚠️ **Important:** X does **not** support mid-stream reconnection.
> - ✅ Your stream key is **permanent** — the same key works for every broadcast, forever
> - ❌ If the stream is interrupted, that broadcast session ends immediately and cannot be resumed
> - The next time you stream with the same key, X starts a **new** broadcast session automatically

```
X_RTMP=rtmp://jp.pscp.tv:80/x
X_KEY=<YOUR_KEY>
```
Where to find: **studio.twitter.com → Broadcasts → Create a broadcast**

---

### LinkedIn Live
> ⚠️ **Important:** The RTMP ingest URL **changes with every new LinkedIn Live event**. Update both `LINKEDIN_RTMP` and `LINKEDIN_KEY` before each session.

```
LINKEDIN_RTMP=rtmps://<YOUR_INGEST_HOST>/live
LINKEDIN_KEY=<YOUR_KEY>
```
Where to find: **LinkedIn → Create a post → Live video → Configure stream**

## Building the Docker Image

```bash
docker build -t ebibibi/ffmpeg-multistream:latest .
docker push ebibibi/ffmpeg-multistream:latest
```

Or use the pre-built image from Docker Hub: `ebibibi/ffmpeg-multistream:latest`

## Running Tests

```bash
# Smoke test: verifies MediaMTX starts and listens on :1935
bash test/smoke-test.sh
```

## Cost

ACI is billed per second of runtime. A typical 1 vCPU / 2 GB container in Japan East costs roughly **¥0.0016/sec** (~¥6/hour). Use `./multistream.sh stop` when done, or pass `-t <minutes>` for an auto-stop timer.

## How It Works

1. `./multistream.sh start` creates an ACI container with stream keys injected as secure env vars.
2. MediaMTX starts inside the container and listens on port 1935.
3. Your streaming app (Teams, OBS, etc.) connects and publishes to `rtmp://<fqdn>:1935/live/<STREAM_NAME>`.
4. MediaMTX triggers `runOnReady` → runs `fanout.sh`.
5. `fanout.sh` builds and executes an `ffmpeg` command that reads from MediaMTX locally and writes to all configured destinations simultaneously using `-c copy` (no transcoding).
6. When the source disconnects, MediaMTX kills ffmpeg automatically.
7. `./multistream.sh stop` deletes the container and ends billing.

## License

MIT
