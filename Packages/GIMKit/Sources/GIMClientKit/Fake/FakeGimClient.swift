import Foundation

/// In-memory `GimClientAPI` for previews, demo mode and tests.
///
/// Emits the same diff semantics as gim-core: the chat list is ordered by last activity (the last message time, or
/// the creation time for empty chats) descending, ties by chat id; each timeline is ordered oldest first and exposes
/// a window of the newest messages that `loadOlder` grows at the front. The window is kept per chat.
/// Delayed behaviour (send status progression, peer typing and replies, reconnecting) runs through `FakeScheduler`.
public actor FakeGimClient: GimClientAPI {
    struct Reaction: Sendable {
        var emoji: String
        var users: [UserId]
    }

    struct StoredMessage: Sendable {
        var message: TimelineMessage
        var reactions: [Reaction] = []
    }

    struct StoredChat: Sendable {
        var id: ChatId
        var kind: ChatKind
        var name: String
        var createdAt: Date
        var members: [UserId]
        var messages: [StoredMessage] = []
        var loadedCount = 0
        var unreadCount: UInt32 = 0
        var typing: [UserId] = []
    }

    struct Seed: Sendable {
        var session: Session?
        var users: [UserProfile] = []
        var chats: [StoredChat] = []
        var media: [MediaId: String] = [:]
    }

    /// Number of newest messages a timeline exposes before `loadOlder` is called.
    public static let initialWindow = 50
    public static let failureReason = "Simulated network failure"

    private let scheduler: any FakeScheduler
    private let dataDirectory: String
    private let now: @Sendable () -> Date
    private let autoReply: Bool

    private var session: Session?
    private var users: [UserId: UserProfile] = [:]
    private var chats: [ChatId: StoredChat] = [:]
    private var chatList: [ChatSummary] = []
    private var messageChats: [MessageId: ChatId] = [:]
    private var media: [MediaId: String] = [:]
    private var networkAvailable = true
    private var connection: ConnectionState = .online
    private var sendFailuresRemaining = 0
    private var waitingForNetwork: [MessageId] = []
    private var nextId = 1
    private var nextReply = 0

    private var chatListSubscribers: [Subscriber<any ChatListListener>] = []
    private var timelineSubscribers: [ChatId: [Subscriber<any TimelineListener>]] = [:]
    private var connectionSubscribers: [Subscriber<any ConnectionListener>] = []
    private var typingSubscribers: [ChatId: [Subscriber<any TypingListener>]] = [:]

    /// - Parameters:
    ///   - users: directory of users `findUser` can return.
    ///   - session: the signed-in user (added to the directory), or `nil` for `unregistered`.
    ///   - autoReply: peers type and reply in direct chats after each own send.
    public init(
        scheduler: any FakeScheduler = ImmediateFakeScheduler(),
        dataDirectory: String = FakeGimClient.defaultDataDirectory,
        now: @escaping @Sendable () -> Date = { Date() },
        autoReply: Bool = false,
        users: [UserProfile] = [],
        session: Session? = nil
    ) {
        var seed = Seed(session: session, users: users)
        if let session {
            seed.users.append(
                UserProfile(userId: session.userId, handle: session.handle, displayName: session.displayName))
        }
        self.init(scheduler: scheduler, dataDirectory: dataDirectory, now: now, autoReply: autoReply, seed: seed)
    }

    init(
        scheduler: any FakeScheduler,
        dataDirectory: String,
        now: @escaping @Sendable () -> Date,
        autoReply: Bool,
        seed: Seed
    ) {
        self.scheduler = scheduler
        self.dataDirectory = dataDirectory
        self.now = now
        self.autoReply = autoReply
        let users = Dictionary(seed.users.map { ($0.userId, $0) }, uniquingKeysWith: { _, last in last })
        let chats = Dictionary(uniqueKeysWithValues: seed.chats.map { ($0.id, $0) })
        self.session = seed.session
        self.users = users
        self.chats = chats
        self.media = seed.media
        var messageChats: [MessageId: ChatId] = [:]
        for chat in seed.chats {
            for stored in chat.messages { messageChats[stored.message.id] = chat.id }
        }
        self.messageChats = messageChats
        self.chatList = Self.sortedSummaries(chats: chats, users: users, session: seed.session)
    }

    public static var defaultDataDirectory: String {
        FileManager.default.temporaryDirectory.appendingPathComponent("gim-fake", isDirectory: true).path
    }

    // MARK: - Test and demo controls

    /// The next `count` own sends (including retries) end in `failed`.
    public func failNextSends(_ count: Int) {
        sendFailuresRemaining = count
    }

    /// Simulates an incoming text message from a chat member.
    @discardableResult
    public func receiveText(_ chatId: ChatId, from sender: UserId, text: String) throws -> MessageId {
        try receive(chatId, from: sender, content: .text(text))
    }

    /// Simulates a chat member starting or stopping to type.
    public func setPeerTyping(_ chatId: ChatId, user: UserId, typing: Bool) throws {
        var chat = try existingChat(chatId)
        guard chat.members.contains(user) else { throw GimError.notFound }
        chat.typing.removeAll { $0 == user }
        if typing { chat.typing.append(user) }
        chats[chatId] = chat
        let profiles = chat.typing.compactMap { users[$0] }
        typingSubscribers[chatId, default: []].deliver { $0.onTyping(chatId: chatId, users: profiles) }
    }

    // MARK: - Account

    public func loginState() async throws -> LoginState {
        session.map(LoginState.registered) ?? .unregistered
    }

    public func register(serverUrl: String, handle: String, displayName: String) async throws -> Session {
        let handle = handle.trimmingCharacters(in: .whitespaces).lowercased()
        let displayName = displayName.trimmingCharacters(in: .whitespaces)
        guard !serverUrl.isEmpty else { throw GimError.invalidInput("Server URL is required") }
        guard !handle.isEmpty, !handle.contains(where: \.isWhitespace) else {
            throw GimError.invalidInput("Handle must not be empty or contain spaces")
        }
        guard !displayName.isEmpty else { throw GimError.invalidInput("Display name is required") }
        let userId = "user-\(handle)"
        if users.values.contains(where: { $0.handle == handle && $0.userId != userId }) || users[userId] != nil {
            throw GimError.invalidInput("Handle is already taken")
        }
        let session = Session(
            userId: userId, deviceId: "device-1", handle: handle, displayName: displayName, serverUrl: serverUrl)
        users[userId] = UserProfile(userId: userId, handle: handle, displayName: displayName)
        self.session = session
        return session
    }

    public func logout() async throws {
        session = nil
        chats = [:]
        messageChats = [:]
        chatList = []
        chatListSubscribers.deliver { $0.onDiffs([.reset([])]) }
    }

    // MARK: - Users and chats

    public func findUser(handle: String) async throws -> UserProfile? {
        _ = try requireSession()
        let handle = handle.trimmingCharacters(in: .whitespaces).lowercased()
        return users.values.first { $0.handle == handle }
    }

    public func createDirectChat(with user: UserId) async throws -> ChatId {
        let session = try requireSession()
        guard user != session.userId else { throw GimError.invalidInput("You can't start a chat with yourself") }
        guard users[user] != nil else { throw GimError.notFound }
        if let existing = chats.values.first(where: { $0.kind == .direct && $0.members.contains(user) }) {
            return existing.id
        }
        let chat = StoredChat(
            id: makeId("chat"), kind: .direct, name: "", createdAt: now(), members: [session.userId, user])
        chats[chat.id] = chat
        publishChatListChange(chat.id)
        return chat.id
    }

    public func createGroupChat(name: String, members: [UserId]) async throws -> ChatId {
        let session = try requireSession()
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { throw GimError.invalidInput("Group name is required") }
        var memberIds = [session.userId]
        for member in members where !memberIds.contains(member) {
            guard users[member] != nil else { throw GimError.notFound }
            memberIds.append(member)
        }
        let chat = StoredChat(id: makeId("chat"), kind: .group, name: name, createdAt: now(), members: memberIds)
        chats[chat.id] = chat
        publishChatListChange(chat.id)
        return chat.id
    }

    public func chatDetails(_ chatId: ChatId) async throws -> ChatDetails {
        let session = try requireSession()
        let chat = try existingChat(chatId)
        let members = chat.members.compactMap { id in
            users[id].map { ChatMember(user: $0, isSelf: id == session.userId) }
        }
        return ChatDetails(summary: summary(of: chat), members: members)
    }

    public func addMember(_ chatId: ChatId, user: UserId) async throws {
        _ = try requireSession()
        var chat = try existingChat(chatId)
        guard chat.kind == .group else { throw GimError.invalidInput("Members can only be added to groups") }
        guard users[user] != nil else { throw GimError.notFound }
        guard !chat.members.contains(user) else { return }
        chat.members.append(user)
        chats[chatId] = chat
        publishChatListChange(chatId)
    }

    public func removeMember(_ chatId: ChatId, user: UserId) async throws {
        let session = try requireSession()
        var chat = try existingChat(chatId)
        guard chat.kind == .group else { throw GimError.invalidInput("Members can only be removed from groups") }
        guard user != session.userId else { throw GimError.invalidInput("You can't remove yourself") }
        guard chat.members.contains(user) else { throw GimError.notFound }
        chat.members.removeAll { $0 == user }
        chat.typing.removeAll { $0 == user }
        chats[chatId] = chat
        publishChatListChange(chatId)
    }

    // MARK: - Messages

    public func sendText(_ chatId: ChatId, text: String, replyTo: MessageId?) async throws -> MessageId {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GimError.invalidInput("Message is empty")
        }
        return try sendOwn(chatId, content: .text(text), replyTo: replyTo)
    }

    public func sendMedia(
        _ chatId: ChatId,
        filePath: String,
        mime: String,
        kind: MediaKind,
        caption: String?,
        replyTo: MessageId?,
        width: UInt32?,
        height: UInt32?
    ) async throws -> MessageId {
        _ = try requireSession()
        _ = try existingChat(chatId)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: filePath) else { throw GimError.invalidInput("File not found") }
        let mediaId = makeId("media")
        let fileName = URL(fileURLWithPath: filePath).lastPathComponent
        let directory = URL(fileURLWithPath: dataDirectory).appendingPathComponent("media", isDirectory: true)
        let destination = directory.appendingPathComponent("\(mediaId)-\(fileName)")
        let size: UInt64
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try fileManager.copyItem(atPath: filePath, toPath: destination.path)
            let attributes = try fileManager.attributesOfItem(atPath: destination.path)
            size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        } catch {
            throw GimError.internal("Could not store media: \(error)")
        }
        media[mediaId] = destination.path
        let info = MediaInfo(
            mediaId: mediaId, mime: mime, size: size, fileName: fileName, width: width, height: height,
            thumbnailPath: kind == .image ? destination.path : nil)
        let content: MessageContent =
            switch kind {
            case .image: .image(info, caption: caption)
            case .file: .file(info, caption: caption)
            }
        return try sendOwn(chatId, content: content, replyTo: replyTo)
    }

    public func edit(_ messageId: MessageId, text: String) async throws {
        _ = try requireSession()
        let stored = try existingMessage(messageId)
        guard stored.message.isOwn else { throw GimError.invalidInput("Only your own messages can be edited") }
        guard case .text = stored.message.content else { throw GimError.invalidInput("Only text can be edited") }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GimError.invalidInput("Message is empty")
        }
        let editedAt = now()
        updateMessage(messageId) {
            $0.message.content = .text(text)
            $0.message.editedAt = editedAt
        }
    }

    public func delete(_ messageId: MessageId) async throws {
        _ = try requireSession()
        let stored = try existingMessage(messageId)
        guard stored.message.isOwn else { throw GimError.invalidInput("Only your own messages can be deleted") }
        updateMessage(messageId) {
            $0.message.content = .deleted
            $0.message.replyTo = nil
            $0.message.editedAt = nil
            $0.reactions = []
        }
    }

    public func react(_ messageId: MessageId, emoji: String, remove: Bool) async throws {
        let session = try requireSession()
        let stored = try existingMessage(messageId)
        guard !emoji.isEmpty else { throw GimError.invalidInput("Reaction is empty") }
        guard stored.message.content != .deleted else { throw GimError.invalidInput("Message was deleted") }
        updateMessage(messageId) {
            Self.setReaction(&$0, emoji: emoji, user: session.userId, active: !remove, selfId: session.userId)
        }
    }

    public func retry(_ messageId: MessageId) async throws {
        _ = try requireSession()
        let stored = try existingMessage(messageId)
        guard case .failed = stored.message.sendState else { throw GimError.invalidInput("Message has not failed") }
        updateMessage(messageId) { $0.message.sendState = .pending }
        startDelivery(messageId)
    }

    public func markRead(_ chatId: ChatId) async throws {
        _ = try requireSession()
        var chat = try existingChat(chatId)
        guard chat.unreadCount > 0 else { return }
        chat.unreadCount = 0
        chats[chatId] = chat
        publishChatListChange(chatId)
    }

    public func setTyping(_ chatId: ChatId, typing: Bool) async throws {
        _ = try requireSession()
        _ = try existingChat(chatId)
    }

    public func loadOlder(_ chatId: ChatId, count: UInt32) async throws -> Bool {
        var chat = try existingChat(chatId)
        let hidden = chat.messages.count - chat.loadedCount
        let loaded = min(Int(count), hidden)
        guard loaded > 0 else { return hidden > 0 }
        let older = chat.messages[(hidden - loaded)..<hidden]
        chat.loadedCount += loaded
        chats[chatId] = chat
        let diffs = older.enumerated().map { offset, stored in
            TimelineDiff.insert(index: UInt32(offset), stored.message)
        }
        timelineSubscribers[chatId, default: []].deliver { $0.onDiffs(diffs) }
        return hidden - loaded > 0
    }

    public func fetchMedia(_ mediaId: MediaId) async throws -> String {
        guard let path = media[mediaId], FileManager.default.fileExists(atPath: path) else {
            throw GimError.notFound
        }
        return path
    }

    // MARK: - Connection

    public func setNetworkAvailable(_ available: Bool) async {
        networkAvailable = available
        if !available {
            setConnection(.offline)
        } else if connection == .offline {
            setConnection(.connecting)
            scheduler.schedule(after: .milliseconds(500)) { [weak self] in await self?.finishConnecting() }
        }
    }

    private func finishConnecting() {
        guard networkAvailable, connection == .connecting else { return }
        setConnection(.online)
        let waiting = waitingForNetwork
        waitingForNetwork = []
        for messageId in waiting { startDelivery(messageId) }
    }

    private func setConnection(_ state: ConnectionState) {
        guard connection != state else { return }
        connection = state
        connectionSubscribers.deliver { $0.onState(state) }
    }

    // MARK: - Subscriptions

    public func subscribeChatList(_ listener: any ChatListListener) async throws -> any SubscriptionHandle {
        let handle = FakeSubscription()
        let list = chatList
        handle.deliver { listener.onDiffs([.reset(list)]) }
        chatListSubscribers.append(Subscriber(handle: handle, listener: listener))
        return handle
    }

    public func subscribeTimeline(
        _ chatId: ChatId, _ listener: any TimelineListener
    ) async throws -> any SubscriptionHandle {
        let chat = try existingChat(chatId)
        let handle = FakeSubscription()
        let window = chat.messages.suffix(chat.loadedCount).map(\.message)
        handle.deliver { listener.onDiffs([.reset(window)]) }
        timelineSubscribers[chatId, default: []].append(Subscriber(handle: handle, listener: listener))
        return handle
    }

    public func subscribeConnection(_ listener: any ConnectionListener) async throws -> any SubscriptionHandle {
        let handle = FakeSubscription()
        let state = connection
        handle.deliver { listener.onState(state) }
        connectionSubscribers.append(Subscriber(handle: handle, listener: listener))
        return handle
    }

    public func subscribeTyping(
        _ chatId: ChatId, _ listener: any TypingListener
    ) async throws -> any SubscriptionHandle {
        let chat = try existingChat(chatId)
        let handle = FakeSubscription()
        let profiles = chat.typing.compactMap { users[$0] }
        handle.deliver { listener.onTyping(chatId: chatId, users: profiles) }
        typingSubscribers[chatId, default: []].append(Subscriber(handle: handle, listener: listener))
        return handle
    }

    // MARK: - Sending

    private func sendOwn(_ chatId: ChatId, content: MessageContent, replyTo: MessageId?) throws -> MessageId {
        let session = try requireSession()
        _ = try existingChat(chatId)
        let reply = try replyTo.map { try replyPreview(for: $0, in: chatId) }
        let message = TimelineMessage(
            id: makeId("msg"), chatId: chatId, senderId: session.userId, senderName: session.displayName,
            isOwn: true, timestamp: now(), content: content, replyTo: reply, sendState: .pending)
        append(StoredMessage(message: message))
        startDelivery(message.id)
        return message.id
    }

    private func startDelivery(_ messageId: MessageId) {
        guard networkAvailable else {
            waitingForNetwork.append(messageId)
            return
        }
        if sendFailuresRemaining > 0 {
            sendFailuresRemaining -= 1
            scheduler.schedule(after: .milliseconds(300)) { [weak self] in
                await self?.advance(messageId, to: .failed(reason: Self.failureReason))
            }
        } else {
            scheduler.schedule(after: .milliseconds(300)) { [weak self] in await self?.advance(messageId, to: .sent) }
        }
    }

    private func advance(_ messageId: MessageId, to state: SendState) {
        guard let stored = try? existingMessage(messageId), stored.message.content != .deleted else { return }
        updateMessage(messageId) { $0.message.sendState = state }
        switch state {
        case .sent:
            scheduler.schedule(after: .milliseconds(700)) { [weak self] in
                await self?.advance(messageId, to: .delivered)
            }
            scheduleAutoReply(stored.message.chatId)
        case .delivered:
            scheduler.schedule(after: .milliseconds(1500)) { [weak self] in await self?.advance(messageId, to: .read) }
        case .pending, .read, .failed:
            break
        }
    }

    private func scheduleAutoReply(_ chatId: ChatId) {
        guard autoReply, let session, let chat = chats[chatId], chat.kind == .direct,
            let peer = chat.members.first(where: { $0 != session.userId })
        else { return }
        scheduler.schedule(after: .seconds(1)) { [weak self] in
            try? await self?.setPeerTyping(chatId, user: peer, typing: true)
        }
        scheduler.schedule(after: .seconds(3)) { [weak self] in await self?.deliverAutoReply(chatId, from: peer) }
    }

    private func deliverAutoReply(_ chatId: ChatId, from peer: UserId) {
        try? setPeerTyping(chatId, user: peer, typing: false)
        let text = FakeDemoData.replies[nextReply % FakeDemoData.replies.count]
        nextReply += 1
        _ = try? receive(chatId, from: peer, content: .text(text))
    }

    private func receive(_ chatId: ChatId, from sender: UserId, content: MessageContent) throws -> MessageId {
        let session = try requireSession()
        var chat = try existingChat(chatId)
        guard sender != session.userId, chat.members.contains(sender), let profile = users[sender] else {
            throw GimError.notFound
        }
        chat.unreadCount += 1
        chats[chatId] = chat
        let message = TimelineMessage(
            id: makeId("msg"), chatId: chatId, senderId: sender, senderName: profile.displayName, isOwn: false,
            timestamp: now(), content: content)
        append(StoredMessage(message: message))
        return message.id
    }

    // MARK: - State helpers

    private func requireSession() throws -> Session {
        guard let session else { throw GimError.unauthorized }
        return session
    }

    private func existingChat(_ chatId: ChatId) throws -> StoredChat {
        guard let chat = chats[chatId] else { throw GimError.notFound }
        return chat
    }

    private func existingMessage(_ messageId: MessageId) throws -> StoredMessage {
        guard let chatId = messageChats[messageId],
            let stored = chats[chatId]?.messages.first(where: { $0.message.id == messageId })
        else { throw GimError.notFound }
        return stored
    }

    private func makeId(_ prefix: String) -> String {
        defer { nextId += 1 }
        return "\(prefix)-local-\(nextId)"
    }

    private func replyPreview(for messageId: MessageId, in chatId: ChatId) throws -> ReplyPreview {
        let target = try existingMessage(messageId).message
        guard target.chatId == chatId else { throw GimError.invalidInput("Reply target is in another chat") }
        return ReplyPreview(
            messageId: target.id, senderName: target.senderName, preview: Self.previewText(target.content))
    }

    private func append(_ stored: StoredMessage) {
        let chatId = stored.message.chatId
        guard var chat = chats[chatId] else { return }
        chat.messages.append(stored)
        chat.loadedCount += 1
        chats[chatId] = chat
        messageChats[stored.message.id] = chatId
        let diff = TimelineDiff.insert(index: UInt32(chat.loadedCount - 1), stored.message)
        timelineSubscribers[chatId, default: []].deliver { $0.onDiffs([diff]) }
        publishChatListChange(chatId)
    }

    private func updateMessage(_ messageId: MessageId, _ mutate: (inout StoredMessage) -> Void) {
        guard let chatId = messageChats[messageId], var chat = chats[chatId],
            let index = chat.messages.firstIndex(where: { $0.message.id == messageId })
        else { return }
        mutate(&chat.messages[index])
        chats[chatId] = chat
        let windowStart = chat.messages.count - chat.loadedCount
        if index >= windowStart {
            let diff = TimelineDiff.update(index: UInt32(index - windowStart), chat.messages[index].message)
            timelineSubscribers[chatId, default: []].deliver { $0.onDiffs([diff]) }
        }
        publishChatListChange(chatId)
    }

    /// Emits the diffs that move the published chat list to the current state after one chat changed.
    private func publishChatListChange(_ chatId: ChatId) {
        let newList = Self.sortedSummaries(chats: chats, users: users, session: session)
        let oldIndex = chatList.firstIndex { $0.id == chatId }
        let newIndex = newList.firstIndex { $0.id == chatId }
        var diffs: [ChatListDiff] = []
        switch (oldIndex, newIndex) {
        case (let old?, let new?) where old == new:
            if chatList[old] != newList[new] { diffs.append(.update(index: UInt32(new), newList[new])) }
        case (let old?, let new?):
            diffs.append(.remove(index: UInt32(old)))
            diffs.append(.insert(index: UInt32(new), newList[new]))
        case (nil, let new?):
            diffs.append(.insert(index: UInt32(new), newList[new]))
        case (let old?, nil):
            diffs.append(.remove(index: UInt32(old)))
        case (nil, nil):
            break
        }
        chatList = newList
        guard !diffs.isEmpty else { return }
        chatListSubscribers.deliver { $0.onDiffs(diffs) }
    }

    private func summary(of chat: StoredChat) -> ChatSummary {
        Self.summary(of: chat, users: users, session: session)
    }

    static func sortedSummaries(
        chats: [ChatId: StoredChat], users: [UserId: UserProfile], session: Session?
    ) -> [ChatSummary] {
        chats.values
            .map { (activity: $0.messages.last?.message.timestamp ?? $0.createdAt, chat: $0) }
            .sorted { lhs, rhs in
                lhs.activity != rhs.activity ? lhs.activity > rhs.activity : lhs.chat.id < rhs.chat.id
            }
            .map { summary(of: $0.chat, users: users, session: session) }
    }

    static func summary(of chat: StoredChat, users: [UserId: UserProfile], session: Session?) -> ChatSummary {
        let last = chat.messages.last?.message
        let title: String
        var avatarPath: String?
        switch chat.kind {
        case .group:
            title = chat.name
        case .direct:
            let peer = chat.members.first { $0 != session?.userId }.flatMap { users[$0] }
            title = peer?.displayName ?? chat.name
            avatarPath = peer?.avatarPath
        }
        return ChatSummary(
            id: chat.id, kind: chat.kind, title: title, avatarPath: avatarPath,
            lastMessagePreview: last.map { previewText($0.content) }, lastMessageSenderName: last?.senderName,
            lastMessageAt: last?.timestamp, unreadCount: chat.unreadCount, memberCount: UInt32(chat.members.count))
    }

    static func previewText(_ content: MessageContent) -> String {
        switch content {
        case .text(let text): text
        case .image(_, let caption): caption.map { "Photo: \($0)" } ?? "Photo"
        case .file(let info, _): info.fileName ?? "File"
        case .deleted: "Message deleted"
        case .unsupported: "Unsupported message"
        }
    }

    static func setReaction(
        _ stored: inout StoredMessage, emoji: String, user: UserId, active: Bool, selfId: UserId
    ) {
        if let index = stored.reactions.firstIndex(where: { $0.emoji == emoji }) {
            stored.reactions[index].users.removeAll { $0 == user }
            if active { stored.reactions[index].users.append(user) }
            if stored.reactions[index].users.isEmpty { stored.reactions.remove(at: index) }
        } else if active {
            stored.reactions.append(Reaction(emoji: emoji, users: [user]))
        }
        stored.message.reactions = stored.reactions.map {
            ReactionGroup(emoji: $0.emoji, count: UInt32($0.users.count), includesMe: $0.users.contains(selfId))
        }
    }
}
