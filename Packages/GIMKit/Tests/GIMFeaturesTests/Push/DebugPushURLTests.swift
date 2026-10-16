#if DEBUG
    import Foundation
    import GIMFeatures
    import XCTest

    final class DebugPushURLTests: XCTestCase {
        func testRoundTripsAPayload() throws {
            // `?>` and `~` encode to `+` and `/` in standard base64.
            let payload = #"{"v":1,"type":"message","gid":"g?>~","seq":42,"collapse_id":"c0ffee"}"#
            let url = DebugPushURL.url(payload: payload)
            XCTAssertEqual(url.scheme, "gim-debug")
            XCTAssertEqual(url.host, "process-push")
            let value = try XCTUnwrap(url.query?.split(separator: "=", maxSplits: 1).last.map(String.init))
            XCTAssertTrue(value.contains("_"), value)
            XCTAssertFalse(value.contains("+") || value.contains("/") || value.contains("="), value)
            XCTAssertEqual(DebugPushURL.payload(from: url), payload)
        }

        func testDecodesUnpaddedBase64url() {
            // "{}" is `e30=` in base64.
            XCTAssertEqual(DebugPushURL.payload(from: URL(string: "gim-debug://process-push?payload=e30")!), "{}")
        }

        func testHoldSyncURL() {
            XCTAssertEqual(DebugPushURL.holdSyncURL.absoluteString, "gim-debug://hold-sync")
            XCTAssertTrue(DebugPushURL.isHoldSync(DebugPushURL.holdSyncURL))
            XCTAssertFalse(DebugPushURL.isHoldSync(DebugPushURL.url(payload: "{}")))
            XCTAssertFalse(DebugPushURL.isHoldSync(URL(string: "https://hold-sync")!))
            XCTAssertNil(DebugPushURL.payload(from: DebugPushURL.holdSyncURL))
        }

        func testRejectsOtherURLsAndBadPayloads() {
            for text in [
                "gim-debug://other?payload=e30", "https://process-push?payload=e30", "gim-debug://process-push",
                "gim-debug://process-push?payload=%25%25", "gim-debug://process-push?payload=_w",
            ] {
                XCTAssertNil(DebugPushURL.payload(from: URL(string: text)!), text)
            }
        }
    }
#endif
