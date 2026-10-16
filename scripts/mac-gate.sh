#!/usr/bin/env bash
# Builds and tests a commit on the shared macOS build host from station.
#
#   scripts/mac-gate.sh build-test [--sha <commit>] [--keep]
#   scripts/mac-gate.sh e2e --hub-url <url> [--hub-b-url <url>] [--push-mock-url <url>] [--sha <commit>] [--keep]
#
# Ships `git archive <sha>` (default HEAD, which needs a clean tree) to ~/gim-ci/<id>-<short sha>/ on the Mac
# (GIM_MAC_HOST, default a@100.99.1.8; id = GIM_GATE_ID, default the last component of the branch name). There, under
# the shared lock ~/gim-ci/.lock-xcode and on a dedicated simulator created for the run, `build-test` runs xcodegen,
# builds the GIM app and runs the GIMKit and GIMUI package tests; `e2e` additionally runs GIMUITests against the hub
# at <url> (as seen from the Mac, e.g. from scripts/e2e-hub.sh; --hub-b-url adds the second hub of
# `e2e-hub.sh fed-start` for HubsSmokeTests, which is skipped without it). With --push-mock-url (`e2e-hub.sh push-url`)
# a helper on the Mac hands every new mock-ios-sim delivery of that push mock to `xcrun simctl push` on the run's
# simulator while GIMUITests run (logged to push-helper.log), and the tests get the URL as
# TEST_RUNNER_GIM_E2E_PUSH_MOCK_URL. Raw xcodebuild logs, the xcbeautify output, the
# `[e2e-summary]` line and the zipped xcresult bundles are copied to .tmp/mac/<short sha>/. Prints one
# `[mac-gate] ...` summary line and exits non-zero on any failure. The Mac work dir is removed on success and kept on
# failure or with --keep.
set -euo pipefail

usage() {
    echo "usage: $0 build-test|e2e [--sha <commit>] [--hub-url <url>] [--hub-b-url <url>] [--push-mock-url <url>]" \
        "[--keep]" >&2
    exit 2
}

[[ $# -ge 1 ]] || usage
mode=$1
shift
[[ $mode == build-test || $mode == e2e ]] || usage
sha=
hub_url=
hub_b_url=
push_mock_url=
keep=
while [[ $# -gt 0 ]]; do
    case $1 in
    --sha)
        [[ $# -ge 2 ]] || usage
        sha=$2
        shift 2
        ;;
    --hub-url)
        [[ $# -ge 2 ]] || usage
        hub_url=$2
        shift 2
        ;;
    --hub-b-url)
        [[ $# -ge 2 ]] || usage
        hub_b_url=$2
        shift 2
        ;;
    --push-mock-url)
        [[ $# -ge 2 ]] || usage
        push_mock_url=$2
        shift 2
        ;;
    --keep)
        keep=1
        shift
        ;;
    *)
        usage
        ;;
    esac
done
if [[ $mode == e2e && -z $hub_url ]]; then
    echo "error: e2e needs --hub-url" >&2
    exit 2
fi

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
host=${GIM_MAC_HOST:-a@100.99.1.8}
id=${GIM_GATE_ID:-$(git -C "$repo" branch --show-current | sed 's|.*/||')}
if [[ -z $sha ]]; then
    if [[ -n $(git -C "$repo" status --porcelain --untracked-files=no) ]]; then
        echo "error: the working tree has uncommitted changes; commit them or pass --sha" >&2
        exit 1
    fi
    sha=HEAD
fi
sha=$(git -C "$repo" rev-parse --verify "$sha^{commit}")
short=${sha:0:7}
name=$id-$short
work=gim-ci/$name
local_out=$repo/.tmp/mac/$short

mac() {
    ssh -o BatchMode=yes -o ServerAliveInterval=30 "$host" "$@"
}

# Runs on the Mac with /bin/bash (3.2) as `gate.sh <mode> <name> <short sha> [hub url] [hub B url] [push mock url]` from
# the work dir.
# shellcheck disable=SC2016
remote_script='
set -uo pipefail
mode=$1 name=$2 short=$3 hub_url=${4:-} hub_b_url=${5:-} push_mock_url=${6:-}
eval "$(/opt/homebrew/bin/brew shellenv)"
work=$PWD
out=$work/.tmp/gate
results=$work/.tmp/results
derived=$work/.tmp/DerivedData
lock=$HOME/gim-ci/.lock-xcode
owner="$name pid=$$ since $(date -u +%Y-%m-%dT%H:%M:%SZ)"
signing="CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM="
locked="" sim="" helper=""
build=fail kit=fail ui=fail e2e=n/a
[ "$mode" = e2e ] && e2e=fail
mkdir -p "$out" "$results"

cleanup() {
    if [ -n "$helper" ]; then
        pkill -P "$helper" >/dev/null 2>&1
        kill "$helper" >/dev/null 2>&1 && echo "[mac-gate] stopped push helper $helper"
    fi
    if [ -n "$sim" ]; then
        xcrun simctl shutdown "$sim" >/dev/null 2>&1
        xcrun simctl delete "$sim" && echo "[mac-gate] deleted simulator $sim"
    fi
    if [ -n "$locked" ]; then
        current=$(cat "$lock/owner" 2>/dev/null)
        if [ -z "$current" ] || [ "$current" = "$owner" ]; then
            rm -f "$lock/owner"
            rmdir "$lock" && echo "[mac-gate] released $lock"
        else
            echo "[mac-gate] $lock is owned by \"$current\", leaving it" >&2
        fi
    fi
}
trap cleanup EXIT
trap "exit 129" HUP INT TERM

# Polls every 20 s for up to 40 min.
for attempt in $(seq 1 120); do
    if mkdir "$lock" 2>/dev/null; then
        locked=1
        echo "$owner" >"$lock/owner"
        break
    fi
    echo "[mac-gate] waiting for $lock held by: $(cat "$lock/owner" 2>/dev/null || echo unknown) ($attempt/120)"
    sleep 20
done
if [ -z "$locked" ]; then
    echo "[mac-gate] error: $lock not acquired within 40 min" >&2
    exit 1
fi
echo "[mac-gate] acquired $lock"

runtime=$(xcrun simctl list runtimes -j | jq -r "[.runtimes[] | select(.platform == \"iOS\" and .isAvailable)]
    | sort_by(.version | split(\".\") | map(tonumber)) | last | .identifier // empty")
device_type=$(xcrun simctl list runtimes -j | jq -r --arg rt "$runtime" ".runtimes[] | select(.identifier == \$rt)
    | [.supportedDeviceTypes[] | select(.productFamily == \"iPhone\")]
    | (map(select(.name == \"iPhone 17 Pro\")) + .) | first | .identifier // empty")
if [ -z "$runtime" ] || [ -z "$device_type" ]; then
    echo "[mac-gate] error: no iOS runtime or iPhone device type available" >&2
    exit 1
fi
sim=$(xcrun simctl create "gim-$name" "$device_type" "$runtime") || exit 1
echo "[mac-gate] created simulator gim-$name ($sim, $device_type, $runtime)"
destination="platform=iOS Simulator,id=$sim"

# Runs a command with its output tee-d to $out/<log>.log and piped to xcbeautify ($out/<log>.xcbeautify.log).
run() {
    log=$1
    shift
    echo "[mac-gate] $log: $*"
    "$@" 2>&1 | tee "$out/$log.log" | xcbeautify --disable-colored-output | tee "$out/$log.xcbeautify.log"
}

# docs/push-mock.md (gim-hub) section 3: long-polls the push mock for mock-ios-sim deliveries after $1 and hands each
# to `xcrun simctl push` on the run simulator, logging seq, delivery_id, bundle_id and the simctl exit code.
push_helper() {
    since=$1
    while true; do
        resp=$(curl -fsS --max-time 40 "$push_mock_url/deliveries?provider=mock-ios-sim&since=$since&wait=30") || {
            sleep 2
            continue
        }
        since=$(jq -r .next <<<"$resp")
        jq -c ".deliveries[]" <<<"$resp" | while read -r delivery; do
            seq=$(jq -r .seq <<<"$delivery")
            file=$out/push-$seq.json
            jq .simctl.payload <<<"$delivery" >"$file"
            bundle=$(jq -r .simctl.bundle_id <<<"$delivery")
            id=$(jq -r .delivery_id <<<"$delivery")
            xcrun simctl push "$sim" "$bundle" "$file" </dev/null >>"$out/push-helper.log" 2>&1
            rc=$?
            echo "[push-helper] $(date -u +%H:%M:%S) seq=$seq delivery_id=$id bundle_id=$bundle simctl_exit=$rc" \
                >>"$out/push-helper.log"
            rm -f "$file"
        done
    done
}

# Multi-product packages expose their tests via the "<name>-Package" scheme.
package_test() {
    (
        cd "Packages/$1" || exit 1
        scheme=$1
        if xcodebuild -list -json | jq -e ".workspace.schemes | index(\"$1-Package\")" >/dev/null; then
            scheme=$1-Package
        fi
        # shellcheck disable=SC2086
        run "$1-test" xcodebuild test -scheme "$scheme" -destination "$destination" -derivedDataPath "$derived" \
            -resultBundlePath "$results/$1-test.xcresult" $signing
    )
}

# shellcheck disable=SC2086
if xcodegen generate >"$out/xcodegen.log" 2>&1 \
    && run build xcodebuild build -project GIM.xcodeproj -scheme GIM -destination "$destination" \
        -derivedDataPath "$derived" -resultBundlePath "$results/GIM-build.xcresult" $signing; then
    build=ok
fi
package_test GIMKit && kit=ok
package_test GIMUI && ui=ok

if [ "$mode" = e2e ] && [ "$build" = ok ]; then
    xcrun simctl boot "$sim"
    xcrun simctl bootstatus "$sim" -b >/dev/null
    xcrun simctl addmedia "$sim" GIM/UITests/Fixtures/photo-library-seed.png
    if [ -n "$push_mock_url" ]; then
        # Starts after the current deliveries, so older ones are not replayed.
        if next=$(curl -fsS --max-time 10 "$push_mock_url/deliveries?provider=mock-ios-sim" | jq -er .next); then
            echo "[push-helper] $push_mock_url since=$next sim=$sim" >"$out/push-helper.log"
            push_helper "$next" &
            helper=$!
            echo "[mac-gate] push helper $helper polling $push_mock_url since $next"
        else
            echo "[mac-gate] error: push mock $push_mock_url not reachable" | tee "$out/push-helper.log" >&2
        fi
    fi
    # shellcheck disable=SC2086
    TEST_RUNNER_GIM_E2E_SERVER_URL=$hub_url TEST_RUNNER_GIM_E2E_SERVER_URL_B=$hub_b_url \
        TEST_RUNNER_GIM_E2E_PUSH_MOCK_URL=$push_mock_url run e2e xcodebuild test -project GIM.xcodeproj -scheme GIM \
        -only-testing:GIMUITests -destination "$destination" -derivedDataPath "$derived" \
        -resultBundlePath "$results/GIM-e2e.xcresult" $signing && e2e=ok
    grep -o "\[e2e-summary\].*" "$out/e2e.log" >"$out/e2e-summary.txt"
    cat "$out/e2e-summary.txt"
fi

for bundle in "$results"/*.xcresult; do
    [ -d "$bundle" ] && ditto -c -k --keepParent "$bundle" "$out/$(basename "$bundle").zip"
done

summary="[mac-gate] mode=$mode sha=$short build=$build kit=$kit ui=$ui e2e=$e2e"
echo "$summary" >"$out/summary.txt"
case "$build $kit $ui $e2e" in
*fail*) exit 1 ;;
esac
'

echo "[mac-gate] shipping $sha to $host:~/$work"
git -C "$repo" archive "$sha" | mac "rm -rf ~/$work && mkdir -p ~/$work/.tmp && tar -x -C ~/$work"
printf '%s' "$remote_script" | mac "cat >~/$work/.tmp/gate.sh"

status=0
# shellcheck disable=SC2029
mac "cd ~/$work && /bin/bash .tmp/gate.sh $mode $name $short $(printf '%q' "$hub_url") $(printf '%q' "$hub_b_url") \
    $(printf '%q' "$push_mock_url")" </dev/null || status=$?

rm -rf "$local_out"
mkdir -p "$local_out"
mac "tar -c -C ~/$work/.tmp/gate ." | tar -x -C "$local_out" || status=1

summary=$(cat "$local_out/summary.txt" 2>/dev/null || true)
if [[ -z $summary ]]; then
    summary="[mac-gate] mode=$mode sha=$short build=fail kit=fail ui=fail e2e=$([[ $mode == e2e ]] && echo fail || echo n/a)"
    status=1
fi
echo "[mac-gate] logs and xcresult bundles in $local_out"
if [[ $status -eq 0 && -z $keep ]]; then
    mac "rm -rf ~/$work"
else
    echo "[mac-gate] kept $host:~/$work"
fi
echo "$summary"
exit "$status"
