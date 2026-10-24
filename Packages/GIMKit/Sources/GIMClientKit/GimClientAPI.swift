import Foundation

// Native mirror of gim-core's UniFFI `GimClient` object, `Timeline`, `LinkSession`, `PendingApproval`, `TaskHandle`,
// callback interfaces, platform hooks and `createClient` (`bindings/gim-ffi/src/`). Method names and argument labels match the generated
// `GIMCore.swift`; see docs/gim-core-mapping.md for the symbol table and the intentional differences.
//
// Callbacks may arrive on any thread (gim-core calls every listener, `LocalTimeZone` and `PlatformHooks` method on its
// single `gim-callbacks` thread, one call at a time). Copy the data and return: hop to the main actor (or a private
// queue) for anything else, keep their order, never call back into the client or block from inside a callback
// (gim-core docs/API.md, "Threading of platform callbacks").

/// Receives chat list changes, most recently updated chat first. The first callback is a `reset`.
public protocol ChatListListener: AnyObject, Sendable {
    func onUpdate(diffs: [ChatListDiff])
}

/// Receives timeline changes, oldest item first. The first callback is a `reset` with the loaded items.
public protocol TimelineListener: AnyObject, Sendable {
    func onUpdate(diffs: [TimelineDiff])
}

/// Receives connection state changes. The first callback carries the current state.
public protocol ConnectionStateListener: AnyObject, Sendable {
    func onChange(state: ConnectionState)
}

/// Receives the ids of the users currently typing in one chat (never the signed-in user). The first callback
/// carries the current set, possibly empty.
public protocol TypingListener: AnyObject, Sendable {
    func onUpdate(userIds: [String])
}

/// Receives the user's hubs (see `GimClientAPI.hubs()`) whenever they may have changed: added, removed, verified,
/// reprioritized, or a URL shared by another own device. The first callback carries the current list.
public protocol HubListListener: AnyObject, Sendable {
    func onUpdate(hubs: [HubInfo])
}

/// The local time zone timeline date separators split calendar days in, set with
/// `GimClientAPI.setLocalTimeZone(zone:)`. Called from any thread (gim-core: its callback thread); do not call back
/// into the client from it.
public protocol LocalTimeZone: AnyObject, Sendable {
    /// The offset from UTC in seconds in effect at `atMs` (milliseconds since the epoch), DST included.
    func utcOffsetSecs(atMs: Int64) -> Int32
}

/// Services the app provides to gim-core, passed to `createClient`. Methods may be called from any thread (gim-core:
/// its callback thread); do not call back into the client from them.
public protocol PlatformHooks: AnyObject, Sendable {
    /// Reads a secret from the platform keystore; `nil` when the key does not exist. Throws when the keystore can't
    /// be read (e.g. locked before first unlock), so gim-core fails the call instead of treating the secret as absent.
    func secureStoreGet(key: String) throws -> Data?
    /// Writes a secret to the platform keystore, replacing any existing value.
    func secureStoreSet(key: String, value: Data) throws
    /// Deletes a secret; a missing key is not an error.
    func secureStoreDelete(key: String)
    /// Absolute path of an app-private directory, stable across launches.
    func dataDir() -> String
    /// Current network reachability. Changes are pushed with `GimClientAPI.setNetworkReachable(reachable:)`.
    func isNetworkReachable() -> Bool
}

/// Keeps a listener subscription alive. Releasing the last reference or calling `cancel()` ends the subscription;
/// no callback is delivered after `cancel()` returns. Calling `cancel()` twice is harmless.
public final class TaskHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var onCancel: (@Sendable () -> Void)?

    /// - Parameter onCancel: stops the subscription; runs once, on `cancel()` or when the handle is released.
    public init(onCancel: @escaping @Sendable () -> Void) {
        self.onCancel = onCancel
    }

    deinit {
        cancel()
    }

    public func cancel() {
        let action = lock.withLock {
            defer { onCancel = nil }
            return onCancel
        }
        action?()
    }

    /// Whether the subscription has ended.
    public func isFinished() -> Bool {
        lock.withLock { onCancel == nil }
    }
}

/// The message timeline of one chat.
public protocol Timeline: AnyObject, Sendable {
    func chatId() -> String
    /// Subscribes to timeline changes. The first callback is a `reset` with the currently loaded items.
    func addListener(listener: any TimelineListener) async -> TaskHandle
    /// Loads up to `count` older items (delivered through the listeners). Returns whether more history exists.
    func paginateBackwards(count: UInt16) async throws -> Bool
    /// The chat's current state, from local state; `nil` while the chat is not known locally. Synchronous.
    func chatState() -> ChatState?
}

/// A link offer of a new device: show `qrString()` as a QR code, then pass it to `GimClientAPI.waitLink(link:)`.
/// Accepts a single bundle: after a `waitLink` failure before the bundle arrived, wait again with the same session;
/// once a bundle arrived it is used up (`waitLink` fails with `InvalidInput`), start a new one.
public protocol LinkSession: AnyObject, Sendable {
    /// The string to encode in the QR code the old device scans.
    func qrString() -> String
}

/// A link approved on the old device: show `sas()`, then pass it to `GimClientAPI.confirmApproval(approval:accepted:)`.
public protocol PendingApproval: AnyObject, Sendable {
    /// The new device.
    func deviceId() -> String
    /// Six-digit short authentication string, `"123 456"`.
    func sas() -> String
}

/// One account on one device. Mirrors `GIMCore.GimClientProtocol`.
public protocol GimClientAPI: AnyObject, Sendable {
    /// The persisted session, or `nil` before an identity exists on this device (`createIdentity`,
    /// `restoreFromRecovery` or a device link).
    func session() async throws -> Session?
    /// The signed-in user's id; `nil` without a session. Synchronous.
    func userId() -> String?
    /// Whether opening this client discarded an existing local database (undecryptable or incompatible). The session
    /// is gone with it: show onboarding and tell the user that local history was lost. Synchronous.
    func localStateReset() -> Bool
    /// Stops sync and the listeners and deletes the session, local data and keystore secrets. Returns only after every
    /// callback in flight returned (gim-core waits at most 5 s for one); no callback runs once it returned. Create a
    /// new client afterwards.
    func signOut() async throws

    // Identity and devices (gim-core docs/API.md, "Identity and devices").

    /// Creates a new identity with this device as its first one and signs in. Returns the recovery code, which is
    /// stored nowhere and must be shown to the user once. `InvalidInput` with a session. A failure keeps nothing of
    /// the attempt: call it again, which creates a new user.
    func createIdentity(displayName: String) async throws -> String
    /// Restores the user on this fresh device from its recovery code: `InvalidInput` for a malformed code, `Crypto`
    /// for a wrong one, `NotFound` if the hub has no DeviceList of the user, `RetryLater` while the hub throttles.
    /// `revokeOthers` revokes every previously listed device. Chats are not rejoined automatically. A failure keeps
    /// nothing of the attempt: call it again with the same arguments.
    func restoreFromRecovery(userId: String, recoveryCode: String, revokeOthers: Bool) async throws
    /// New device: starts a link; show `LinkSession.qrString()` and call `waitLink`. `hubs` are the hub URLs the old
    /// device may post the bundle to. Synchronous.
    func startLink(hubs: [String]) throws -> any LinkSession
    /// New device: waits (up to 10 minutes) for the old device to approve the link, then signs in as a new device of
    /// that user. Returns the SAS to compare with the old device's; finish with `confirmLink`. A failure keeps nothing
    /// of the attempt: if no bundle arrived, call it again with the same `link`; otherwise `link` is used up.
    func waitLink(link: any LinkSession) async throws -> String
    /// New device: the user compared the SAS. `false` wipes the device like `signOut()`; create a new client
    /// afterwards.
    func confirmLink(accepted: Bool) async throws
    /// Old device: approves the link offer scanned from the new device's QR code and returns the pending approval
    /// carrying the SAS.
    func approveLink(qrString: String) async throws -> any PendingApproval
    /// Old device: the user compared the SAS. `true` adds the new device to every joined chat (the new device must
    /// have finished `waitLink`); `false` revokes it.
    func confirmApproval(approval: any PendingApproval, accepted: Bool) async throws
    /// The signed-in user's devices, including revoked ones.
    func devices() async throws -> [DeviceInfo]
    /// Another user's devices; empty for an unknown user.
    func userDevices(userId: String) async throws -> [DeviceInfo]
    /// Revokes another device of the signed-in user and removes it from every chat. `InvalidInput` for the current
    /// device.
    func revokeDevice(deviceId: String) async throws
    /// Synced to the user's other devices and announced to every joined chat. `InvalidInput` if empty.
    func setDisplayName(name: String) async throws
    /// Claims `handle` in the hub directory so others find the user with `findUser`; `Server(409)` if it is taken.
    func claimHandle(handle: String) async throws
    /// Releases the handle claimed with `claimHandle`; `InvalidInput` if there is none.
    func releaseHandle() async throws

    /// `InvalidInput` in `ClientMode.extension`.
    func startSync() async throws
    func stopSync() async throws
    /// Synchronous and never throws.
    func setNetworkReachable(reachable: Bool)

    /// `nil` if no such user exists.
    func findUser(handle: String) async throws -> UserProfile?
    /// Returns the existing direct chat with `userId` if there is one.
    func createDirectChat(userId: String) async throws -> String
    func createGroupChat(name: String, memberUserIds: [String]) async throws -> String
    /// Current members, one entry per user, including the signed-in user. There is no members listener: re-query
    /// when a `ChatListDiff` touches the chat or a `TimelineItem.membershipChange` arrives.
    func chatMembers(chatId: String) async throws -> [UserProfile]
    func addMembers(chatId: String, userIds: [String]) async throws
    func removeMember(chatId: String, userId: String) async throws
    /// Starts leaving the chat; returns once the hub accepted the request, with the chat `ChatState.leaving`. Calling
    /// it again while leaving re-sends the request. A leave the hub refuses for good returns the chat to `active` and
    /// throws the rejection; `ChatNotActive(left)` once left.
    func leaveChat(chatId: String) async throws
    /// Where this device stands in the chat, from local state (no network call, so it is available right after a
    /// restart). `NotFound` for an unknown chat.
    func chatState(chatId: String) async throws -> ChatState
    /// `nil` leaves a field unchanged.
    func setGroupInfo(chatId: String, name: String?, avatarFilePath: String?) async throws

    // Sends and changes to a `leaving` or `left` chat (`sendText` … `retrySend`, `setGroupInfo`, `addMembers`,
    // `removeMember`) throw `ChatNotActive(chatId:state:)`.

    /// Returns the message id; the message appears in the timeline immediately as `SendState.pending`.
    func sendText(chatId: String, body: String, replyTo: String?) async throws -> String
    /// The file is copied before the call returns.
    func sendMedia(
        chatId: String, filePath: String, mime: String, caption: String?, replyTo: String?
    ) async throws -> String
    func editMessage(chatId: String, messageId: String, newBody: String) async throws
    func deleteMessage(chatId: String, messageId: String) async throws
    func react(chatId: String, messageId: String, emoji: String) async throws
    func unreact(chatId: String, messageId: String, emoji: String) async throws
    /// For messages in `SendState.failed`.
    func retrySend(chatId: String, messageId: String) async throws
    /// Removes an unsent message from the outbox and the timeline.
    func cancelSend(chatId: String, messageId: String) async throws
    /// Marks everything up to and including `upToMessageId` as read and sends a read receipt.
    func markRead(chatId: String, upToMessageId: String) async throws
    func setTyping(chatId: String, active: Bool) async throws
    /// Tells the chat the user stopped typing; same as `setTyping(chatId:active: false)`. Does nothing unless typing
    /// was reported.
    func stopTyping(chatId: String) async throws

    /// Downloads and decrypts the attachment to `destPath`; returns the path of the decrypted file.
    func fetchMedia(chatId: String, messageId: String, destPath: String) async throws -> String
    /// Like `fetchMedia` for the thumbnail; `nil` if the media has none.
    func fetchThumbnail(chatId: String, messageId: String, destPath: String) async throws -> String?

    func chatList(listener: any ChatListListener) async throws -> TaskHandle
    func timeline(chatId: String) async throws -> any Timeline
    /// Sets the time zone date separators split calendar days in; `nil` (the default) is UTC. Call it again when the
    /// system time zone changes: open timelines move their date separators through their listeners. Synchronous and
    /// never throws.
    func setLocalTimeZone(zone: (any LocalTimeZone)?)
    func connectionState(listener: any ConnectionStateListener) async throws -> TaskHandle
    func typing(chatId: String, listener: any TypingListener) async throws -> TaskHandle

    // Hub management (gim-core docs/API.md, "Hub management").

    /// The hubs of the user's hosting record known to this device, primary first (by priority, then hub id),
    /// including removed ones. With a single hub: the home hub.
    func hubs() async throws -> [HubInfo]
    /// Adds the hub at `url` (entered by the user) to the hosting record: checks that it is a gim hub, signs in there,
    /// lists it last (least preferred), uploads this device's KeyPackages there, follows its events and shares its URL
    /// with the own other devices. Adding a listed hub again only records `url` for it on this device. Returns the
    /// hub. `InvalidInput` for a URL that is not `http(s)://host…` or does not serve a gim hub, `Network` if it cannot
    /// be reached.
    func addHub(url: String) async throws -> HubInfo
    /// Removes a hub from the hosting record. `HomeHub` for the hub this client was created for, `LastHub` for the
    /// only listed hub, `HubOwnsGroups` (with the number of chats) unless `confirmOwnedGroups` if the hub owns chats
    /// of this user, `HubNotDrained` while something sent through it is not settled; `InvalidInput` for a hub that
    /// is not listed.
    func removeHub(hubId: String, confirmOwnedGroups: Bool) async throws
    /// Makes a listed hub the primary hub (priority 0, the others follow in their order). Every hub whose priority
    /// changes must be reachable from this device (`HubInfo.signedIn`), else `InvalidInput`. Nothing happens for the
    /// current primary.
    func setPrimaryHub(hubId: String) async throws
    /// Subscribes to the user's hubs; the first callback carries the current list.
    func hubList(listener: any HubListListener) async throws -> TaskHandle

    // Push (gim-core docs/API.md, "Push").

    /// Stores the registration on the device and sends it to every verified hub (gim-core sends it again by itself
    /// when hubs change, after sign-in, restore or link). Call it whenever the platform hands out a new token.
    /// `InvalidInput` for a malformed field, `Server(400)` if a hub rejects it. Does nothing in `ClientMode.extension`.
    func registerPush(registration: PushRegistration) async throws
    /// Removes the registration from every hub, then the local copy (removed even if a hub failed; the first hub
    /// failure is thrown). Does nothing in `ClientMode.extension`.
    func unregisterPush() async throws
    /// For the notification extension: processes the push data payload exactly as delivered and returns what to show,
    /// within about 15 s. Content that cannot be processed comes back `generic` (`New message`, displayed).
    /// `InvalidInput` only if `payload` is not a JSON object.
    func processPush(payload: String) async throws -> NotificationContent

    // Profile photo (gim-core docs/API.md, "GimClient").

    /// The signed-in user's own profile; `nil` before it is stored.
    func ownProfile() async throws -> UserProfile?
    /// Sets the signed-in user's profile photo from an image file (crop and scale it first: every chat member
    /// downloads it); synced and announced like `setDisplayName`.
    func setAvatar(filePath: String, mime: String) async throws
    /// Removes the signed-in user's profile photo.
    func removeAvatar() async throws
    /// Downloads and decrypts the profile photo of `userId` (the own user included) to `destPath` and returns the
    /// path; `NotFound` if they have none (`UserProfile.hasAvatar`).
    func fetchUserAvatar(userId: String, destPath: String) async throws -> String
    /// Downloads and decrypts the avatar of a group chat to `destPath` and returns the path; `NotFound` if it has
    /// none.
    func fetchChatAvatar(chatId: String, destPath: String) async throws -> String

    // Privacy and chat settings (gim-core docs/API.md, "Privacy and chat settings"): stored on the user's devices
    // and synced to the own other devices; hubs never see them.

    /// The privacy settings.
    func privacy() async throws -> PrivacySettings
    /// Turns sending (and showing) read receipts on or off.
    func setReadReceipts(enabled: Bool) async throws
    /// Turns sending (and showing) typing indicators on or off.
    func setTypingIndicators(enabled: Bool) async throws
    /// Blocks a user: their messages and invites are dropped and no chat can be created with them or add them
    /// (`InvalidInput`). Existing chats stay; a direct chat shows `blocked`. `InvalidInput` for the signed-in user.
    func blockUser(userId: String) async throws
    /// Lets new messages of the user through; the dropped ones do not come back.
    func unblockUser(userId: String) async throws
    /// Mutes a chat's notifications until `mutedUntilMs` (Unix milliseconds; `mutedForever()` for good, 0 to unmute).
    /// `NotFound` for an unknown chat.
    func setChatMuted(chatId: String, mutedUntilMs: UInt64) async throws
    /// Pinned chats come first in the chat list. `NotFound` for an unknown chat.
    func setChatPinned(chatId: String, pinned: Bool) async throws
    /// Only sets `ChatSummary.archived`: show archived chats apart. A new message does not unarchive a chat.
    /// `NotFound` for an unknown chat.
    func setChatArchived(chatId: String, archived: Bool) async throws

    // Meta server (gim-core docs/API.md, "Meta server"): gim-meta, not deployed yet.

    /// Reports a user to the meta server's moderators with the messages `messageIds` (at most 50, from the local
    /// history) in plaintext, and an optional `note` (at most 1000 characters). Returns the report id. Does not block:
    /// call `blockUser` too if wanted. `InvalidInput` without a meta server (`ClientConfig.metaServerUrl`).
    func reportUser(userId: String, reason: ReportReason, note: String?, messageIds: [String]) async throws -> String

    // Recovery and account deletion (gim-core docs/API.md, "Identity and devices", "Account deletion").

    /// Replaces the recovery code with a new one, for a user who lost it: the previous code stops working on every
    /// hub that takes the new backup (the home hub always does, or the call fails without any change). Returns the
    /// new code, which is not stored and must be shown to the user once.
    func rotateRecoveryCode() async throws -> RecoveryRotation
    /// Deletes the account for good: the meta server's data, every chat (the user leaves), the account on every hub,
    /// then everything on this device as `signOut` does. Returns the ids of the user's other hubs that could not be
    /// reached (their records expire on their own). On an error nothing local is deleted and it can be called again.
    /// Irreversible: confirm with the user first.
    func deleteAccount() async throws -> [String]
}

/// Creates the client. Opens (or creates) local state under `hooks.dataDir()`; does not touch the network.
///
/// Until the gim-core bindings land this returns a demo `FakeGimClient` without a session that seeds the demo chats
/// when `createIdentity` is called.
public func createClient(config: ClientConfig, hooks: any PlatformHooks) async throws -> any GimClientAPI {
    try validateServerUrl(config.serverUrl)
    return FakeGimClient.demo(
        dataDirectory: hooks.dataDir(), registered: false, networkReachable: hooks.isNetworkReachable(),
        homeHubUrl: config.serverUrl, mode: config.mode)
}

/// `ChatSummary.mutedUntilMs` of a chat muted until it is unmuted (`setChatMuted`).
public func mutedForever() -> UInt64 {
    UInt64.max
}

/// Same rules as gim-core: an `http` or `https` URL with a host. `what` prefixes the `InvalidInput` reason.
func validateServerUrl(_ value: String, what: String = "server_url") throws {
    guard let components = URLComponents(string: value), let scheme = components.scheme else {
        throw GimError.InvalidInput(reason: "\(what): relative URL without a base")
    }
    guard ["http", "https"].contains(scheme.lowercased()) else {
        throw GimError.InvalidInput(reason: "\(what): unsupported scheme '\(scheme)'")
    }
    guard let host = components.host, !host.isEmpty else {
        throw GimError.InvalidInput(reason: "\(what): missing host")
    }
}

/// gim-core's recovery-kit free functions (`formatRecoveryKit`, `parseRecoveryKit`, `recoveryKeyEnding`,
/// `matchesRecoveryKeyEnding`), behind a protocol so Linux tests and previews can use a pure-Swift copy.
public protocol RecoveryKitFunctions: Sendable {
    /// The kit text: title, `"<accountId>: <user id>"`, `"<recoveryKey>: <code grouped by four>"`, a blank line and
    /// the note.
    func formatRecoveryKit(userId: String, recoveryCode: String, labels: RecoveryKitLabels) -> String
    /// Finds the user id and the recovery code in pasted text, whatever the labels' language.
    func parseRecoveryKit(text: String) -> ParsedRecoveryKit
    /// The last four symbols of the recovery code.
    func recoveryKeyEnding(recoveryCode: String) -> String
    /// `typed` is the code's last four symbols (case, `-` and spaces ignored).
    func matchesRecoveryKeyEnding(recoveryCode: String, typed: String) -> Bool
}

/// App-level factory, the single swap point between `createClient` and test or preview clients.
public protocol GimClientFactory: Sendable {
    func make(config: ClientConfig, hooks: any PlatformHooks) async throws -> any GimClientAPI
}

/// Creates clients with `createClient(config:hooks:)`.
public struct CoreGimClientFactory: GimClientFactory {
    public init() {}

    public func make(config: ClientConfig, hooks: any PlatformHooks) async throws -> any GimClientAPI {
        try await createClient(config: config, hooks: hooks)
    }
}
