import Foundation
import GIMClientKit
import Observation

/// One chat's timeline: the display items, older-history pagination, typing, read receipts, retries, media files and
/// the chat's state.
///
/// The items are rebuilt from gim-core's timeline (kept with `DiffApplier`) on every change; `onChange` reports the
/// difference so the timeline view can run batch updates.
@MainActor
@Observable
public final class TimelineViewModel {
    public let chatId: String
    /// The chat name; empty until the chat list arrives.
    public private(set) var title = ""
    public private(set) var isGroup = false
    public private(set) var items: [TimelineDisplayItem] = []
    /// The change that produced `items`.
    public private(set) var lastChange = TimelineChangeSet.reset
    /// Who is typing, for the navigation subtitle; the same text is in the typing row.
    public private(set) var typingText: String?
    /// True until the first timeline arrives.
    public private(set) var isLoading = true
    /// Whether gim-core may have older history; false once `paginateBackwards` reports none.
    public private(set) var hasMore = true
    public private(set) var isLoadingOlder = false
    public private(set) var errorMessage: String?
    /// Last message a read receipt was sent for.
    public private(set) var markedReadUpTo: String?
    /// Where this device stands in the chat, from `Timeline.chatState()`, the chat list and `ChatNotActive` errors;
    /// `nil` until known.
    public private(set) var chatState: ChatState?

    /// Leaving or left: nothing can be sent or changed.
    public var isReadOnly: Bool {
        chatState == .leaving || chatState == .left
    }

    /// Called after `items` changed, on the main actor.
    @ObservationIgnored public var onChange: ((TimelineChangeSet) -> Void)?

    private let client: any GimClientAPI
    private let builder: TimelineItemBuilder
    private let mediaDirectory: String
    private let pageSize: UInt16
    @ObservationIgnored private var timeline: (any Timeline)?
    @ObservationIgnored private var source: [TimelineItem] = []
    @ObservationIgnored private var chatList: [ChatSummary] = []
    @ObservationIgnored private var typingUserIds: [String] = []
    /// Display names by user id, from the members and the loaded messages.
    @ObservationIgnored private var names: [String: String] = [:]
    /// Messages whose attachment couldn't be downloaded for now; see `isTemporaryMediaFailure(_:)`.
    @ObservationIgnored private var unavailableMedia: Set<String> = []
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    /// - Parameter mediaDirectory: where fetched media files are kept; defaults to the caches directory.
    public init(
        client: any GimClientAPI, chatId: String, builder: TimelineItemBuilder = TimelineItemBuilder(),
        mediaDirectory: String? = nil, pageSize: UInt16 = 30
    ) {
        self.client = client
        self.chatId = chatId
        self.builder = builder
        self.mediaDirectory = mediaDirectory ?? Self.defaultMediaDirectory
        self.pageSize = pageSize
    }

    deinit {
        for task in tasks { task.cancel() }
    }

    // MARK: - Subscriptions

    /// Subscribes to the timeline, typing and the chat's summary. Does nothing while already subscribed.
    public func start() {
        guard tasks.isEmpty else { return }
        errorMessage = nil
        let client = client
        let chatId = chatId
        tasks.append(
            Task { [weak self] in
                do {
                    let timeline = try await client.timeline(chatId: chatId)
                    self?.timeline = timeline
                    // From local state: right after a restart, before any diff.
                    self?.updateChatState(timeline.chatState())
                    for await diffs in await Self.stream(timeline) {
                        self?.apply(diffs)
                    }
                } catch {
                    self?.fail(error)
                }
            })
        tasks.append(
            Task { [weak self] in
                guard let stream = try? await ListenerBridge.typing(client, chatId: chatId) else { return }
                for await userIds in stream {
                    self?.updateTyping(userIds)
                }
            })
        tasks.append(
            Task { [weak self] in
                guard let stream = try? await ListenerBridge.chatList(client) else { return }
                for await diffs in stream {
                    self?.applyChatList(diffs)
                }
            })
        tasks.append(
            Task { [weak self] in
                // Best effort: only used for typing and membership names.
                guard let members = try? await client.chatMembers(chatId: chatId) else { return }
                self?.learnNames(members)
            })
    }

    public func stop() {
        for task in tasks { task.cancel() }
        tasks = []
        timeline = nil
    }

    // MARK: - Actions

    /// Loads one page of older history. Ignored while a load runs or when there is no more history.
    public func loadOlder() async {
        guard !isLoadingOlder, hasMore, let timeline else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        do {
            hasMore = try await timeline.paginateBackwards(count: pageSize)
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// Sends a read receipt up to the newest incoming message when the bottom of the timeline is visible and the app
    /// is active. Each message is marked at most once.
    public func markReadIfNeeded(bottomVisible: Bool, appActive: Bool) async {
        guard bottomVisible, appActive, let newest = newestIncomingMessageId, newest != markedReadUpTo else { return }
        markedReadUpTo = newest
        do {
            try await client.markRead(chatId: chatId, upToMessageId: newest)
        } catch {
            if markedReadUpTo == newest { markedReadUpTo = nil }
        }
    }

    /// Sends a failed message again.
    public func retry(messageId: String) async {
        do {
            try await client.retrySend(chatId: chatId, messageId: messageId)
        } catch {
            guard !handleChatNotActive(error) else { return }
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// Takes the state from a `ChatNotActive` error, which makes the chat read-only instead of showing an error.
    /// Returns whether `error` was one; other errors are left to the caller.
    @discardableResult
    public func handleChatNotActive(_ error: any Error) -> Bool {
        guard case .ChatNotActive(_, let state) = error as? GimError else { return false }
        updateChatState(state)
        return true
    }

    public func dismissError() {
        errorMessage = nil
    }

    public func message(withId messageId: String) -> MessageItem? {
        items.first { $0.id == TimelineDisplayItem.id(forMessage: messageId) }?.messageRow?.message
    }

    // MARK: - Media

    /// Local path of the attachment's thumbnail, fetched on first use; `nil` if it has none or fetching failed.
    public func thumbnailPath(for media: MediaRef) async -> String? {
        guard media.hasThumbnail, let destination = try? mediaPath(media, name: "thumbnail") else { return nil }
        if FileManager.default.fileExists(atPath: destination) { return destination }
        return try? await client.fetchThumbnail(
            chatId: media.chatId, messageId: media.messageId, destPath: destination)
    }

    /// Local path of the decrypted attachment, fetched on first use. `fileName` keeps the extension QuickLook needs.
    /// A temporary failure marks the message's row `isMediaUnavailable` until `retryMedia(messageId:)`.
    public func mediaFilePath(for media: MediaRef, fileName: String?) async throws -> String {
        let destination = try mediaPath(media, name: fileName.map(Self.safeComponent) ?? "media")
        if FileManager.default.fileExists(atPath: destination) { return destination }
        do {
            return try await client.fetchMedia(chatId: media.chatId, messageId: media.messageId, destPath: destination)
        } catch {
            if Self.isTemporaryMediaFailure(error), unavailableMedia.insert(media.messageId).inserted {
                rebuild(isReset: false)
            }
            throw error
        }
    }

    /// Clears the row's `isMediaUnavailable` so the cell fetches the attachment again.
    public func retryMedia(messageId: String) {
        guard unavailableMedia.remove(messageId) != nil else { return }
        rebuild(isReset: false)
    }

    /// gim-core fetches a blob uploaded on another hub through the own hub and gives up with `RetryLater(503)` while
    /// that hub stays unreachable or `Server(502)` while it keeps refusing; both may succeed later.
    public nonisolated static func isTemporaryMediaFailure(_ error: any Error) -> Bool {
        switch error as? GimError {
        case .RetryLater: true
        case .Server(let status, _): status == 502 || status == 503
        default: false
        }
    }

    // MARK: - Private

    private var newestIncomingMessageId: String? {
        for item in source.reversed() {
            if case .message(let message) = item, !message.isOwn { return message.messageId }
        }
        return nil
    }

    private func apply(_ diffs: [TimelineDiff]) {
        let change: ListChangeSet
        do {
            change = try DiffApplier.apply(diffs, to: &source)
        } catch {
            // Out of sync with the core; a new subscription starts with a reset.
            refresh()
            return
        }
        isLoading = false
        updateChatState(timeline?.chatState())
        for item in source {
            switch item {
            case .message(let message) where names[message.sender.userId] == nil:
                names[message.sender.userId] = UserLabel.name(for: message.sender)
            case .membershipChange(let userName, _, _, let userId, _) where names[userId] == nil:
                names[userId] = UserLabel.name(userName)
            default:
                break
            }
        }
        rebuild(isReset: change.isReset)
    }

    private func refresh() {
        stop()
        hasMore = true
        start()
    }

    private func updateTyping(_ userIds: [String]) {
        typingUserIds = userIds
        rebuild(isReset: false)
    }

    private func learnNames(_ users: [UserProfile]) {
        for user in users { names[user.userId] = UserLabel.name(for: user) }
        // Typing and membership rows name users.
        rebuild(isReset: false)
    }

    private func applyChatList(_ diffs: [ChatListDiff]) {
        guard (try? DiffApplier.apply(diffs, to: &chatList)) != nil,
            let summary = chatList.first(where: { $0.chatId == chatId })
        else { return }
        title = summary.name
        updateChatState(summary.state)
        if isGroup != (summary.kind == .group) {
            isGroup = summary.kind == .group
            rebuild(isReset: false)
        }
    }

    private func updateChatState(_ state: ChatState?) {
        guard let state, state != chatState else { return }
        chatState = state
    }

    private func rebuild(isReset: Bool) {
        typingText = TimelineItemBuilder.typingText(names: typingUserIds.map { names[$0] ?? "Someone" })
        let newItems = builder.build(
            source, isGroup: isGroup, typingText: typingText, unavailableMedia: unavailableMedia,
            ownUserId: client.userId(), names: names)
        let change = TimelineChangeSet(from: items, to: newItems, isReset: isReset)
        guard !change.isEmpty else { return }
        items = newItems
        lastChange = change
        onChange?(change)
    }

    private func fail(_ error: any Error) {
        isLoading = false
        errorMessage = ErrorPresenter.message(for: error)
    }

    private func mediaPath(_ media: MediaRef, name: String) throws -> String {
        let directory = URL(fileURLWithPath: mediaDirectory, isDirectory: true)
            .appendingPathComponent(Self.safeComponent(media.chatId), isDirectory: true)
            .appendingPathComponent(Self.safeComponent(media.messageId), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(name).path
    }

    private static func safeComponent(_ value: String) -> String {
        let cleaned = value.replacingOccurrences(of: "/", with: "_")
        return cleaned.isEmpty || cleaned.hasPrefix(".") ? "_\(cleaned)" : cleaned
    }

    private static var defaultMediaDirectory: String {
        let caches =
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("gim-media", isDirectory: true).path
    }

    private static func stream(_ timeline: any Timeline) async -> AsyncStream<[TimelineDiff]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [TimelineDiff].self)
        let handle = await timeline.addListener(listener: TimelineDiffListener(continuation))
        continuation.onTermination = { _ in handle.cancel() }
        return stream
    }
}

/// Feeds one `Timeline` object into a stream, so pagination and the subscription use the same object.
private final class TimelineDiffListener: TimelineListener {
    let continuation: AsyncStream<[TimelineDiff]>.Continuation
    init(_ continuation: AsyncStream<[TimelineDiff]>.Continuation) { self.continuation = continuation }
    func onUpdate(diffs: [TimelineDiff]) { continuation.yield(diffs) }
}
