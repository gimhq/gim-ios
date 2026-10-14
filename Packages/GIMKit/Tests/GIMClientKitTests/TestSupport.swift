import Foundation
import GIMClientKit
import XCTest

/// Records every callback a listener receives.
final class Recorder<Event: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Event] = []
    private var seen = 0

    /// Events received since the last `clear()`.
    var events: [Event] {
        lock.withLock { Array(recorded[seen...]) }
    }

    /// Every event, including cleared ones (used to replay diffs).
    var allEvents: [Event] {
        lock.withLock { recorded }
    }

    func record(_ event: Event) {
        lock.withLock { recorded.append(event) }
    }

    /// Hides the events received so far from `events`.
    func clear() {
        lock.withLock { seen = recorded.count }
    }
}

extension Recorder: ChatListListener where Event == [ChatListDiff] {
    func onDiffs(_ diffs: [ChatListDiff]) { record(diffs) }

    /// The list obtained by applying every recorded diff in order.
    var items: [ChatSummary] {
        var items: [ChatSummary] = []
        for diff in allEvents.joined() {
            switch diff {
            case .reset(let all): items = all
            case .insert(let index, let item): items.insert(item, at: Int(index))
            case .update(let index, let item): items[Int(index)] = item
            case .remove(let index): items.remove(at: Int(index))
            }
        }
        return items
    }
}

extension Recorder: TimelineListener where Event == [TimelineDiff] {
    func onDiffs(_ diffs: [TimelineDiff]) { record(diffs) }

    var items: [TimelineMessage] {
        var items: [TimelineMessage] = []
        for diff in allEvents.joined() {
            switch diff {
            case .reset(let all): items = all
            case .insert(let index, let item): items.insert(item, at: Int(index))
            case .update(let index, let item): items[Int(index)] = item
            case .remove(let index): items.remove(at: Int(index))
            }
        }
        return items
    }
}

extension Recorder: ConnectionListener where Event == ConnectionState {
    func onState(_ state: ConnectionState) { record(state) }
}

extension Recorder: TypingListener where Event == [String] {
    /// Records the handles of the typing users.
    func onTyping(chatId: ChatId, users: [UserProfile]) { record(users.map(\.handle)) }
}

/// A settable clock for `FakeGimClient(now:)`.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ date: Date) {
        current = date
    }

    var now: Date {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}

extension XCTestCase {
    func makeTemporaryDirectory() throws -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "gimkit-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url.path
    }

    func assertThrows<T>(
        _ expected: GimError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> T
    ) async {
        do {
            _ = try await body()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? GimError, expected, file: file, line: line)
        }
    }
}
