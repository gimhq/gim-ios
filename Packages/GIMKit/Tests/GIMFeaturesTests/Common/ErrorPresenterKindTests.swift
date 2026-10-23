import GIMClientKit
import GIMFeatures
import XCTest

final class ErrorPresenterKindTests: XCTestCase {
    private struct OtherError: Error {}

    func testMapsEveryKindToItsText() {
        let cases: [(ErrorPresenter.Kind, String)] = [
            (.network, "Can't reach the server. Check your internet and try again."),
            (.notRegistered, "This device isn't signed in. Sign in again."),
            (.invalidInput(reason: "Handle is taken"), "Handle is taken"),
            (.invalidInputEmpty, "Check what you typed and try again."),
            (.notFound, "Couldn't find that. It may have been removed."),
            (.crypto, "Couldn't unlock this message."),
            (.storage, "Couldn't save on this device. Free up some space and try again."),
            (.server, "The server couldn't do that right now. Try again later."),
            (.serverBusy(retryAfterSecs: 30), "The server is busy. Try again in 30 s."),
            (.peerUnavailable(retryAfterSecs: 10), "Another server isn't answering. Try again in 10 s."),
            (.cancelled, "That was cancelled."),
            (.notImplemented, "This isn't available yet."),
            (.generic, "Something went wrong. Try again."),
            (.chatLeaving, "You're leaving this chat."),
            (.chatLeft, "You're no longer in this chat."),
            (.hubNotVerified, "Couldn't reach a server at this address. Check the address and try again."),
            (.hubOwnsGroups(count: 1), "This server hosts 1 group you own."),
            (.hubOwnsGroups(count: 3), "This server hosts 3 groups you own."),
            (.lastHub, "This is your only server. Add another server before you remove it."),
            (.homeHub, "Your main server can't be removed. Make another server the main one first."),
            (.hubNotDrained, "Messages sent through this server are still on their way. Try again later."),
            (.suspended(host: nil), suspended),
            (
                .suspended(host: "hub2.example.eu"),
                "Your account is suspended on hub2.example.eu. Your chats on this device stay readable. Contact the"
                    + " server's operator to get access back."
            ),
            (.notAdmitted(host: nil), "This server doesn't accept your account."),
            (.notAdmitted(host: "hub2.example.eu"), "hub2.example.eu doesn't accept your account."),
            (.notAdmittedByPeer, "This chat's server doesn't accept messages from you."),
            (.hubRefused, "This server doesn't accept your account."),
            (.contactNotAdmitted(names: []), "This person doesn't accept messages from you."),
            (.contactNotAdmitted(names: ["Ana Kovač"]), "Ana Kovač doesn't accept messages from you."),
            (
                .contactNotAdmitted(names: ["Ana Kovač", "@lars"]),
                "Ana Kovač and @lars don't accept messages from you."
            ),
            (
                .contactNotAdmitted(names: ["Ana Kovač", "@lars", "u-x"]),
                "Ana Kovač, @lars and u-x don't accept messages from you."
            ),
        ]
        for (kind, text) in cases {
            XCTAssertEqual(ErrorPresenter.text(for: kind), text, "\(kind)")
        }
    }

    func testPicksTheKindForEveryGimError() {
        let cases: [(GimError, ErrorPresenter.Kind)] = [
            (.Network(reason: "timeout"), .network),
            (.NotRegistered, .notRegistered),
            (.InvalidInput(reason: "Handle is taken"), .invalidInput(reason: "Handle is taken")),
            (.InvalidInput(reason: ""), .invalidInputEmpty),
            (.NotFound(reason: "chat x"), .notFound),
            (.Crypto(reason: "mls"), .crypto),
            (.Storage(reason: "disk full"), .storage),
            (.Server(status: 503, reason: "unavailable"), .server),
            (.RetryLater(status: 429, retryAfterSecs: 30, reason: "rate_limited"), .serverBusy(retryAfterSecs: 30)),
            (
                .RetryLater(status: 503, retryAfterSecs: 10, reason: "peer_unavailable"),
                .peerUnavailable(retryAfterSecs: 10)
            ),
            (.Cancelled, .cancelled),
            (.NotImplemented, .notImplemented),
            (.Internal(reason: "sqlite busy"), .generic),
            (.ChatNotActive(chatId: "h/g1", state: .left), .chatLeft),
            (.ChatNotActive(chatId: "h/g1", state: .leaving), .chatLeaving),
            (.HubNotVerified(reason: "audience_url_mismatch"), .hubNotVerified),
            (.HubOwnsGroups(hubId: "h2", groupCount: 3), .hubOwnsGroups(count: 3)),
            (.LastHub(hubId: "h2"), .lastHub),
            (.HomeHub(hubId: "h1"), .homeHub),
            (.HubNotDrained(hubId: "h2", reason: "1 messages"), .hubNotDrained),
            (.UserSuspended(hubId: "h2"), .suspended(host: nil)),
            (.UserNotAdmitted(hubId: "h2"), .notAdmitted(host: nil)),
            (.NotAdmittedByPeer(hubId: "h2", chatId: "h2/g1"), .notAdmittedByPeer),
            (.ContactNotAdmitted(userIds: ["u-ana", "u-lars"]), .contactNotAdmitted(names: ["u-ana", "u-lars"])),
        ]
        for (error, kind) in cases {
            XCTAssertEqual(ErrorPresenter.kind(for: error), kind, "\(error)")
        }
        XCTAssertEqual(ErrorPresenter.kind(for: OtherError()), .generic)
    }

    func testRegistrationKindRefusesTheHub() {
        XCTAssertEqual(ErrorPresenter.registrationKind(for: GimError.UserNotAdmitted(hubId: "")), .hubRefused)
        XCTAssertEqual(ErrorPresenter.registrationKind(for: GimError.Network(reason: "x")), .network)
    }

    func testHubKindsNameTheHubOnlyWhenSeveralHubsAreListed() {
        let hubs = [hub("hub-a", "https://hub.g.im"), hub("hub-b", "https://Hub2.example.eu:8443")]
        XCTAssertEqual(ErrorPresenter.suspendedKind(hubId: "hub-b", hubs: hubs), .suspended(host: "hub2.example.eu"))
        XCTAssertEqual(ErrorPresenter.suspendedKind(hubId: "hub-a", hubs: [hubs[0]]), .suspended(host: nil))
        XCTAssertEqual(
            ErrorPresenter.notAdmittedKind(hubId: "hub-b", hubs: hubs), .notAdmitted(host: "hub2.example.eu"))
        XCTAssertEqual(ErrorPresenter.notAdmittedKind(hubId: "", hubs: hubs), .notAdmitted(host: nil))
    }

    @MainActor
    func testClientKindReadsTheClientsHubs() async throws {
        let scheduler = ManualFakeScheduler()
        let client = FakeGimClient(
            scheduler: scheduler, session: Session(userId: "u", deviceId: "d", handle: "", displayName: "U"))
        let hubId = FakeGimClient.hubId(forUrl: "https://hub2.example.eu")
        let single = await ErrorPresenter.kind(for: GimError.UserSuspended(hubId: hubId), client: client)
        XCTAssertEqual(single, .suspended(host: nil))

        _ = try await client.addHub(url: "https://hub2.example.eu")
        await scheduler.advance(by: FakeGimClient.hubVerifyDelay)

        let suspended = await ErrorPresenter.kind(for: GimError.UserSuspended(hubId: hubId), client: client)
        XCTAssertEqual(suspended, .suspended(host: "hub2.example.eu"))
        let notAdmitted = await ErrorPresenter.kind(for: GimError.UserNotAdmitted(hubId: hubId), client: client)
        XCTAssertEqual(notAdmitted, .notAdmitted(host: "hub2.example.eu"))
        let other = await ErrorPresenter.kind(for: GimError.Cancelled, client: client)
        XCTAssertEqual(other, .cancelled)
    }

    func testSendFailureKinds() {
        XCTAssertEqual(ErrorPresenter.sendFailureKind(.userSuspended), .suspended(host: nil))
        XCTAssertEqual(ErrorPresenter.sendFailureKind(.userNotAdmitted), .notAdmitted(host: nil))
        XCTAssertEqual(ErrorPresenter.sendFailureKind(.notAdmittedByPeer), .notAdmittedByPeer)
        XCTAssertNil(ErrorPresenter.sendFailureKind(.rejected))
        XCTAssertNil(ErrorPresenter.sendFailureKind(.other))
    }

    func testContactNotAdmittedKindResolvesNames() {
        let profiles = [
            UserProfile(userId: "u-ana", handle: "ana", displayName: "Ana Kovač"),
            UserProfile(userId: "u-lars", handle: "lars", displayName: ""),
            UserProfile(userId: "u-x", handle: "", displayName: ""),
        ]
        XCTAssertEqual(
            ErrorPresenter.contactNotAdmittedKind(userIds: ["u-ana", "u-lars", "u-x", "u-new"], profiles: profiles),
            .contactNotAdmitted(names: ["Ana Kovač", "@lars", "u-x", "u-new"]))
        XCTAssertEqual(
            ErrorPresenter.contactNotAdmittedKind(userIds: [], profiles: profiles), .contactNotAdmitted(names: []))
    }

    private let suspended =
        "Your account is suspended. Your chats on this device stay readable. Contact the server's operator to get access"
        + " back."

    private func hub(_ hubId: String, _ url: String?, _ state: HubState = .verified) -> HubInfo {
        HubInfo(hubId: hubId, url: url, state: state, priority: 0, isPrimary: false, isHome: false, signedIn: true)
    }
}
