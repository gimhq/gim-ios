#!/usr/bin/env bash
# Runs a standalone gim-hub in Docker for device E2E runs on the Mac build host.
#
#   scripts/e2e-hub.sh start [--sha <hub sha>] [--port <port>]   # default port 18080
#   scripts/e2e-hub.sh stop
#   scripts/e2e-hub.sh url [--port <port>]
#
# `start` builds the image `ai-agent/gim-hub:<short sha>` from `git archive` of the gim-hub repo (GIM_HUB_REPO,
# default /srv/gimhq/im-client/hub) at the pinned commit (GIM_HUB_SHA or --sha) if it is missing, replaces this
# run's hub container, publishes the client API on the Docker host, waits for /healthz (via `gim-hub healthcheck` in
# the container) and prints the URL as seen from the Mac (GIM_E2E_HUB_HOST, default the station host's Tailscale IP
# 100.99.1.1). The hub keeps its data in the container, so every start is a fresh hub. The run id is GIM_GATE_ID,
# default the last component of the branch name.
set -euo pipefail

default_hub_sha=fa19ec2020a58eba5c020055fad43a73ce363ef7

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
hub_repo=${GIM_HUB_REPO:-/srv/gimhq/im-client/hub}
hub_sha=${GIM_HUB_SHA:-$default_hub_sha}
hub_host=${GIM_E2E_HUB_HOST:-100.99.1.1}
id=${GIM_GATE_ID:-$(git -C "$repo" branch --show-current | sed 's|.*/||')}
container=ai-agent-gim-ios-hub-$id
port=

usage() {
    echo "usage: $0 start [--sha <hub sha>] [--port <port>] | stop | url [--port <port>]" >&2
    exit 2
}

# Port of the running container, else --port, else 18080.
published_port() {
    if [[ -z $port ]]; then
        port=$(docker port "$container" 8080/tcp 2>/dev/null | head -1 | sed 's/.*://' || true)
    fi
    echo "${port:-18080}"
}

stop() {
    if docker container inspect "$container" >/dev/null 2>&1; then
        docker rm -f "$container" >/dev/null
        echo "Stopped $container"
    fi
}

start() {
    local full_sha image
    full_sha=$(git -C "$hub_repo" rev-parse --verify "$hub_sha^{commit}")
    image=ai-agent/gim-hub:${full_sha:0:12}
    port=${port:-18080}

    if ! docker image inspect "$image" >/dev/null 2>&1; then
        echo "Building $image from $hub_repo at $full_sha"
        git -C "$hub_repo" archive "$full_sha" | docker build --label ai-agent=true -t "$image" -
    fi

    stop
    docker run -d --rm \
        --label ai-agent=true \
        --label "ai-run=gim-ios-e2e-$id" \
        --name "$container" \
        -p "$port:8080" \
        -e RUST_LOG=info \
        "$image" >/dev/null

    for _ in $(seq 1 60); do
        # `gim-hub healthcheck` probes /healthz from inside the container (station shares no network with it).
        if docker exec "$container" gim-hub healthcheck >/dev/null 2>&1; then
            echo "gim-hub $full_sha ready in $container"
            echo "http://$hub_host:$port"
            return
        fi
        sleep 1
    done

    echo "error: gim-hub did not become healthy within 60 s; log:" >&2
    docker logs "$container" >&2 || true
    stop
    exit 1
}

[[ $# -ge 1 ]] || usage
cmd=$1
shift
while [[ $# -gt 0 ]]; do
    case $1 in
    --sha)
        [[ $# -ge 2 && $cmd == start ]] || usage
        hub_sha=$2
        shift 2
        ;;
    --port)
        [[ $# -ge 2 && $cmd != stop ]] || usage
        port=$2
        shift 2
        ;;
    *)
        usage
        ;;
    esac
done

case $cmd in
start) start ;;
stop) stop ;;
url) echo "http://$hub_host:$(published_port)" ;;
*) usage ;;
esac
