import GIMClientKit
import GIMFeatures
import SwiftUI

/// Edits the display name friends see.
struct EditNameScreen: View {
    @State private var viewModel: ProfileViewModel
    @Environment(\.dismiss) private var dismiss

    init(client: any GimClientAPI, refreshSession: @escaping @MainActor () async -> Void) {
        _viewModel = State(initialValue: ProfileViewModel(client: client, onChanged: refreshSession))
    }

    var body: some View {
        Form {
            Section {
                TextField(text: $viewModel.name) {
                    Text("Name", tableName: "Settings", bundle: .module)
                }
                .textContentType(.name)
                .submitLabel(.done)
                .accessibilityIdentifier("settings.name")
                if viewModel.session != nil, let nameError = viewModel.nameError {
                    Text(Self.message(for: nameError)).font(.footnote).foregroundStyle(.red)
                }
            } footer: {
                VStack(alignment: .leading) {
                    Text("Friends see this name.", tableName: "Settings", bundle: .module)
                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
        }
        .navigationTitle(Text("Name", tableName: "Settings", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task {
                        if await viewModel.saveName() { dismiss() }
                    }
                } label: {
                    Text("Save", tableName: "Common", bundle: .module)
                }
                .disabled(!viewModel.canSave)
                .accessibilityIdentifier("settings.saveName")
            }
        }
        .task { await viewModel.load() }
    }

    private static func message(for error: ProfileViewModel.NameError) -> String {
        switch error {
        case .empty: String(localized: "Enter a name.", table: "Settings", bundle: .module)
        case .tooLong: String(localized: "Use at most 64 characters.", table: "Settings", bundle: .module)
        }
    }
}
