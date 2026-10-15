import GIMClientKit

/// Turns gim-core listener callbacks into `AsyncStream`s for ViewModels.
///
/// Each stream starts with the current state (the subscription's initial `reset`). Ending iteration (or cancelling
/// the consuming task) cancels the underlying subscription.
public enum ListenerBridge {
    public static func chatList(_ client: any GimClientAPI) async throws -> AsyncStream<[ChatListDiff]> {
        try await stream { continuation in
            try await client.subscribeChatList(ChatListStreamListener(continuation))
        }
    }

    public static func timeline(
        _ client: any GimClientAPI, chatId: ChatId
    ) async throws -> AsyncStream<[TimelineDiff]> {
        try await stream { continuation in
            try await client.subscribeTimeline(chatId, TimelineStreamListener(continuation))
        }
    }

    public static func connection(_ client: any GimClientAPI) async throws -> AsyncStream<ConnectionState> {
        try await stream { continuation in
            try await client.subscribeConnection(ConnectionStreamListener(continuation))
        }
    }

    public static func typing(_ client: any GimClientAPI, chatId: ChatId) async throws -> AsyncStream<[UserProfile]> {
        try await stream { continuation in
            try await client.subscribeTyping(chatId, TypingStreamListener(continuation))
        }
    }

    private static func stream<Value: Sendable>(
        _ subscribe: (AsyncStream<Value>.Continuation) async throws -> any SubscriptionHandle
    ) async throws -> AsyncStream<Value> {
        let (stream, continuation) = AsyncStream.makeStream(of: Value.self)
        do {
            let handle = try await subscribe(continuation)
            continuation.onTermination = { _ in handle.cancel() }
        } catch {
            continuation.finish()
            throw error
        }
        return stream
    }
}

private final class ChatListStreamListener: ChatListListener {
    let continuation: AsyncStream<[ChatListDiff]>.Continuation
    init(_ continuation: AsyncStream<[ChatListDiff]>.Continuation) { self.continuation = continuation }
    func onDiffs(_ diffs: [ChatListDiff]) { continuation.yield(diffs) }
}

private final class TimelineStreamListener: TimelineListener {
    let continuation: AsyncStream<[TimelineDiff]>.Continuation
    init(_ continuation: AsyncStream<[TimelineDiff]>.Continuation) { self.continuation = continuation }
    func onDiffs(_ diffs: [TimelineDiff]) { continuation.yield(diffs) }
}

private final class ConnectionStreamListener: ConnectionListener {
    let continuation: AsyncStream<ConnectionState>.Continuation
    init(_ continuation: AsyncStream<ConnectionState>.Continuation) { self.continuation = continuation }
    func onState(_ state: ConnectionState) { continuation.yield(state) }
}

private final class TypingStreamListener: TypingListener {
    let continuation: AsyncStream<[UserProfile]>.Continuation
    init(_ continuation: AsyncStream<[UserProfile]>.Continuation) { self.continuation = continuation }
    func onTyping(chatId: ChatId, users: [UserProfile]) { continuation.yield(users) }
}
