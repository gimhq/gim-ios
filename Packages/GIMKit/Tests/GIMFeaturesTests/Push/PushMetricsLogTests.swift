import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

final class PushMetricsLogTests: XCTestCase {
    func testMetricsLogNumbersItsLines() throws {
        let url = URL(fileURLWithPath: makeTemporaryDirectory()).appendingPathExtension("log")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let log = PushMetricsLog(url: url)
        XCTAssertEqual(
            try log.append(footprintBytes: 9_437_184, elapsedMs: 412, kind: .message),
            "nse seq=1 footprint_bytes=9437184 elapsed_ms=412 kind=message")
        try log.append(footprintBytes: 8_000_000, elapsedMs: 15, kind: .generic)
        XCTAssertEqual(
            try String(contentsOf: url, encoding: .utf8),
            "nse seq=1 footprint_bytes=9437184 elapsed_ms=412 kind=message\n"
                + "nse seq=2 footprint_bytes=8000000 elapsed_ms=15 kind=generic\n")
    }
}
