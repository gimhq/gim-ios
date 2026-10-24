# GIMClientKit mirror → GIMCore mapping

`Packages/GIMKit/Sources/GIMClientKit` mirrors the UniFFI Swift bindings of gim-core so that switching to the real
`GIMCore.xcframework` is a mechanical swap.

- Mirrored commit: gim-core `c1b7503` (`bindings/gim-ffi/src/`, generated
  `bindings/gim-ffi/generated/swift/GIMCore.swift`, contract in `docs/API.md`).
- Vendored commit: gim-client-sdk `b86283e` (CI run 40038617133), GIMCore `0.1.0+b86283e`; the mirror covers it
  (see "Changes since `16a5efa`" and "Changes since `c1b7503`").
- Mirror sources: `GimClientAPI.swift` (objects, callback interfaces, hooks, `createClient`) and `Models.swift`
  (records, enums, diffs, errors).
- Everything else in GIMClientKit (`Fake/`, `GimClientFactory`, `CoreGimClientFactory`) is app-level and stays after
  the swap.

## Records

All records are structs with every field public and a memberwise `init` without default values, in field order,
except `ClientConfig.mode` and `ClientConfig.metaServerUrl`, which default to `nil` like the generated init. Fields
added after `c1b7503` (`MessagePreview.sendState`, `UserProfile.hasAvatar`, the account safety fields of
`ChatSummary`) have mirror init defaults (`nil`, `false`, `0`) so existing call sites keep compiling; the generated
inits have none.
Generated records are `Equatable, Hashable` plus `extension …: Sendable`; the mirror declares `Sendable, Hashable`.

| Mirror | GIMCore | Fields |
|---|---|---|
| `ClientConfig` | `ClientConfig` | `serverUrl`, `mode: ClientMode?` (`nil` is `app`), `metaServerUrl: String?` (the gim meta server, gim-meta; `nil` until it is deployed, so `reportUser` fails and settings are not backed up) |
| `PushRegistration` | `PushRegistration` | `provider`, `token`, `appId: String?`, `sandbox: Bool?`, `p256dh: String?`, `auth: String?` |
| `NotificationContent` | `NotificationContent` | `chatId: String?`, `chatTitle: String?`, `senderUserId: String?`, `senderDisplayName: String?`, `body`, `messageId: String?`, `collapseId: String?`, `kind: NotificationKind`, `shouldDisplay`, `timestamp: UInt64` |
| `Session` | `Session` | `userId`, `deviceId`, `handle` (empty until `claimHandle`), `displayName` |
| `DeviceInfo` | `DeviceInfo` | `deviceId`, `createdAtMs: UInt64` (0 for revoked devices), `isCurrent`, `revoked` |
| `HubInfo` | `HubInfo` | `hubId`, `url: String?`, `state: HubState`, `priority: UInt8`, `isPrimary`, `isHome`, `signedIn` |
| `UserProfile` | `UserProfile` | `userId`, `handle`, `displayName`, `hasAvatar` (get the photo with `fetchUserAvatar`) |
| `ChatSummary` | `ChatSummary` | `chatId`, `kind`, `name`, `avatar: MediaRef?`, `lastMessage: MessagePreview?`, `unreadCount: UInt32`, `updatedAtMs: UInt64`, `memberCount: UInt32`, `state: ChatState`, `peer: UserProfile?` (direct chats: the other user), `mutedUntilMs: UInt64` (0: not muted, `mutedForever()`: until unmuted), `pinned`, `archived`, `blocked` (direct chat with a blocked user) |
| `PrivacySettings` | `PrivacySettings` | `readReceipts`, `typingIndicators`, `blockedUserIds: [String]` |
| `RecoveryRotation` | `RecoveryRotation` | `recoveryCode`, `unsyncedHubIds: [String]` |
| `MessagePreview` | `MessagePreview` | `senderName`, `text`, `sentAtMs: UInt64`, `isOwn`, `sendState: SendState?` (own messages only; the mirror init defaults it to `nil`) |
| `MessageItem` | `MessageItem` | `messageId`, `chatId`, `sender: UserProfile`, `isOwn`, `sentAtMs: UInt64`, `content`, `replyTo: ReplyPreview?`, `reactions: [ReactionGroup]`, `edited`, `sendState: SendState?` |
| `MediaRef` | `MediaRef` | `chatId`, `messageId`, `mime`, `size: UInt64`, `hasThumbnail` |
| `ReplyPreview` | `ReplyPreview` | `messageId`, `senderName`, `text` |
| `ReactionGroup` | `ReactionGroup` | `emoji`, `count: UInt32`, `own` |
| `RecoveryKitLabels` | `RecoveryKitLabels` | `title`, `accountId`, `recoveryKey`, `note` |
| `ParsedRecoveryKit` | `ParsedRecoveryKit` | `userId: String?`, `recoveryCode: String?` (39 symbols, no separators) |

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
| `SendState` | `SendState` | `pending`, `sent`, `delivered`, `read`, `failed(reason:cause: SendFailure)` |
| `SendFailure` | `SendFailure` | `userSuspended`, `userNotAdmitted`, `notAdmittedByPeer`, `rejected`, `other` |
| `ReportReason` | `ReportReason` | `spam`, `harassment`, `inappropriate`, `scam`, `other` (mirror → core only) |
| `ConnectionState` | `ConnectionState` | `offline`, `connecting`, `connected`, `syncing` |
| `ChatListDiff` | `ChatListDiff` | `append(values:)`, `clear`, `pushFront(value:)`, `pushBack(value:)`, `popFront`, `popBack`, `insert(index:value:)`, `set(index:value:)`, `remove(index:)`, `truncate(length:)`, `reset(values:)` |
| `TimelineDiff` | `TimelineDiff` | same cases as `ChatListDiff`, with `TimelineItem` values |
| `GimError` | `GimError` | `Network(reason:)`, `NotRegistered`, `InvalidInput(reason:)`, `NotFound(reason:)`, `Crypto(reason:)`, `Storage(reason:)`, `Server(status: UInt16, reason:)`, `RetryLater(status: UInt16, retryAfterSecs: UInt64, reason:)`, `Cancelled`, `NotImplemented`, `Internal(reason:)`, `ChatNotActive(chatId:state: ChatState)`, `HubNotVerified(reason:)`, `HubOwnsGroups(hubId:groupCount: UInt32)`, `LastHub(hubId:)`, `HomeHub(hubId:)`, `HubNotDrained(hubId:reason:)`, `UserSuspended(hubId:)`, `UserNotAdmitted(hubId:)`, `NotAdmittedByPeer(hubId:chatId:)`, `ContactNotAdmitted(userIds: [String])` |

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
| `protocol RecoveryKitFunctions` | free functions `formatRecoveryKit(userId:recoveryCode:labels:)`, `parseRecoveryKit(text:)`, `recoveryKeyEnding(recoveryCode:)`, `matchesRecoveryKeyEnding(recoveryCode:typed:)` | Intentional: same names and labels as methods of a protocol, so Linux tests and previews can swap the implementation. See "Recovery kit". |
| `mutedForever() -> UInt64` | `mutedForever() -> UInt64` | Same name and value (`UInt64.max`, gim-sdk `MUTED_FOREVER`); `CoreMappingTests.testMutedForeverMatchesGimCore` checks it. |
| — | `coreVersion()`, `ciphersuiteName()` | Not mirrored; nothing uses them yet. |
| — | `LocalTimeZoneImpl` | Generated wrapper for a Rust-implemented zone; gim-core never hands one to the app. |
| — | `*Impl` classes, `NoHandle`, `uniffi*` | Generated plumbing, not mirrored. |

## GimClient methods

Every method of `GimClientProtocol` at `c1b7503`, with identical labels, argument types and `async`/`throws`. The
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
| `ownProfile() async throws -> UserProfile?` | same |
| `setAvatar(filePath:mime:) async throws` | same |
| `removeAvatar() async throws` | same |
| `fetchUserAvatar(userId:destPath:) async throws -> String` | same; `NotFound` without a photo |
| `fetchChatAvatar(chatId:destPath:) async throws -> String` | same; `NotFound` without an avatar |
| `privacy() async throws -> PrivacySettings` | same |
| `setReadReceipts(enabled:) async throws` | same |
| `setTypingIndicators(enabled:) async throws` | same |
| `blockUser(userId:) async throws` | same; `InvalidInput` for the signed-in user |
| `unblockUser(userId:) async throws` | same |
| `setChatMuted(chatId:mutedUntilMs: UInt64) async throws` | same; `mutedForever()` for good, 0 to unmute |
| `setChatPinned(chatId:pinned:) async throws` | same |
| `setChatArchived(chatId:archived:) async throws` | same |
| `reportUser(userId:reason: ReportReason, note: String?, messageIds: [String]) async throws -> String` | same; **needs the meta server** (`InvalidInput` without `ClientConfig.metaServerUrl`): keep it hidden in the UI until gim-meta is deployed |
| `rotateRecoveryCode() async throws -> RecoveryRotation` | same |
| `deleteAccount() async throws -> [String]` | same; returns the other hubs it could not reach. Deletes the meta server's data first when one is configured, so it works without one |

The meta server (gim-meta, `ClientConfig.metaServerUrl`) is not deployed: the app passes `nil`. Without it
`reportUser` fails with `InvalidInput` and the privacy settings (blocked users included) are not backed up, so they
do not survive the loss of every device; per-chat settings are never backed up. `FakeGimClient.reportUser` needs no
meta server and records the report in `reports`. The bridge maps `ClientConfig.metaServerUrl` 1:1.

`chatMembers` has no listener in M1. `GroupInfoViewModel` queries it again when a `ChatListDiff` changes that chat or
a `TimelineItem.membershipChange` arrives. When a query fails before any list has loaded it shows the error with
`ChatSummary.memberCount` (no member list, no removal); a list that loaded before stays on later failures.
Renaming a group goes `GroupInfoViewModel.saveName()` → `GimClientAPI.setGroupInfo(name:)` →
`RealGimClient` → `GIMCore.GimClient.setGroupInfo`.

## Recovery kit

`RecoveryKitFunctions` (GIMClientKit) has two implementations:

- `FakeRecoveryKitFunctions` (GIMClientKit, `Fake/`): a pure-Swift copy of gim-client-sdk
  `crates/gim-sdk/src/recovery_kit.rs` for Linux tests and previews. GIMClientKit cannot import GIMFeatures, so it
  keeps its own copy. Like the Rust code it counts Unicode scalars, not grapheme clusters.
- `CoreRecoveryKitFunctions` (GIMPlatform, `Bridge/CoreRecoveryKit.swift`): calls the generated free functions and
  maps `RecoveryKitLabels` / `ParsedRecoveryKit` in `CoreMapping`.

`CoreMappingTests.testFakeRecoveryKitFunctionsMatchGimCore` runs the same vectors through both, so drift between the
copy and gim-core fails the macOS tests.

## Changes since `16a5efa`

`b86283e` (gim-client-sdk main, vendored with `GIM_CORE_REPO=gimhq/gim-client-sdk scripts/sync-gim-core.sh
40038617133`; the artifact's `Package.swift` is unchanged). Breaking rename: the server for settings backups and
reports is now the gim meta server (gim-meta), and `ClientConfig`'s URL field is `metaServerUrl: String? = nil`; the
mirror has used that name from the start and `CoreMapping` now passes it through. Otherwise only doc comments ("meta
server") and the UniFFI checksums of `reportUser` and `deleteAccount` changed; no signature, enum case or error
changed.

## Changes since `c1b7503`

`16a5efa` (gim-client-sdk, vendored with `scripts/sync-gim-core.sh 40023818869`; the vendored `Package.swift` adds
macOS 15 and links SystemConfiguration, CoreFoundation, c++ and resolv). Diff of the generated `GIMCore.swift`, not
yet mirrored: `ClientConfig` gained the optional meta server URL (renamed in `b86283e`, see above); `UserProfile` gained
`hasAvatar`; `ChatSummary` gained `peer`, `mutedUntilMs`, `pinned`, `archived` and `blocked`; `MessagePreview` gained
`sendState`; new records `PrivacySettings`, `RecoveryRotation`, `RecoveryKitLabels`, `ParsedRecoveryKit`, a new enum
`ReportReason`; new `GimClient` methods `blockUser`, `unblockUser`, `privacy`, `setReadReceipts`,
`setTypingIndicators`, `setChatMuted`, `setChatPinned`, `setChatArchived`, `reportUser`, `rotateRecoveryCode`,
`deleteAccount`, `ownProfile`, `setAvatar`, `removeAvatar`, `fetchUserAvatar`, `fetchChatAvatar`; new functions
`mutedForever`, `formatRecoveryKit`, `parseRecoveryKit`, `recoveryKeyEnding`, `matchesRecoveryKeyEnding`. No enum
case and no callback interface changed. All of it is now mirrored, with the field renamed `metaServerUrl` in the
mirror (see "GimClient methods"). `FakeGimClient` implements the new methods in memory (see its doc comment):
blocking drops the blocked user's messages and typing, refuses chats with them and marks their direct chat; sends to
a blocked chat are allowed (gim-core specifies no error); read receipts off stops own messages at `delivered`;
typing indicators off hides peer typing; pinned chats come first; `rotateRecoveryCode` replaces the code
`restoreFromRecovery` accepts; `deleteAccount` wipes like `signOut`, forgets the account and returns `[]`.

## Changes since `fa6f7e9`

`c1b7503` (gim-core C-policy, hub H12 user allow/deny policy; built on the macOS host from gim-core `c1b7503` like
`f8db42c` below, vendored with `scripts/sync-gim-core.sh --from-dir`). Diff of the generated `GIMCore.swift`: three
`GimError` cases appended last, `UserNotAdmitted(hubId:)` (index 19), `NotAdmittedByPeer(hubId:chatId:)` (20) and
`ContactNotAdmitted(userIds:)` (21); a new enum `SendFailure`; and, breaking, `SendState.failed(reason:)` became
`failed(reason:cause:)`. No function changed. Behaviour (gim-core `docs/API.md`, "User policy"): `UserNotAdmitted` is
handled like `UserSuspended`, and a refused registration (`createIdentity`, `restoreFromRecovery`, `waitLink`) or
`addHub` keeps nothing; `NotAdmittedByPeer` refuses member changes and leaves of one chat (its messages fail with
cause `notAdmittedByPeer`); `ContactNotAdmitted` only when no invitee could be added, refused invitees among others are
skipped and reported as `MembershipChanged(Removed)`. Retry is hidden for the causes `userSuspended`,
`userNotAdmitted` and `notAdmittedByPeer`.

App adaptations:

- Mirror and `CoreMapping`: the three errors both ways, `SendFailure` and `SendState.failed(reason:cause:)` from
  gim-core. `MessageStatus.failed(reason:cause:)` carries the cause to the timeline cells.
- The typed cause replaces the reason prefix match of `fa6f7e9` (`ErrorPresenter.suspendedHubId(failureReason:)` is
  gone): `MessageActionsViewModel.canRetry` offers Retry only for `rejected` and `other`; for the other causes tapping
  the status shows `ErrorPresenter.sendFailureMessage(_:)` instead of resending (`TimelineViewModel.retry`), and the
  status's accessibility hint says so. Delete stays available.
- `ErrorPresenter`: `UserNotAdmitted` → "Your account is not admitted on this hub." (`message(for:client:)` names the
  host like for a suspension); onboarding and Add Hub show "This hub does not admit your account."
  (`registrationMessage(for:)`, `hubRefusedMessage`), without retrying. `NotAdmittedByPeer` → "This chat's hub does not
  accept messages from you." `ContactNotAdmitted` → "<names> does/do not accept contacts from you."
  (`contactNotAdmittedMessage(userIds:profiles:)`; New Chat, New Group and Group Info pass the profiles they know,
  falling back to the handle, then the user id). A partial result of `createGroupChat` / `addMembers` is a success.
  Nothing signs out or wipes on these errors; `AppModel` stays signed in.
- `FakeGimClient`: `simulateNotAdmitted(hubId:)` (registration, `addHub` of that hub, then calls and sends like a
  suspension), `simulateNotAdmittedByPeer(chatId:hubId:)` (sends fail with cause `notAdmittedByPeer`; `addMembers`,
  `removeMember` and `leaveChat` throw), `refuseContacts(_:)` (`createDirectChat` throws; `createGroupChat` /
  `addMembers` skip the refused users and throw only if nobody could be added). Every fake failure carries its cause
  (`simulateSuspension` → `userSuspended`, `rejectNextSend` → `rejected`, `failNextSends` → `other`).

## Changes since `9c6022c`

`fa6f7e9` (built on the macOS host from gim-core `fa6f7e9` like `f8db42c` below, vendored with
`scripts/sync-gim-core.sh --from-dir`). Diff of the generated `GIMCore.swift`: one `GimError` case appended last,
`UserSuspended(hubId:)` (index 18; an admin of the hub suspended the user, the hub refused the sign-in with 403
`user_suspended`), and the UniFFI checksums; nothing else changed. Behaviour (gim-core `docs/API.md`, "Suspended
users"): every call that may sign in can throw it; the session and local data are kept; gim-core does not sign in on
that hub again for 10 minutes; a failed send keeps the error's text as its reason (`user suspended on hub <hub id>`);
`ConnectionState` has no extra value and there is no callback.

App adaptations:

- Mirror and `CoreMapping`: `GimError.UserSuspended(hubId:)` both ways.
- `ErrorPresenter` shows "Your account is suspended." plus that the chats on this device stay readable;
  `message(for:client:)` (used by the signed-in view models) names the hub by its URL host ("… suspended on
  <host>.") when more than one hub is listed and `hubId` matches one. Not retryable: a failed send whose reason is a
  suspension (`ErrorPresenter.suspendedHubId(failureReason:)`) offers no Retry (`MessageActionsViewModel.canRetry`,
  the timeline's default menu); tapping its status explains the suspension instead of resending
  (`TimelineViewModel.retry`). Nothing signs out, wipes or retries on it; `AppModel` stays signed in.
- `FakeGimClient.simulateSuspension(hubId:)`: calls that need a session throw `UserSuspended`; own sends end
  `failed` with the suspension reason; `startSync`, `session()` and `hubs()` keep working.

## Changes since `225b809`

`9c6022c` (built on the macOS host from gim-core `9c6022c` like `f8db42c` below, vendored with
`scripts/sync-gim-core.sh --from-dir`). Diff of the generated `GIMCore.swift`: the `signOut` doc comment and its
UniFFI checksum; no signature changed, no mirror change. Behaviour only (gim-core `docs/API.md`, "Sign-out"):
`signOut` throws `InvalidInput` in `extension` mode and deletes nothing; the app's `signOut` deletes the store under the
store lock, after which every client opened before it fails its changes of the local state with
`Storage("the local store was deleted by sign-out")`, and a new extension client fails with `InvalidInput` (no
database key). `PushNotificationHandler` shows the generic content for both. `FakeGimClient` mirrors this per data
directory: `signOut` throws `InvalidInput` in `extension` mode, and `processPush` of a client created before a
sign-out of its directory throws that `Storage` error.

## Changes since `f8db42c`

`225b809` (built on the macOS host from gim-core `225b809` like `f8db42c` below, vendored with
`scripts/sync-gim-core.sh --from-dir`). The generated bindings are identical (`GIMCore.swift` byte-identical, no
mirror change). Behaviour only (gim-core `docs/API.md`, "Push"): `processPush` joins a chat this device was invited to
for a chat invitation, a member change that added this device, a message in a chat not joined yet and a wake-up, and
then describes it as `invite` (`chatTitle` = the group name, `senderUserId` = the inviter, `senderDisplayName` = the
inviter's name, or handle until their profile is known); a push whose item shows nothing catches the chat up and shows
the newest unread message from someone else, else the invitation, else nothing (`shouldDisplay = false`, also for an
alert-priority push). `Generic` (`New message`) is left for a push that cannot be decrypted or processed in time.

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
- The Notification Service Extension creates its clients with `mode: .extension` on the App Group's data directory
  (`PushNotificationHandler` in GIMFeatures, `NotificationService` in `GIM/NotificationService`) and passes the
  `gim` entry of the push's `userInfo` (the hub's payload as gim-push-mock relays it) to `processPush` as JSON text.
  The app registers `PushRegistration(provider: "mock-ios-sim", token: "sim-<uuid>", appId: <bundle id>)` in Debug
  builds (`PushRegistrar`). The bridge and the platform hooks moved to the `GIMPlatform` target of `Packages/GIMUI`,
  which the extension links without SwiftUI.

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
- `Packages/GIMUI/Sources/GIMPlatform/Bridge` maps `GIMCore` to the mirror: `RealGimClientFactory` calls
  `GIMCore.createClient`, `RealGimClient` implements `GimClientAPI` by converting every value 1:1 (`CoreMapping`),
  rethrowing errors as the mirror's `GimError`, and `CoreListeners` adapts the callback interfaces and delivers
  them on the main queue.
- `RealGimClientFactory` is the default client (`AppModel.defaultFactory()`); release builds always use it.
- In debug builds the launch argument `-GIMUseFakeCore YES` makes `AppModel.defaultFactory()` return
  `CoreGimClientFactory` (`FakeGimClient`), the demo mode. The fake also drives previews and tests.
