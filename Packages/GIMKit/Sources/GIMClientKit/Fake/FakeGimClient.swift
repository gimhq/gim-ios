import Foundation
import Synchronization

/// In-memory `GimClientAPI` for previews, demo mode and tests.
///
/// Emits the same diff semantics as gim-core (eyeball-im `VectorDiff`): the chat list is ordered by `updatedAtMs`
/// descending, ties by chat id; each timeline is ordered oldest first, exposes a window of the newest items that
/// `paginateBackwards` grows at the front, and has a `dateSeparator` before the first item of each local calendar
/// day (in the zone set with `setLocalTimeZone`, UTC until then). Sync only runs between `startSync()` and `stopSync()`; own messages wait in the outbox until
/// the client is connected. Delayed behaviour (connecting, send state progression, peer typing and replies) runs
/// through `FakeScheduler`.
///
/// Identity: `createIdentity` returns a deterministic recovery code that `restoreFromRecovery` accepts after
/// `signOut`; the device link runs on one client per side (`startLink`/`waitLink`/`confirmLink` signs in as the demo
/// user, `approveLink`/`confirmApproval` adds a device) with the fixed SAS `fakeSas`.
public actor FakeGimClient: GimClientAPI {
    struct Reaction: Sendable {
        var emoji: String
        var users: [String]
    }

    struct StoredMessage: Sendable {
        var item: MessageItem
        var reactions: [Reaction] = []
    }

    enum Entry: Sendable {
        case message(StoredMessage)
        case membership(userName: String, change: MembershipChangeKind, atMs: UInt64)

        var atMs: UInt64 {
            switch self {
            case .message(let stored): stored.item.sentAtMs
            case .membership(_, _, let atMs): atMs
            }
        }

        var message: StoredMessage? {
            if case .message(let stored) = self { stored } else { nil }
        }

        var timelineItem: TimelineItem {
            switch self {
            case .message(let stored): .message(item: stored.item)
            case .membership(let userName, let change, let atMs):
                .membershipChange(userName: userName, change: change, atMs: atMs)
            }
        }
    }

    struct StoredChat: Sendable {
        var id: String
        var kind: ChatKind
        var name: String
        var createdAtMs: UInt64
        var members: [String]
        var avatar: MediaRef?
        var entries: [Entry] = []
        /// Number of newest entries the timeline exposes.
        var loadedCount = 0
        var unreadCount: UInt32 = 0
        var typing: [String] = []
    }

    struct StoredMedia: Sendable {
        var path: String
        var thumbnailPath: String?
    }

    struct Seed: Sendable {
        var session: Session?
        var users: [UserProfile] = []
        var chats: [StoredChat] = []
        /// Keyed by `mediaKey(chatId:messageId:)`.
        var media: [String: StoredMedia] = [:]
    }

    struct Options: Sendable {
        var scheduler: any FakeScheduler
        var dataDirectory: String
        var now: @Sendable () -> Date
        var autoReply: Bool
        var networkReachable: Bool
    }

    /// Number of newest timeline entries exposed before `paginateBackwards` is called.
    public static let initialWindow = 50
    public static let failureReason = "Simulated network failure"
    /// The SAS of every simulated device link.
    public static let fakeSas = "123 456"
    /// The other device of a client created with a session.
    public static let fakeOtherDeviceId = "device-tablet"
    static let linkQrPrefix = "gim-link:fake:"

    private let options: Options
    private let seedsDemoOnRegister: Bool
    private let reachabilityUpdates: AsyncStream<Bool>.Continuation
    private let timeZoneUpdates: AsyncStream<(any LocalTimeZone)?>.Continuation

    private var session: Session? {
        didSet { sessionUserId.withLock { $0 = session?.userId } }
    }
    /// `session?.userId` for the synchronous `userId()`.
    private let sessionUserId = Mutex<String?>(nil)
    /// Hub-side state that survives `signOut`: each user's DeviceList (`isCurrent` false) and recovery code
    /// (normalized).
    private var deviceLists: [String: [DeviceInfo]] = [:]
    private var recoveryCodes: [String: String] = [:]
    private var createdIdentities = 0
    /// Links started by `startLink`, by QR string, and whether `waitLink` consumed them.
    private let startedLinks = Mutex<[String: Bool]>([:])
    private var awaitingLinkConfirmation = false
    /// Devices approved with `approveLink` and not yet confirmed.
    private var pendingApprovals: Set<String> = []
    private var users: [String: UserProfile] = [:]
    private var chats: [String: StoredChat] = [:]
    private var media: [String: StoredMedia] = [:]
    private var publishedChatList: [ChatSummary] = []
    private var publishedTimelines: [String: [TimelineItem]] = [:]
    private var networkReachable: Bool
    /// Splits the timelines into days; `nil` is UTC.
    private var localTimeZone: (any LocalTimeZone)?
    private var syncRunning = false
    private var connection: ConnectionState = .offline
    /// Bumped on every connection change so stale scheduled steps do nothing.
    private var connectionGeneration = 0
    private var sendFailuresRemaining = 0
    private var chatMembersFailure: GimError?
    private var chatMembersHeld = false
    private var heldChatMembers: [CheckedContinuation<Void, Never>] = []
    private var outbox: [String] = []
    private var nextId = 1
    private var nextReply = 0

    private var chatListSubscribers: [Subscriber<any ChatListListener>] = []
    private var timelineSubscribers: [String: [Subscriber<any TimelineListener>]] = [:]
    private var connectionSubscribers: [Subscriber<any ConnectionStateListener>] = []
    private var typingSubscribers: [String: [Subscriber<any TypingListener>]] = [:]

    /// - Parameters:
    ///   - autoReply: peers type and reply in direct chats after each own send.
    ///   - networkReachable: initial reachability, as `PlatformHooks.isNetworkReachable()` reports it.
    ///   - users: directory of users `findUser` can return.
    ///   - session: the signed-in user (added to the directory, with a second device `fakeOtherDeviceId`), or `nil`
    ///     before `createIdentity`.
    public init(
        scheduler: any FakeScheduler = ImmediateFakeScheduler(),
        dataDirectory: String = FakeGimClient.defaultDataDirectory,
        now: @escaping @Sendable () -> Date = { Date() },
        autoReply: Bool = false,
        networkReachable: Bool = true,
        users: [UserProfile] = [],
        session: Session? = nil
    ) {
        var seed = Seed(session: session, users: users)
        if let session {
            seed.users.append(
                UserProfile(userId: session.userId, handle: session.handle, displayName: session.displayName))
        }
        self.init(
            options: Options(
                scheduler: scheduler, dataDirectory: dataDirectory, now: now, autoReply: autoReply,
                networkReachable: networkReachable),
            seed: seed, seedsDemoOnRegister: false)
    }

    init(options: Options, seed: Seed, seedsDemoOnRegister: Bool) {
        self.options = options
        self.seedsDemoOnRegister = seedsDemoOnRegister
        let (updates, continuation) = AsyncStream.makeStream(of: Bool.self)
        reachabilityUpdates = continuation
        let (zoneUpdates, zoneContinuation) = AsyncStream.makeStream(of: (any LocalTimeZone)?.self)
        timeZoneUpdates = zoneContinuation
        networkReachable = options.networkReachable
        session = seed.session
        sessionUserId.withLock { $0 = seed.session?.userId }
        if let session = seed.session {
            let nowMs = Self.milliseconds(options.now())
            let day: UInt64 = 86_400_000
            deviceLists[session.userId] = [
                DeviceInfo(deviceId: session.deviceId, createdAtMs: nowMs - 30 * day, isCurrent: false, revoked: false),
                DeviceInfo(
                    deviceId: Self.fakeOtherDeviceId, createdAtMs: nowMs - 7 * day, isCurrent: false, revoked: false),
            ]
        }
        users = Dictionary(seed.users.map { ($0.userId, $0) }, uniquingKeysWith: { _, last in last })
        chats = Dictionary(uniqueKeysWithValues: seed.chats.map { ($0.id, $0) })
        media = seed.media
        publishedChatList = Self.sortedSummaries(chats: chats, users: users, session: seed.session)
        publishedTimelines = chats.mapValues { Self.timelineItems(of: $0, zone: nil) }
        // `setNetworkReachable` and `setLocalTimeZone` are synchronous; this keeps their updates in call order.
        Task { [weak self] in
            for await reachable in updates {
                await self?.simulateNetworkReachable(reachable)
            }
        }
        Task { [weak self] in
            for await zone in zoneUpdates {
                await self?.simulateLocalTimeZone(zone)
            }
        }
    }

    deinit {
        reachabilityUpdates.finish()
        timeZoneUpdates.finish()
    }

    public static var defaultDataDirectory: String {
        FileManager.default.temporaryDirectory.appendingPathComponent("gim-fake", isDirectory: true).path
    }

    // MARK: - Test and demo controls

    /// The next `count` own sends (including retries) end in `failed`.
    public func failNextSends(_ count: Int) {
        sendFailuresRemaining = count
    }

    /// While set, `chatMembers` throws `error` (for example `.Network`).
    public func failChatMembers(with error: GimError?) {
        chatMembersFailure = error
    }

    /// While held, `chatMembers` takes its snapshot of the members and then waits for `releaseChatMembers(at:)`, so
    /// tests can finish overlapping queries in any order. Releasing the hold resumes every waiting call.
    public func holdChatMembers(_ held: Bool) {
        chatMembersHeld = held
        guard !held else { return }
        let waiting = heldChatMembers
        heldChatMembers = []
        for continuation in waiting { continuation.resume() }
    }

    /// Number of `chatMembers` calls waiting while held, oldest first.
    public var heldChatMembersCount: Int { heldChatMembers.count }

    public func releaseChatMembers(at index: Int) {
        heldChatMembers.remove(at: index).resume()
    }

    /// Applies a reachability change immediately; `setNetworkReachable(reachable:)` does the same asynchronously.
    public func simulateNetworkReachable(_ reachable: Bool) {
        networkReachable = reachable
        if reachable {
            reconnect()
        } else {
            setConnection(.offline)
        }
    }

    /// Applies a time zone change immediately; `setLocalTimeZone(zone:)` does the same asynchronously. Open timelines
    /// move their date separators through their listeners.
    public func simulateLocalTimeZone(_ zone: (any LocalTimeZone)?) {
        localTimeZone = zone
        for chatId in chats.keys {
            publishTimelineChange(chatId)
        }
    }

    /// Simulates an incoming text message from a chat member.
    @discardableResult
    public func receiveText(chatId: String, from sender: String, body: String) throws -> String {
        try receive(chatId, from: sender, content: .text(body: body))
    }

    /// Simulates a chat member starting or stopping to type.
    public func setPeerTyping(chatId: String, userId: String, active: Bool) throws {
        var chat = try existingChat(chatId)
        guard chat.members.contains(userId), userId != session?.userId else {
            throw GimError.NotFound(reason: "member \(userId)")
        }
        chat.typing.removeAll { $0 == userId }
        if active { chat.typing.append(userId) }
        chats[chatId] = chat
        let typing = chat.typing
        typingSubscribers[chatId, default: []].deliver { $0.onUpdate(userIds: typing) }
    }

    // MARK: - Account

    public func session() async throws -> Session? {
        session
    }

    public nonisolated func userId() -> String? {
        sessionUserId.withLock { $0 }
    }

    /// Always `false`: the fake keeps no local database.
    public nonisolated func localStateReset() -> Bool {
        false
    }

    public func signOut() async throws {
        session = nil
        awaitingLinkConfirmation = false
        pendingApprovals = []
        syncRunning = false
        outbox = []
        setConnection(.offline)
        for chatId in chats.keys {
            timelineSubscribers[chatId, default: []].deliver { $0.onUpdate(diffs: [.clear]) }
        }
        chats = [:]
        publishedTimelines = [:]
        timelineSubscribers = [:]
        typingSubscribers = [:]
        publishChatList()
    }

    // MARK: - Identity and devices

    public func createIdentity(displayName: String) async throws -> String {
        guard session == nil else { throw GimError.InvalidInput(reason: "This device already has an identity") }
        let displayName = try Self.validDisplayName(displayName)
        let userId = makeId("user")
        createdIdentities += 1
        let code = Self.recoveryCode(
            bytes: (0..<24).map { UInt8(truncatingIfNeeded: createdIdentities &* 37 &+ $0 &* 11) })
        recoveryCodes[userId] = Self.normalizedRecoveryCode(code)
        let profile = UserProfile(userId: userId, handle: "", displayName: displayName)
        signIn(profile, deviceId: "device-1")
        if seedsDemoOnRegister { seedDemo(around: profile) }
        return code
    }

    public func restoreFromRecovery(userId: String, recoveryCode: String, revokeOthers: Bool) async throws {
        guard session == nil else { throw GimError.InvalidInput(reason: "This device already has an identity") }
        guard let code = Self.normalizedRecoveryCode(recoveryCode) else {
            throw GimError.InvalidInput(reason: "Malformed recovery code")
        }
        guard let expected = recoveryCodes[userId], let profile = users[userId] else {
            throw GimError.NotFound(reason: "device list of \(userId)")
        }
        guard code == expected else { throw GimError.Crypto(reason: "Wrong recovery code") }
        if revokeOthers {
            deviceLists[userId] = deviceLists[userId, default: []].map(Self.revoked)
        }
        signIn(profile, deviceId: makeId("device"))
    }

    public nonisolated func startLink(hubs: [String]) throws -> any LinkSession {
        guard userId() == nil else { throw GimError.InvalidInput(reason: "This device already has an identity") }
        let qrString = startedLinks.withLock { links in
            let qrString = "\(Self.linkQrPrefix)\(links.count + 1)"
            links[qrString] = false
            return qrString
        }
        return FakeLinkSession(qrString: qrString)
    }

    /// Signs in as the demo user (`demoSelfId`), whose first device is `device-1`.
    public func waitLink(link: any LinkSession) async throws -> String {
        guard session == nil else { throw GimError.InvalidInput(reason: "This device already has an identity") }
        let qrString = link.qrString()
        let started = startedLinks.withLock { links in
            guard links[qrString] == false else { return false }
            links[qrString] = true
            return true
        }
        guard started else { throw GimError.InvalidInput(reason: "Start a new device link") }
        let profile = users[Self.demoSelfId] ?? FakeDemoData.me
        if deviceLists[profile.userId] == nil {
            deviceLists[profile.userId] = [
                DeviceInfo(deviceId: "device-1", createdAtMs: nowMs(), isCurrent: false, revoked: false)
            ]
        }
        signIn(profile, deviceId: makeId("device"))
        awaitingLinkConfirmation = true
        return Self.fakeSas
    }

    public func confirmLink(accepted: Bool) async throws {
        guard awaitingLinkConfirmation, let session else {
            throw GimError.InvalidInput(reason: "No device link to confirm")
        }
        awaitingLinkConfirmation = false
        guard accepted else {
            try await signOut()
            return
        }
        if seedsDemoOnRegister, let profile = users[session.userId] { seedDemo(around: profile) }
    }

    public func approveLink(qrString: String) async throws -> any PendingApproval {
        let session = try requireSession()
        guard qrString.hasPrefix(Self.linkQrPrefix) else {
            throw GimError.InvalidInput(reason: "Not a device link QR code")
        }
        let deviceId = makeId("device")
        deviceLists[session.userId, default: []].append(
            DeviceInfo(deviceId: deviceId, createdAtMs: nowMs(), isCurrent: false, revoked: false))
        pendingApprovals.insert(deviceId)
        return FakePendingApproval(deviceId: deviceId, sas: Self.fakeSas)
    }

    public func confirmApproval(approval: any PendingApproval, accepted: Bool) async throws {
        let session = try requireSession()
        let deviceId = approval.deviceId()
        guard pendingApprovals.remove(deviceId) != nil else {
            throw GimError.InvalidInput(reason: "No pending approval for \(deviceId)")
        }
        if !accepted {
            deviceLists[session.userId] = deviceLists[session.userId, default: []].map {
                $0.deviceId == deviceId ? Self.revoked($0) : $0
            }
        }
    }

    public func devices() async throws -> [DeviceInfo] {
        let session = try requireSession()
        return deviceList(of: session.userId, current: session)
    }

    public func userDevices(userId: String) async throws -> [DeviceInfo] {
        let session = try requireSession()
        return deviceList(of: userId, current: session)
    }

    public func revokeDevice(deviceId: String) async throws {
        let session = try requireSession()
        guard deviceId != session.deviceId else {
            throw GimError.InvalidInput(reason: "The current device can't be revoked")
        }
        var list = deviceLists[session.userId, default: []]
        guard let index = list.firstIndex(where: { $0.deviceId == deviceId }) else {
            throw GimError.NotFound(reason: "device \(deviceId)")
        }
        list[index] = Self.revoked(list[index])
        deviceLists[session.userId] = list
    }

    public func setDisplayName(name: String) async throws {
        var session = try requireSession()
        session.displayName = try Self.validDisplayName(name)
        updateProfile(session)
    }

    public func claimHandle(handle: String) async throws {
        var session = try requireSession()
        let handle = handle.trimmingCharacters(in: .whitespaces).lowercased()
        guard !handle.isEmpty, !handle.contains(where: \.isWhitespace) else {
            throw GimError.InvalidInput(reason: "Handle must not be empty or contain spaces")
        }
        if users.values.contains(where: { $0.handle == handle && $0.userId != session.userId }) {
            throw GimError.Server(status: 409, reason: "Handle is already taken")
        }
        session.handle = handle
        updateProfile(session)
    }

    public func releaseHandle() async throws {
        var session = try requireSession()
        guard !session.handle.isEmpty else { throw GimError.InvalidInput(reason: "No handle is claimed") }
        session.handle = ""
        updateProfile(session)
    }

    private func signIn(_ profile: UserProfile, deviceId: String) {
        users[profile.userId] = profile
        deviceLists[profile.userId, default: []].append(
            DeviceInfo(deviceId: deviceId, createdAtMs: nowMs(), isCurrent: false, revoked: false))
        session = Session(
            userId: profile.userId, deviceId: deviceId, handle: profile.handle, displayName: profile.displayName)
    }

    private func seedDemo(around me: UserProfile) {
        let seed = FakeDemoData.seed(me: me, dataDirectory: options.dataDirectory, now: options.now())
        for chat in seed.chats {
            chats[chat.id] = chat
            publishTimelineChange(chat.id)
        }
        media.merge(seed.media) { _, new in new }
        publishChatList()
    }

    private func updateProfile(_ session: Session) {
        self.session = session
        users[session.userId] = UserProfile(
            userId: session.userId, handle: session.handle, displayName: session.displayName)
        publishChatList()
    }

    private func deviceList(of userId: String, current: Session) -> [DeviceInfo] {
        deviceLists[userId, default: []].map {
            var device = $0
            device.isCurrent = userId == current.userId && device.deviceId == current.deviceId
            return device
        }
    }

    // MARK: - Sync

    public func startSync() async throws {
        _ = try requireSession()
        syncRunning = true
        reconnect()
    }

    public func stopSync() async throws {
        syncRunning = false
        setConnection(.offline)
    }

    public nonisolated func setNetworkReachable(reachable: Bool) {
        reachabilityUpdates.yield(reachable)
    }

    public nonisolated func setLocalTimeZone(zone: (any LocalTimeZone)?) {
        timeZoneUpdates.yield(zone)
    }

    private func reconnect() {
        guard syncRunning, networkReachable, connection == .offline else { return }
        setConnection(.connecting)
        let generation = connectionGeneration
        options.scheduler.schedule(after: .milliseconds(500)) { [weak self] in
            await self?.advanceConnection(from: .connecting, to: .syncing, generation: generation)
        }
    }

    private func advanceConnection(from current: ConnectionState, to next: ConnectionState, generation: Int) {
        guard connectionGeneration == generation, connection == current else { return }
        setConnection(next)
        if next == .syncing {
            let generation = connectionGeneration
            options.scheduler.schedule(after: .milliseconds(300)) { [weak self] in
                await self?.advanceConnection(from: .syncing, to: .connected, generation: generation)
            }
        } else if next == .connected {
            let waiting = outbox
            outbox = []
            for messageId in waiting { startDelivery(messageId) }
        }
    }

    private func setConnection(_ state: ConnectionState) {
        guard connection != state else { return }
        connection = state
        connectionGeneration += 1
        connectionSubscribers.deliver { $0.onChange(state: state) }
    }

    // MARK: - Users and chats

    public func findUser(handle: String) async throws -> UserProfile? {
        _ = try requireSession()
        let handle = handle.trimmingCharacters(in: .whitespaces).lowercased()
        return users.values.first { $0.handle == handle }
    }

    public func createDirectChat(userId: String) async throws -> String {
        let session = try requireSession()
        guard userId != session.userId else {
            throw GimError.InvalidInput(reason: "You can't start a chat with yourself")
        }
        _ = try existingUser(userId)
        if let existing = chats.values.first(where: { $0.kind == .direct && $0.members.contains(userId) }) {
            return existing.id
        }
        let chat = StoredChat(
            id: makeId("chat"), kind: .direct, name: "", createdAtMs: nowMs(), members: [session.userId, userId])
        chats[chat.id] = chat
        publishTimelineChange(chat.id)
        publishChatList()
        return chat.id
    }

    public func createGroupChat(name: String, memberUserIds: [String]) async throws -> String {
        let session = try requireSession()
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { throw GimError.InvalidInput(reason: "Group name is required") }
        var memberIds = [session.userId]
        for member in memberUserIds where !memberIds.contains(member) {
            _ = try existingUser(member)
            memberIds.append(member)
        }
        let chat = StoredChat(id: makeId("chat"), kind: .group, name: name, createdAtMs: nowMs(), members: memberIds)
        chats[chat.id] = chat
        publishTimelineChange(chat.id)
        publishChatList()
        return chat.id
    }

    public func chatMembers(chatId: String) async throws -> [UserProfile] {
        _ = try requireSession()
        if let chatMembersFailure { throw chatMembersFailure }
        let members = try existingChat(chatId).members.compactMap { users[$0] }
        if chatMembersHeld {
            await withCheckedContinuation { heldChatMembers.append($0) }
        }
        return members
    }

    public func addMembers(chatId: String, userIds: [String]) async throws {
        _ = try requireSession()
        var chat = try existingGroup(chatId, "Members can only be added to groups")
        var added: [UserProfile] = []
        for userId in userIds where !chat.members.contains(userId) && !added.contains(where: { $0.userId == userId }) {
            added.append(try existingUser(userId))
        }
        guard !added.isEmpty else { return }
        chat.members += added.map(\.userId)
        chats[chatId] = chat
        for user in added {
            appendEntry(.membership(userName: user.displayName, change: .added, atMs: nowMs()), chatId)
        }
    }

    public func removeMember(chatId: String, userId: String) async throws {
        let session = try requireSession()
        var chat = try existingGroup(chatId, "Members can only be removed from groups")
        guard userId != session.userId else { throw GimError.InvalidInput(reason: "Use leaveChat to leave a group") }
        guard chat.members.contains(userId), let user = users[userId] else {
            throw GimError.NotFound(reason: "member \(userId)")
        }
        chat.members.removeAll { $0 == userId }
        chat.typing.removeAll { $0 == userId }
        chats[chatId] = chat
        appendEntry(.membership(userName: user.displayName, change: .removed, atMs: nowMs()), chatId)
    }

    public func leaveChat(chatId: String) async throws {
        let session = try requireSession()
        _ = try existingGroup(chatId, "Only groups can be left")
        appendEntry(.membership(userName: session.displayName, change: .left, atMs: nowMs()), chatId)
        chats[chatId] = nil
        publishedTimelines[chatId] = nil
        timelineSubscribers[chatId] = nil
        typingSubscribers[chatId] = nil
        publishChatList()
    }

    public func setGroupInfo(chatId: String, name: String?, avatarFilePath: String?) async throws {
        _ = try requireSession()
        var chat = try existingGroup(chatId, "Only groups have a name and avatar")
        guard name != nil || avatarFilePath != nil else {
            throw GimError.InvalidInput(reason: "Set a name or an avatar")
        }
        if let name {
            let name = name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { throw GimError.InvalidInput(reason: "Group name is required") }
            chat.name = name
        }
        if let avatarFilePath {
            let avatarId = makeId("avatar")
            let stored = try storeFile(avatarFilePath, as: avatarId)
            media[Self.mediaKey(chatId: chatId, messageId: avatarId)] = StoredMedia(
                path: stored.path, thumbnailPath: stored.path)
            chat.avatar = MediaRef(
                chatId: chatId, messageId: avatarId, mime: Self.mime(forPath: avatarFilePath), size: stored.size,
                hasThumbnail: true)
        }
        chats[chatId] = chat
        publishChatList()
    }

    // MARK: - Messages

    public func sendText(chatId: String, body: String, replyTo: String?) async throws -> String {
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GimError.InvalidInput(reason: "Message is empty")
        }
        return try sendOwn(chatId, messageId: makeId("msg"), content: .text(body: body), replyTo: replyTo)
    }

    public func sendMedia(
        chatId: String, filePath: String, mime: String, caption: String?, replyTo: String?
    ) async throws -> String {
        _ = try requireSession()
        _ = try existingChat(chatId)
        let messageId = makeId("msg")
        let stored = try storeFile(filePath, as: messageId)
        let isImage = mime.hasPrefix("image/")
        media[Self.mediaKey(chatId: chatId, messageId: messageId)] = StoredMedia(
            path: stored.path, thumbnailPath: isImage ? stored.path : nil)
        let ref = MediaRef(chatId: chatId, messageId: messageId, mime: mime, size: stored.size, hasThumbnail: isImage)
        let content: MessageContent =
            isImage
            ? .image(media: ref, width: nil, height: nil, caption: caption)
            : .file(media: ref, fileName: URL(fileURLWithPath: filePath).lastPathComponent, caption: caption)
        return try sendOwn(chatId, messageId: messageId, content: content, replyTo: replyTo)
    }

    public func editMessage(chatId: String, messageId: String, newBody: String) async throws {
        _ = try requireSession()
        let stored = try existingMessage(chatId, messageId)
        guard stored.item.isOwn else { throw GimError.InvalidInput(reason: "Only your own messages can be edited") }
        guard case .text = stored.item.content else { throw GimError.InvalidInput(reason: "Only text can be edited") }
        guard !newBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GimError.InvalidInput(reason: "Message is empty")
        }
        updateMessage(chatId, messageId) {
            $0.item.content = .text(body: newBody)
            $0.item.edited = true
        }
    }

    public func deleteMessage(chatId: String, messageId: String) async throws {
        _ = try requireSession()
        let stored = try existingMessage(chatId, messageId)
        guard stored.item.isOwn else {
            throw GimError.InvalidInput(reason: "Only your own messages can be deleted")
        }
        updateMessage(chatId, messageId) {
            $0.item.content = .deleted
            $0.item.replyTo = nil
            $0.item.edited = false
            $0.reactions = []
            $0.item.reactions = []
        }
    }

    public func react(chatId: String, messageId: String, emoji: String) async throws {
        try setOwnReaction(chatId, messageId, emoji: emoji, active: true)
    }

    public func unreact(chatId: String, messageId: String, emoji: String) async throws {
        try setOwnReaction(chatId, messageId, emoji: emoji, active: false)
    }

    public func retrySend(chatId: String, messageId: String) async throws {
        _ = try requireSession()
        let stored = try existingMessage(chatId, messageId)
        guard case .failed = stored.item.sendState else {
            throw GimError.InvalidInput(reason: "Message has not failed")
        }
        updateMessage(chatId, messageId) { $0.item.sendState = .pending }
        startDelivery(messageId)
    }

    public func cancelSend(chatId: String, messageId: String) async throws {
        _ = try requireSession()
        let stored = try existingMessage(chatId, messageId)
        switch stored.item.sendState {
        case .pending, .failed: break
        default: throw GimError.InvalidInput(reason: "Message was already sent")
        }
        guard var chat = chats[chatId],
            let index = chat.entries.firstIndex(where: { $0.message?.item.messageId == messageId })
        else { return }
        if index >= chat.entries.count - chat.loadedCount { chat.loadedCount -= 1 }
        chat.entries.remove(at: index)
        chats[chatId] = chat
        outbox.removeAll { $0 == messageId }
        publishTimelineChange(chatId)
        publishChatList()
    }

    public func markRead(chatId: String, upToMessageId: String) async throws {
        _ = try requireSession()
        var chat = try existingChat(chatId)
        guard let index = chat.entries.firstIndex(where: { $0.message?.item.messageId == upToMessageId }) else {
            throw GimError.NotFound(reason: "message \(upToMessageId)")
        }
        let unreadAfter = chat.entries[(index + 1)...].filter { $0.message.map { !$0.item.isOwn } ?? false }.count
        let unread = min(chat.unreadCount, UInt32(unreadAfter))
        guard unread != chat.unreadCount else { return }
        chat.unreadCount = unread
        chats[chatId] = chat
        publishChatList()
    }

    public func setTyping(chatId: String, active: Bool) async throws {
        _ = try requireSession()
        _ = try existingChat(chatId)
    }

    public func stopTyping(chatId: String) async throws {
        try await setTyping(chatId: chatId, active: false)
    }

    // MARK: - Media

    public func fetchMedia(chatId: String, messageId: String, destPath: String) async throws -> String {
        guard let stored = media[Self.mediaKey(chatId: chatId, messageId: messageId)] else {
            throw GimError.NotFound(reason: "media \(messageId)")
        }
        return try copyFile(stored.path, to: destPath)
    }

    public func fetchThumbnail(chatId: String, messageId: String, destPath: String) async throws -> String? {
        guard let stored = media[Self.mediaKey(chatId: chatId, messageId: messageId)] else {
            throw GimError.NotFound(reason: "media \(messageId)")
        }
        return try stored.thumbnailPath.map { try copyFile($0, to: destPath) }
    }

    // MARK: - Listeners

    public func chatList(listener: any ChatListListener) async throws -> TaskHandle {
        let subscription = FakeSubscription()
        let list = publishedChatList
        subscription.deliver { listener.onUpdate(diffs: [.reset(values: list)]) }
        chatListSubscribers.append(Subscriber(subscription: subscription, listener: listener))
        return subscription.taskHandle()
    }

    public func timeline(chatId: String) async throws -> any Timeline {
        _ = try existingChat(chatId)
        return FakeTimeline(client: self, chatId: chatId)
    }

    public func connectionState(listener: any ConnectionStateListener) async throws -> TaskHandle {
        let subscription = FakeSubscription()
        let state = connection
        subscription.deliver { listener.onChange(state: state) }
        connectionSubscribers.append(Subscriber(subscription: subscription, listener: listener))
        return subscription.taskHandle()
    }

    public func typing(chatId: String, listener: any TypingListener) async throws -> TaskHandle {
        let typing = try existingChat(chatId).typing
        let subscription = FakeSubscription()
        subscription.deliver { listener.onUpdate(userIds: typing) }
        typingSubscribers[chatId, default: []].append(Subscriber(subscription: subscription, listener: listener))
        return subscription.taskHandle()
    }

    func addTimelineListener(chatId: String, listener: any TimelineListener) -> TaskHandle {
        let subscription = FakeSubscription()
        let items = publishedTimelines[chatId] ?? []
        subscription.deliver { listener.onUpdate(diffs: [.reset(values: items)]) }
        if chats[chatId] != nil {
            timelineSubscribers[chatId, default: []].append(Subscriber(subscription: subscription, listener: listener))
        }
        return subscription.taskHandle()
    }

    func paginateBackwards(chatId: String, count: UInt16) throws -> Bool {
        var chat = try existingChat(chatId)
        let hidden = chat.entries.count - chat.loadedCount
        let loaded = min(Int(count), hidden)
        guard loaded > 0 else { return hidden > 0 }
        chat.loadedCount += loaded
        chats[chatId] = chat
        publishTimelineChange(chatId)
        return hidden - loaded > 0
    }

    // MARK: - Sending

    private func sendOwn(
        _ chatId: String, messageId: String, content: MessageContent, replyTo: String?
    ) throws -> String {
        let session = try requireSession()
        _ = try existingChat(chatId)
        let reply = try replyTo.map { try replyPreview(for: $0, in: chatId) }
        let item = MessageItem(
            messageId: messageId, chatId: chatId,
            sender: UserProfile(userId: session.userId, handle: session.handle, displayName: session.displayName),
            isOwn: true, sentAtMs: nowMs(), content: content, replyTo: reply, reactions: [], edited: false,
            sendState: .pending)
        appendEntry(.message(StoredMessage(item: item)), chatId)
        startDelivery(messageId)
        return messageId
    }

    private func startDelivery(_ messageId: String) {
        guard connection == .connected else {
            outbox.append(messageId)
            return
        }
        let state: SendState
        if sendFailuresRemaining > 0 {
            sendFailuresRemaining -= 1
            state = .failed(reason: Self.failureReason)
        } else {
            state = .sent
        }
        options.scheduler.schedule(after: .milliseconds(300)) { [weak self] in await self?.advance(messageId, to: state)
        }
    }

    private func advance(_ messageId: String, to state: SendState) {
        guard let located = locateMessage(messageId), located.message.item.content != .deleted else { return }
        let chatId = located.chatId
        updateMessage(chatId, messageId) { $0.item.sendState = state }
        switch state {
        case .sent:
            options.scheduler.schedule(after: .milliseconds(700)) { [weak self] in
                await self?.advance(messageId, to: .delivered)
            }
            scheduleAutoReply(chatId)
        case .delivered:
            options.scheduler.schedule(after: .milliseconds(1500)) { [weak self] in
                await self?.advance(messageId, to: .read)
            }
        case .pending, .read, .failed:
            break
        }
    }

    private func scheduleAutoReply(_ chatId: String) {
        guard options.autoReply, let session, let chat = chats[chatId], chat.kind == .direct,
            let peer = chat.members.first(where: { $0 != session.userId })
        else { return }
        options.scheduler.schedule(after: .seconds(1)) { [weak self] in
            try? await self?.setPeerTyping(chatId: chatId, userId: peer, active: true)
        }
        options.scheduler.schedule(after: .seconds(3)) { [weak self] in await self?.deliverAutoReply(chatId, from: peer)
        }
    }

    private func deliverAutoReply(_ chatId: String, from peer: String) {
        try? setPeerTyping(chatId: chatId, userId: peer, active: false)
        let body = FakeDemoData.replies[nextReply % FakeDemoData.replies.count]
        nextReply += 1
        _ = try? receive(chatId, from: peer, content: .text(body: body))
    }

    private func receive(_ chatId: String, from sender: String, content: MessageContent) throws -> String {
        let session = try requireSession()
        var chat = try existingChat(chatId)
        guard sender != session.userId, chat.members.contains(sender), let profile = users[sender] else {
            throw GimError.NotFound(reason: "member \(sender)")
        }
        chat.unreadCount += 1
        chats[chatId] = chat
        let item = MessageItem(
            messageId: makeId("msg"), chatId: chatId, sender: profile, isOwn: false, sentAtMs: nowMs(),
            content: content, replyTo: nil, reactions: [], edited: false, sendState: nil)
        appendEntry(.message(StoredMessage(item: item)), chatId)
        return item.messageId
    }

    private func setOwnReaction(_ chatId: String, _ messageId: String, emoji: String, active: Bool) throws {
        let session = try requireSession()
        let stored = try existingMessage(chatId, messageId)
        guard !emoji.isEmpty else { throw GimError.InvalidInput(reason: "Reaction is empty") }
        guard stored.item.content != .deleted else { throw GimError.InvalidInput(reason: "Message was deleted") }
        updateMessage(chatId, messageId) {
            Self.setReaction(&$0, emoji: emoji, user: session.userId, active: active, selfId: session.userId)
        }
    }

    // MARK: - State helpers

    private func requireSession() throws -> Session {
        guard let session else { throw GimError.NotRegistered }
        return session
    }

    private func existingUser(_ userId: String) throws -> UserProfile {
        guard let user = users[userId] else { throw GimError.NotFound(reason: "user \(userId)") }
        return user
    }

    private func existingChat(_ chatId: String) throws -> StoredChat {
        guard let chat = chats[chatId] else { throw GimError.NotFound(reason: "chat \(chatId)") }
        return chat
    }

    private func existingGroup(_ chatId: String, _ notGroupReason: String) throws -> StoredChat {
        let chat = try existingChat(chatId)
        guard chat.kind == .group else { throw GimError.InvalidInput(reason: notGroupReason) }
        return chat
    }

    private func existingMessage(_ chatId: String, _ messageId: String) throws -> StoredMessage {
        let chat = try existingChat(chatId)
        guard let stored = chat.entries.lazy.compactMap(\.message).first(where: { $0.item.messageId == messageId })
        else { throw GimError.NotFound(reason: "message \(messageId)") }
        return stored
    }

    private func locateMessage(_ messageId: String) -> (chatId: String, message: StoredMessage)? {
        for chat in chats.values {
            if let stored = chat.entries.lazy.compactMap(\.message).first(where: { $0.item.messageId == messageId }) {
                return (chat.id, stored)
            }
        }
        return nil
    }

    private func makeId(_ prefix: String) -> String {
        defer { nextId += 1 }
        return "\(prefix)-local-\(nextId)"
    }

    private func nowMs() -> UInt64 {
        Self.milliseconds(options.now())
    }

    private func replyPreview(for messageId: String, in chatId: String) throws -> ReplyPreview {
        guard let target = locateMessage(messageId) else {
            throw GimError.NotFound(reason: "message \(messageId)")
        }
        guard target.chatId == chatId else { throw GimError.InvalidInput(reason: "Reply target is in another chat") }
        return ReplyPreview(
            messageId: messageId, senderName: target.message.item.sender.displayName,
            text: Self.previewText(target.message.item.content))
    }

    private func storeFile(_ sourcePath: String, as id: String) throws -> (path: String, size: UInt64) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: sourcePath) else { throw GimError.InvalidInput(reason: "File not found") }
        let directory = URL(fileURLWithPath: options.dataDirectory).appendingPathComponent("media", isDirectory: true)
        let destination = directory.appendingPathComponent(
            "\(id)-\(URL(fileURLWithPath: sourcePath).lastPathComponent)")
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try fileManager.copyItem(atPath: sourcePath, toPath: destination.path)
            let attributes = try fileManager.attributesOfItem(atPath: destination.path)
            return (destination.path, (attributes[.size] as? NSNumber)?.uint64Value ?? 0)
        } catch {
            throw GimError.Storage(reason: "Could not store media: \(error)")
        }
    }

    private func copyFile(_ sourcePath: String, to destPath: String) throws -> String {
        let fileManager = FileManager.default
        do {
            let destination = URL(fileURLWithPath: destPath)
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destPath) { try fileManager.removeItem(at: destination) }
            try fileManager.copyItem(atPath: sourcePath, toPath: destPath)
            return destPath
        } catch {
            throw GimError.Storage(reason: "Could not write media: \(error)")
        }
    }

    private func appendEntry(_ entry: Entry, _ chatId: String) {
        guard var chat = chats[chatId] else { return }
        chat.entries.append(entry)
        chat.loadedCount += 1
        chats[chatId] = chat
        publishTimelineChange(chatId)
        publishChatList()
    }

    private func updateMessage(_ chatId: String, _ messageId: String, _ mutate: (inout StoredMessage) -> Void) {
        guard var chat = chats[chatId],
            let index = chat.entries.firstIndex(where: { $0.message?.item.messageId == messageId }),
            var stored = chat.entries[index].message
        else { return }
        mutate(&stored)
        chat.entries[index] = .message(stored)
        chats[chatId] = chat
        publishTimelineChange(chatId)
        publishChatList()
    }

    /// Emits the diffs that move the published timeline of `chatId` to its current state.
    private func publishTimelineChange(_ chatId: String) {
        guard let chat = chats[chatId] else { return }
        let items = Self.timelineItems(of: chat, zone: localTimeZone)
        let diffs = Self.timelineDiffs(from: publishedTimelines[chatId] ?? [], to: items)
        publishedTimelines[chatId] = items
        guard !diffs.isEmpty else { return }
        timelineSubscribers[chatId, default: []].deliver { $0.onUpdate(diffs: diffs) }
    }

    /// Emits the diffs that move the published chat list to the current state. A chat that changed position is
    /// removed and inserted again.
    private func publishChatList() {
        let newList = Self.sortedSummaries(chats: chats, users: users, session: session)
        let diffs = Self.chatListDiffs(from: publishedChatList, to: newList)
        publishedChatList = newList
        guard !diffs.isEmpty else { return }
        chatListSubscribers.deliver { $0.onUpdate(diffs: diffs) }
    }

    // MARK: - Pure helpers

    static let recoveryAlphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    /// gim-core's recovery code format: Crockford base32 of the bytes, most significant bit first, zero-padded,
    /// in blocks of four separated by `-`.
    static func recoveryCode(bytes: [UInt8]) -> String {
        var symbols: [Character] = []
        var buffer = 0
        var bits = 0
        for byte in bytes {
            buffer = (buffer << 8 | Int(byte)) & 0xFFFF
            bits += 8
            while bits >= 5 {
                bits -= 5
                symbols.append(recoveryAlphabet[buffer >> bits & 31])
            }
        }
        if bits > 0 { symbols.append(recoveryAlphabet[buffer << (5 - bits) & 31]) }
        return stride(from: 0, to: symbols.count, by: 4)
            .map { String(symbols[$0..<min($0 + 4, symbols.count)]) }
            .joined(separator: "-")
    }

    /// The 39 symbols of a 24-byte recovery code, parsed like gim-core (case-insensitive, `I`/`L` as `1`, `O` as `0`,
    /// `-` and ASCII whitespace ignored, zero padding bits); `nil` when malformed.
    static func normalizedRecoveryCode(_ code: String) -> String? {
        var symbols = ""
        for character in code.uppercased() {
            if character == "-" || (character.isASCII && character.isWhitespace) { continue }
            let symbol: Character =
                switch character {
                case "I", "L": "1"
                case "O": "0"
                default: character
                }
            guard recoveryAlphabet.contains(symbol) else { return nil }
            symbols.append(symbol)
        }
        guard symbols.count == 39, let last = symbols.last.flatMap({ recoveryAlphabet.firstIndex(of: $0) }),
            last % 8 == 0
        else { return nil }
        return symbols
    }

    static func validDisplayName(_ name: String) throws -> String {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { throw GimError.InvalidInput(reason: "Display name is required") }
        return name
    }

    static func revoked(_ device: DeviceInfo) -> DeviceInfo {
        DeviceInfo(deviceId: device.deviceId, createdAtMs: 0, isCurrent: false, revoked: true)
    }

    static func milliseconds(_ date: Date) -> UInt64 {
        UInt64(max(0, (date.timeIntervalSince1970 * 1000).rounded()))
    }

    static func mediaKey(chatId: String, messageId: String) -> String {
        "\(chatId)/\(messageId)"
    }

    static func mime(forPath path: String) -> String {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "heic": "image/heic"
        default: "application/octet-stream"
        }
    }

    /// The loaded window of `chat` with a `dateSeparator` before the first item of each local calendar day in `zone`
    /// (UTC when `nil`).
    static func timelineItems(of chat: StoredChat, zone: (any LocalTimeZone)?) -> [TimelineItem] {
        var items: [TimelineItem] = []
        var currentDay: UInt64?
        for entry in chat.entries.suffix(chat.loadedCount) {
            let day = dayStartMs(of: entry.atMs, zone: zone)
            if day != currentDay {
                items.append(.dateSeparator(dayStartMs: day))
                currentDay = day
            }
            items.append(entry.timelineItem)
        }
        return items
    }

    /// Start of the local calendar day containing `atMs`, like gim-core: offsets are taken at the start of the UTC
    /// hour, and the day starts at local midnight with the offset in effect at midnight.
    static func dayStartMs(of atMs: UInt64, zone: (any LocalTimeZone)?) -> UInt64 {
        /// `value` rounded down to a multiple of `unit`, also for negative values.
        func floor(_ value: Int64, to unit: Int64) -> Int64 {
            value - ((value % unit) + unit) % unit
        }
        func offsetMs(_ at: Int64) -> Int64 {
            guard let zone else { return 0 }
            return Int64(zone.utcOffsetSecs(atMs: floor(at, to: 3_600_000))) * 1000
        }
        let at = Int64(clamping: atMs)
        let midnight = floor(at + offsetMs(at), to: 86_400_000)
        return UInt64(clamping: midnight - offsetMs(midnight - offsetMs(midnight)))
    }

    /// Diffs from `old` to `new` that keep the common prefix and suffix and replace the middle.
    static func timelineDiffs(from old: [TimelineItem], to new: [TimelineItem]) -> [TimelineDiff] {
        if old == new { return [] }
        if old.isEmpty { return [.append(values: new)] }
        if new.isEmpty { return [.clear] }
        var prefix = 0
        while prefix < min(old.count, new.count), old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(old.count, new.count) - prefix, old[old.count - 1 - suffix] == new[new.count - 1 - suffix] {
            suffix += 1
        }
        let oldMiddle = old.count - prefix - suffix
        let newMiddle = new.count - prefix - suffix
        let paired = min(oldMiddle, newMiddle)
        var diffs: [TimelineDiff] = (prefix..<(prefix + paired)).map { .set(index: UInt32($0), value: new[$0]) }
        let start = prefix + paired
        if oldMiddle > paired {
            let removed = oldMiddle - paired
            if suffix == 0 {
                diffs.append(removed == 1 ? .popBack : .truncate(length: UInt32(start)))
            } else if start == 0 && removed == 1 {
                diffs.append(.popFront)
            } else {
                diffs += Array(repeating: .remove(index: UInt32(start)), count: removed)
            }
        } else if newMiddle > paired {
            let added = Array(new[start..<(start + newMiddle - paired)])
            if suffix == 0 {
                diffs.append(added.count == 1 ? .pushBack(value: added[0]) : .append(values: added))
            } else if start == 0 && added.count == 1 {
                diffs.append(.pushFront(value: added[0]))
            } else {
                diffs += added.enumerated().map { .insert(index: UInt32(start + $0.offset), value: $0.element) }
            }
        }
        return diffs
    }

    /// `set` for a chat that stayed in place, `remove` plus `pushFront`/`insert`/`pushBack` for one that moved,
    /// `clear` when the list became empty.
    static func chatListDiffs(from old: [ChatSummary], to new: [ChatSummary]) -> [ChatListDiff] {
        if old == new { return [] }
        if new.isEmpty { return [.clear] }
        var current = old
        var diffs: [ChatListDiff] = []
        let newIds = Set(new.map(\.chatId))
        for index in current.indices.reversed() where !newIds.contains(current[index].chatId) {
            current.remove(at: index)
            diffs.append(.remove(index: UInt32(index)))
        }
        for (index, summary) in new.enumerated() {
            if index < current.count, current[index].chatId == summary.chatId {
                if current[index] != summary { diffs.append(.set(index: UInt32(index), value: summary)) }
                current[index] = summary
                continue
            }
            if let oldIndex = current.firstIndex(where: { $0.chatId == summary.chatId }) {
                current.remove(at: oldIndex)
                diffs.append(.remove(index: UInt32(oldIndex)))
            }
            current.insert(summary, at: index)
            if index == 0 {
                diffs.append(.pushFront(value: summary))
            } else if index == current.count - 1 {
                diffs.append(.pushBack(value: summary))
            } else {
                diffs.append(.insert(index: UInt32(index), value: summary))
            }
        }
        return diffs
    }

    static func sortedSummaries(
        chats: [String: StoredChat], users: [String: UserProfile], session: Session?
    ) -> [ChatSummary] {
        chats.values
            .map { summary(of: $0, users: users, session: session) }
            .sorted { lhs, rhs in
                lhs.updatedAtMs != rhs.updatedAtMs ? lhs.updatedAtMs > rhs.updatedAtMs : lhs.chatId < rhs.chatId
            }
    }

    static func summary(of chat: StoredChat, users: [String: UserProfile], session: Session?) -> ChatSummary {
        let last = chat.entries.last { $0.message != nil }?.message?.item
        let name: String
        switch chat.kind {
        case .group:
            name = chat.name
        case .direct:
            let peer = chat.members.first { $0 != session?.userId }.flatMap { users[$0] }
            name = peer?.displayName ?? chat.name
        }
        return ChatSummary(
            chatId: chat.id, kind: chat.kind, name: name, avatar: chat.avatar,
            lastMessage: last.map {
                MessagePreview(
                    senderName: $0.sender.displayName, text: previewText($0.content), sentAtMs: $0.sentAtMs,
                    isOwn: $0.isOwn)
            },
            unreadCount: chat.unreadCount, updatedAtMs: chat.entries.last?.atMs ?? chat.createdAtMs,
            memberCount: UInt32(chat.members.count))
    }

    static func previewText(_ content: MessageContent) -> String {
        switch content {
        case .text(let body): body
        case .image(_, _, _, let caption): caption.map { "Photo: \($0)" } ?? "Photo"
        case .file(_, let fileName, _): "File: \(fileName ?? "attachment")"
        case .deleted: "Message deleted"
        case .unsupported: "Unsupported message"
        }
    }

    static func setReaction(_ stored: inout StoredMessage, emoji: String, user: String, active: Bool, selfId: String) {
        if let index = stored.reactions.firstIndex(where: { $0.emoji == emoji }) {
            stored.reactions[index].users.removeAll { $0 == user }
            if active { stored.reactions[index].users.append(user) }
            if stored.reactions[index].users.isEmpty { stored.reactions.remove(at: index) }
        } else if active {
            stored.reactions.append(Reaction(emoji: emoji, users: [user]))
        }
        stored.item.reactions = stored.reactions.map {
            ReactionGroup(emoji: $0.emoji, count: UInt32($0.users.count), own: $0.users.contains(selfId))
        }
    }
}

/// `Timeline` of one chat of a `FakeGimClient`.
final class FakeTimeline: Timeline {
    private let client: FakeGimClient
    private let id: String

    init(client: FakeGimClient, chatId: String) {
        self.client = client
        id = chatId
    }

    func chatId() -> String {
        id
    }

    func addListener(listener: any TimelineListener) async -> TaskHandle {
        await client.addTimelineListener(chatId: id, listener: listener)
    }

    func paginateBackwards(count: UInt16) async throws -> Bool {
        try await client.paginateBackwards(chatId: id, count: count)
    }
}

/// `LinkSession` of a `FakeGimClient`.
final class FakeLinkSession: LinkSession {
    private let qr: String

    init(qrString: String) {
        qr = qrString
    }

    func qrString() -> String {
        qr
    }
}

/// `PendingApproval` of a `FakeGimClient`.
final class FakePendingApproval: PendingApproval {
    private let id: String
    private let code: String

    init(deviceId: String, sas: String) {
        id = deviceId
        code = sas
    }

    func deviceId() -> String {
        id
    }

    func sas() -> String {
        code
    }
}
