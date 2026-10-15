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
```

Downloads the `gim-core-ios-<sha>` artifact with `gh`, verifies its sha256, replaces `Vendor/GIMCore` and writes
`GIM_CORE_VERSION`. Then compare the generated `Vendor/GIMCore/Sources/GIMCore/GIMCore.swift` with the mirror and
update `docs/gim-core-mapping.md`.

## Device E2E server

```sh
scripts/start-gim-server.sh start [port]   # default 8080; prints base URL and log path
scripts/start-gim-server.sh stop
```

Runs the vendored gim-server fixture (`ci/fixtures/gim-server`, see its `SOURCE.md`) with bun on 127.0.0.1 and a fresh
database under `.gim-server/` (override with `GIM_SERVER_RUNTIME_DIR`).
