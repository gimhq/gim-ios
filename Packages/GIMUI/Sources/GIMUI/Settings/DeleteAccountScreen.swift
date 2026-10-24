import GIMFeatures
import SwiftUI

/// Explains what deleting the account removes and deletes it once the user typed the confirmation word.
struct DeleteAccountScreen: View {
    @State private var viewModel: DeleteAccountViewModel

    /// - Parameter deleteAccount: deletes the account and returns the error text when it fails.
    init(deleteAccount: @escaping @MainActor () async -> String?) {
        _viewModel = State(
            initialValue: DeleteAccountViewModel(
                confirmationWord: String(localized: "DELETE", table: "Settings", bundle: .module),
                deleteAccount: deleteAccount))
    }

    var body: some View {
        Form {
            Section {
                Text(
                    "Your account is deleted from every server this device can reach.", tableName: "Settings",
                    bundle: .module)
                Text(
                    "You leave all your chats. Other members see that you left.", tableName: "Settings", bundle: .module
                )
                Text("Your other devices are signed out.", tableName: "Settings", bundle: .module)
                Text(
                    "Everything on this device is removed, including your messages.", tableName: "Settings",
                    bundle: .module)
            } header: {
                Text("What gets deleted", tableName: "Settings", bundle: .module)
            } footer: {
                Text(
                    "This can't be undone, and your recovery key stops working. Servers that can't be reached now remove your account later on their own.",
                    tableName: "Settings", bundle: .module)
            }
            Section {
                TextField(viewModel.confirmationWord, text: $viewModel.typedConfirmation)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .disabled(viewModel.isDeleting)
                    .accessibilityIdentifier("settings.deleteAccount.confirmField")
            } header: {
                Text("Type \(viewModel.confirmationWord) to confirm", tableName: "Settings", bundle: .module)
            }
            Section {
                Button(role: .destructive) {
                    Task { await viewModel.confirm() }
                } label: {
                    HStack {
                        Text("Delete account", tableName: "Settings", bundle: .module)
                        Spacer()
                        if viewModel.isDeleting { ProgressView() }
                    }
                }
                .disabled(!viewModel.canConfirm || viewModel.isDeleting)
                .accessibilityIdentifier("settings.deleteAccount.confirm")
            } footer: {
                if let error = viewModel.errorMessage {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(Text("Delete account", tableName: "Settings", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
    }
}
