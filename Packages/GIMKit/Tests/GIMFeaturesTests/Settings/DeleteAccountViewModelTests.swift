import Foundation
import GIMFeatures
import XCTest

final class DeleteAccountViewModelTests: XCTestCase {
    @MainActor
    private final class Deletions {
        var count = 0
        var error: String?
    }

    @MainActor
    private func makeViewModel(word: String = "DELETE") -> (DeleteAccountViewModel, Deletions) {
        let deletions = Deletions()
        let viewModel = DeleteAccountViewModel(confirmationWord: word) {
            deletions.count += 1
            return deletions.error
        }
        return (viewModel, deletions)
    }

    @MainActor
    func testCanConfirmOnlyWhenTheWordIsTyped() {
        let (viewModel, _) = makeViewModel()
        XCTAssertFalse(viewModel.canConfirm)

        for typed in ["", "DELET", "DELETE ME", "remove"] {
            viewModel.typedConfirmation = typed
            XCTAssertFalse(viewModel.canConfirm, typed)
        }
        for typed in ["DELETE", "delete", "  Delete\n"] {
            viewModel.typedConfirmation = typed
            XCTAssertTrue(viewModel.canConfirm, typed)
        }
    }

    @MainActor
    func testCanConfirmWithANonLatinWord() {
        let (viewModel, _) = makeViewModel(word: "删除")

        viewModel.typedConfirmation = "删"
        XCTAssertFalse(viewModel.canConfirm)

        viewModel.typedConfirmation = " 删除 "
        XCTAssertTrue(viewModel.canConfirm)
    }

    @MainActor
    func testConfirmWithoutTheWordDoesNothing() async {
        let (viewModel, deletions) = makeViewModel()
        viewModel.typedConfirmation = "DELET"

        await viewModel.confirm()

        XCTAssertEqual(deletions.count, 0)
    }

    @MainActor
    func testConfirmCallsTheDeleteAction() async {
        let (viewModel, deletions) = makeViewModel()
        viewModel.typedConfirmation = "delete"

        await viewModel.confirm()

        XCTAssertEqual(deletions.count, 1)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isDeleting)
    }

    @MainActor
    func testFailedDeletionShowsTheErrorAndCanBeRetried() async {
        let (viewModel, deletions) = makeViewModel()
        deletions.error = "Can't reach the server. Check your connection and try again."
        viewModel.typedConfirmation = "DELETE"

        await viewModel.confirm()

        XCTAssertEqual(viewModel.errorMessage, deletions.error)
        XCTAssertFalse(viewModel.isDeleting)
        XCTAssertTrue(viewModel.canConfirm)

        deletions.error = nil
        await viewModel.confirm()

        XCTAssertEqual(deletions.count, 2)
        XCTAssertNil(viewModel.errorMessage)
    }
}
