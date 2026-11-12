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
