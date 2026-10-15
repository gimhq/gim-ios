# GIMClientKit mirror → GIMCore mapping

`Packages/GIMKit/Sources/GIMClientKit` mirrors the UniFFI Swift bindings of gim-core so that switching to the real
`GIMCore.xcframework` is a mechanical swap.

- Mirrored commit: gim-core `2d08f38` (`bindings/gim-ffi/src/`, generated
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
| `Session` | `Session` | `userId`, `deviceId`, `handle`, `displayName` |
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
| `GimError` | `GimError` | `Network(reason:)`, `NotRegistered`, `InvalidInput(reason:)`, `NotFound(reason:)`, `Crypto(reason:)`, `Storage(reason:)`, `Server(status: UInt16, reason:)`, `Cancelled`, `NotImplemented`, `Internal(reason:)` |

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
| `PlatformHooks` | `PlatformHooks` | `secureStoreGet(key:) -> Data?`, `secureStoreSet(key:value:) throws`, `secureStoreDelete(key:)`, `dataDir() -> String`, `isNetworkReachable() -> Bool` |

All are `AnyObject, Sendable` protocols in both. The mirror spells parameter types `any ChatListListener`; the
generated code writes the bare protocol name, which is the same type.

## Objects and functions

| Mirror | GIMCore | Notes |
|---|---|---|
| `protocol GimClientAPI` | `protocol GimClientProtocol` / `open class GimClient` | Intentional: ViewModels depend on the protocol so `FakeGimClient` can implement it. |
| `protocol Timeline` | `open class Timeline: TimelineProtocol` | Intentional: protocol instead of class. `chatId()`, `addListener(listener:) async -> TaskHandle`, `paginateBackwards(count: UInt16) async throws -> Bool`. |
| `final class TaskHandle` | `open class TaskHandle: TaskHandleProtocol` | Intentional: concrete class with `init(onCancel:)`. `cancel()`, `isFinished() -> Bool`; releasing the last reference cancels, like the Rust `Drop`. No `TaskHandleProtocol` mirror. |
| `createClient(config:hooks:) async throws -> any GimClientAPI` | `createClient(config:hooks:) async throws -> GimClient` | Mirror validates the URL like gim-core (`InvalidInput(reason: "server_url: …")`) and returns an unregistered demo `FakeGimClient` that seeds the demo chats on `register`. |
| — | `coreVersion()`, `ciphersuiteName()` | Not mirrored; nothing uses them yet. |
| — | `*Impl` classes, `NoHandle`, `uniffi*` | Generated plumbing, not mirrored. |

## GimClient methods

Every method of `GimClientProtocol` at `7df3f84`, with identical labels, argument types and `async`/`throws`. The
only return-type differences are `any Timeline` (generated: `Timeline`) and the listener parameter spelling above.

| Mirror (`GimClientAPI`) | GIMCore (`GimClientProtocol`) |
|---|---|
| `session() async throws -> Session?` | same |
| `register(handle:displayName:) async throws -> Session` | same |
| `signOut() async throws` | same |
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
| `fetchMedia(chatId:messageId:destPath:) async throws -> String` | same |
| `fetchThumbnail(chatId:messageId:destPath:) async throws -> String?` | same |
| `chatList(listener:) async throws -> TaskHandle` | same |
| `timeline(chatId:) async throws -> any Timeline` | `-> Timeline` |
| `connectionState(listener:) async throws -> TaskHandle` | same |
| `typing(chatId:listener:) async throws -> TaskHandle` | same |

`chatMembers` has no listener in M1. `GroupInfoViewModel` queries it again when a `ChatListDiff` changes that chat or
a `TimelineItem.membershipChange` arrives. When a query fails before any list has loaded it shows the error with
`ChatSummary.memberCount` (no member list, no removal); a list that loaded before stays on later failures.
Renaming a group goes `GroupInfoViewModel.saveName()` → `GimClientAPI.setGroupInfo(name:)` →
`RealGimClient` → `GIMCore.GimClient.setGroupInfo`.

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
