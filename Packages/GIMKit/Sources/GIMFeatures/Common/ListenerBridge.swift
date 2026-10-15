import GIMClientKit

/// Turns gim-core listener callbacks into `AsyncStream`s for ViewModels.
///
/// gim-core calls listeners on a Rust background thread. The listeners only enqueue into the stream, which keeps
/// the callback order; a ViewModel iterating the stream from a `@MainActor` task receives every batch on the main
/// actor. Each stream starts with the current state (the subscription's initial `reset` or value). The stream keeps
/// the `TaskHandle` alive; ending iteration (or cancelling the consuming task) cancels the subscription.
public enum ListenerBridge {
    public static func chatList(_ client: any GimClientAPI) async throws -> AsyncStream<[ChatListDiff]> {
        try await stream { continuation in
            try await client.chatList(listener: ChatListStreamListener(continuation))
        }
    }

    public static func timeline(
        _ client: any GimClientAPI, chatId: String
    ) async throws -> AsyncStream<[TimelineDiff]> {
        let timeline = try await client.timeline(chatId: chatId)
        return try await stream { continuation in
            await timeline.addListener(listener: TimelineStreamListener(continuation))
        }
    }

    public static func connectionState(_ client: any GimClientAPI) async throws -> AsyncStream<ConnectionState> {
        try await stream { continuation in
            try await client.connectionState(listener: ConnectionStateStreamListener(continuation))
        }
    }

    /// User ids of the people typing, never the signed-in user.
    public static func typing(_ client: any GimClientAPI, chatId: String) async throws -> AsyncStream<[String]> {
        try await stream { continuation in
            try await client.typing(chatId: chatId, listener: TypingStreamListener(continuation))
        }
    }

    private static func stream<Value: Sendable>(
        _ subscribe: (AsyncStream<Value>.Continuation) async throws -> TaskHandle
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
    func onUpdate(diffs: [ChatListDiff]) { continuation.yield(diffs) }
}

private final class TimelineStreamListener: TimelineListener {
    let continuation: AsyncStream<[TimelineDiff]>.Continuation
    init(_ continuation: AsyncStream<[TimelineDiff]>.Continuation) { self.continuation = continuation }
    func onUpdate(diffs: [TimelineDiff]) { continuation.yield(diffs) }
}

private final class ConnectionStateStreamListener: ConnectionStateListener {
    let continuation: AsyncStream<ConnectionState>.Continuation
    init(_ continuation: AsyncStream<ConnectionState>.Continuation) { self.continuation = continuation }
    func onChange(state: ConnectionState) { continuation.yield(state) }
}

private final class TypingStreamListener: TypingListener {
    let continuation: AsyncStream<[String]>.Continuation
    init(_ continuation: AsyncStream<[String]>.Continuation) { self.continuation = continuation }
    func onUpdate(userIds: [String]) { continuation.yield(userIds) }
}
