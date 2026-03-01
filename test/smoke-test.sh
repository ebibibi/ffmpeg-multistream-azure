#!/bin/bash
# smoke-test.sh — verifies the Docker image builds and MediaMTX starts correctly
set -e

IMAGE="${1:-ebibibi/ffmpeg-multistream:latest}"
PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== ffmpeg-multistream-azure smoke test ==="
echo "Image: $IMAGE"
echo ""

# -----------------------------------------------------------------------
# Test 1: Docker image builds without errors
# -----------------------------------------------------------------------
echo "[1] Docker build"
if docker build -t "$IMAGE" "$(dirname "$0")/.." -q > /dev/null 2>&1; then
    ok "Image built successfully"
else
    fail "docker build failed"
    exit 1
fi

# -----------------------------------------------------------------------
# Test 2: Container starts and MediaMTX listens on :1935
# -----------------------------------------------------------------------
echo "[2] Container startup"
CONTAINER_ID=$(docker run -d -p 11935:1935 "$IMAGE" 2>/dev/null)
sleep 4

if docker ps -q --filter "id=$CONTAINER_ID" | grep -q .; then
    ok "Container is running"
else
    fail "Container exited unexpectedly"
    docker logs "$CONTAINER_ID" 2>&1 | sed 's/^/  /'
    docker rm "$CONTAINER_ID" &>/dev/null
    exit 1
fi

LOGS=$(docker logs "$CONTAINER_ID" 2>&1)

if echo "$LOGS" | grep -q "listener opened on :1935"; then
    ok "RTMP listener is up on :1935"
else
    fail "RTMP listener not found in logs"
    echo "$LOGS" | sed 's/^/  /'
fi

if echo "$LOGS" | grep -q "configuration loaded"; then
    ok "mediamtx.yml loaded successfully"
else
    fail "mediamtx.yml not loaded"
fi

docker stop "$CONTAINER_ID" &>/dev/null
docker rm   "$CONTAINER_ID" &>/dev/null

# -----------------------------------------------------------------------
# Test 3: config.example has required fields
# -----------------------------------------------------------------------
echo "[3] config.example validation"
CONFIG="$(dirname "$0")/../config.example"
REQUIRED=(RESOURCE_GROUP CONTAINER_NAME LOCATION CPU MEMORY IMAGE STREAM_NAME)

for field in "${REQUIRED[@]}"; do
    if grep -q "^${field}=" "$CONFIG"; then
        ok "Required field present: $field"
    else
        fail "Missing required field: $field"
    fi
done

# At least one streaming destination should be present (even as placeholder)
if grep -qE "^(YOUTUBE_RTMP|FACEBOOK_RTMP|X_RTMP|LINKEDIN_RTMP)=" "$CONFIG"; then
    ok "At least one streaming destination defined"
else
    fail "No streaming destination found in config.example"
fi

# -----------------------------------------------------------------------
# Test 4: fanout.sh is executable and has exec at the end
# -----------------------------------------------------------------------
echo "[4] fanout.sh sanity check"
FANOUT="$(dirname "$0")/../fanout.sh"

if [ -x "$FANOUT" ]; then
    ok "fanout.sh is executable"
else
    fail "fanout.sh is not executable"
fi

if grep -q "^exec \"\$@\"" "$FANOUT"; then
    ok "fanout.sh ends with exec \"\$@\""
else
    fail "fanout.sh missing exec \"\$@\" — ffmpeg won't run"
fi

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
