# GIMClientKit mirror → GIMCore mapping

`Packages/GIMKit/Sources/GIMClientKit` mirrors the UniFFI Swift bindings of gim-core so that switching to the real
`GIMCore.xcframework` is a mechanical swap.

- Mirrored commit: gim-core `7077421` (`bindings/gim-ffi/src/`, generated
  `bindings/gim-ffi/generated/swift/GIMCore.swift`, contract in `docs/API.md`).
- Mirror sources: `GimClientAPI.swift` (objects, callback interfaces, hooks, `createClient`) and `Models.swift`
  (records, enums, diffs, errors).
- Everything else in GIMClientKit (`Fake/`, `GimClientFactory`, `CoreGimClientFactory`) is app-level and stays after
  the swap.

## Records

All records are structs with every field public and a memberwise `init` without default values, in field order.
Generated records are `Equatable, Hashable` plus `extension …: Sendable`; the mirror declares `Sendable, Hashable`.

| Mirror | GIMCore | Fields |
|---|---|---|
| `ClientConfig` | `ClientConfig` | `serverUrl` |
| `Session` | `Session` | `userId`, `deviceId`, `handle` (empty until `claimHandle`), `displayName` |
| `DeviceInfo` | `DeviceInfo` | `deviceId`, `createdAtMs: UInt64` (0 for revoked devices), `isCurrent`, `revoked` |
| `UserProfile` | `UserProfile` | `userId`, `handle`, `displayName` |
| `ChatSummary` | `ChatSummary` | `chatId`, `kind`, `name`, `avatar: MediaRef?`, `lastMessage: MessagePreview?`, `unreadCount: UInt32`, `updatedAtMs: UInt64`, `memberCount: UInt32` |
| `MessagePreview` | `MessagePreview` | `senderName`, `text`, `sentAtMs: UInt64`, `isOwn` |
| `MessageItem` | `MessageItem` | `messageId`, `chatId`, `sender: UserProfile`, `isOwn`, `sentAtMs: UInt64`, `content`, `replyTo: ReplyPreview?`, `reactions: [ReactionGroup]`, `edited`, `sendState: SendState?` |
| `MediaRef` | `MediaRef` | `chatId`, `messageId`, `mime`, `size: UInt64`, `hasThumbnail` |
| `ReplyPreview` | `ReplyPreview` | `messageId`, `senderName`, `text` |
| `ReactionGroup` | `ReactionGroup` | `emoji`, `count: UInt32`, `own` |

## Enums

| Mirror | GIMCore | Cases |
|---|---|---|
| `ChatKind` | `ChatKind` | `direct`, `group` |
| `TimelineItem` | `TimelineItem` | `message(item:)`, `dateSeparator(dayStartMs:)`, `membershipChange(userName:change:atMs:)` |
| `MembershipChangeKind` | `MembershipChangeKind` | `added`, `removed`, `left` |
| `MessageContent` | `MessageContent` | `text(body:)`, `image(media:width:height:caption:)`, `file(media:fileName:caption:)`, `deleted`, `unsupported` |
| `SendState` | `SendState` | `pending`, `sent`, `delivered`, `read`, `failed(reason:)` |
| `ConnectionState` | `ConnectionState` | `offline`, `connecting`, `connected`, `syncing` |
| `ChatListDiff` | `ChatListDiff` | `append(values:)`, `clear`, `pushFront(value:)`, `pushBack(value:)`, `popFront`, `popBack`, `insert(index:value:)`, `set(index:value:)`, `remove(index:)`, `truncate(length:)`, `reset(values:)` |
| `TimelineDiff` | `TimelineDiff` | same cases as `ChatListDiff`, with `TimelineItem` values |
| `GimError` | `GimError` | `Network(reason:)`, `NotRegistered`, `InvalidInput(reason:)`, `NotFound(reason:)`, `Crypto(reason:)`, `Storage(reason:)`, `Server(status: UInt16, reason:)`, `RetryLater(status: UInt16, retryAfterSecs: UInt64, reason:)`, `Cancelled`, `NotImplemented`, `Internal(reason:)` |

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
| `PlatformHooks` | `PlatformHooks` | `secureStoreGet(key:) throws -> Data?`, `secureStoreSet(key:value:) throws`, `secureStoreDelete(key:)`, `dataDir() -> String`, `isNetworkReachable() -> Bool` |
| `LocalTimeZone` | `LocalTimeZone` | `utcOffsetSecs(atMs: Int64) -> Int32` |

All are `AnyObject, Sendable` protocols in both. The mirror spells parameter types `any ChatListListener`; the
generated code writes the bare protocol name, which is the same type.

## Objects and functions

| Mirror | GIMCore | Notes |
|---|---|---|
| `protocol GimClientAPI` | `protocol GimClientProtocol` / `open class GimClient` | Intentional: ViewModels depend on the protocol so `FakeGimClient` can implement it. |
| `protocol Timeline` | `open class Timeline: TimelineProtocol` | Intentional: protocol instead of class. `chatId()`, `addListener(listener:) async -> TaskHandle`, `paginateBackwards(count: UInt16) async throws -> Bool`. |
| `protocol LinkSession` | `open class LinkSession: LinkSessionProtocol` | Intentional: protocol instead of class. `qrString() -> String`. `RealGimClient.waitLink` only accepts the `RealLinkSession` it created. |
| `protocol PendingApproval` | `open class PendingApproval: PendingApprovalProtocol` | Intentional: protocol instead of class. `deviceId() -> String`, `sas() -> String`. `RealGimClient.confirmApproval` only accepts the `RealPendingApproval` it created. |
| `final class TaskHandle` | `open class TaskHandle: TaskHandleProtocol` | Intentional: concrete class with `init(onCancel:)`. `cancel()`, `isFinished() -> Bool`; releasing the last reference cancels, like the Rust `Drop`. No `TaskHandleProtocol` mirror. |
| `createClient(config:hooks:) async throws -> any GimClientAPI` | `createClient(config:hooks:) async throws -> GimClient` | Mirror validates the URL like gim-core (`InvalidInput(reason: "server_url: …")`) and returns a demo `FakeGimClient` without a session that seeds the demo chats on `createIdentity`. |
| — | `coreVersion()`, `ciphersuiteName()` | Not mirrored; nothing uses them yet. |
| — | `LocalTimeZoneImpl` | Generated wrapper for a Rust-implemented zone; gim-core never hands one to the app. |
| — | `*Impl` classes, `NoHandle`, `uniffi*` | Generated plumbing, not mirrored. |

## GimClient methods

Every method of `GimClientProtocol` at `7077421`, with identical labels, argument types and `async`/`throws`. The
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

`chatMembers` has no listener in M1. `GroupInfoViewModel` queries it again when a `ChatListDiff` changes that chat or
a `TimelineItem.membershipChange` arrives. When a query fails before any list has loaded it shows the error with
`ChatSummary.memberCount` (no member list, no removal); a list that loaded before stays on later failures.
Renaming a group goes `GroupInfoViewModel.saveName()` → `GimClientAPI.setGroupInfo(name:)` →
`RealGimClient` → `GIMCore.GimClient.setGroupInfo`.

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
