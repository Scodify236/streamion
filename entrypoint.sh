#!/usr/bin/env bash
set -ex

echo "[ENTRYPOINT] Starting WireGuard SOCKS5 Proxy"

if [[ -z "${WIREGUARD_INTERFACE_PRIVATE_KEY}" ]]; then
    echo "[ENTRYPOINT] Generating Cloudflare Warp configuration..."
    
    if WARP_ENV=$(deno run --allow-net src/lib/helpers/generateWarpKeys.ts 2>/dev/null); then
        eval "$WARP_ENV"
        export WIREGUARD_INTERFACE_DNS="${WIREGUARD_INTERFACE_DNS:-1.1.1.1}"
        echo "[ENTRYPOINT] Cloudflare Warp config generated successfully via Deno"
    elif WARP_OUTPUT=$(warp 2>/dev/null); then
        export WIREGUARD_INTERFACE_PRIVATE_KEY=$(echo "$WARP_OUTPUT" | grep "PrivateKey" | awk '{print $3}')
        export WIREGUARD_INTERFACE_ADDRESS=$(echo "$WARP_OUTPUT" | grep "Address" | awk '{print $3}')
        export WIREGUARD_PEER_PUBLIC_KEY=$(echo "$WARP_OUTPUT" | grep "PublicKey" | awk '{print $3}')
        export WIREGUARD_PEER_ENDPOINT=$(echo "$WARP_OUTPUT" | grep "Endpoint" | awk '{print $3}')
        export WIREGUARD_INTERFACE_DNS="${WIREGUARD_INTERFACE_DNS:-1.1.1.1}"
        echo "[ENTRYPOINT] Warp config generated successfully via warp binary"
    else
        echo "[WARN] Cloudflare Warp registration failed. Falling back to DIRECT mode."
    fi
else
    echo "[ENTRYPOINT] Using provided WireGuard configuration"
fi

echo "[ENTRYPOINT] Starting SOCKS5 proxy server..."
server &
SERVER_PID=$!

echo "[ENTRYPOINT] Waiting for WireGuard tunnel to stabilize..."
sleep 5

echo "[ENTRYPOINT] Testing tunnel connectivity..."
TRACE=$(curl -s --max-time 5 --socks5 127.0.0.1:1080 https://cloudflare.com/cdn-cgi/trace 2>&1 || true)
if echo "$TRACE" | grep -q "ip="; then
    echo "[ENTRYPOINT] Tunnel OK — proxy IP info:"
    echo "$TRACE" | grep -E "ip=|loc=|warp="
else
    echo "[WARN] Tunnel test inconclusive, response was:"
    echo "$TRACE"
fi

echo "[ENTRYPOINT] Testing YouTube connectivity..."
YT_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 --socks5 127.0.0.1:1080 https://www.youtube.com)
if [[ "$YT_STATUS" == "200" || "$YT_STATUS" == "301" || "$YT_STATUS" == "302" ]]; then
    echo "[ENTRYPOINT] YouTube reachable — HTTP $YT_STATUS"
else
    echo "[WARN] YouTube returned HTTP $YT_STATUS — TLS may still be unstable, continuing anyway..."
fi

echo "[ENTRYPOINT] Setting proxy environment..."
export ALL_PROXY=socks5://127.0.0.1:1080
export HTTPS_PROXY=socks5://127.0.0.1:1080
export HTTP_PROXY=socks5://127.0.0.1:1080

echo "[ENTRYPOINT] Starting Streamion..."
exec deno run --v8-flags=--max-old-space-size=256 --allow-import=github.com:443,jsr.io:443,cdn.jsdelivr.net:443,esm.sh:443,deno.land:443 --allow-net --allow-env --allow-sys=hostname --allow-read=.,/var/tmp/youtubei.js,/tmp/invidious-companion.sock,/tmp/mp3-downloads --allow-write=/var/tmp/youtubei.js,/tmp/invidious-companion.sock,/tmp/mp3-downloads --allow-run=ffmpeg src/main.ts
