import Foundation
import GIMClientKit
import GIMCore

/// Creates clients backed by gim-core (`GIMCore.createClient`).
public struct RealGimClientFactory: GimClientFactory {
    public init() {}

    public func make(
        config: GIMClientKit.ClientConfig, hooks: any GIMClientKit.PlatformHooks
    ) async throws -> any GimClientAPI {
        let core = try await bridged {
            try await GIMCore.createClient(config: GIMCore.ClientConfig(config), hooks: CorePlatformHooks(hooks))
        }
        return RealGimClient(core)
    }
}

/// Adapts gim-core's generated `GimClient` to `GimClientAPI`: converts every value 1:1, rethrows `GimError`s as
/// the mirror type and delivers listener callbacks on the main queue.
public final class RealGimClient: GimClientAPI {
    private let core: GIMCore.GimClient

    init(_ core: GIMCore.GimClient) {
        self.core = core
    }

    public func session() async throws -> GIMClientKit.Session? {
        try await bridged { try await core.session().map { GIMClientKit.Session($0) } }
    }

    public func register(handle: String, displayName: String) async throws -> GIMClientKit.Session {
        try await bridged { try await GIMClientKit.Session(core.register(handle: handle, displayName: displayName)) }
    }

    public func signOut() async throws {
        try await bridged { try await core.signOut() }
    }

    public func startSync() async throws {
        try await bridged { try await core.startSync() }
    }

    public func stopSync() async throws {
        try await bridged { try await core.stopSync() }
    }

    public func setNetworkReachable(reachable: Bool) {
        core.setNetworkReachable(reachable: reachable)
    }

    public func findUser(handle: String) async throws -> GIMClientKit.UserProfile? {
        try await bridged { try await core.findUser(handle: handle).map { GIMClientKit.UserProfile($0) } }
    }

    public func createDirectChat(userId: String) async throws -> String {
        try await bridged { try await core.createDirectChat(userId: userId) }
    }

    public func createGroupChat(name: String, memberUserIds: [String]) async throws -> String {
        try await bridged { try await core.createGroupChat(name: name, memberUserIds: memberUserIds) }
    }

    public func chatMembers(chatId: String) async throws -> [GIMClientKit.UserProfile] {
        try await bridged { try await core.chatMembers(chatId: chatId).map { GIMClientKit.UserProfile($0) } }
    }

    public func addMembers(chatId: String, userIds: [String]) async throws {
        try await bridged { try await core.addMembers(chatId: chatId, userIds: userIds) }
    }

    public func removeMember(chatId: String, userId: String) async throws {
        try await bridged { try await core.removeMember(chatId: chatId, userId: userId) }
    }

    public func leaveChat(chatId: String) async throws {
        try await bridged { try await core.leaveChat(chatId: chatId) }
    }

    public func setGroupInfo(chatId: String, name: String?, avatarFilePath: String?) async throws {
        try await bridged { try await core.setGroupInfo(chatId: chatId, name: name, avatarFilePath: avatarFilePath) }
    }

    public func sendText(chatId: String, body: String, replyTo: String?) async throws -> String {
        try await bridged { try await core.sendText(chatId: chatId, body: body, replyTo: replyTo) }
    }

    public func sendMedia(
        chatId: String, filePath: String, mime: String, caption: String?, replyTo: String?
    ) async throws -> String {
        try await bridged {
            try await core.sendMedia(chatId: chatId, filePath: filePath, mime: mime, caption: caption, replyTo: replyTo)
        }
    }

    public func editMessage(chatId: String, messageId: String, newBody: String) async throws {
        try await bridged { try await core.editMessage(chatId: chatId, messageId: messageId, newBody: newBody) }
    }

    public func deleteMessage(chatId: String, messageId: String) async throws {
        try await bridged { try await core.deleteMessage(chatId: chatId, messageId: messageId) }
    }

    public func react(chatId: String, messageId: String, emoji: String) async throws {
        try await bridged { try await core.react(chatId: chatId, messageId: messageId, emoji: emoji) }
    }

    public func unreact(chatId: String, messageId: String, emoji: String) async throws {
        try await bridged { try await core.unreact(chatId: chatId, messageId: messageId, emoji: emoji) }
    }

    public func retrySend(chatId: String, messageId: String) async throws {
        try await bridged { try await core.retrySend(chatId: chatId, messageId: messageId) }
    }

    public func cancelSend(chatId: String, messageId: String) async throws {
        try await bridged { try await core.cancelSend(chatId: chatId, messageId: messageId) }
    }

    public func markRead(chatId: String, upToMessageId: String) async throws {
        try await bridged { try await core.markRead(chatId: chatId, upToMessageId: upToMessageId) }
    }

    public func setTyping(chatId: String, active: Bool) async throws {
        try await bridged { try await core.setTyping(chatId: chatId, active: active) }
    }

    public func fetchMedia(chatId: String, messageId: String, destPath: String) async throws -> String {
        try await bridged { try await core.fetchMedia(chatId: chatId, messageId: messageId, destPath: destPath) }
    }

    public func fetchThumbnail(chatId: String, messageId: String, destPath: String) async throws -> String? {
        try await bridged { try await core.fetchThumbnail(chatId: chatId, messageId: messageId, destPath: destPath) }
    }

    public func chatList(listener: any GIMClientKit.ChatListListener) async throws -> GIMClientKit.TaskHandle {
        let relay = MainQueueRelay()
        let handle = try await bridged {
            try await core.chatList(listener: CoreChatListListener(listener, relay: relay))
        }
        return relay.handle(handle)
    }

    public func timeline(chatId: String) async throws -> any GIMClientKit.Timeline {
        try await bridged { try await RealTimeline(core.timeline(chatId: chatId)) }
    }

    public func connectionState(
        listener: any GIMClientKit.ConnectionStateListener
    ) async throws -> GIMClientKit.TaskHandle {
        let relay = MainQueueRelay()
        let handle = try await bridged {
            try await core.connectionState(listener: CoreConnectionStateListener(listener, relay: relay))
        }
        return relay.handle(handle)
    }

    public func typing(
        chatId: String, listener: any GIMClientKit.TypingListener
    ) async throws -> GIMClientKit.TaskHandle {
        let relay = MainQueueRelay()
        let handle = try await bridged {
            try await core.typing(chatId: chatId, listener: CoreTypingListener(listener, relay: relay))
        }
        return relay.handle(handle)
    }
}

/// Adapts gim-core's generated `Timeline` object to the mirror `Timeline` protocol.
final class RealTimeline: GIMClientKit.Timeline {
    private let core: GIMCore.Timeline

    init(_ core: GIMCore.Timeline) {
        self.core = core
    }

    func chatId() -> String {
        core.chatId()
    }

    func addListener(listener: any GIMClientKit.TimelineListener) async -> GIMClientKit.TaskHandle {
        let relay = MainQueueRelay()
        return relay.handle(await core.addListener(listener: CoreTimelineListener(listener, relay: relay)))
    }

    func paginateBackwards(count: UInt16) async throws -> Bool {
        try await bridged { try await core.paginateBackwards(count: count) }
    }
}
