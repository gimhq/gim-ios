import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

final class CreateIdentityViewModelTests: XCTestCase {
    @MainActor
    private final class Created {
        var results: [(client: any GimClientAPI, userId: String, recoveryCode: String?)] = []
    }

    @MainActor
    private func makeViewModel(
        client: @escaping @MainActor () async throws -> any GimClientAPI
    ) -> (CreateIdentityViewModel, Created) {
        let created = Created()
        let context = OnboardingContext(
            config: ClientConfig(serverUrl: "https://gim.example.eu"), client: client, discardClient: {},
            onRegistered: { _ in })
        let viewModel = CreateIdentityViewModel(context: context) { created.results.append(($0, $1, $2)) }
        return (viewModel, created)
    }

    @MainActor
    func testEmptyNameShowsTheErrorOnSubmitWithoutCreatingAClient() async {
        var clientRequests = 0
        let (viewModel, created) = makeViewModel {
            clientRequests += 1
            return FakeGimClient()
        }
        XCTAssertNil(viewModel.displayNameError)
        XCTAssertFalse(viewModel.canSubmit)

        await viewModel.submit()

        XCTAssertNotNil(viewModel.displayNameError)
        XCTAssertEqual(clientRequests, 0)
        XCTAssertTrue(created.results.isEmpty)
    }

    @MainActor
    func testTooLongNameShowsInlineError() async {
        let (viewModel, _) = makeViewModel { FakeGimClient() }
        viewModel.displayName = String(repeating: "a", count: 65)
        XCTAssertNotNil(viewModel.displayNameError)
        viewModel.displayName = "Sofia"
        XCTAssertNil(viewModel.displayNameError)
    }

    @MainActor
    func testSubmitCreatesTheIdentityWithTheTrimmedNameAndReturnsTheCode() async throws {
        let client = FakeGimClient()
        let (viewModel, created) = makeViewModel { client }
        viewModel.displayName = "  Sofia Marin \n"

        await viewModel.submit()

        let result = try XCTUnwrap(created.results.first)
        XCTAssertTrue(result.client === client)
        let code = try XCTUnwrap(result.recoveryCode)
        XCTAssertEqual(code.count, 39 + 9, "39 symbols in ten groups")
        let session = try await client.session()
        XCTAssertEqual(session?.displayName, "Sofia Marin")
        XCTAssertEqual(result.userId, session?.userId, "the user ID of the new session")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isSubmitting)
    }

    @MainActor
    func testCreateIdentityErrorIsPresentedAndRetryCreatesTheIdentityOnTheSameClient() async throws {
        let client = IdentityStubClient(createIdentityErrors: [.Network(reason: "offline")])
        var clientRequests = 0
        let (viewModel, created) = makeViewModel {
            clientRequests += 1
            return client
        }
        viewModel.displayName = "Sofia"

        await viewModel.submit()

        XCTAssertTrue(created.results.isEmpty)
        XCTAssertEqual(viewModel.errorMessage, ErrorPresenter.message(for: GimError.Network(reason: "offline")))
        XCTAssertFalse(viewModel.isSubmitting)

        await viewModel.submit()

        XCTAssertEqual(created.results.count, 1, "only the code of the call that succeeded is shown")
        let result = try XCTUnwrap(created.results.first)
        XCTAssertTrue(result.client === client)
        XCTAssertNotNil(result.recoveryCode)
        let session = try await client.session()
        XCTAssertEqual(session?.displayName, "Sofia")
        XCTAssertEqual(clientRequests, 2, "the cached client is reused through the context")
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testMissingSessionAfterCreatingShowsTheErrorAndDoesNotContinue() async {
        let (viewModel, created) = makeViewModel { SessionlessIdentityClient() }
        viewModel.displayName = "Sofia"

        await viewModel.submit()

        XCTAssertTrue(created.results.isEmpty)
        XCTAssertEqual(viewModel.errorMessage, ErrorPresenter.registrationMessage(for: GimError.NotRegistered))
        XCTAssertFalse(viewModel.isSubmitting)
    }

    @MainActor
    func testClientCreationErrorIsPresented() async {
        let (viewModel, created) = makeViewModel { throw GimError.InvalidInput(reason: "server_url: missing host") }
        viewModel.displayName = "Sofia"

        await viewModel.submit()

        XCTAssertTrue(created.results.isEmpty)
        XCTAssertEqual(viewModel.errorMessage, "server_url: missing host")
    }

    @MainActor
    func testClientWithAnIdentityShowsTheCoreError() async throws {
        let session = Session(userId: "user-sofia", deviceId: "device-1", handle: "", displayName: "Sofia")
        let client = FakeGimClient(session: session)
        let (viewModel, created) = makeViewModel { client }
        viewModel.displayName = "Someone Else"

        await viewModel.submit()

        XCTAssertTrue(created.results.isEmpty)
        XCTAssertEqual(
            viewModel.errorMessage,
            ErrorPresenter.message(for: GimError.InvalidInput(reason: "This device already has an identity")))
        let current = try await client.session()
        XCTAssertEqual(current, session)
    }

    @MainActor
    func testAHubThatDoesNotAdmitTheUserRefusesTheRegistration() async throws {
        let client = FakeGimClient()
        await client.simulateNotAdmitted(hubId: "")
        let (viewModel, created) = makeViewModel { client }
        viewModel.displayName = "Sofia"

        await viewModel.submit()

        XCTAssertEqual(viewModel.errorMessage, "This server doesn't accept your account.")
        XCTAssertTrue(created.results.isEmpty)
        let session = try await client.session()
        XCTAssertNil(session, "nothing is kept")
        XCTAssertFalse(viewModel.isSubmitting)
    }
}

/// Client whose `createIdentity` returns a code but whose `session()` stays `nil`.
private final class SessionlessIdentityClient: GimClientAPI {
    func session() async throws -> Session? { nil }
    func userId() -> String? { nil }
    func localStateReset() -> Bool { false }
    func createIdentity(displayName: String) async throws -> String {
        "7BQ2-K9MX-4TVA-0HZR-PC63-W8NE-1SJD-5GFY-QK2M-V7R"
    }
    func restoreFromRecovery(userId: String, recoveryCode: String, revokeOthers: Bool) async throws {}
    func startLink(hubs: [String]) throws -> any LinkSession { throw GimError.NotImplemented }
    func waitLink(link: any LinkSession) async throws -> String { throw GimError.NotImplemented }
    func confirmLink(accepted: Bool) async throws {}
    func approveLink(qrString: String) async throws -> any PendingApproval { throw GimError.NotRegistered }
    func confirmApproval(approval: any PendingApproval, accepted: Bool) async throws {}
    func devices() async throws -> [DeviceInfo] { throw GimError.NotRegistered }
    func userDevices(userId: String) async throws -> [DeviceInfo] { throw GimError.NotRegistered }
    func revokeDevice(deviceId: String) async throws {}
    func setDisplayName(name: String) async throws {}
    func claimHandle(handle: String) async throws {}
    func releaseHandle() async throws {}
    func signOut() async throws {}
    func startSync() async throws {}
    func stopSync() async throws {}
    func setNetworkReachable(reachable: Bool) {}
    func setLocalTimeZone(zone: (any LocalTimeZone)?) {}
    func findUser(handle: String) async throws -> UserProfile? { nil }
    func createDirectChat(userId: String) async throws -> String { throw GimError.NotRegistered }
    func createGroupChat(name: String, memberUserIds: [String]) async throws -> String {
        throw GimError.NotRegistered
    }
    func chatMembers(chatId: String) async throws -> [UserProfile] { throw GimError.NotRegistered }
    func addMembers(chatId: String, userIds: [String]) async throws {}
    func removeMember(chatId: String, userId: String) async throws {}
    func leaveChat(chatId: String) async throws {}
    func chatState(chatId: String) async throws -> ChatState { .active }
    func setGroupInfo(chatId: String, name: String?, avatarFilePath: String?) async throws {}
    func sendText(chatId: String, body: String, replyTo: String?) async throws -> String {
        throw GimError.NotRegistered
    }
    func sendMedia(
        chatId: String, filePath: String, mime: String, caption: String?, replyTo: String?
    ) async throws -> String {
        throw GimError.NotRegistered
    }
    func editMessage(chatId: String, messageId: String, newBody: String) async throws {}
    func deleteMessage(chatId: String, messageId: String) async throws {}
    func react(chatId: String, messageId: String, emoji: String) async throws {}
    func unreact(chatId: String, messageId: String, emoji: String) async throws {}
    func retrySend(chatId: String, messageId: String) async throws {}
    func cancelSend(chatId: String, messageId: String) async throws {}
    func markRead(chatId: String, upToMessageId: String) async throws {}
    func setTyping(chatId: String, active: Bool) async throws {}
    func stopTyping(chatId: String) async throws {}
    func fetchMedia(chatId: String, messageId: String, destPath: String) async throws -> String {
        throw GimError.NotFound(reason: "media")
    }
    func fetchThumbnail(chatId: String, messageId: String, destPath: String) async throws -> String? { nil }
    func chatList(listener: any ChatListListener) async throws -> TaskHandle { throw GimError.NotRegistered }
    func timeline(chatId: String) async throws -> any Timeline { throw GimError.NotRegistered }
    func connectionState(listener: any ConnectionStateListener) async throws -> TaskHandle {
        throw GimError.NotRegistered
    }
    func typing(chatId: String, listener: any TypingListener) async throws -> TaskHandle {
        throw GimError.NotRegistered
    }
    func hubs() async throws -> [HubInfo] { throw GimError.NotRegistered }
    func addHub(url: String) async throws -> HubInfo { throw GimError.NotRegistered }
    func removeHub(hubId: String, confirmOwnedGroups: Bool) async throws { throw GimError.NotRegistered }
    func setPrimaryHub(hubId: String) async throws { throw GimError.NotRegistered }
    func hubList(listener: any HubListListener) async throws -> TaskHandle { throw GimError.NotRegistered }
    func registerPush(registration: PushRegistration) async throws { throw GimError.NotRegistered }
    func unregisterPush() async throws { throw GimError.NotRegistered }
    func processPush(payload: String) async throws -> NotificationContent { throw GimError.NotRegistered }
    func ownProfile() async throws -> UserProfile? { throw GimError.NotRegistered }
    func setAvatar(filePath: String, mime: String) async throws { throw GimError.NotRegistered }
    func removeAvatar() async throws { throw GimError.NotRegistered }
    func fetchUserAvatar(userId: String, destPath: String) async throws -> String { throw GimError.NotRegistered }
    func fetchChatAvatar(chatId: String, destPath: String) async throws -> String { throw GimError.NotRegistered }
    func privacy() async throws -> PrivacySettings { throw GimError.NotRegistered }
    func setReadReceipts(enabled: Bool) async throws { throw GimError.NotRegistered }
    func setTypingIndicators(enabled: Bool) async throws { throw GimError.NotRegistered }
    func blockUser(userId: String) async throws { throw GimError.NotRegistered }
    func unblockUser(userId: String) async throws { throw GimError.NotRegistered }
    func setChatMuted(chatId: String, mutedUntilMs: UInt64) async throws { throw GimError.NotRegistered }
    func setChatPinned(chatId: String, pinned: Bool) async throws { throw GimError.NotRegistered }
    func setChatArchived(chatId: String, archived: Bool) async throws { throw GimError.NotRegistered }
    func reportUser(userId: String, reason: ReportReason, note: String?, messageIds: [String]) async throws -> String {
        throw GimError.NotRegistered
    }
    func rotateRecoveryCode() async throws -> RecoveryRotation { throw GimError.NotRegistered }
    func deleteAccount() async throws -> [String] { throw GimError.NotRegistered }
}
