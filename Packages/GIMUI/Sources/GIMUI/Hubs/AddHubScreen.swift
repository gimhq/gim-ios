import GIMFeatures
import SwiftUI

/// Adds a hub by its URL (`addHub`); closes once gim-core listed it.
struct AddHubScreen: View {
    @State private var viewModel: AddHubViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusesUrl: Bool

    init(viewModel: AddHubViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Form {
            Section {
                TextField(text: $viewModel.url) {
                    Text("https://hub.example.eu", tableName: "Hubs", bundle: .module)
                }
                .textContentType(.URL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusesUrl)
                .accessibilityIdentifier("addHub.url")
                .submitLabel(.done)
                .onSubmit(submit)
                ValidationMessage(text: viewModel.urlError)
            } header: {
                Text("Server address", tableName: "Hubs", bundle: .module)
            } footer: {
                Text(
                    "Your messages are also kept on this server. It takes over when your other servers are down.",
                    tableName: "Hubs", bundle: .module)
            }

            Section {
                Button(action: submit) {
                    HStack {
                        Spacer()
                        if viewModel.isSubmitting {
                            ProgressView()
                        } else {
                            Text("Add server", tableName: "Hubs", bundle: .module).bold()
                        }
                        Spacer()
                    }
                }
                .disabled(!viewModel.canSubmit)
                .accessibilityIdentifier("addHub.submit")
            } footer: {
                if let error = viewModel.errorMessage {
                    Text(error).foregroundStyle(.red).accessibilityIdentifier("addHub.error")
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(Text("Add server", tableName: "Hubs", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focusesUrl = true }
        .onChange(of: viewModel.addedHub) { _, hub in
            if hub != nil { dismiss() }
        }
    }

    private func submit() {
        focusesUrl = false
        Task { await viewModel.submit() }
    }
}
