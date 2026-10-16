#!/usr/bin/env bash
# Runs gim-hub in Docker for device E2E runs on the Mac build host.
#
#   scripts/e2e-hub.sh start [--sha <hub sha>] [--port <port>]   # default port 18080
#   scripts/e2e-hub.sh stop
#   scripts/e2e-hub.sh url [--port <port>]
#   scripts/e2e-hub.sh fed-start [--run <id>] [--sha <hub sha>] [--port-a <port>] [--port-b <port>]
#   scripts/e2e-hub.sh fed-stop [--run <id>]
#   scripts/e2e-hub.sh fed-url a|b [--run <id>]
#
# The image `ai-agent/gim-hub:<short sha>` is built from `git archive` of the gim-hub repo (GIM_HUB_REPO, default
# /srv/gimhq/im-client/hub) at the pinned commit (GIM_HUB_SHA or --sha) if it is missing. Every hub publishes its
# client API on the Docker host and runs with GIM_HUB_PUBLIC_URL set to the URL the Mac reaches it at,
# http://<GIM_E2E_HUB_HOST>:<port> (default host: the station host's Tailscale IP 100.99.1.1): gim-core signs in
# only at the URL the hub proves, so clients must use exactly that URL. A requested port that is already in use is
# an error. The run id is GIM_GATE_ID (or --run), default the last component of the branch name.
#
# `start` replaces this run's standalone hub, waits for /healthz (via `gim-hub healthcheck` in the container) and
# prints the URL. The hub keeps its data in the container, so every start is a fresh hub.
#
# `fed-start` starts hubs A and B in closed federation: each allows the other, both share a generated libp2p PSK
# (TCP only, on a dedicated network), each has its root key in its own named volume. Default ports are the first
# free ones from 18181. It waits until both are healthy and have bound each other, then prints GIM_E2E_HUB_A=<url>
# and GIM_E2E_HUB_B=<url> (plus GIM_E2E_HUB_ID_A/B). Containers, network and volumes carry the labels
# ai-agent=true and ai-agent-run=gim-ios-e2e-<run>; `fed-stop` removes exactly those.
set -euo pipefail

default_hub_sha=50b3401726c99781e30b7c0311f5c63a56bc5657

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
hub_repo=${GIM_HUB_REPO:-/srv/gimhq/im-client/hub}
hub_sha=${GIM_HUB_SHA:-$default_hub_sha}
hub_host=${GIM_E2E_HUB_HOST:-100.99.1.1}
id=${GIM_GATE_ID:-$(git -C "$repo" branch --show-current | sed 's|.*/||')}
port=
port_a=
port_b=
fed_hub=

usage() {
    {
        echo "usage: $0 start [--sha <hub sha>] [--port <port>] | stop | url [--port <port>]"
        echo "       $0 fed-start [--run <id>] [--sha <hub sha>] [--port-a <port>] [--port-b <port>]"
        echo "       $0 fed-stop [--run <id>] | fed-url a|b [--run <id>]"
    } >&2
    exit 2
}

hub_url() {
    echo "http://$hub_host:$1"
}

# GIM_HUB_PUBLIC_URL of a running container.
container_url() {
    docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$1" 2>/dev/null |
        sed -n 's/^GIM_HUB_PUBLIC_URL=//p'
}

port_in_use() {
    [[ -n $(ss -ltnH "sport = :$1") ]]
}

require_free_port() {
    if port_in_use "$1"; then
        echo "error: port $1 is already in use on this host (ss -ltn); pick another one" >&2
        exit 1
    fi
}

# First free port from $1 on that is not in the remaining arguments.
free_port() {
    local p=$1
    shift
    while port_in_use "$p" || [[ " $* " == *" $p "* ]]; do
        p=$((p + 1))
    done
    echo "$p"
}

build_image() {
    local full_sha
    full_sha=$(git -C "$hub_repo" rev-parse --verify "$hub_sha^{commit}")
    image=ai-agent/gim-hub:${full_sha:0:12}
    if ! docker image inspect "$image" >/dev/null 2>&1; then
        echo "Building $image from $hub_repo at $full_sha" >&2
        git -C "$hub_repo" archive "$full_sha" |
            docker build --label ai-agent=true --label "gim.hub.commit=$full_sha" -t "$image" - >&2
    fi
}

# Waits up to 60 s for /healthz of container $1; `gim-hub healthcheck` probes it from inside the container.
wait_healthy() {
    local _
    for _ in $(seq 1 60); do
        if docker exec "$1" gim-hub healthcheck >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    echo "error: $1 did not become healthy within 60 s; log:" >&2
    docker logs "$1" >&2 || true
    return 1
}

container=ai-agent-gim-ios-hub-$id

stop() {
    if docker container inspect "$container" >/dev/null 2>&1; then
        docker rm -f "$container" >/dev/null
        echo "Stopped $container"
    fi
}

start() {
    port=${port:-18080}
    stop
    require_free_port "$port"
    build_image
    docker run -d --rm \
        --label ai-agent=true \
        --label "ai-run=gim-ios-e2e-$id" \
        --name "$container" \
        -p "$port:8080" \
        -e RUST_LOG=info \
        -e "GIM_HUB_PUBLIC_URL=$(hub_url "$port")" \
        "$image" >/dev/null

    if ! wait_healthy "$container"; then
        stop
        exit 1
    fi
    echo "gim-hub $image ready in $container"
    container_url "$container"
}

url() {
    local u
    u=$(container_url "$container")
    echo "${u:-$(hub_url "${port:-18080}")}"
}

fed_prefix() {
    echo "ai-agent-gim-ios-fed-$id"
}

fed_stop() {
    local label=ai-agent-run=gim-ios-e2e-$id
    docker ps -aq --filter "label=$label" | xargs -r docker rm -f >/dev/null
    docker network ls -q --filter "label=$label" | xargs -r docker network rm >/dev/null
    docker volume ls -q --filter "label=$label" | xargs -r docker volume rm >/dev/null
    rm -rf "$repo/.tmp/e2e-fed-$id"
}

# Waits up to 60 s until the log of container $1 shows "peer hub bound" for hub id $2.
fed_wait_bound() {
    local _
    for _ in $(seq 1 60); do
        if docker logs "$1" 2>&1 | grep "peer hub bound" | grep -q "$2"; then
            echo "$1 bound $2" >&2
            return 0
        fi
        sleep 1
    done
    echo "error: $1 did not bind $2 within 60 s; log:" >&2
    docker logs "$1" >&2 || true
    return 1
}

fed_start() {
    local prefix dir hub other labels=(--label ai-agent=true --label "ai-agent-run=gim-ios-e2e-$id")
    local -A hub_id hub_port
    prefix=$(fed_prefix)
    dir=$repo/.tmp/e2e-fed-$id
    fed_stop
    [[ -n $port_a ]] && require_free_port "$port_a"
    [[ -n $port_b ]] && require_free_port "$port_b"
    if [[ -n $port_a && $port_a == "$port_b" ]]; then
        echo "error: --port-a and --port-b must differ" >&2
        exit 1
    fi
    build_image

    hub_port[a]=${port_a:-$(free_port 18181 "$port_b")}
    hub_port[b]=${port_b:-$(free_port 18181 "${hub_port[a]}")}

    mkdir -p "$dir"
    {
        echo "/key/swarm/psk/1.0.0/"
        echo "/base16/"
        od -An -tx1 -N32 /dev/urandom | tr -d ' \n'
        echo
    } >"$dir/swarm.key"
    docker network create "${labels[@]}" "$prefix" >/dev/null
    for hub in a b; do
        docker volume create "${labels[@]}" "$prefix-$hub" >/dev/null
        # Creates the hub root key in the volume and prints its hub_id.
        hub_id[$hub]=$(docker run --rm "${labels[@]}" -v "$prefix-$hub:/data" "$image" gim-hub hub-id | tr -d '\r\n')
    done
    for hub in a b; do
        echo "${hub_id[$hub]} /dns4/hub-$hub/tcp/4001"
    done >"$dir/allowlist"
    chmod 0755 "$dir"
    chmod 0644 "$dir"/*

    for hub in a b; do
        docker run -d "${labels[@]}" --name "$prefix-$hub" \
            --network "$prefix" --network-alias "hub-$hub" \
            -p "${hub_port[$hub]}:8080" \
            -v "$prefix-$hub:/data" -v "$dir:/config:ro" \
            -e RUST_LOG=info \
            -e "GIM_HUB_PUBLIC_URL=$(hub_url "${hub_port[$hub]}")" \
            -e GIM_HUB_FEDERATION=true \
            -e GIM_HUB_P2P_LISTEN=/ip4/0.0.0.0/tcp/4001 \
            -e "GIM_HUB_P2P_EXTERNAL_ADDRS=/dns4/hub-$hub/tcp/4001" \
            -e GIM_HUB_FEDERATION_ALLOWLIST=/config/allowlist \
            -e GIM_HUB_P2P_PSK_FILE=/config/swarm.key \
            -e GIM_HUB_S2S_TIMEOUT_SECONDS=3 \
            -e GIM_HUB_OUTBOX_BACKOFF_MAX_SECONDS=2 \
            "$image" >/dev/null
    done
    for hub in a b; do
        wait_healthy "$prefix-$hub" || exit 1
    done
    for hub in a b; do
        other=a
        [[ $hub == a ]] && other=b
        fed_wait_bound "$prefix-$hub" "${hub_id[$other]}" || exit 1
    done

    echo "GIM_E2E_HUB_A=$(container_url "$prefix-a")"
    echo "GIM_E2E_HUB_B=$(container_url "$prefix-b")"
    echo "GIM_E2E_HUB_ID_A=${hub_id[a]}"
    echo "GIM_E2E_HUB_ID_B=${hub_id[b]}"
}

fed_url() {
    local u
    u=$(container_url "$(fed_prefix)-$fed_hub")
    if [[ -z $u ]]; then
        echo "error: hub $fed_hub of run $id is not running" >&2
        exit 1
    fi
    echo "$u"
}

[[ $# -ge 1 ]] || usage
cmd=$1
shift
if [[ $cmd == fed-url ]]; then
    [[ $# -ge 1 && ($1 == a || $1 == b) ]] || usage
    fed_hub=$1
    shift
fi
while [[ $# -gt 0 ]]; do
    case $1 in
    --sha)
        [[ $# -ge 2 && ($cmd == start || $cmd == fed-start) ]] || usage
        hub_sha=$2
        shift 2
        ;;
    --port)
        [[ $# -ge 2 && ($cmd == start || $cmd == url) ]] || usage
        port=$2
        shift 2
        ;;
    --port-a | --port-b)
        [[ $# -ge 2 && $cmd == fed-start ]] || usage
        if [[ $1 == --port-a ]]; then port_a=$2; else port_b=$2; fi
        shift 2
        ;;
    --run)
        [[ $# -ge 2 && $cmd == fed-* ]] || usage
        id=$2
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
url) url ;;
fed-start) fed_start ;;
fed-stop) fed_stop ;;
fed-url) fed_url ;;
*) usage ;;
esac
