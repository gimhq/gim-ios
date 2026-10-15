import Foundation
import GIMCore
import UIKit

/// A second gim-core client that runs inside the UI test runner and plays the other side of the conversation. It
/// has its own temporary data directory and keeps its secrets in memory, so every run starts from a fresh device.
final class ScriptedPeer: Sendable {
    let session: Session
    private let client: GimClient
    private let directory: URL
    private let chats = ChatListCollector()
    private let timelines = TimelineStore()

    private init(session: Session, client: GimClient, directory: URL) {
        self.session = session
        self.client = client
        self.directory = directory
    }

    /// Creates an identity on `serverUrl`, claims `handle`, starts syncing and follows the chat list.
    static func register(serverUrl: String, handle: String, displayName: String) async throws -> ScriptedPeer {
        let (client, directory) = try await makeClient(serverUrl: serverUrl)
        _ = try await client.createIdentity(displayName: displayName)
        try await client.claimHandle(handle: handle)
        guard let session = try await client.session() else { throw GimError.NotRegistered }
        try await client.startSync()
        let peer = ScriptedPeer(session: session, client: client, directory: directory)
        peer.chats.handle = try await client.chatList(listener: peer.chats)
        return peer
    }

    /// Stops syncing and removes the data directory.
    func shutdown() async {
        chats.handle?.cancel()
        timelines.cancelAll()
        try? await client.stopSync()
        try? FileManager.default.removeItem(at: directory)
    }

    /// The id of the chat named `name`, once the peer has joined it.
    func chatId(named name: String) -> String? {
        chats.current.first { $0.name == name }?.chatId
    }

    /// The messages of `chatId`, oldest first. The first call subscribes to the timeline, so it may return an
    /// empty list until gim-core delivers the first diff.
    func messages(in chatId: String) async throws -> [MessageItem] {
        if let collector = timelines.collector(for: chatId) { return collector.messages }
        let collector = TimelineCollector()
        let timeline = try await client.timeline(chatId: chatId)
        collector.handle = await timeline.addListener(listener: collector)
        timelines.add(collector, timeline: timeline, for: chatId)
        return collector.messages
    }

    func sendText(chatId: String, body: String, replyTo: String? = nil) async throws -> String {
        try await client.sendText(chatId: chatId, body: body, replyTo: replyTo)
    }

    /// Sends a small generated PNG.
    func sendImage(chatId: String) async throws -> String {
        let url = directory.appendingPathComponent("peer-\(UUID().uuidString).png")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 96, height: 64)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 96, height: 64))
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 24, y: 16, width: 48, height: 32))
        }
        try image.pngData()!.write(to: url)
        return try await client.sendMedia(
            chatId: chatId, filePath: url.path, mime: "image/png", caption: nil, replyTo: nil)
    }

    func markRead(chatId: String, upToMessageId: String) async throws {
        try await client.markRead(chatId: chatId, upToMessageId: upToMessageId)
    }
}

/// A fresh gim-core client in the UI test runner that links itself as a new device of the app's user: it plays the
/// new-device side of gim-core's device link flow (`startLink`, `waitLink`, `confirmLink`) against the app as the
/// old device.
final class ScriptedLinkingDevice: Sendable {
    /// The link code to paste into the app (the QR code's text).
    let qrString: String
    private let client: GimClient
    private let link: LinkSession
    private let directory: URL

    private init(client: GimClient, link: LinkSession, directory: URL) {
        self.client = client
        self.link = link
        self.directory = directory
        qrString = link.qrString()
    }

    /// Starts a link on a new client without a session; the old device may post the bundle to `serverUrl`.
    static func startLink(serverUrl: String) async throws -> ScriptedLinkingDevice {
        let (client, directory) = try await makeClient(serverUrl: serverUrl)
        let link = try client.startLink(hubs: [serverUrl])
        return ScriptedLinkingDevice(client: client, link: link, directory: directory)
    }

    /// Waits for the old device's approval, signs in as the new device and returns the SAS to compare.
    func waitLink() async throws -> String {
        try await client.waitLink(link: link)
    }

    func confirmLink(accepted: Bool) async throws {
        try await client.confirmLink(accepted: accepted)
    }

    /// The session once `waitLink` signed in.
    func session() async throws -> Session? {
        try await client.session()
    }

    /// The devices of the user this device is linked to.
    func devices() async throws -> [DeviceInfo] {
        try await client.devices()
    }

    /// Stops syncing and removes the data directory.
    func shutdown() async {
        try? await client.stopSync()
        try? FileManager.default.removeItem(at: directory)
    }
}

/// A gim-core client with its own temporary data directory and in-memory secrets.
private func makeClient(serverUrl: String) async throws -> (GimClient, URL) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("gim-peer-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let client = try await createClient(
        config: ClientConfig(serverUrl: serverUrl), hooks: InMemoryPlatformHooks(dataDirectory: directory.path))
    return (client, directory)
}

/// Secrets in a dictionary instead of the Keychain; they disappear with the test process.
private final class InMemoryPlatformHooks: PlatformHooks, @unchecked Sendable {
    private let lock = NSLock()
    private var secrets: [String: Data] = [:]
    private let dataDirectory: String

    init(dataDirectory: String) {
        self.dataDirectory = dataDirectory
    }

    func secureStoreGet(key: String) throws -> Data? {
        lock.withLock { secrets[key] }
    }

    func secureStoreSet(key: String, value: Data) throws {
        lock.withLock { secrets[key] = value }
    }

    func secureStoreDelete(key: String) {
        lock.withLock { secrets[key] = nil }
    }

    func dataDir() -> String {
        dataDirectory
    }

    func isNetworkReachable() -> Bool {
        true
    }
}

/// The peer's chat list, kept up to date from gim-core's diffs (delivered on a background thread).
private final class ChatListCollector: ChatListListener, @unchecked Sendable {
    private let lock = NSLock()
    private var chats: [ChatSummary] = []
    private var taskHandle: TaskHandle?

    var current: [ChatSummary] { lock.withLock { chats } }

    var handle: TaskHandle? {
        get { lock.withLock { taskHandle } }
        set { lock.withLock { taskHandle = newValue } }
    }

    func onUpdate(diffs: [ChatListDiff]) {
        lock.withLock {
            for diff in diffs {
                switch diff {
                case .append(let values): chats.apply(.append(values))
                case .clear: chats.apply(.clear)
                case .pushFront(let value): chats.apply(.pushFront(value))
                case .pushBack(let value): chats.apply(.pushBack(value))
                case .popFront: chats.apply(.popFront)
                case .popBack: chats.apply(.popBack)
                case .insert(let index, let value): chats.apply(.insert(Int(index), value))
                case .set(let index, let value): chats.apply(.set(Int(index), value))
                case .remove(let index): chats.apply(.remove(Int(index)))
                case .truncate(let length): chats.apply(.truncate(Int(length)))
                case .reset(let values): chats.apply(.reset(values))
                }
            }
        }
    }
}

/// The items of one timeline, kept up to date from gim-core's diffs (delivered on a background thread).
private final class TimelineCollector: TimelineListener, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [TimelineItem] = []
    private var taskHandle: TaskHandle?

    var messages: [MessageItem] {
        lock.withLock {
            items.compactMap { item -> MessageItem? in
                if case .message(let message) = item { return message }
                return nil
            }
        }
    }

    var handle: TaskHandle? {
        get { lock.withLock { taskHandle } }
        set { lock.withLock { taskHandle = newValue } }
    }

    func onUpdate(diffs: [TimelineDiff]) {
        lock.withLock {
            for diff in diffs {
                switch diff {
                case .append(let values): items.apply(.append(values))
                case .clear: items.apply(.clear)
                case .pushFront(let value): items.apply(.pushFront(value))
                case .pushBack(let value): items.apply(.pushBack(value))
                case .popFront: items.apply(.popFront)
                case .popBack: items.apply(.popBack)
                case .insert(let index, let value): items.apply(.insert(Int(index), value))
                case .set(let index, let value): items.apply(.set(Int(index), value))
                case .remove(let index): items.apply(.remove(Int(index)))
                case .truncate(let length): items.apply(.truncate(Int(length)))
                case .reset(let values): items.apply(.reset(values))
                }
            }
        }
    }
}

/// Timeline subscriptions by chat id; the `Timeline` objects are kept so their listeners stay alive.
private final class TimelineStore: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: (collector: TimelineCollector, timeline: Timeline)] = [:]

    func collector(for chatId: String) -> TimelineCollector? {
        lock.withLock { entries[chatId]?.collector }
    }

    func add(_ collector: TimelineCollector, timeline: Timeline, for chatId: String) {
        lock.withLock { entries[chatId] = (collector, timeline) }
    }

    func cancelAll() {
        lock.withLock {
            for entry in entries.values { entry.collector.handle?.cancel() }
            entries = [:]
        }
    }
}

/// The cases shared by `ChatListDiff` and `TimelineDiff`.
private enum ListChange<Element> {
    case append([Element])
    case clear
    case pushFront(Element)
    case pushBack(Element)
    case popFront
    case popBack
    case insert(Int, Element)
    case set(Int, Element)
    case remove(Int)
    case truncate(Int)
    case reset([Element])
}

extension Array {
    fileprivate mutating func apply(_ change: ListChange<Element>) {
        switch change {
        case .append(let values): append(contentsOf: values)
        case .clear: removeAll()
        case .pushFront(let value): insert(value, at: 0)
        case .pushBack(let value): append(value)
        case .popFront: if !isEmpty { removeFirst() }
        case .popBack: if !isEmpty { removeLast() }
        case .insert(let index, let value): insert(value, at: Swift.min(index, count))
        case .set(let index, let value): if indices.contains(index) { self[index] = value }
        case .remove(let index): if indices.contains(index) { remove(at: index) }
        case .truncate(let length): if length < count { removeSubrange(length...) }
        case .reset(let values): self = values
        }
    }
}
