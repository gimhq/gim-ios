import GIMClientKit
import GIMFeatures
import XCTest

final class ErrorPresenterTests: XCTestCase {
    private struct OtherError: Error {}

    func testMapsEveryGimError() {
        let cases: [(GimError, String)] = [
            (.Network(reason: "timeout"), "Can't reach the server. Check your connection and try again."),
            (.NotRegistered, "This device isn't signed in. Please register again."),
            (.InvalidInput(reason: "Handle is taken"), "Handle is taken"),
            (.InvalidInput(reason: ""), "Please check what you entered and try again."),
            (.NotFound(reason: "chat x"), "We couldn't find what you were looking for."),
            (.Crypto(reason: "mls"), "This content couldn't be decrypted."),
            (.Storage(reason: "disk full"), "Couldn't save data on this device. Check the free storage and try again."),
            (
                .Server(status: 503, reason: "unavailable"),
                "The server couldn't complete the request (error 503). Please try again later."
            ),
            (.Cancelled, "The operation was cancelled."),
            (.NotImplemented, "This isn't available in this version yet."),
            (.Internal(reason: "sqlite busy"), "Something went wrong. Please try again."),
        ]
        for (error, message) in cases {
            XCTAssertEqual(ErrorPresenter.message(for: error), message, "\(error)")
        }
    }

    func testUnknownErrorsGetGenericText() {
        XCTAssertEqual(ErrorPresenter.message(for: OtherError()), "Something went wrong. Please try again.")
    }
}
