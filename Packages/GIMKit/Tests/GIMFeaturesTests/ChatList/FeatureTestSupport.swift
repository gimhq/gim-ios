import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

/// Fixed clock shared by the demo client and the date formatter.
let fixedNow = Date(timeIntervalSince1970: 1_791_000_000)

func makeFormatter() -> RelativeDateFormatter {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return RelativeDateFormatter(calendar: calendar, locale: Locale(identifier: "en_US_POSIX"), now: { fixedNow })
}

extension XCTestCase {
    func makeDemoClient() -> (FakeGimClient, ManualFakeScheduler) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let scheduler = ManualFakeScheduler()
        let client = FakeGimClient.demo(
            scheduler: scheduler, dataDirectory: directory.path, now: { fixedNow }, autoReply: false)
        return (client, scheduler)
    }
}

/// Lets main-actor tasks run until `condition` holds; fails after about a second.
@MainActor
func eventually(
    _ message: String = "condition not met", file: StaticString = #filePath, line: UInt = #line,
    _ condition: () -> Bool
) async {
    for _ in 0..<1_000 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(1))
    }
    XCTFail(message, file: file, line: line)
}

/// Gives already-scheduled main-actor tasks a chance to run.
@MainActor
func settle() async {
    for _ in 0..<20 {
        try? await Task.sleep(for: .milliseconds(1))
    }
}

/// Debounce sleep the test releases by hand. Cancelled sleepers throw `CancellationError`.
final class ManualSleeper: @unchecked Sendable {
    private struct Waiter {
        var id: Int
        var continuation: CheckedContinuation<Void, any Error>
    }

    private let lock = NSLock()
    private var waiters: [Waiter] = []
    private var nextId = 0
    private var recorded: [Duration] = []

    var pendingCount: Int { lock.withLock { waiters.count } }
    var durations: [Duration] { lock.withLock { recorded } }

    func sleep(_ duration: Duration) async throws {
        let id = lock.withLock {
            recorded.append(duration)
            nextId += 1
            return nextId
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                lock.withLock {
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        waiters.append(Waiter(id: id, continuation: continuation))
                    }
                }
            }
        } onCancel: {
            let waiter = lock.withLock {
                waiters.firstIndex { $0.id == id }.map { waiters.remove(at: $0) }
            }
            waiter?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Ends every pending sleep.
    func releaseAll() {
        let released = lock.withLock {
            defer { waiters = [] }
            return waiters
        }
        for waiter in released { waiter.continuation.resume() }
    }
}
