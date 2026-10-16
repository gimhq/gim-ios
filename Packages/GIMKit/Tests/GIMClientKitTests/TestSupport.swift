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
    func onUpdate(diffs: [ChatListDiff]) { record(diffs) }

    /// The list obtained by applying every recorded diff in order.
    var items: [ChatSummary] {
        var items: [ChatSummary] = []
        for diff in allEvents.joined() {
            switch diff {
            case .append(let values): items += values
            case .clear: items = []
            case .pushFront(let value): items.insert(value, at: 0)
            case .pushBack(let value): items.append(value)
            case .popFront: items.removeFirst()
            case .popBack: items.removeLast()
            case .insert(let index, let value): items.insert(value, at: Int(index))
            case .set(let index, let value): items[Int(index)] = value
            case .remove(let index): items.remove(at: Int(index))
            case .truncate(let length): items.removeSubrange(Int(length)...)
            case .reset(let values): items = values
            }
        }
        return items
    }
}

extension Recorder: TimelineListener where Event == [TimelineDiff] {
    func onUpdate(diffs: [TimelineDiff]) { record(diffs) }

    var items: [TimelineItem] {
        var items: [TimelineItem] = []
        for diff in allEvents.joined() {
            switch diff {
            case .append(let values): items += values
            case .clear: items = []
            case .pushFront(let value): items.insert(value, at: 0)
            case .pushBack(let value): items.append(value)
            case .popFront: items.removeFirst()
            case .popBack: items.removeLast()
            case .insert(let index, let value): items.insert(value, at: Int(index))
            case .set(let index, let value): items[Int(index)] = value
            case .remove(let index): items.remove(at: Int(index))
            case .truncate(let length): items.removeSubrange(Int(length)...)
            case .reset(let values): items = values
            }
        }
        return items
    }

    /// The message items, without date separators and membership changes.
    var messages: [MessageItem] {
        items.compactMap { if case .message(let item) = $0 { item } else { nil } }
    }
}

extension Recorder: ConnectionStateListener where Event == ConnectionState {
    func onChange(state: ConnectionState) { record(state) }
}

extension Recorder: TypingListener where Event == [String] {
    func onUpdate(userIds: [String]) { record(userIds) }
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

/// A `LocalTimeZone` answering with the offsets of a Foundation `TimeZone`.
final class TimeZoneStub: LocalTimeZone {
    let zone: TimeZone

    init(_ zone: TimeZone) {
        self.zone = zone
    }

    func utcOffsetSecs(atMs: Int64) -> Int32 {
        Int32(zone.secondsFromGMT(for: Date(timeIntervalSince1970: Double(atMs) / 1000)))
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

    /// Polls `condition` until it holds; fails after about a second.
    func eventually(
        file: StaticString = #filePath, line: UInt = #line, _ condition: @Sendable () async -> Bool
    ) async {
        for _ in 0..<1_000 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("condition not met", file: file, line: line)
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
