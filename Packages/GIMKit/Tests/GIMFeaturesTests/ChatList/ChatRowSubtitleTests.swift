import GIMFeatures
import XCTest

final class ChatRowSubtitleTests: XCTestCase {
    func testEveryKindMapsToItsEnglishText() {
        XCTAssertEqual(ChatRowSubtitle.preview("Nikos: Hi").text, "Nikos: Hi")
        XCTAssertEqual(ChatRowSubtitle.preview("").text, "")
        XCTAssertEqual(ChatRowSubtitle.noMessages.text, "No messages yet")
        XCTAssertEqual(ChatRowSubtitle.leaving.text, "Leaving…")
        XCTAssertEqual(ChatRowSubtitle.left.text, "You left")
        XCTAssertEqual(ChatRowSubtitle.removed.text, "You were removed")
        XCTAssertEqual(ChatRowSubtitle.leftUnknown.text, "Left")
    }
}
