import GIMClientKit
import GIMFeatures
import XCTest

final class ErrorPresenterTests: XCTestCase {
    private struct OtherError: Error {}

    func testMapsEveryGimError() {
        XCTAssertEqual(
            ErrorPresenter.message(for: GimError.unauthorized),
            "Your session has expired. Please register this device again.")
        XCTAssertEqual(
            ErrorPresenter.message(for: GimError.notFound), "We couldn't find what you were looking for.")
        XCTAssertEqual(
            ErrorPresenter.message(for: GimError.network("timeout")),
            "Can't reach the server. Check your connection and try again.")
        XCTAssertEqual(ErrorPresenter.message(for: GimError.invalidInput("Handle is taken")), "Handle is taken")
        XCTAssertEqual(
            ErrorPresenter.message(for: GimError.invalidInput("")), "Please check what you entered and try again.")
        XCTAssertEqual(
            ErrorPresenter.message(for: GimError.internal("sqlite busy")), "Something went wrong. Please try again.")
    }

    func testUnknownErrorsGetGenericText() {
        XCTAssertEqual(ErrorPresenter.message(for: OtherError()), "Something went wrong. Please try again.")
    }
}
