import GIMClientKit
import GIMFeatures
import XCTest

final class ErrorPresenterTests: XCTestCase {
    private struct OtherError: Error {}

    func testMapsEveryGimError() {
        let cases: [(GimError, String)] = [
            (.Network(reason: "timeout"), "Can't reach the server. Check your internet and try again."),
            (.NotRegistered, "This device isn't signed in. Sign in again."),
            (.InvalidInput(reason: "Handle is taken"), "Handle is taken"),
            (.InvalidInput(reason: ""), "Check what you typed and try again."),
            (.NotFound(reason: "chat x"), "Couldn't find that. It may have been removed."),
            (.Crypto(reason: "mls"), "Couldn't unlock this message."),
            (.Storage(reason: "disk full"), "Couldn't save on this device. Free up some space and try again."),
            (.Server(status: 503, reason: "unavailable"), "The server couldn't do that right now. Try again later."),
            (
                .RetryLater(status: 429, retryAfterSecs: 30, reason: "rate_limited"),
                "The server is busy. Try again in 30 s."
            ),
            (
                .RetryLater(status: 503, retryAfterSecs: 10, reason: "peer_unavailable"),
                "Another server isn't answering. Try again in 10 s."
            ),
            (.Cancelled, "That was cancelled."),
            (.NotImplemented, "This isn't available yet."),
            (.Internal(reason: "sqlite busy"), "Something went wrong. Try again."),
            (.ChatNotActive(chatId: "h/g1", state: .left), "You're no longer in this chat."),
            (.ChatNotActive(chatId: "h/g1", state: .leaving), "You're leaving this chat."),
            (
                .HubNotVerified(reason: "audience_url_mismatch"),
                "Couldn't reach a server at this address. Check the address and try again."
            ),
            (.HubOwnsGroups(hubId: "h2", groupCount: 3), "This server hosts 3 groups you own."),
            (.HubOwnsGroups(hubId: "h2", groupCount: 1), "This server hosts 1 group you own."),
            (.LastHub(hubId: "h2"), "This is your only server. Add another server before you remove it."),
            (
                .HomeHub(hubId: "h1"),
                "Your main server can't be removed. Make another server the main one first."
            ),
            (
                .HubNotDrained(hubId: "h2", reason: "1 messages and 0 commits not acknowledged yet"),
                "Messages sent through this server are still on their way. Try again later."
            ),
            (.UserSuspended(hubId: "h2"), suspended),
            (.UserSuspended(hubId: ""), suspended),
            (.UserNotAdmitted(hubId: "h2"), "This server doesn't accept your account."),
            (.UserNotAdmitted(hubId: ""), "This server doesn't accept your account."),
            (
                .NotAdmittedByPeer(hubId: "h2", chatId: "h2/g1"),
                "This chat's server doesn't accept messages from you."
            ),
            (.ContactNotAdmitted(userIds: ["u-ana"]), "u-ana doesn't accept messages from you."),
        ]
        for (error, message) in cases {
            XCTAssertEqual(ErrorPresenter.message(for: error), message, "\(error)")
        }
    }

    func testUnknownErrorsGetGenericText() {
        XCTAssertEqual(ErrorPresenter.message(for: OtherError()), "Something went wrong. Try again.")
    }

    func testSuspensionNamesTheHubOnlyWhenSeveralHubsAreListed() {
        let home = hub("hub-a", "https://Hub.G.im")
        let second = hub("hub-b", "https://hub2.example.eu:8443/api")
        let named =
            "Your account is suspended on hub2.example.eu. Your chats on this device stay readable. Contact the"
            + " server's operator to get access back."
        XCTAssertEqual(ErrorPresenter.suspendedMessage(hubId: "hub-b", hubs: [home, second]), named)
        XCTAssertEqual(
            ErrorPresenter.suspendedMessage(hubId: "hub-a", hubs: [home, second]),
            "Your account is suspended on hub.g.im. Your chats on this device stay readable. Contact the"
                + " server's operator to get access back.")
        XCTAssertEqual(ErrorPresenter.suspendedMessage(hubId: "hub-a", hubs: [home]), suspended, "a single hub")
        XCTAssertEqual(ErrorPresenter.suspendedMessage(hubId: "", hubs: [home, second]), suspended, "no hub id")
        XCTAssertEqual(ErrorPresenter.suspendedMessage(hubId: "hub-x", hubs: [home, second]), suspended, "unknown")
        XCTAssertEqual(
            ErrorPresenter.suspendedMessage(hubId: "hub-a", hubs: [home, hub("hub-b", "https://b.eu", .removed)]),
            suspended, "a removed hub is not listed")
        XCTAssertEqual(
            ErrorPresenter.suspendedMessage(hubId: "hub-b", hubs: [home, hub("hub-b", nil)]), suspended, "no URL")
    }

    @MainActor
    func testSuspensionReadsTheClientsHubs() async throws {
        let scheduler = ManualFakeScheduler()
        let client = FakeGimClient(
            scheduler: scheduler, session: Session(userId: "u", deviceId: "d", handle: "", displayName: "U"))
        let error = GimError.UserSuspended(hubId: FakeGimClient.hubId(forUrl: "https://hub2.example.eu"))
        let single = await ErrorPresenter.message(for: error, client: client)
        XCTAssertEqual(single, suspended)

        _ = try await client.addHub(url: "https://hub2.example.eu")
        await scheduler.advance(by: FakeGimClient.hubVerifyDelay)

        let named = await ErrorPresenter.message(for: error, client: client)
        XCTAssertTrue(named.hasPrefix("Your account is suspended on hub2.example.eu."), named)
        let other = await ErrorPresenter.message(for: GimError.Cancelled, client: client)
        XCTAssertEqual(other, ErrorPresenter.message(for: GimError.Cancelled))
    }

    func testNotAdmittedNamesTheHubOnlyWhenSeveralHubsAreListed() {
        let home = hub("hub-a", "https://hub.g.im")
        let second = hub("hub-b", "https://Hub2.example.eu:8443")
        XCTAssertEqual(
            ErrorPresenter.notAdmittedMessage(hubId: "hub-b", hubs: [home, second]),
            "hub2.example.eu doesn't accept your account.")
        let plain = "This server doesn't accept your account."
        XCTAssertEqual(ErrorPresenter.notAdmittedMessage(hubId: "hub-a", hubs: [home]), plain, "a single hub")
        XCTAssertEqual(ErrorPresenter.notAdmittedMessage(hubId: "", hubs: [home, second]), plain, "no hub id")
        XCTAssertEqual(ErrorPresenter.notAdmittedMessage(hubId: "hub-x", hubs: [home, second]), plain, "unknown")
    }

    @MainActor
    func testNotAdmittedReadsTheClientsHubs() async throws {
        let scheduler = ManualFakeScheduler()
        let client = FakeGimClient(
            scheduler: scheduler, session: Session(userId: "u", deviceId: "d", handle: "", displayName: "U"))
        _ = try await client.addHub(url: "https://hub2.example.eu")
        await scheduler.advance(by: FakeGimClient.hubVerifyDelay)
        let error = GimError.UserNotAdmitted(hubId: FakeGimClient.hubId(forUrl: "https://hub2.example.eu"))

        let named = await ErrorPresenter.message(for: error, client: client)

        XCTAssertEqual(named, "hub2.example.eu doesn't accept your account.")
    }

    func testRegistrationRefusalNamesTheRefusingHub() {
        XCTAssertEqual(
            ErrorPresenter.registrationMessage(for: GimError.UserNotAdmitted(hubId: "")),
            "This server doesn't accept your account.")
        XCTAssertEqual(
            ErrorPresenter.registrationMessage(for: GimError.Network(reason: "x")),
            ErrorPresenter.message(for: GimError.Network(reason: "x")))
    }

    func testContactRefusalNamesTheUsers() {
        let profiles = [
            UserProfile(userId: "u-ana", handle: "ana", displayName: "Ana Kovač"),
            UserProfile(userId: "u-lars", handle: "lars", displayName: ""),
            UserProfile(userId: "u-x", handle: "", displayName: ""),
        ]
        XCTAssertEqual(
            ErrorPresenter.contactNotAdmittedMessage(userIds: ["u-ana"], profiles: profiles),
            "Ana Kovač doesn't accept messages from you.")
        XCTAssertEqual(
            ErrorPresenter.contactNotAdmittedMessage(userIds: ["u-ana", "u-lars"], profiles: profiles),
            "Ana Kovač and u-lars don't accept messages from you.")
        XCTAssertEqual(
            ErrorPresenter.contactNotAdmittedMessage(userIds: ["u-ana", "u-lars", "u-x", "u-new"], profiles: profiles),
            "Ana Kovač, u-lars, u-x and u-new don't accept messages from you.")
        XCTAssertEqual(
            ErrorPresenter.contactNotAdmittedMessage(userIds: [], profiles: profiles),
            "This person doesn't accept messages from you.")
    }

    func testSendFailureExplanations() {
        XCTAssertEqual(ErrorPresenter.sendFailureMessage(.userSuspended), suspended)
        XCTAssertEqual(
            ErrorPresenter.sendFailureMessage(.userNotAdmitted), "This server doesn't accept your account.")
        XCTAssertEqual(
            ErrorPresenter.sendFailureMessage(.notAdmittedByPeer),
            "This chat's server doesn't accept messages from you.")
        XCTAssertNil(ErrorPresenter.sendFailureMessage(.rejected))
        XCTAssertNil(ErrorPresenter.sendFailureMessage(.other))
    }

    private let suspended =
        "Your account is suspended. Your chats on this device stay readable. Contact the server's operator to get"
        + " access back."

    private func hub(_ hubId: String, _ url: String?, _ state: HubState = .verified) -> HubInfo {
        HubInfo(hubId: hubId, url: url, state: state, priority: 0, isPrimary: false, isHome: false, signedIn: true)
    }
}
