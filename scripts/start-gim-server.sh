#!/usr/bin/env bash
# Starts or stops the vendored gim-server fixture (ci/fixtures/gim-server) for device E2E runs.
#
#   scripts/start-gim-server.sh start [port]   # default port 8080
#   scripts/start-gim-server.sh stop
#
# `start` installs the fixture's dependencies with bun, launches `src/index.ts` in the background on 127.0.0.1
# with a fresh database and per-request logging (LOG_LEVEL from GIM_SERVER_LOG_LEVEL, default debug), waits for
# /healthz and prints the base URL and log path. The database, data dir, pid file
# and log live in GIM_SERVER_RUNTIME_DIR (default .gim-server/ at the repo root), which `start` recreates.
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$repo/ci/fixtures/gim-server
runtime=${GIM_SERVER_RUNTIME_DIR:-$repo/.gim-server}
pid_file=$runtime/server.pid
log_file=$runtime/server.log

usage() {
    echo "usage: $0 start [port] | stop" >&2
    exit 2
}

stop() {
    if [[ -f $pid_file ]]; then
        pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            for _ in $(seq 1 10); do
                kill -0 "$pid" 2>/dev/null || break
                sleep 1
            done
            kill -0 "$pid" 2>/dev/null && kill -9 "$pid"
            echo "Stopped gim-server (pid $pid)"
        fi
        rm -f "$pid_file"
    fi
}

# The fixture logs no requests, so its entry point is started with Bun.serve wrapped to log one JSON line per
# request (method, path, status, duration) in the fixture's log format.
request_logger='
const serve = Bun.serve
Bun.serve = (options) => serve({
  ...options,
  async fetch(request, server) {
    const started = performance.now()
    const log = (status) => console.log(JSON.stringify({
      time: new Date().toISOString(), level: "debug", msg: "request", method: request.method,
      path: new URL(request.url).pathname, status, ms: Math.round(performance.now() - started),
    }))
    try {
      const response = await options.fetch.call(server, request, server)
      log(response?.status ?? 101)
      return response
    } catch (error) {
      log(`error: ${error}`)
      throw error
    }
  },
})
await import("./src/index.ts")
'

healthy() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsS -o /dev/null --max-time 2 "$1/healthz"
    else
        bun -e "const r = await fetch('$1/healthz'); process.exit(r.ok ? 0 : 1)" >/dev/null 2>&1
    fi
}

start() {
    local port=${1:-8080}
    local base_url=http://127.0.0.1:$port

    stop
    rm -rf "$runtime"
    mkdir -p "$runtime/data"

    echo "Installing gim-server dependencies"
    if ! (cd "$fixture" && bun install --frozen-lockfile --production); then
        (cd "$fixture" && bun install --frozen-lockfile)
    fi

    (
        cd "$fixture"
        PORT=$port HOST=127.0.0.1 LOG_LEVEL=${GIM_SERVER_LOG_LEVEL:-debug} \
            DATABASE_PATH=$runtime/data/gim.db DATA_DIR=$runtime/data \
            nohup bun -e "$request_logger" >"$log_file" 2>&1 &
        echo $! >"$pid_file"
    )

    for _ in $(seq 1 30); do
        if healthy "$base_url"; then
            echo "gim-server ready at $base_url"
            echo "Log: $log_file"
            return
        fi
        sleep 1
    done

    echo "error: gim-server did not become healthy within 30 s; log ($log_file):" >&2
    cat "$log_file" >&2
    stop
    exit 1
}

case ${1:-} in
start)
    [[ $# -le 2 ]] || usage
    start "${2:-}"
    ;;
stop)
    [[ $# -eq 1 ]] || usage
    stop
    ;;
*)
    usage
    ;;
esac
