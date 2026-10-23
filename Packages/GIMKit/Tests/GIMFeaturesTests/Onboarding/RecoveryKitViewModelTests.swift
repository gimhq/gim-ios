import Foundation
import GIMFeatures
import XCTest

final class RecoveryKitViewModelTests: XCTestCase {
    @MainActor
    private final class Confirmations {
        var count = 0
    }

    private let userId = "u" + String(repeating: "abcdefghijklmnopqrstuvwxyz234567", count: 2).prefix(54) + "q"
    private let code = "7BQ2-K9MX-4TVA-0HZR-PC63-W8NE-1SJD-5GFY-QK2M-V7R"
    private let labels = RecoveryKit.Labels(
        title: "Recovery kit", accountId: "Account ID", recoveryKey: "Recovery key", note: "Keep this safe.")

    @MainActor
    private func makeViewModel(code: String? = nil) -> (RecoveryKitViewModel, Confirmations) {
        let confirmations = Confirmations()
        let viewModel = RecoveryKitViewModel(userId: userId, code: code ?? self.code, labels: labels) {
            confirmations.count += 1
        }
        return (viewModel, confirmations)
    }

    @MainActor
    func testShowsTheKitTextAndTheGroupedCode() async {
        let (viewModel, _) = makeViewModel(code: code.replacingOccurrences(of: "-", with: "").lowercased())

        XCTAssertEqual(viewModel.userId, userId)
        XCTAssertEqual(viewModel.groupedCode, code)
        XCTAssertEqual(viewModel.kitText, RecoveryKit.format(userId: userId, recoveryCode: code, labels: labels))
        XCTAssertEqual(viewModel.labels, labels)
        XCTAssertEqual(viewModel.endingLength, RecoveryKit.endingSymbols)
        XCTAssertFalse(viewModel.isChecking)
        XCTAssertFalse(viewModel.isConfirmed)
    }

    @MainActor
    func testContinueToCheckAndShowKitAgain() async {
        let (viewModel, _) = makeViewModel()
        viewModel.continueToCheck()
        XCTAssertTrue(viewModel.isChecking)

        viewModel.endingInput = "XXXX"
        viewModel.confirm()
        XCTAssertNotNil(viewModel.endingError)
        viewModel.showKitAgain()
        XCTAssertFalse(viewModel.isChecking)

        viewModel.continueToCheck()
        XCTAssertTrue(viewModel.isChecking)
        XCTAssertEqual(viewModel.endingInput, "", "the check starts empty")
        XCTAssertNil(viewModel.endingError)
    }

    @MainActor
    func testWrongEndingShowsTheErrorAndKeepsTheCode() async {
        let (viewModel, confirmations) = makeViewModel()
        viewModel.continueToCheck()
        viewModel.endingInput = "M-V7Q"

        viewModel.confirm()

        XCTAssertEqual(viewModel.endingError, RecoveryKitViewModel.mismatchMessage)
        XCTAssertEqual(viewModel.code, code)
        XCTAssertEqual(viewModel.endingInput, "M-V7Q", "kept for correction")
        XCTAssertTrue(viewModel.isChecking)
        XCTAssertEqual(confirmations.count, 0)
    }

    @MainActor
    func testRightEndingInAnyFormDropsTheCodeAndConfirmsOnce() async {
        for typed in ["MV7R", "mv7r", "m-v7r", " M V7R "] {
            let (viewModel, confirmations) = makeViewModel()
            viewModel.continueToCheck()
            viewModel.endingInput = typed

            viewModel.confirm()

            XCTAssertNil(viewModel.code, typed)
            XCTAssertTrue(viewModel.isConfirmed)
            XCTAssertEqual(viewModel.groupedCode, "")
            XCTAssertEqual(viewModel.kitText, "")
            XCTAssertEqual(viewModel.endingInput, "")
            XCTAssertNil(viewModel.endingError)
            XCTAssertEqual(confirmations.count, 1)

            viewModel.confirm()
            viewModel.continueToCheck()
            viewModel.showKitAgain()
            XCTAssertEqual(confirmations.count, 1, "nothing happens after the confirmation")
            XCTAssertTrue(viewModel.isChecking, "the check step stays once confirmed")
        }
    }

    @MainActor
    func testConfirmBeforeTheCheckStepDoesNothing() async {
        let (viewModel, confirmations) = makeViewModel()
        viewModel.endingInput = "MV7R"

        viewModel.confirm()

        XCTAssertEqual(viewModel.code, code)
        XCTAssertNil(viewModel.endingError)
        XCTAssertEqual(confirmations.count, 0)
    }

    func testLocalizedLabelsHaveTheEnglishWords() {
        let labels = RecoveryKit.Labels.localized
        XCTAssertEqual(labels.title, "gim recovery kit")
        XCTAssertEqual(labels.accountId, "Account ID")
        XCTAssertEqual(labels.recoveryKey, "Recovery key")
        XCTAssertEqual(
            labels.note,
            "Keep this secret. Anyone who has it can get into your account. Lost all your devices? Open gim, tap "
                + "Restore and paste this text.")
    }
}
