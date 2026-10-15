import Foundation
import GIMFeatures
import XCTest

final class RecoveryCodeViewModelTests: XCTestCase {
    private let code = "0123-4567-89AB-CDEF-GHJK-MNPQ-RSTV-WXYZ-0A1B-C20"

    @MainActor
    private final class Confirmations {
        var count = 0
    }

    @MainActor
    private func makeViewModel(group: Int = 2) -> (RecoveryCodeViewModel, Confirmations) {
        let confirmations = Confirmations()
        let viewModel = RecoveryCodeViewModel(code: code, chooseGroup: { _ in group }) { confirmations.count += 1 }
        return (viewModel, confirmations)
    }

    @MainActor
    func testShowsTheCodeGroupedAsReturned() async {
        let (viewModel, _) = makeViewModel()
        XCTAssertEqual(viewModel.code, code)
        XCTAssertEqual(viewModel.groups.count, 10)
        XCTAssertEqual(viewModel.groups.last, "C20")
        XCTAssertFalse(viewModel.isConfirming)
        XCTAssertFalse(viewModel.isConfirmed)
    }

    @MainActor
    func testGroupChoiceIsClampedAndNumberedFromOne() async {
        var counts: [Int] = []
        let viewModel = RecoveryCodeViewModel(
            code: code,
            chooseGroup: {
                counts.append($0)
                return 42
            }, onConfirmed: {})
        XCTAssertEqual(counts, [10])
        XCTAssertEqual(viewModel.confirmationGroupIndex, 9)
        XCTAssertEqual(viewModel.confirmationGroupNumber, 10)
    }

    @MainActor
    func testRightGroupConfirmsAndDropsTheCode() async {
        let (viewModel, confirmations) = makeViewModel(group: 2)
        viewModel.continueToConfirmation()
        XCTAssertTrue(viewModel.isConfirming)
        XCTAssertEqual(viewModel.confirmationGroupNumber, 3)
        viewModel.confirmationInput = "89AB"

        viewModel.confirm()

        XCTAssertEqual(confirmations.count, 1)
        XCTAssertTrue(viewModel.isConfirmed)
        XCTAssertNil(viewModel.code)
        XCTAssertTrue(viewModel.groups.isEmpty)
        XCTAssertNil(viewModel.confirmationError)
    }

    @MainActor
    func testConfirmationUsesTheRecoveryCodeParsingRules() async {
        let (viewModel, confirmations) = makeViewModel(group: 8)
        viewModel.continueToConfirmation()
        viewModel.confirmationInput = " o-a l b "

        viewModel.confirm()

        XCTAssertEqual(confirmations.count, 1)
    }

    @MainActor
    func testWrongGroupShowsAnErrorAndKeepsTheCode() async {
        let (viewModel, confirmations) = makeViewModel(group: 2)
        viewModel.continueToConfirmation()
        viewModel.confirmationInput = "4567"

        viewModel.confirm()

        XCTAssertEqual(confirmations.count, 0)
        XCTAssertNotNil(viewModel.confirmationError)
        XCTAssertEqual(viewModel.code, code)
        XCTAssertTrue(viewModel.isConfirming)
    }

    @MainActor
    func testShowCodeAgainReturnsToTheCodeOnlyBeforeConfirmation() async {
        let (viewModel, _) = makeViewModel(group: 0)
        viewModel.continueToConfirmation()
        viewModel.confirmationInput = "0000"
        viewModel.confirm()
        XCTAssertNotNil(viewModel.confirmationError)

        viewModel.showCodeAgain()

        XCTAssertFalse(viewModel.isConfirming)
        XCTAssertNil(viewModel.confirmationError)
        XCTAssertEqual(viewModel.code, code)

        viewModel.continueToConfirmation()
        XCTAssertEqual(viewModel.confirmationInput, "", "the field starts empty again")
        viewModel.confirmationInput = "0123"
        viewModel.confirm()
        viewModel.showCodeAgain()
        viewModel.continueToConfirmation()
        XCTAssertTrue(viewModel.isConfirming, "no way back to the code after confirmation")
        XCTAssertNil(viewModel.code)
    }

    @MainActor
    func testConfirmDoesNothingBeforeTheConfirmationStep() async {
        let (viewModel, confirmations) = makeViewModel(group: 0)
        viewModel.confirmationInput = "0123"
        viewModel.confirm()
        XCTAssertEqual(confirmations.count, 0)
        XCTAssertFalse(viewModel.isConfirmed)
    }
}
