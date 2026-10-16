# gim-ios

Native iOS client for gim (Swift 6, SwiftUI, iOS 18, bundle id `im.g.apps`). The app is UI, ViewModels and platform
integration only; storage, networking, sync, the outbox, MLS and media crypto live in the Rust core gim-core,
vendored as `Vendor/GIMCore` (UniFFI bindings + `GIMCore.xcframework.zip`, version in `GIM_CORE_VERSION`).

## Layout

- `GIM/` — app target.
- `Packages/GIMKit` — Foundation-only, builds and tests on Linux: `GIMClientKit` (mirror of the gim-core API and
  `FakeGimClient`) and `GIMFeatures` (ViewModels).
- `Packages/GIMUI` — SwiftUI/UIKit views, platform hooks and the `Bridge` from `GIMCore` to the mirror.
- `docs/gim-core-mapping.md` — how the mirror maps to the generated gim-core API.

## Build

```sh
xcodegen generate
open GIM.xcodeproj
```

GIMKit tests also run without Xcode: `swift test --package-path Packages/GIMKit`.

## Demo mode

The app uses gim-core by default. Debug builds run against the in-memory `FakeGimClient` instead when launched with
`-GIMUseFakeCore YES` (scheme → Run → Arguments). Release builds always use gim-core.

## Default server

Onboarding pre-fills the last used server, else the `-GIMDefaultServerURL <url>` launch argument, else the
`GIM_DEFAULT_SERVER_URL` build setting (Debug: `http://localhost:8080`, Release: empty).

## Refreshing gim-core

```sh
scripts/sync-gim-core.sh <gim-core CI run id>
scripts/sync-gim-core.sh --from-dir <dir> --core-sha <gim-core sha>
```

Downloads the `gim-core-ios-<sha>` artifact with `gh` (or takes a local directory with the same layout, e.g. a build
made from that gim-core commit), verifies its sha256, replaces `Vendor/GIMCore` and writes `GIM_CORE_VERSION`
(`<core version>+<short sha>`). Then compare the generated `Vendor/GIMCore/Sources/GIMCore/GIMCore.swift` with the mirror and
update `docs/gim-core-mapping.md`.

## Device E2E test

`GIMUITests` (`GIM/UITests`, run by the `GIM` scheme's test action) drives the app in the iOS simulator against a
gim-hub (see *E2E hub*). `IdentitySmokeTests` creates an identity, links a second device by its pasted link code and
compares the SAS, revokes it, and restores the identity from the recovery code. `MessagingSmokeTests` covers onboarding,
group creation with scripted peers, text and images both ways, a reply, a reaction, read ticks and sign-out. The peers
and the linked device are gim-core clients inside the test runner with their own temporary data directories.

```sh
url=$(scripts/e2e-hub.sh start | tail -1)
xcodegen generate
TEST_RUNNER_GIM_E2E_SERVER_URL=$url xcodebuild test -project GIM.xcodeproj -scheme GIM -only-testing:GIMUITests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=
scripts/e2e-hub.sh stop
```

Don't pass `CODE_SIGNING_ALLOWED=NO`: the app must be signed (ad hoc is enough) to use the Keychain, otherwise onboarding
fails with "Couldn't save data on this device". `docker logs ai-agent-gim-ios-hub-<id>` has the hub's log.

Without `TEST_RUNNER_GIM_E2E_SERVER_URL` the tests use `http://127.0.0.1:8080`, which the simulator shares with the
host. For the app-to-peer photo step, add an image to the simulator first
(`xcrun simctl addmedia booted GIM/UITests/Fixtures/photo-library-seed.png`); when the system photo picker can't be
automated the step is skipped with a screenshot attachment. Each test class prints one `[e2e-summary] <class> …` line.

## Mac gate

```sh
scripts/mac-gate.sh build-test [--sha <commit>] [--keep]
scripts/mac-gate.sh e2e --hub-url <url> [--hub-b-url <url>] [--push-mock-url <url>] [--sha <commit>] [--keep]
```

Runs from station against the shared Mac build host (`GIM_MAC_HOST`, default `a@100.99.1.8`): ships `git archive` of
the commit (default `HEAD`, clean tree required) to `~/gim-ci/<id>-<short sha>/` (`GIM_GATE_ID`, default the branch
name's last component), takes the `~/gim-ci/.lock-xcode` lock and creates a simulator for the run. `build-test` builds
the app and runs the GIMKit and GIMUI package tests; `e2e` also runs `GIMUITests` against the hub at `<url>`
(`--hub-b-url`: the second federated hub). With `--push-mock-url` (from `scripts/e2e-hub.sh push-url`) a helper on the
Mac long-polls the push mock for new `mock-ios-sim` deliveries while the tests run and hands each to
`xcrun simctl push` on the run's simulator, logging seq, delivery id, bundle id and the simctl exit code to
`push-helper.log`; the tests get the URL as `TEST_RUNNER_GIM_E2E_PUSH_MOCK_URL` (for `/deliveries` and `/stats`). Logs,
the `[e2e-summary]` lines and zipped xcresult bundles land in `.tmp/mac/<short sha>/`; the last line is the
`[mac-gate] mode=… build=… kit=… ui=… e2e=…` summary. The Mac work dir is kept on failure or with `--keep`.

## E2E hub

```sh
url=$(scripts/e2e-hub.sh start | tail -1)   # [--sha <gim-hub commit>] [--port <port>], default port 18080
scripts/mac-gate.sh e2e --hub-url "$url"
scripts/e2e-hub.sh stop
```

Builds `ai-agent/gim-hub:<short sha>` from the gim-hub repo (`GIM_HUB_REPO`, pinned commit in the script or
`GIM_HUB_SHA`) if missing and runs a fresh standalone hub in Docker. The printed URL is the Docker host as seen from
the Mac (`GIM_E2E_HUB_HOST`, default `100.99.1.1`); `scripts/e2e-hub.sh url` prints it again. The hub runs with
`GIM_HUB_PUBLIC_URL` set to exactly that URL: gim-core signs in only at the URL the hub proves (`GET /v2/hub`), so
clients must use it verbatim. A port already in use on the host is an error.

Two federated hubs:

```sh
eval "$(scripts/e2e-hub.sh fed-start)"   # [--run <id>] [--sha <commit>] [--port-a <port>] [--port-b <port>]
echo "$GIM_E2E_HUB_A $GIM_E2E_HUB_B"     # also GIM_E2E_HUB_ID_A / GIM_E2E_HUB_ID_B
scripts/e2e-hub.sh fed-url a             # prints a hub's URL again
scripts/e2e-hub.sh fed-stop
```

Hubs A and B run in closed federation (each allows the other, shared libp2p PSK on a dedicated network, root keys in
named volumes), each with its own published port (default: the first free ones from 18181) and public URL as above.
`fed-start` returns once both are healthy and have bound each other. The run id defaults to `GIM_GATE_ID` or the
branch name's last component; containers, network and volumes are labelled `ai-agent-run=gim-ios-e2e-<run>` and
`fed-stop` removes exactly those.

Both `start` and `fed-start` also run a mock push server for the run (`ai-agent/gim-push-mock:<short sha>`, built from
`Dockerfile.push-mock` of the same gim-hub commit; see the hub's `docs/push-mock.md`) on the `traefik` network with
the first free port from 18190 and a random webhook secret in the run's state dir (`.tmp/e2e-hub-<run>/push.env` or
`.tmp/e2e-fed-<run>/push.env`, never printed). Every hub of the run posts its push webhook to it. Start returns once
its `/healthz` is OK; `fed-start` also prints `GIM_E2E_PUSH_MOCK_URL`, and the matching stop removes it.

```sh
scripts/e2e-hub.sh push-url [--run <id>]   # the mock's URL as seen from the Mac
```
