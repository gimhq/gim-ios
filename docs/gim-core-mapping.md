# GIMClientKit mirror → GIMCore mapping

`Packages/GIMKit/Sources/GIMClientKit` mirrors the UniFFI Swift bindings of gim-core so that switching to the real
`GIMCore.xcframework` is a mechanical swap.

- Mirrored and vendored commit: gim-core `f8db42c`, GIMCore `0.1.0+f8db42c` (`bindings/gim-ffi/src/`, generated
  `bindings/gim-ffi/generated/swift/GIMCore.swift`, contract in `docs/API.md`).
- Mirror sources: `GimClientAPI.swift` (objects, callback interfaces, hooks, `createClient`) and `Models.swift`
  (records, enums, diffs, errors).
- Everything else in GIMClientKit (`Fake/`, `GimClientFactory`, `CoreGimClientFactory`) is app-level and stays after
  the swap.

## Records

All records are structs with every field public and a memberwise `init` without default values, in field order,
except `ClientConfig.mode`, which defaults to `nil` like the generated init.
Generated records are `Equatable, Hashable` plus `extension …: Sendable`; the mirror declares `Sendable, Hashable`.

| Mirror | GIMCore | Fields |
|---|---|---|
| `ClientConfig` | `ClientConfig` | `serverUrl`, `mode: ClientMode?` (`nil` is `app`) |
| `PushRegistration` | `PushRegistration` | `provider`, `token`, `appId: String?`, `sandbox: Bool?`, `p256dh: String?`, `auth: String?` |
| `NotificationContent` | `NotificationContent` | `chatId: String?`, `chatTitle: String?`, `senderUserId: String?`, `senderDisplayName: String?`, `body`, `messageId: String?`, `collapseId: String?`, `kind: NotificationKind`, `shouldDisplay`, `timestamp: UInt64` |
| `Session` | `Session` | `userId`, `deviceId`, `handle` (empty until `claimHandle`), `displayName` |
| `DeviceInfo` | `DeviceInfo` | `deviceId`, `createdAtMs: UInt64` (0 for revoked devices), `isCurrent`, `revoked` |
| `HubInfo` | `HubInfo` | `hubId`, `url: String?`, `state: HubState`, `priority: UInt8`, `isPrimary`, `isHome`, `signedIn` |
| `UserProfile` | `UserProfile` | `userId`, `handle`, `displayName` |
| `ChatSummary` | `ChatSummary` | `chatId`, `kind`, `name`, `avatar: MediaRef?`, `lastMessage: MessagePreview?`, `unreadCount: UInt32`, `updatedAtMs: UInt64`, `memberCount: UInt32`, `state: ChatState` |
| `MessagePreview` | `MessagePreview` | `senderName`, `text`, `sentAtMs: UInt64`, `isOwn` |
| `MessageItem` | `MessageItem` | `messageId`, `chatId`, `sender: UserProfile`, `isOwn`, `sentAtMs: UInt64`, `content`, `replyTo: ReplyPreview?`, `reactions: [ReactionGroup]`, `edited`, `sendState: SendState?` |
| `MediaRef` | `MediaRef` | `chatId`, `messageId`, `mime`, `size: UInt64`, `hasThumbnail` |
| `ReplyPreview` | `ReplyPreview` | `messageId`, `senderName`, `text` |
| `ReactionGroup` | `ReactionGroup` | `emoji`, `count: UInt32`, `own` |

## Enums

| Mirror | GIMCore | Cases |
|---|---|---|
| `ChatKind` | `ChatKind` | `direct`, `group` |
| `ChatState` | `ChatState` | `active`, `leaving`, `left` |
| `HubState` | `HubState` | `unverified`, `verified`, `removed` |
| `ClientMode` | `ClientMode` | `app`, `` `extension` `` |
| `NotificationKind` | `NotificationKind` | `message`, `reaction`, `invite`, `membership`, `generic` |
| `TimelineItem` | `TimelineItem` | `message(item:)`, `dateSeparator(dayStartMs:)`, `membershipChange(userName:change:atMs:userId:actorUserId:)` (`actorUserId: String?`) |
| `MembershipChangeKind` | `MembershipChangeKind` | `added`, `removed`, `left` |
| `MessageContent` | `MessageContent` | `text(body:)`, `image(media:width:height:caption:)`, `file(media:fileName:caption:)`, `deleted`, `unsupported` |
| `SendState` | `SendState` | `pending`, `sent`, `delivered`, `read`, `failed(reason:)` |
| `ConnectionState` | `ConnectionState` | `offline`, `connecting`, `connected`, `syncing` |
| `ChatListDiff` | `ChatListDiff` | `append(values:)`, `clear`, `pushFront(value:)`, `pushBack(value:)`, `popFront`, `popBack`, `insert(index:value:)`, `set(index:value:)`, `remove(index:)`, `truncate(length:)`, `reset(values:)` |
| `TimelineDiff` | `TimelineDiff` | same cases as `ChatListDiff`, with `TimelineItem` values |
| `GimError` | `GimError` | `Network(reason:)`, `NotRegistered`, `InvalidInput(reason:)`, `NotFound(reason:)`, `Crypto(reason:)`, `Storage(reason:)`, `Server(status: UInt16, reason:)`, `RetryLater(status: UInt16, retryAfterSecs: UInt64, reason:)`, `Cancelled`, `NotImplemented`, `Internal(reason:)`, `ChatNotActive(chatId:state: ChatState)`, `HubNotVerified(reason:)`, `HubOwnsGroups(hubId:groupCount: UInt32)`, `LastHub(hubId:)`, `HomeHub(hubId:)`, `HubNotDrained(hubId:reason:)` |

`GimError` keeps the generated UpperCamelCase case names (hence the `swift-format-ignore: AlwaysUseLowerCamelCase`
on its declaration) and conforms to `Error, Sendable, Hashable, LocalizedError` with
`errorDescription == String(reflecting: self)`, like the generated enum.

## Callback interfaces

| Mirror | GIMCore | Method |
|---|---|---|
| `ChatListListener` | `ChatListListener` | `onUpdate(diffs: [ChatListDiff])` |
| `TimelineListener` | `TimelineListener` | `onUpdate(diffs: [TimelineDiff])` |
| `ConnectionStateListener` | `ConnectionStateListener` | `onChange(state: ConnectionState)` |
| `TypingListener` | `TypingListener` | `onUpdate(userIds: [String])` |
| `HubListListener` | `HubListListener` | `onUpdate(hubs: [HubInfo])` |
| `PlatformHooks` | `PlatformHooks` | `secureStoreGet(key:) throws -> Data?`, `secureStoreSet(key:value:) throws`, `secureStoreDelete(key:)`, `dataDir() -> String`, `isNetworkReachable() -> Bool` |
| `LocalTimeZone` | `LocalTimeZone` | `utcOffsetSecs(atMs: Int64) -> Int32` |

All are `AnyObject, Sendable` protocols in both. The mirror spells parameter types `any ChatListListener`; the
generated code writes the bare protocol name, which is the same type.

## Objects and functions

| Mirror | GIMCore | Notes |
|---|---|---|
| `protocol GimClientAPI` | `protocol GimClientProtocol` / `open class GimClient` | Intentional: ViewModels depend on the protocol so `FakeGimClient` can implement it. |
| `protocol Timeline` | `open class Timeline: TimelineProtocol` | Intentional: protocol instead of class. `chatId()`, `addListener(listener:) async -> TaskHandle`, `paginateBackwards(count: UInt16) async throws -> Bool`, `chatState() -> ChatState?` (synchronous). |
| `protocol LinkSession` | `open class LinkSession: LinkSessionProtocol` | Intentional: protocol instead of class. `qrString() -> String`. `RealGimClient.waitLink` only accepts the `RealLinkSession` it created. |
| `protocol PendingApproval` | `open class PendingApproval: PendingApprovalProtocol` | Intentional: protocol instead of class. `deviceId() -> String`, `sas() -> String`. `RealGimClient.confirmApproval` only accepts the `RealPendingApproval` it created. |
| `final class TaskHandle` | `open class TaskHandle: TaskHandleProtocol` | Intentional: concrete class with `init(onCancel:)`. `cancel()`, `isFinished() -> Bool`; releasing the last reference cancels, like the Rust `Drop`. No `TaskHandleProtocol` mirror. |
| `createClient(config:hooks:) async throws -> any GimClientAPI` | `createClient(config:hooks:) async throws -> GimClient` | Mirror validates the URL like gim-core (`InvalidInput(reason: "server_url: …")`) and returns a demo `FakeGimClient` without a session that seeds the demo chats on `createIdentity`. |
| — | `coreVersion()`, `ciphersuiteName()` | Not mirrored; nothing uses them yet. |
| — | `LocalTimeZoneImpl` | Generated wrapper for a Rust-implemented zone; gim-core never hands one to the app. |
| — | `*Impl` classes, `NoHandle`, `uniffi*` | Generated plumbing, not mirrored. |

## GimClient methods

Every method of `GimClientProtocol` at `f8db42c`, with identical labels, argument types and `async`/`throws`. The
only type differences are `any Timeline` / `any LinkSession` / `any PendingApproval` (generated: the classes) and the
listener parameter spelling above.

| Mirror (`GimClientAPI`) | GIMCore (`GimClientProtocol`) |
|---|---|
| `session() async throws -> Session?` | same |
| `userId() -> String?` | same (synchronous) |
| `localStateReset() -> Bool` | same (synchronous) |
| `signOut() async throws` | same |
| `createIdentity(displayName:) async throws -> String` | same; returns the recovery code |
| `restoreFromRecovery(userId:recoveryCode:revokeOthers:) async throws` | same |
| `startLink(hubs: [String]) throws -> any LinkSession` | `-> LinkSession` (synchronous) |
| `waitLink(link: any LinkSession) async throws -> String` | `link: LinkSession`; returns the SAS |
| `confirmLink(accepted:) async throws` | same |
| `approveLink(qrString:) async throws -> any PendingApproval` | `-> PendingApproval` |
| `confirmApproval(approval: any PendingApproval, accepted:) async throws` | `approval: PendingApproval` |
| `devices() async throws -> [DeviceInfo]` | same |
| `userDevices(userId:) async throws -> [DeviceInfo]` | same |
| `revokeDevice(deviceId:) async throws` | same |
| `setDisplayName(name:) async throws` | same |
| `claimHandle(handle:) async throws` | same |
| `releaseHandle() async throws` | same |
| `startSync() async throws` | same |
| `stopSync() async throws` | same |
| `setNetworkReachable(reachable: Bool)` | same (synchronous, never throws) |
| `findUser(handle:) async throws -> UserProfile?` | same |
| `createDirectChat(userId:) async throws -> String` | same |
| `createGroupChat(name:memberUserIds:) async throws -> String` | same |
| `chatMembers(chatId:) async throws -> [UserProfile]` | same |
| `addMembers(chatId:userIds:) async throws` | same |
| `removeMember(chatId:userId:) async throws` | same |
| `leaveChat(chatId:) async throws` | same |
| `chatState(chatId:) async throws -> ChatState` | same; `NotFound` for an unknown chat |
| `setGroupInfo(chatId:name:avatarFilePath:) async throws` | same; at least one of `name`/`avatarFilePath` must be set, `InvalidInput` for direct chats |
| `sendText(chatId:body:replyTo:) async throws -> String` | same |
| `sendMedia(chatId:filePath:mime:caption:replyTo:) async throws -> String` | same |
| `editMessage(chatId:messageId:newBody:) async throws` | same |
| `deleteMessage(chatId:messageId:) async throws` | same |
| `react(chatId:messageId:emoji:) async throws` | same |
| `unreact(chatId:messageId:emoji:) async throws` | same |
| `retrySend(chatId:messageId:) async throws` | same |
| `cancelSend(chatId:messageId:) async throws` | same |
| `markRead(chatId:upToMessageId:) async throws` | same |
| `setTyping(chatId:active:) async throws` | same |
| `stopTyping(chatId:) async throws` | same |
| `fetchMedia(chatId:messageId:destPath:) async throws -> String` | same |
| `fetchThumbnail(chatId:messageId:destPath:) async throws -> String?` | same |
| `chatList(listener:) async throws -> TaskHandle` | same |
| `timeline(chatId:) async throws -> any Timeline` | `-> Timeline` |
| `setLocalTimeZone(zone: (any LocalTimeZone)?)` | `zone: LocalTimeZone?` (synchronous, never throws) |
| `connectionState(listener:) async throws -> TaskHandle` | same |
| `typing(chatId:listener:) async throws -> TaskHandle` | same |
| `hubs() async throws -> [HubInfo]` | same |
| `addHub(url:) async throws -> HubInfo` | same |
| `removeHub(hubId:confirmOwnedGroups:) async throws` | same |
| `setPrimaryHub(hubId:) async throws` | same |
| `hubList(listener:) async throws -> TaskHandle` | same |
| `registerPush(registration:) async throws` | same |
| `unregisterPush() async throws` | same |
| `processPush(payload:) async throws -> NotificationContent` | same |

`chatMembers` has no listener in M1. `GroupInfoViewModel` queries it again when a `ChatListDiff` changes that chat or
a `TimelineItem.membershipChange` arrives. When a query fails before any list has loaded it shows the error with
`ChatSummary.memberCount` (no member list, no removal); a list that loaded before stays on later failures.
Renaming a group goes `GroupInfoViewModel.saveName()` → `GimClientAPI.setGroupInfo(name:)` →
`RealGimClient` → `GIMCore.GimClient.setGroupInfo`.

## Changes since `5877765`

`f8db42c` (built on the macOS host from gim-core `f8db42c` with `scripts/build-xcframework.sh`, the CI size gate and
the 4 link tests, then vendored with `scripts/sync-gim-core.sh --from-dir`). Diff of the generated `GIMCore.swift`:

- App extensions (gim-core `docs/API.md`, "App extensions"): `ClientConfig.mode: ClientMode?` (`init` default `nil`,
  which is `app`) and `enum ClientMode { app, extension }`. In `extension` mode `startSync()` throws `InvalidInput`,
  `registerPush`/`unregisterPush` do nothing, and local state is never reset.
- Push (gim-core `docs/API.md`, "Push"): `GimClientProtocol.registerPush(registration:)`, `unregisterPush()` and
  `processPush(payload:) -> NotificationContent` (all async, throwing); records `PushRegistration` and
  `NotificationContent`, enum `NotificationKind { message, reaction, invite, membership, generic }`.
- No `GimError` case changed. Behaviour only: chats are created on the primary hub, submissions pass hubs that do not
  have the group, and `findUser` looks a handle up on every listed hub (C4-T9).

App adaptations:

- Mirror and `CoreMapping`: `ClientMode` and `PushRegistration` mirror → core, `NotificationContent` and
  `NotificationKind` core → mirror; `RealGimClient` forwards the three push methods. The app keeps creating clients
  with `mode == nil` (`app`).
- `FakeGimClient(mode:)` (`createClient` passes `ClientConfig.mode`): `registerPush` rejects an empty provider or
  token (`InvalidInput`) and keeps the registration in `pushRegistration` until `unregisterPush` or `signOut`;
  `processPush` throws `InvalidInput` for a payload that is not a JSON object, describes
  `{"type":"message","chat_id":…,"body":…}` as a displayed `message` (title from the chat list), and returns the
  generic content (`New message`, displayed) for anything else. In `extension` mode `startSync` throws `InvalidInput`
  and `registerPush`/`unregisterPush` do nothing, like gim-core.

## Changes since `50f7915`

`5877765` adds the guarded migration `0007_hubs_url_shared.sql` (schema v7), which restores `hubs.url_shared` on
databases from `d5ead6d`; bindings and `GIMCore.swift` are byte-identical to `50f7915`.

## Changes since `d5ead6d`

`50f7915` (built on the macOS host from gim-core `50f7915` with `scripts/build-xcframework.sh`, the CI size gate and
the 4 link tests, then vendored with `scripts/sync-gim-core.sh --from-dir`; local database schema v6, see below). Diff
of the generated `GIMCore.swift`:

- Hub management (gim-core `docs/API.md`, "Hub management"): `GimClientProtocol.hubs()`, `addHub(url:)`,
  `removeHub(hubId:confirmOwnedGroups:)`, `setPrimaryHub(hubId:)` (all async, throwing) and
  `hubList(listener:) -> TaskHandle`; record `HubInfo`, enum `HubState { unverified, verified, removed }`, callback
  interface `HubListListener` (`onUpdate(hubs:)`, the current list first, then on every possible registry change).
  `hubs()` lists primary first (priority, then hub id), removed hubs included; the first hub not removed is
  `isPrimary`.
- `GimError`: new cases 13–17, appended after `ChatNotActive`: `HubNotVerified(reason:)` (the server at a URL did not
  prove it is that hub, URL-bound hub proof and `AuthChallenge` v2, gim-core `docs/identity.md`, "Hub proof of
  possession"; the device did not sign in there), `HubOwnsGroups(hubId:groupCount: UInt32)`, `LastHub(hubId:)`,
  `HomeHub(hubId:)`, `HubNotDrained(hubId:reason:)` (all from `removeHub`). `addHub` reports a URL that does not serve
  a gim hub as `InvalidInput`.
- Multi-hub receive and submit (primary/fallback, per-hub cursors and KeyPackages, read fallback): behaviour only, no
  further signature change. With a single hub nothing changes.

Schema: `0005_hub_cursors.sql` and `0006_key_package_ledger.sql` are forward migrations (v4 → v5 → v6, keeping rows;
`migrates_a_v4_database_keeping_its_rows`, `migrates_a_v5_database_keeping_its_rows`), so `localStateReset()` stays
`false` and `AppModel`'s routing is unchanged (`AppModelTests`). Caveat: `0004_hubs.sql` was edited in place after
`d5ead6d` (new column `hubs.url_shared`), so a v4 database written by `d5ead6d` lacks that column after the migration
and gim-core's hub reads fail with "no such column: url_shared" instead of a reset; reported to the gim-core
workstream.

App adaptations:

- Mirror and `CoreMapping`: `HubInfo`/`HubState` core → mirror, the five errors both ways; `RealGimClient` forwards
  the five methods; `CoreHubListListener` converts and hops to the main queue through `MainQueueRelay` like the other
  listeners, never calling the client.
- `FakeGimClient` keeps a deterministic hub registry. The home hub is `homeHubUrl` (`createClient` passes
  `ClientConfig.serverUrl`; default `defaultHomeHubUrl`), with hub id `hubId(forUrl:)` (`hub-` and the host). `addHub`
  validates the URL like `createClient` (`InvalidInput("url: …")`), throws `HubNotVerified` for a URL containing
  "unverified", lists the hub last as `unverified` and makes it `verified` and signed in `hubVerifyDelay` later.
  `setPrimaryHub` reorders like gim-core (`InvalidInput` for an unlisted hub or a reprioritized hub without a
  session). `removeHub` checks in gim-core's order: unlisted (`InvalidInput`), `HomeHub`, `LastHub`, `HubOwnsGroups`
  (`simulateOwnedGroups(hubId:count:)`) unless confirmed, `HubNotDrained` once for a URL containing "busy"; the hub
  stays listed as `removed`. `simulateHubSharedByOtherDevice(url:)` and `simulateHubRemovedElsewhere(hubId:)` play
  the other own devices (the latter also makes `LastHub` reachable). `signOut` resets the registry to the home hub.
- `ErrorPresenter` maps the five errors (e.g. "This hub hosts 3 groups you own."); I3b-3 may refine the wording.

## Changes since `7077421`

`d5ead6d` (built on the macOS host from gim-core `d5ead6d` with `scripts/build-xcframework.sh`, the CI size gate and
the 4 link tests, then vendored with `scripts/sync-gim-core.sh --from-dir`; local database schema v4, migrated from v3
by gim-core, see below). Diff of the generated `GIMCore.swift`:

- Added `enum ChatState { active, leaving, left }`, `ChatSummary.state`, `GimClientProtocol.chatState(chatId:)` (async,
  throws, `NotFound` for an unknown chat; local state, no network) and `TimelineProtocol.chatState() -> ChatState?`
  (synchronous, `nil` while the chat is not known locally). A chat is `leaving` once `leaveChat` returned (also across
  restarts; calling it again re-sends the leave), `left` once removed (after leaving, by another member or hub-side);
  history is kept and the chat stays in the list. Transitions arrive as a `set` of the row.
- `GimError.ChatNotActive(chatId:state:)` (new case 12): sends and changes to a `leaving`/`left` chat (`sendText`,
  `sendMedia`, `editMessage`, `deleteMessage`, `react`, `unreact`, `retrySend`, `setGroupInfo`, `addMembers`,
  `removeMember`; `leaveChat` once `left`) throw it instead of `InvalidInput("invalid state: leaving chat …")`.
- `TimelineItem.membershipChange` gains `userId` (who joined or left; the own `left` carries the own user id) and
  `actorUserId: String?` (the adder/remover, the user themselves for `left`, `nil` if unknown; an invitee that could
  not be added is `removed` by the inviter).
- Typed 4xx semantics, no signature change: a 4xx is a definite rejection that gim-core does not resend
  (`Server(403, …)`, `InvalidInput` for 400 `validation_failed`/422); a 5xx, 408 or 429 is resent unchanged. A
  rejected message send still returns its id and the message is `SendState.failed(reason:)` at once (the reason is
  gim-core's error text); `SendState` is unchanged.
- Hub registry (multi-homing groundwork): internal to gim-core, nothing generated for the app.
- Doc-only (checksums changed): `leaveChat`, `signOut` (also stops the listeners and returns only after every callback
  in flight returned, waiting at most 5 s; no callback runs afterwards). Every callback interface (`PlatformHooks`,
  `LocalTimeZone`, the four listeners) is now called on gim-core's single `gim-callbacks` thread, one call at a time;
  objects passed in may be released there.

Schema: `0004_hubs.sql` adds the `hubs` table; gim-core migrates a v3 database (written by `7077421`) in place,
keeping its rows (`migrates_a_v3_database_keeping_its_rows`), so `localStateReset()` stays `false` after the update.
Only a database it cannot open (wrong key, foreign `application_id`, or a schema newer than the build, e.g. after a
downgrade back to `7077421`) is discarded with `localStateReset() == true`, which `AppModel` routes to onboarding with
the "local history was lost" notice (D5; `AppModelTests`).

App adaptations:

- Mirror and `CoreMapping`: `ChatState` both ways (core → mirror for summaries and `chatState`, mirror → core for
  `ChatNotActive` thrown back from hooks), the new `membershipChange` fields, `RealGimClient.chatState(chatId:)` and
  `RealTimeline.chatState()`.
- `FakeGimClient` keeps a `ChatState` per chat: `leaveChat` → `leaving` → `left` after `leaveCommitDelay` (with the own
  `left` change; a repeated `leaveChat` while leaving does not restart it), `simulateRemoval(chatId:by:)` → `left` at
  once with the own `removed` change; left chats stay in the list with their history (they used to be removed).
  Sends and changes to a chat that is not `active` throw `ChatNotActive` (the `InvalidInput("invalid state: leaving
  chat …")` is gone). Membership changes carry `userId`/`actorUserId`. `rejectNextSend(status:code:)` (default 403
  `not_member`) makes the next own send `failed` at once with `"rejected (403 not_member)"`, without resending.
- `ErrorPresenter` maps `ChatNotActive` to a neutral "no longer a member" text; `LeavingChats.isLeavingRefusal`
  recognizes `ChatNotActive(_, .leaving)` (and still the old reason text). The screens switch to `ChatState` in I3a-2.
- Callback threading (gim-core `docs/API.md`, "Threading of platform callbacks"): the listener adapters convert and hop
  to the main queue; `CorePlatformHooks`/`KeychainSecureStorage`, `CoreLocalTimeZone`/`SystemLocalTimeZone` answer
  directly without calling the client. `MainQueueRelay` now cancels and releases the gim-core `TaskHandle` on the main
  queue: a stream listener released by gim-core on its callback thread (after `signOut`) cancels its subscription there.

## Changes since `3724543`

`7077421` (vendored with `scripts/sync-gim-core.sh 38830392117`; local database schema v3, migrated by gim-core).
Diff of the generated `GIMCore.swift`:

- Added `GimClientProtocol.setLocalTimeZone(zone: LocalTimeZone?)` (synchronous, never throws) and the callback
  interface `LocalTimeZone` (`utcOffsetSecs(atMs: Int64) -> Int32`, the offset from UTC in effect at that instant,
  DST included). `nil` is UTC, the default.
- `TimelineItem.dateSeparator(dayStartMs:)` is now the start of a local calendar day in that zone (was: UTC day).
  Changing the zone moves the separators of open timelines through their listeners as ordinary diffs.
- Doc-only (checksums changed): `createIdentity`, `restoreFromRecovery` and `waitLink` keep nothing of a failed
  attempt (gim-core `docs/API.md`, "Retrying onboarding"). `waitLink` on a `LinkSession` that already received a
  bundle fails with `InvalidInput` (gim-core `crates/gim-sdk/src/link.rs`); before a bundle arrived the same session
  can wait again.
- Federation behaviour (hosting record, pending invites, peer retries) needs no new API; no record, enum or error
  case changed.

App adaptations:

- `AppModel` wraps its factory so that every client (gim-core or demo) is attached to `TimeZoneMonitor`, which sets
  a new `SystemLocalTimeZone` (`TimeZone.current` at creation) right after creation and again on
  `NSSystemTimeZoneDidChange`. `RealGimClient` passes it through `CoreLocalTimeZone`, answered on gim-core's thread.
  The app never re-bucketed separators; `TimelineItemBuilder` still only formats `dayStartMs`.
- `FakeGimClient` buckets its date separators with the zone set by `setLocalTimeZone` (UTC when `nil`), with gim-core's
  rule (offsets at the start of the UTC hour, day start at local midnight), and republishes open timelines on a change.
  Its `calendar` parameter is gone.
- Onboarding retries no longer skip calls when the client has a user: `CreateIdentityViewModel` calls
  `createIdentity` again (new user and code), `RestoreViewModel` calls `restoreFromRecovery` again, and
  `LinkThisDeviceViewModel` waits again on the same `LinkSession`, starting a new one when that fails with
  `InvalidInput` (bundle already received). `confirmLink(false)` still wipes the device and discards the client.

## Changes since `2d08f38`

`3724543` (vendored with `scripts/sync-gim-core.sh --from-dir`) adds identity and devices (gim-core `docs/API.md`,
"Identity and devices"; `docs/identity.md`, "Device link flow"). Diff of the generated `GIMCore.swift`:

- Removed: `GimClientProtocol.register(handle:displayName:) -> Session`. A new user is `createIdentity(displayName:)`
  (returns the recovery code) followed by an optional `claimHandle(handle:)`; `Session.handle` is empty until then.
- Added `GimClientProtocol` methods: `createIdentity`, `restoreFromRecovery`, `startLink` (synchronous `throws`),
  `waitLink`, `confirmLink`, `approveLink`, `confirmApproval`, `devices`, `userDevices`, `revokeDevice`,
  `setDisplayName`, `claimHandle`, `releaseHandle`, `stopTyping`, `userId()` and `localStateReset()` (both
  synchronous, non-throwing).
- Added objects `LinkSession` (`qrString()`) and `PendingApproval` (`deviceId()`, `sas()`), record `DeviceInfo`.
- `GimError`: new case `RetryLater(status:retryAfterSecs:reason:)`; no case was renamed or removed. `NotRegistered`
  now also means "this device was revoked".
- `PlatformHooks.secureStoreGet(key:)` now `throws`: the app must throw when the keystore can't be read
  (`KeychainSecureStorage` throws `GimError.Storage` for any `SecItemCopyMatching` status other than
  `errSecSuccess` / `errSecItemNotFound`) instead of reporting the secret as absent.
- Doc-only: "gim-server" became "the hub" (`ClientConfig.serverUrl`, `Server`).

App adaptations: onboarding calls `createIdentity` (unless the client already has a user, after a failed claim) then
`claimHandle`, and discards the recovery code until I2c; a taken handle is now `Server(409)`. `ErrorPresenter` maps
`RetryLater`. `FakeGimClient` simulates the new calls deterministically (recovery code in the core format, fixed SAS
`"123 456"`).

## Changes since `e69fcba`

`2d08f38` is a packaging-only change on top of `7df3f84` (the xcframework now links on macOS, fixing
"ld: LSDA in __eh_frame section not supported"); no API change, the vendored `GIMCore.swift` is byte-identical.

`7df3f84` changes no signature, record, enum or error of the generated bindings; only doc comments and the
`set_group_info` / `start_sync` UniFFI checksums differ (the vendored xcframework and `GIMCore.swift` must come from
the same build). Behaviour that the app now relies on:

- `chatMembers` is implemented (no `NotImplemented`); names come from the local user directory and resolve later
  through `ChatListDiff`s and timeline `Set`s.
- `setGroupInfo` shares the name/avatar with the members; the avatar is encrypted and uploaded before it returns.
- `startSync` reconnects with backoff and reports `Offline` while waiting; `setNetworkReachable(true)` reconnects and
  retries the outbox at once.

## Swap checklist

The mirror is permanent; there is no swap that deletes it.

- GIMClientKit keeps `GimClientAPI`, the models and `FakeGimClient`. GIMKit never imports `GIMCore`, so the
  ViewModels and their tests stay on Linux.
- `Packages/GIMUI/Sources/GIMUI/Bridge` maps `GIMCore` to the mirror: `RealGimClientFactory` calls
  `GIMCore.createClient`, `RealGimClient` implements `GimClientAPI` by converting every value 1:1 (`CoreMapping`),
  rethrowing errors as the mirror's `GimError`, and `CoreListeners` adapts the callback interfaces and delivers
  them on the main queue.
- `RealGimClientFactory` is the default client (`AppModel.defaultFactory()`); release builds always use it.
- In debug builds the launch argument `-GIMUseFakeCore YES` makes `AppModel.defaultFactory()` return
  `CoreGimClientFactory` (`FakeGimClient`), the demo mode. The fake also drives previews and tests.
