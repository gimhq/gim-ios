import GIMClientKit
import GIMFeatures
import XCTest

final class ComposerTextKindsTests: XCTestCase {
    func testEveryReadOnlyKindMapsToItsEnglishText() {
        XCTAssertEqual(ComposerReadOnlyKind.leaving.text, "Leaving…")
        XCTAssertEqual(ComposerReadOnlyKind.left.text, "You can no longer send messages in this chat.")
    }

    func testEveryPreviewKindMapsToItsEnglishText() {
        XCTAssertEqual(MessagePreviewKind.content("Sunset").text, "Sunset")
        XCTAssertEqual(MessagePreviewKind.photo.text, "Photo")
        XCTAssertEqual(MessagePreviewKind.file.text, "File")
        XCTAssertEqual(MessagePreviewKind.deleted.text, "This message was deleted")
        XCTAssertEqual(MessagePreviewKind.unsupported.text, "Unsupported message")
    }

    func testPreviewKindFollowsTheContent() {
        let media = MediaRef(chatId: "chat", messageId: "m", mime: "image/png", size: 1, hasThumbnail: false)
        func kind(_ content: MessageContent) -> MessagePreviewKind {
            ComposerViewModel.previewKind(for: makeMessage(content: content))
        }
        XCTAssertEqual(kind(.text(body: "Hi")), .content("Hi"))
        XCTAssertEqual(kind(.image(media: media, width: nil, height: nil, caption: nil)), .photo)
        XCTAssertEqual(kind(.image(media: media, width: nil, height: nil, caption: "Sunset")), .content("Sunset"))
        XCTAssertEqual(kind(.file(media: media, fileName: "a.pdf", caption: "")), .content("a.pdf"))
        XCTAssertEqual(kind(.file(media: media, fileName: nil, caption: nil)), .file)
        XCTAssertEqual(kind(.deleted), .deleted)
        XCTAssertEqual(kind(.unsupported), .unsupported)
    }

    func testEveryMediaErrorKindMapsToItsEnglishText() {
        XCTAssertEqual(
            MediaPreparationErrorKind.tooLarge(limitMegabytes: 100).text,
            "This file is larger than 100 MB and can't be sent.")
        XCTAssertEqual(MediaPreparationErrorKind.unreadable.text, "This file couldn't be read.")
        XCTAssertEqual(MediaPreparationError.tooLarge(byteCount: 1).kind, .tooLarge(limitMegabytes: 100))
        XCTAssertEqual(MediaPreparationError.unreadable.kind, .unreadable)
    }
}
