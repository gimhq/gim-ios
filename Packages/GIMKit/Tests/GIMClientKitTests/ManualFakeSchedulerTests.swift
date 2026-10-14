import GIMClientKit
import XCTest

final class ManualFakeSchedulerTests: XCTestCase {
    func testRunsActionsInDueOrderIncludingNestedOnes() async {
        let scheduler = ManualFakeScheduler()
        let log = Recorder<String>()
        scheduler.schedule(after: .seconds(2)) { log.record("b") }
        scheduler.schedule(after: .seconds(1)) {
            log.record("a")
            scheduler.schedule(after: .seconds(5)) { log.record("d") }
        }
        scheduler.schedule(after: .seconds(2)) { log.record("c") }
        XCTAssertEqual(scheduler.pendingCount, 3)

        await scheduler.advance(by: .seconds(2))
        XCTAssertEqual(log.events, ["a", "b", "c"])
        XCTAssertEqual(scheduler.pendingCount, 1)

        await scheduler.advance(by: .seconds(3))
        XCTAssertEqual(log.events, ["a", "b", "c"])
        await scheduler.advance(by: .seconds(1))
        XCTAssertEqual(log.events, ["a", "b", "c", "d"])
    }

    func testRunUntilIdleDrainsTheQueue() async {
        let scheduler = ManualFakeScheduler()
        let log = Recorder<Int>()
        scheduler.schedule(after: .seconds(10)) { log.record(2) }
        scheduler.schedule(after: .zero) { log.record(1) }
        await scheduler.runUntilIdle()
        XCTAssertEqual(log.events, [1, 2])
        XCTAssertEqual(scheduler.pendingCount, 0)
    }
}
