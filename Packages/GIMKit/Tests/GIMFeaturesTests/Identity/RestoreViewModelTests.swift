import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

final class RestoreViewModelTests: XCTestCase {
    private let validUserId = "u" + String(repeating: "abcdefghijklmnopqrstuvwxyz234567", count: 2).prefix(54) + "q"
    private let validCode = "7BQ2-K9MX-4TVA-0HZR-PC63-W8NE-1SJD-5GFY-QK2M-V7R"
    private let kit = FakeRecoveryKitFunctions()
    private let english = RecoveryKitLabels(
        title: "gim recovery kit", accountId: "Account ID", recoveryKey: "Recovery key", note: "Keep this secret.")
    private let chinese = RecoveryKitLabels(title: "恢复工具包", accountId: "账户 ID", recoveryKey: "恢复密钥", note: "请妥善保管。")

    @MainActor
    private final class Registered {
        var registrations: [Registration] = []
    }

    @MainActor
    private func makeViewModel(
        recoveryKit: any RecoveryKitFunctions = FakeRecoveryKitFunctions(),
        client: @escaping @MainActor () async throws -> any GimClientAPI
    ) -> (RestoreViewModel, Registered) {
        let registered = Registered()
        let context = OnboardingContext(
            config: ClientConfig(serverUrl: "https://gim.example.eu"), client: client, discardClient: {},
            recoveryKit: recoveryKit, onRegistered: { registered.registrations.append($0) })
        return (RestoreViewModel(context: context), registered)
    }

    /// A fake that knows the identity of `userId` with `code`, signed out like a fresh device.
    @MainActor
    private func restorableClient() async throws -> (client: FakeGimClient, userId: String, code: String) {
        let client = FakeGimClient()
        let code = try await client.createIdentity(displayName: "Sofia")
        let userId = try XCTUnwrap(client.userId())
        try await client.signOut()
        return (client, userId, code)
    }

    @MainActor
    func testEmptyFieldsShowErrorsOnSubmitWithoutCreatingAClient() async {
        var clientRequests = 0
        let (viewModel, registered) = makeViewModel {
            clientRequests += 1
            return FakeGimClient()
        }
        XCTAssertNil(viewModel.userIdError)
        XCTAssertNil(viewModel.recoveryCodeError)
        XCTAssertFalse(viewModel.canSubmit)
        XCTAssertTrue(viewModel.revokeOthers)

        viewModel.userId = "   "
        await viewModel.submit()

        XCTAssertNotNil(viewModel.userIdError)
        XCTAssertNotNil(viewModel.recoveryCodeError)
        XCTAssertEqual(clientRequests, 0)
        XCTAssertTrue(registered.registrations.isEmpty)
    }

    @MainActor
    func testPastingAFullKitFillsBothFields() async {
        for labels in [english, chinese] {
            let (viewModel, _) = makeViewModel { FakeGimClient() }
            XCTAssertFalse(viewModel.showsFields)

            viewModel.kitText = kit.formatRecoveryKit(
                userId: validUserId.uppercased(), recoveryCode: validCode.lowercased(), labels: labels)

            XCTAssertEqual(viewModel.userId, validUserId)
            XCTAssertEqual(viewModel.recoveryCode, validCode)
            XCTAssertEqual(
                viewModel.parsed,
                ParsedRecoveryKit(userId: validUserId, recoveryCode: validCode.replacingOccurrences(of: "-", with: "")))
            XCTAssertNil(viewModel.kitError)
            XCTAssertTrue(viewModel.showsFields)
        }
    }

    @MainActor
    func testPastingOnlyTheKeyFillsTheCodeAndReportsTheMissingPart() async {
        let (viewModel, _) = makeViewModel { FakeGimClient() }
        viewModel.userId = "typed before"

        viewModel.kitText = "Recovery key: \(validCode.replacingOccurrences(of: "-", with: ""))"

        XCTAssertEqual(viewModel.recoveryCode, validCode)
        XCTAssertEqual(viewModel.userId, "typed before", "a part that is not found leaves its field as it is")
        XCTAssertEqual(viewModel.kitError, RestoreViewModel.kitPartMissingMessage)
        XCTAssertTrue(viewModel.showsFields)
    }

    @MainActor
    func testPastingProseReportsThatNothingWasRecognized() async {
        let (viewModel, _) = makeViewModel { FakeGimClient() }

        viewModel.kitText = "Hello, I lost my phone. Can you help?"

        XCTAssertEqual(viewModel.parsed, ParsedRecoveryKit(userId: nil, recoveryCode: nil))
        XCTAssertEqual(viewModel.kitError, RestoreViewModel.kitNotRecognizedMessage)
        XCTAssertFalse(viewModel.showsFields)
        XCTAssertEqual(viewModel.userId, "")
        XCTAssertEqual(viewModel.recoveryCode, "")
    }

    @MainActor
    func testPastingUsesTheInjectedParser() async {
        let recording = RecordingRecoveryKitFunctions()
        let (viewModel, _) = makeViewModel(recoveryKit: recording) { FakeGimClient() }
        let text = "Account ID: \(validUserId)\nRecovery key: \(validCode)\n"

        viewModel.kitText = text
        viewModel.kitText = " \n"

        XCTAssertEqual(recording.calls, [.parse(text: text)], "blank text is not parsed")
        XCTAssertEqual(viewModel.userId, validUserId)
        XCTAssertEqual(viewModel.recoveryCode, validCode)
    }

    /// gim-core counts Unicode Nl/No characters ("²", "①") as numeric, so they belong to the token they touch, as in
    /// gim-client-sdk `parse_recovery_kit` (`char::is_numeric`).
    @MainActor
    func testNumericSymbolsBelongToTheirTokenLikeTheSdk() async {
        let symbols = validCode.replacingOccurrences(of: "-", with: "")
        let cases: [(text: String, parsed: ParsedRecoveryKit)] = [
            // "²" lengthens the last group to "V7R²", so no run of tokens has exactly 39 characters.
            (
                "Account ID: \(validUserId)\nRecovery key: \(validCode)²\n",
                ParsedRecoveryKit(userId: validUserId, recoveryCode: nil)
            ),
            // "①" glued to the key makes a 40-character token.
            (
                "Account ID: \(validUserId)\nRecovery key: ①\(symbols)\n",
                ParsedRecoveryKit(userId: validUserId, recoveryCode: nil)
            ),
            // Joined by a space, "①" is a token of its own before the key, which is still found.
            (
                "Account ID: \(validUserId)\nRecovery key: ① \(symbols)\n",
                ParsedRecoveryKit(userId: validUserId, recoveryCode: symbols)
            ),
            // In the key the symbol is kept, so the 39 characters are not a valid key.
            ("Recovery key: \(symbols.dropLast())²", ParsedRecoveryKit(userId: nil, recoveryCode: nil)),
        ]
        for (text, parsed) in cases {
            let (viewModel, _) = makeViewModel { FakeGimClient() }

            viewModel.kitText = text

            XCTAssertEqual(viewModel.parsed, parsed, text)
            XCTAssertEqual(viewModel.parsed, kit.parseRecoveryKit(text: text), text)
            XCTAssertEqual(viewModel.userId, parsed.userId ?? "", text)
        }
    }

    @MainActor
    func testBlankKitTextClearsTheParseAndTheError() async {
        let (viewModel, _) = makeViewModel { FakeGimClient() }
        viewModel.kitText = "not a kit"
        XCTAssertNotNil(viewModel.kitError)

        viewModel.kitText = "  \n "

        XCTAssertNil(viewModel.parsed)
        XCTAssertNil(viewModel.kitError)
        XCTAssertFalse(viewModel.showsFields)
    }

    @MainActor
    func testEnteringSeparatelyShowsTheFields() async {
        let (viewModel, _) = makeViewModel { FakeGimClient() }

        viewModel.enterSeparately()

        XCTAssertTrue(viewModel.showsFields)
        XCTAssertNil(viewModel.kitError)
    }

    @MainActor
    func testSubmitAfterAPasteRestoresWithTheParsedNormalizedValues() async throws {
        let (client, userId, code) = try await restorableClient()
        let (viewModel, registered) = makeViewModel { client }
        // The fake's user IDs are not real ones, so the kit yields only the code and the ID is typed.
        viewModel.kitText = kit.formatRecoveryKit(userId: userId, recoveryCode: code.lowercased(), labels: english)
        XCTAssertEqual(
            viewModel.recoveryCode, RecoveryKit.groupedRecoveryCode(RecoveryKit.normalizedRecoveryCode(code)))
        viewModel.userId = "  \(userId.uppercased())\n"

        await viewModel.submit()
        viewModel.finish()

        XCTAssertNil(viewModel.errorMessage)
        let registration = try XCTUnwrap(registered.registrations.first)
        XCTAssertEqual(registration.session.userId, userId)
    }

    @MainActor
    func testSubmitAfterAFullPasteUsesTheParsedAccountId() async throws {
        let (client, _, _) = try await restorableClient()
        let (viewModel, registered) = makeViewModel { client }
        viewModel.kitText = kit.formatRecoveryKit(userId: validUserId, recoveryCode: validCode, labels: chinese)

        await viewModel.submit()

        XCTAssertEqual(viewModel.errorMessage, RestoreViewModel.notFoundMessage, "the fake has no such user")
        XCTAssertEqual(viewModel.recoveryCode, validCode, "kept for correction")
        XCTAssertTrue(registered.registrations.isEmpty)
    }

    @MainActor
    func testSubmitRestoresWithTrimmedInputAndSignsInAfterTheNotice() async throws {
        let (client, userId, code) = try await restorableClient()
        let (viewModel, registered) = makeViewModel { client }
        viewModel.userId = "  \(userId)\n"
        viewModel.recoveryCode = " \(code.lowercased()) \n"

        await viewModel.submit()

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.showsRejoinNotice)
        XCTAssertEqual(viewModel.recoveryCode, "", "the code is dropped once used")
        XCTAssertFalse(viewModel.canSubmit)
        XCTAssertTrue(registered.registrations.isEmpty, "signs in only after the notice")

        viewModel.finish()

        let registration = try XCTUnwrap(registered.registrations.first)
        XCTAssertTrue(registration.client === client)
        XCTAssertEqual(registration.session.userId, userId)
        XCTAssertEqual(registration.config.serverUrl, "https://gim.example.eu")
        XCTAssertFalse(viewModel.showsRejoinNotice)
        viewModel.finish()
        XCTAssertEqual(registered.registrations.count, 1)
    }

    @MainActor
    func testRevokeOthersRevokesThePreviousDevices() async throws {
        let (client, userId, code) = try await restorableClient()
        let (viewModel, _) = makeViewModel { client }
        viewModel.userId = userId
        viewModel.recoveryCode = code

        await viewModel.submit()

        let devices = try await client.devices()
        XCTAssertEqual(devices.filter { !$0.isCurrent }.map(\.revoked), [true])
        XCTAssertEqual(devices.filter(\.isCurrent).map(\.revoked), [false])
    }

    @MainActor
    func testKeepingOtherDevicesLeavesThemActive() async throws {
        let (client, userId, code) = try await restorableClient()
        let (viewModel, _) = makeViewModel { client }
        viewModel.userId = userId
        viewModel.recoveryCode = code
        viewModel.revokeOthers = false

        await viewModel.submit()

        let devices = try await client.devices()
        XCTAssertEqual(devices.map(\.revoked), [false, false])
    }

    @MainActor
    func testUnknownUserShowsNotFoundMessage() async throws {
        let (client, _, code) = try await restorableClient()
        let (viewModel, registered) = makeViewModel { client }
        viewModel.userId = "user-nobody"
        viewModel.recoveryCode = code

        await viewModel.submit()

        XCTAssertEqual(viewModel.errorMessage, RestoreViewModel.notFoundMessage)
        XCTAssertFalse(viewModel.showsRejoinNotice)
        XCTAssertTrue(registered.registrations.isEmpty)
        XCTAssertFalse(viewModel.isSubmitting)
    }

    @MainActor
    func testMalformedCodeShowsTheCoreMessage() async throws {
        let (client, userId, _) = try await restorableClient()
        let (viewModel, _) = makeViewModel { client }
        viewModel.userId = userId
        viewModel.recoveryCode = "ABCD-EFGH"

        await viewModel.submit()

        XCTAssertEqual(
            viewModel.errorMessage,
            ErrorPresenter.message(for: GimError.InvalidInput(reason: "Malformed recovery code")))
        XCTAssertEqual(viewModel.recoveryCode, "ABCD-EFGH", "kept for correction")
    }

    @MainActor
    func testWrongCodeShowsMismatchMessageAndIsRetryable() async throws {
        let (client, userId, code) = try await restorableClient()
        let (viewModel, registered) = makeViewModel { client }
        viewModel.userId = userId
        // Another valid code: a different first symbol.
        viewModel.recoveryCode = (code.first == "0" ? "1" : "0") + code.dropFirst()

        await viewModel.submit()

        XCTAssertEqual(viewModel.errorMessage, RestoreViewModel.wrongCodeMessage)

        viewModel.recoveryCode = code
        await viewModel.submit()
        viewModel.finish()

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(registered.registrations.count, 1)
    }

    @MainActor
    func testRestoreErrorIsPresentedAndRetryRestoresOnTheSameClient() async throws {
        let (fake, userId, code) = try await restorableClient()
        let client = IdentityStubClient(fake, restoreErrors: [.Network(reason: "offline")])
        var clientRequests = 0
        let (viewModel, registered) = makeViewModel {
            clientRequests += 1
            return client
        }
        viewModel.userId = userId
        viewModel.recoveryCode = code

        await viewModel.submit()

        XCTAssertEqual(viewModel.errorMessage, ErrorPresenter.message(for: GimError.Network(reason: "offline")))
        XCTAssertEqual(viewModel.recoveryCode, code, "kept for the retry")
        XCTAssertFalse(viewModel.showsRejoinNotice)

        await viewModel.submit()
        viewModel.finish()

        XCTAssertNil(viewModel.errorMessage)
        let registration = try XCTUnwrap(registered.registrations.first)
        XCTAssertTrue(registration.client === client)
        XCTAssertEqual(registration.session.userId, userId)
        XCTAssertEqual(clientRequests, 2)
    }

    @MainActor
    func testClientCreationErrorIsPresented() async {
        let (viewModel, registered) = makeViewModel { throw GimError.Network(reason: "offline") }
        viewModel.userId = "user-sofia"
        viewModel.recoveryCode = "code"

        await viewModel.submit()

        XCTAssertEqual(viewModel.errorMessage, ErrorPresenter.message(for: GimError.Network(reason: "offline")))
        XCTAssertTrue(registered.registrations.isEmpty)
    }

    @MainActor
    func testAHubThatDoesNotAdmitTheUserRefusesTheRestore() async throws {
        let (client, userId, code) = try await restorableClient()
        await client.simulateNotAdmitted(hubId: "")
        let (viewModel, registered) = makeViewModel { client }
        viewModel.userId = userId
        viewModel.recoveryCode = code

        await viewModel.submit()

        XCTAssertEqual(viewModel.errorMessage, "This server doesn't accept your account.")
        XCTAssertFalse(viewModel.showsRejoinNotice)
        XCTAssertTrue(registered.registrations.isEmpty)
    }
}
