import Foundation
import GIMFeatures
import XCTest

final class MediaPreparationTests: XCTestCase {
    func testMimeTable() {
        let expected = [
            "jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png", "heic": "image/heic", "gif": "image/gif",
            "pdf": "application/pdf", "zip": "application/zip", "txt": "text/plain", "mp4": "video/mp4",
            "mov": "video/quicktime",
            "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        ]
        for (fileExtension, mime) in expected {
            XCTAssertEqual(MediaPreparation.mimeType(forExtension: fileExtension), mime, fileExtension)
        }
    }

    func testMimeIsCaseInsensitiveAndFallsBack() {
        XCTAssertEqual(MediaPreparation.mimeType(forExtension: "JPG"), "image/jpeg")
        XCTAssertEqual(MediaPreparation.mimeType(forExtension: ".Png"), "image/png")
        XCTAssertEqual(MediaPreparation.mimeType(forExtension: "xyz"), "application/octet-stream")
        XCTAssertEqual(MediaPreparation.mimeType(forExtension: ""), "application/octet-stream")
        XCTAssertEqual(MediaPreparation.mimeType(forPath: "/tmp/a/Holiday.HEIC"), "image/heic")
        XCTAssertEqual(MediaPreparation.mimeType(forPath: "/tmp/a/README"), "application/octet-stream")
    }

    func testSizeLimit() throws {
        XCTAssertEqual(MediaPreparation.maxFileSize, 104_857_600)
        XCTAssertNoThrow(try MediaPreparation.validateSize(0))
        XCTAssertNoThrow(try MediaPreparation.validateSize(MediaPreparation.maxFileSize))
        XCTAssertThrowsError(try MediaPreparation.validateSize(MediaPreparation.maxFileSize + 1)) { error in
            XCTAssertEqual(error as? MediaPreparationError, .tooLarge(byteCount: MediaPreparation.maxFileSize + 1))
        }
        XCTAssertEqual(
            MediaPreparationError.tooLarge(byteCount: 1).message, "This file is larger than 100 MB and can't be sent.")
    }

    func testFileSize() throws {
        let directory = makeTemporaryDirectory()
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let path = directory + "/file.bin"
        try Data(count: 1_234).write(to: URL(fileURLWithPath: path))
        XCTAssertEqual(try MediaPreparation.fileSize(atPath: path), 1_234)
        XCTAssertThrowsError(try MediaPreparation.fileSize(atPath: directory + "/missing")) { error in
            XCTAssertEqual(error as? MediaPreparationError, .unreadable)
        }
    }

    func testTargetImageSize() {
        func target(_ width: Int, _ height: Int) -> [Int] {
            let size = MediaPreparation.targetImageSize(width: width, height: height)
            return [size.width, size.height]
        }
        XCTAssertEqual(target(4032, 3024), [2048, 1536])
        XCTAssertEqual(target(3024, 4032), [1536, 2048])
        XCTAssertEqual(target(4096, 4096), [2048, 2048])
        XCTAssertEqual(target(3000, 1001), [2048, 683])
        XCTAssertEqual(target(1920, 1080), [1920, 1080], "smaller images keep their size")
        XCTAssertEqual(target(2048, 100), [2048, 100])
        XCTAssertEqual(target(100_000, 10), [2048, 1], "no side below one pixel")
        XCTAssertEqual(target(0, 0), [0, 0])
        let custom = MediaPreparation.targetImageSize(width: 1000, height: 500, maxLongestSide: 100)
        XCTAssertEqual([custom.width, custom.height], [100, 50])
    }
}
