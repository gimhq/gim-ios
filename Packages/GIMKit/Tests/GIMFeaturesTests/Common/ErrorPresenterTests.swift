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
            (
                .RetryLater(status: 429, retryAfterSecs: 30, reason: "rate_limited"),
                "The server is busy. Try again in 30 s."
            ),
            (
                .RetryLater(status: 503, retryAfterSecs: 10, reason: "peer_unavailable"),
                "Another server is unavailable. Try again in 10 s."
            ),
            (.Cancelled, "The operation was cancelled."),
            (.NotImplemented, "This isn't available in this version yet."),
            (.Internal(reason: "sqlite busy"), "Something went wrong. Please try again."),
            (.ChatNotActive(chatId: "h/g1", state: .left), "You're no longer a member of this chat."),
            (.ChatNotActive(chatId: "h/g1", state: .leaving), "You're leaving this chat."),
            (
                .HubNotVerified(reason: "audience_url_mismatch"),
                "This server couldn't prove it is the hub at this address. Check the address and try again."
            ),
            (.HubOwnsGroups(hubId: "h2", groupCount: 3), "This hub hosts 3 groups you own."),
            (.HubOwnsGroups(hubId: "h2", groupCount: 1), "This hub hosts 1 group you own."),
            (.LastHub(hubId: "h2"), "This is your only hub. Add another hub before removing it."),
            (.HomeHub(hubId: "h1"), "This device's home hub can't be removed. Make another hub primary instead."),
            (
                .HubNotDrained(hubId: "h2", reason: "1 messages and 0 commits not acknowledged yet"),
                "Messages sent through this hub are still on their way. Try again in a moment."
            ),
        ]
        for (error, message) in cases {
            XCTAssertEqual(ErrorPresenter.message(for: error), message, "\(error)")
        }
    }

    func testUnknownErrorsGetGenericText() {
        XCTAssertEqual(ErrorPresenter.message(for: OtherError()), "Something went wrong. Please try again.")
    }
}
