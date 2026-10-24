import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

final class OnboardingValidationKindTests: XCTestCase {
    func testServerUrlErrorTexts() {
        XCTAssertEqual(OnboardingValidation.ServerUrlError.empty.text, "Enter the server address.")
        XCTAssertEqual(
            OnboardingValidation.ServerUrlError.notAFullAddress.text, "Enter a full address, like https://example.com")
    }

    func testServerUrlErrorKindSelection() {
        XCTAssertNil(OnboardingValidation.serverUrlErrorKind("https://gim.example.eu"))
        XCTAssertEqual(OnboardingValidation.serverUrlErrorKind("  / "), .empty)
        XCTAssertEqual(OnboardingValidation.serverUrlErrorKind("gim.example.eu"), .notAFullAddress)
        XCTAssertEqual(OnboardingValidation.serverUrlErrorKind("ftp://gim.example.eu"), .notAFullAddress)
        XCTAssertEqual(OnboardingValidation.serverUrlError(""), OnboardingValidation.ServerUrlError.empty.text)
    }

    func testHandleErrorTexts() {
        XCTAssertEqual(OnboardingValidation.HandleError.empty.text, "Choose a username.")
        XCTAssertEqual(OnboardingValidation.HandleError.length.text, "Usernames are 3 to 32 characters long.")
        XCTAssertEqual(
            OnboardingValidation.HandleError.characters.text, "Use only letters, digits, underscores and dots.")
    }

    func testHandleErrorKindSelection() {
        XCTAssertNil(OnboardingValidation.handleErrorKind(" Sofia_M.1 "))
        XCTAssertEqual(OnboardingValidation.handleErrorKind("  "), .empty)
        XCTAssertEqual(OnboardingValidation.handleErrorKind("so"), .length)
        XCTAssertEqual(OnboardingValidation.handleErrorKind(String(repeating: "a", count: 33)), .length)
        XCTAssertEqual(OnboardingValidation.handleErrorKind("so fia"), .characters)
        XCTAssertEqual(OnboardingValidation.handleError("so"), OnboardingValidation.HandleError.length.text)
    }

    func testDisplayNameErrorTexts() {
        XCTAssertEqual(OnboardingValidation.DisplayNameError.empty.text, "Enter your name.")
        XCTAssertEqual(OnboardingValidation.DisplayNameError.tooLong.text, "Your name can be 1 to 64 characters long.")
    }

    func testDisplayNameErrorKindSelection() {
        XCTAssertNil(OnboardingValidation.displayNameErrorKind(" Sofia "))
        XCTAssertEqual(OnboardingValidation.displayNameErrorKind(" "), .empty)
        XCTAssertEqual(OnboardingValidation.displayNameErrorKind(String(repeating: "a", count: 65)), .tooLong)
        XCTAssertEqual(
            OnboardingValidation.displayNameError(""), OnboardingValidation.DisplayNameError.empty.text)
    }

    @MainActor
    func testOnboardingViewModelServerUrlErrorKind() async {
        let viewModel = OnboardingViewModel(
            factory: RecordingFactory { _ in FakeGimClient() }, hooks: TestHooks(dataDir: makeTemporaryDirectory()),
            recoveryKit: FakeRecoveryKitFunctions()
        ) { _ in }
        XCTAssertNil(viewModel.serverUrlErrorKind, "untouched field")

        viewModel.choose(.createIdentity)
        XCTAssertEqual(viewModel.serverUrlErrorKind, .empty)

        viewModel.serverUrl = "gim.example.eu"
        XCTAssertEqual(viewModel.serverUrlErrorKind, .notAFullAddress)
        XCTAssertEqual(viewModel.serverUrlError, viewModel.serverUrlErrorKind?.text)
    }
}

final class ClaimHandleKindTests: XCTestCase {
    private let session = Session(userId: "user-sofia", deviceId: "device-1", handle: "", displayName: "Sofia")

    @MainActor
    func testErrorKindTexts() async {
        XCTAssertEqual(
            ClaimHandleViewModel.ErrorKind.taken.text, "Someone already has this username. Try another one.")
        XCTAssertEqual(ClaimHandleViewModel.takenMessage, ClaimHandleViewModel.ErrorKind.taken.text)
        XCTAssertEqual(
            ClaimHandleViewModel.ErrorKind.error(.network).text,
            "Can't reach the server. Check your internet and try again.")
    }

    @MainActor
    func testHandleErrorKind() async {
        let viewModel = ClaimHandleViewModel(client: FakeGimClient(session: session)) {}
        XCTAssertNil(viewModel.handleErrorKind, "untouched field")

        await viewModel.claim()
        XCTAssertEqual(viewModel.handleErrorKind, .empty)

        viewModel.handle = "so"
        XCTAssertEqual(viewModel.handleErrorKind, .length)
        viewModel.handle = "so fia"
        XCTAssertEqual(viewModel.handleErrorKind, .characters)
        XCTAssertEqual(viewModel.handleError, viewModel.handleErrorKind?.text)
        viewModel.handle = "sofia"
        XCTAssertNil(viewModel.handleErrorKind)
    }

    @MainActor
    func testTakenHandleSelectsTaken() async {
        let taken = UserProfile(userId: "user-other", handle: "sofia", displayName: "Other")
        let viewModel = ClaimHandleViewModel(client: FakeGimClient(users: [taken], session: session)) {}
        viewModel.handle = "sofia"

        await viewModel.claim()

        XCTAssertEqual(viewModel.errorKind, .taken)
    }

    @MainActor
    func testForwardedErrorsSelectTheErrorPresenterKind() async {
        let client = IdentityStubClient(
            FakeGimClient(session: session), claimHandleError: .RetryLater(status: 429, retryAfterSecs: 5, reason: ""))
        let viewModel = ClaimHandleViewModel(client: client) { throw GimError.NotRegistered }
        viewModel.handle = "sofia"

        await viewModel.claim()
        XCTAssertEqual(viewModel.errorKind, .error(.serverBusy(retryAfterSecs: 5)))

        await viewModel.skip()
        XCTAssertEqual(viewModel.errorKind, .error(.notRegistered))
        XCTAssertEqual(viewModel.errorMessage, viewModel.errorKind?.text)
    }
}

final class RecoveryKitKindTests: XCTestCase {
    @MainActor
    func testEndingErrorKindText() async {
        XCTAssertEqual(
            RecoveryKitViewModel.EndingErrorKind.mismatch.text,
            "That doesn't match. Look at your recovery key and try again.")
        XCTAssertEqual(RecoveryKitViewModel.mismatchMessage, RecoveryKitViewModel.EndingErrorKind.mismatch.text)
    }

    @MainActor
    func testWrongEndingSelectsMismatch() async {
        let viewModel = RecoveryKitViewModel(
            userId: "user-sofia", code: "7BQ2-K9MX-4TVA-0HZR-PC63-W8NE-1SJD-5GFY-QK2M-V7R",
            recoveryKit: FakeRecoveryKitFunctions()
        ) {}
        viewModel.continueToCheck()
        XCTAssertNil(viewModel.endingErrorKind)
        viewModel.endingInput = "XXXX"

        viewModel.confirm()

        XCTAssertEqual(viewModel.endingErrorKind, .mismatch)
        XCTAssertEqual(viewModel.endingError, RecoveryKitViewModel.mismatchMessage)

        viewModel.continueToCheck()
        XCTAssertNil(viewModel.endingErrorKind)
    }
}
